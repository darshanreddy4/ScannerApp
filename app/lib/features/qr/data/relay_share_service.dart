import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../../../core/error/failures.dart';
import '../../../core/error/result.dart';
import '../domain/local_share.dart';
import '../domain/share_options.dart';

/// Payload layout, shared with the relay's download page: 12-byte nonce, then AES-256-GCM ciphertext with its 16-byte tag.
/// The key travels only in the link's #fragment, which browsers never send to a server.
class RelayShareService implements RemoteShareService, RemoteShareRestorer {
  RelayShareService({required String baseUrl, this.maxBytes = 25 * 1024 * 1024, HttpClient Function()? clientFactory})
    : _base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl,
      _clientFactory = clientFactory ?? HttpClient.new;

  /// Slows down guessing: the browser page repeats exactly this many rounds to turn the password into the key.
  static const passwordIterations = 300000;

  final String _base;
  final HttpClient Function() _clientFactory;

  @override
  final int maxBytes;

  @override
  bool get isConfigured => _base.isNotEmpty;

  @override
  Future<Result<ShareHandle>> start({required String filePath, required String fileName, required String mimeType, required Duration ttl, String? password}) =>
      guard(
        () async {
          final file = File(filePath);
          if (!await file.exists()) throw const ExportFailure('The file to share could not be found.');
          if (await file.length() > maxBytes) {
            throw ExportFailure('This file is too large to share over the internet (limit ${maxBytes ~/ (1024 * 1024)} MB). Use "Same Wi-Fi" instead.');
          }

          final sealed = await Isolate.run(() => _seal(filePath, password));
          final client = _clientFactory()..connectionTimeout = const Duration(seconds: 20);
          try {
            final request = await client.postUrl(Uri.parse('$_base/api/upload'));
            request.headers
              ..contentType = ContentType.binary
              ..set('X-Ttl', ttl.inSeconds.toString())
              ..contentLength = sealed.payload.length;
            request.add(sealed.payload);
            final response = await request.close().timeout(const Duration(minutes: 2));
            final body = await response.transform(utf8.decoder).join();
            if (response.statusCode == 413) {
              throw const ExportFailure('This file is too large to share over the internet. Use "Same Wi-Fi" instead.');
            }
            if (response.statusCode != 200) {
              throw ExportFailure('The sharing service is not available right now. Please try again later.', cause: 'HTTP ${response.statusCode}');
            }
            final json = jsonDecode(body) as Map<String, dynamic>;
            final id = json['id'] as String;
            final token = json['deleteToken'] as String;
            final expiresAt = DateTime.fromMillisecondsSinceEpoch(json['expiresAt'] as int);
            final secret = sealed.salt == null ? 'k=${sealed.key}' : 'p=1&s=${sealed.salt}&i=$passwordIterations';
            final link = '$_base/d/$id#$secret&n=${Uri.encodeComponent(fileName)}&t=${Uri.encodeComponent(mimeType)}';
            return _RemoteHandle(id: id, deleteToken: token, url: link, expiresAt: expiresAt, onStop: () => _delete(id, token));
          } finally {
            client.close();
          }
        },
        onError: (e) => switch (e) {
          SocketException() ||
          HandshakeException() ||
          TimeoutException() => ExportFailure('Could not reach the internet. Check your connection or use "Same Wi-Fi".', cause: e),
          _ => ExportFailure('The file could not be uploaded for sharing.', cause: e),
        },
      );

  @override
  ShareHandle? restore(Map<String, Object?> json) {
    final id = json['id'];
    final token = json['deleteToken'];
    final url = json['url'];
    final at = json['expiresAt'];
    if (id is! String || token is! String || url is! String || at is! int) return null;
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(at);
    if (!expiresAt.isAfter(DateTime.now())) {
      // It ran out while the app was closed; make sure the relay no longer keeps it.
      unawaited(_delete(id, token));
      return null;
    }
    return _RemoteHandle(id: id, deleteToken: token, url: url, expiresAt: expiresAt, onStop: () => _delete(id, token));
  }

  Future<void> _delete(String id, String token) async {
    final client = _clientFactory()..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.deleteUrl(Uri.parse('$_base/api/file/$id'));
      request.headers.set('X-Delete-Token', token);
      await (await request.close()).drain<void>();
    } catch (_) {
      // The relay deletes it at expiry anyway.
    } finally {
      client.close();
    }
  }
}

/// [key] is set for a random-key share and [salt] for a password share; exactly one of them is non-null.
typedef _Sealed = ({Uint8List payload, String? key, String? salt});

String _b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

Future<_Sealed> _seal(String path, String? password) async {
  final bytes = await File(path).readAsBytes();
  final algorithm = AesGcm.with256bits();
  SecretKey key;
  String? keyText;
  String? saltText;
  if (password == null) {
    key = await algorithm.newSecretKey();
    keyText = _b64(await key.extractBytes());
  } else {
    final random = Random.secure();
    final salt = Uint8List.fromList(List.generate(16, (_) => random.nextInt(256)));
    key = await Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: RelayShareService.passwordIterations,
      bits: 256,
    ).deriveKeyFromPassword(password: password, nonce: salt);
    saltText = _b64(salt);
  }
  final box = await algorithm.encrypt(bytes, secretKey: key);
  final out = BytesBuilder(copy: false)
    ..add(box.nonce)
    ..add(box.cipherText)
    ..add(box.mac.bytes);
  return (payload: out.takeBytes(), key: keyText, salt: saltText);
}

class _RemoteHandle implements PersistentShareHandle {
  _RemoteHandle({required this.id, required this.deleteToken, required this.url, required this.expiresAt, required Future<void> Function() onStop})
    : _onStop = onStop {
    _timer = Timer(expiresAt.difference(DateTime.now()), _finish);
  }

  final String id;
  final String deleteToken;

  @override
  Map<String, Object?> toJson() => {'id': id, 'deleteToken': deleteToken, 'url': url, 'expiresAt': expiresAt.millisecondsSinceEpoch};

  @override
  final String url;
  @override
  final DateTime expiresAt;

  final Future<void> Function() _onStop;
  final _done = Completer<void>();
  late final Timer _timer;
  bool _stopped = false;

  // The relay does not count downloads.
  @override
  Stream<int> get downloads => const Stream.empty();

  @override
  Future<void> get done => _done.future;

  void _finish() {
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    _timer.cancel();
    _finish();
    await _onStop();
  }
}

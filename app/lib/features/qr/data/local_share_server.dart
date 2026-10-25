import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../../../core/error/failures.dart';
import '../../../core/error/result.dart';
import '../domain/local_share.dart';

/// Serves one file over HTTP on the local network behind an unguessable, time-limited link.
class LocalShareServerImpl implements LocalShareServer {
  LocalShareServerImpl({Future<String?> Function()? hostResolver}) : _resolveHost = hostResolver ?? _findLanAddress;

  final Future<String?> Function() _resolveHost;

  static bool _isPrivate(InternetAddress a) {
    final b = a.rawAddress;
    return b.length == 4 && (b[0] == 10 || (b[0] == 172 && b[1] >= 16 && b[1] <= 31) || (b[0] == 192 && b[1] == 168));
  }

  static Future<String?> _findLanAddress() async {
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
    for (final i in interfaces) {
      for (final a in i.addresses) {
        if (_isPrivate(a)) return a.address;
      }
    }
    return null;
  }

  @override
  Future<Result<ShareHandle>> start({
    required String filePath,
    required String fileName,
    required String mimeType,
    Duration ttl = const Duration(minutes: 5),
    String? password,
  }) => guard(() async {
    final file = File(filePath);
    if (!await file.exists()) throw const ExportFailure('The file to share could not be found.');

    final host = await _resolveHost();
    if (host == null) {
      throw const ExportFailure('Connect to Wi-Fi (or turn on a hotspot) to share with a QR code.');
    }

    final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    final token = _token();
    final safeName = Uri.encodeComponent(fileName);
    final handle = _Handle(server: server, url: 'http://$host:${server.port}/$token/$safeName', expiresAt: DateTime.now().add(ttl));
    handle._serve(file: file, token: token, fileName: fileName, mimeType: mimeType, ttl: ttl, password: password);
    return handle;
  }, onError: (e) => ExportFailure('Sharing could not be started on this network.', cause: e));

  static String _token() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }
}

class _Handle implements ShareHandle {
  _Handle({required this.server, required this.url, required this.expiresAt});

  final HttpServer server;
  @override
  final String url;
  @override
  final DateTime expiresAt;

  final _downloads = StreamController<int>.broadcast();
  final _done = Completer<void>();
  Timer? _timer;
  int _count = 0;
  bool _stopped = false;

  @override
  Stream<int> get downloads => _downloads.stream;

  @override
  Future<void> get done => _done.future;

  static const _maxAttempts = 5;
  int _wrongAttempts = 0;

  void _serve({required File file, required String token, required String fileName, required String mimeType, required Duration ttl, String? password}) {
    _timer = Timer(ttl, stop);
    final expectedPath = '/$token/${Uri.encodeComponent(fileName)}';

    server.listen((request) async {
      try {
        // Anything other than the exact secret path looks like a missing page.
        final isGet = request.method == 'GET';
        final isPost = request.method == 'POST' && password != null;
        if ((!isGet && !isPost) || request.uri.path != expectedPath) {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }
        if (password != null) {
          if (_wrongAttempts >= _maxAttempts) {
            await _page(request, fileName, locked: true);
            return;
          }
          if (isGet) {
            await _page(request, fileName);
            return;
          }
          final given = await _readPassword(request);
          // Compared in constant time so response timing reveals nothing about the password.
          if (given == null || !_sameSecret(given, password)) {
            _wrongAttempts++;
            await _page(request, fileName, left: _maxAttempts - _wrongAttempts, wrong: true, locked: _wrongAttempts >= _maxAttempts);
            return;
          }
          _wrongAttempts = 0;
        }
        final length = await file.length();
        request.response.headers
          ..contentType = ContentType.parse(mimeType)
          ..set('Content-Disposition', 'attachment; filename="${fileName.replaceAll('"', '')}"; filename*=UTF-8\'\'${Uri.encodeComponent(fileName)}')
          ..set('Cache-Control', 'no-store')
          ..contentLength = length;
        await request.response.addStream(file.openRead());
        await request.response.close();
        _count++;
        if (!_downloads.isClosed) _downloads.add(_count);
      } catch (_) {
        try {
          await request.response.close();
        } catch (_) {}
      }
    }, onError: (_) {});
  }

  /// Reads the small form body; anything large or malformed counts as a wrong password.
  Future<String?> _readPassword(HttpRequest request) async {
    if (request.contentLength > 1024) return null;
    final bytes = <int>[];
    await for (final chunk in request) {
      bytes.addAll(chunk);
      if (bytes.length > 1024) return null;
    }
    try {
      return Uri.splitQueryString(utf8.decode(bytes))['password'];
    } on FormatException {
      return null;
    }
  }

  static bool _sameSecret(String a, String b) {
    final x = utf8.encode(a), y = utf8.encode(b);
    var diff = x.length ^ y.length;
    for (var i = 0; i < x.length && i < y.length; i++) {
      diff |= x[i] ^ y[i];
    }
    return diff == 0;
  }

  Future<void> _page(HttpRequest request, String fileName, {int? left, bool wrong = false, bool locked = false}) async {
    final name = const HtmlEscape().convert(fileName);
    final message = locked
        ? 'Too many wrong attempts. Ask the sender to share the file again.'
        : wrong
        ? 'Wrong password. $left ${left == 1 ? 'try' : 'tries'} left.'
        : 'Enter the password the sender gave you.';
    final form = locked
        ? ''
        : '<form method="post"><input type="password" name="password" autocomplete="off" autofocus maxlength="64" placeholder="Password">'
              '<button type="submit">Download</button></form>';
    request.response
      ..statusCode = locked ? HttpStatus.forbidden : HttpStatus.ok
      ..headers.contentType = ContentType.html
      ..headers.set('Cache-Control', 'no-store')
      ..headers.set('Referrer-Policy', 'no-referrer')
      ..headers.set('Content-Security-Policy', "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'")
      ..write(
        '<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">'
        '<title>Protected file</title><style>body{font-family:system-ui,sans-serif;background:#f6f8fb;color:#0f172a;display:grid;place-items:center;min-height:100vh;margin:0}'
        'main{background:#fff;border:1px solid #e2e8f0;border-radius:14px;padding:28px;max-width:380px;width:calc(100% - 40px);text-align:center}'
        'h1{font-size:19px;margin:0 0 6px;word-break:break-word}p{color:${wrong || locked ? '#b91c1c' : '#64748b'};margin:8px 0 16px}'
        'input{width:100%;box-sizing:border-box;padding:12px;border:1px solid #cbd5e1;border-radius:10px;font-size:16px;margin-bottom:12px}'
        'button{width:100%;padding:13px;border:0;border-radius:10px;background:#1d4ed8;color:#fff;font-size:16px;font-weight:600}</style></head>'
        '<body><main><h1>$name</h1><p>$message</p>$form</main></body></html>',
      );
    await request.response.close();
  }

  @override
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    _timer?.cancel();
    await server.close(force: true);
    await _downloads.close();
    if (!_done.isCompleted) _done.complete();
  }
}

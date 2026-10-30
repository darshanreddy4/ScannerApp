import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:doculoom/features/qr/data/relay_share_service.dart';

class _FakeRelay {
  _FakeRelay(this.server);
  final HttpServer server;
  final uploads = <({Uint8List body, Map<String, String> headers})>[];
  final deleted = <({String path, String? token})>[];
  int status = 200;

  String get baseUrl => 'http://127.0.0.1:${server.port}';

  static Future<_FakeRelay> start() async {
    final relay = _FakeRelay(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
    relay.server.listen((req) async {
      if (req.method == 'POST' && req.uri.path == '/api/upload') {
        final body = await req.fold<BytesBuilder>(BytesBuilder(copy: false), (b, d) => b..add(d));
        relay.uploads.add((body: body.takeBytes(), headers: {'x-ttl': req.headers.value('x-ttl') ?? '', 'content-length': '${req.contentLength}'}));
        req.response.statusCode = relay.status;
        req.response.write(
          jsonEncode({
            'id': 'abcdefghijklmnopqrstuv',
            'deleteToken': 'tok123',
            'expiresAt': DateTime.now().add(const Duration(minutes: 15)).millisecondsSinceEpoch,
          }),
        );
      } else if (req.method == 'DELETE') {
        relay.deleted.add((path: req.uri.path, token: req.headers.value('x-delete-token')));
      }
      await req.response.close();
    });
    return relay;
  }

  Future<void> close() => server.close(force: true);
}

void main() {
  late Directory dir;
  late _FakeRelay relay;
  late File file;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('sv_relay');
    file = File(p.join(dir.path, 'contract.pdf'))..writeAsBytesSync(List.generate(5000, (i) => i % 251));
    relay = await _FakeRelay.start();
  });

  tearDown(() async {
    await relay.close();
    dir.deleteSync(recursive: true);
  });

  RelayShareService service({int maxBytes = 25 * 1024 * 1024}) => RelayShareService(baseUrl: '${relay.baseUrl}/', maxBytes: maxBytes);

  test('uploads an encrypted copy and returns a link that carries the key', () async {
    final result = await service().start(filePath: file.path, fileName: 'my contract.pdf', mimeType: 'application/pdf', ttl: const Duration(minutes: 15));
    final handle = result.valueOrNull!;

    final upload = relay.uploads.single;
    expect(upload.headers['x-ttl'], '900');
    expect(upload.headers['content-length'], '${upload.body.length}');
    expect(upload.body.length, 5000 + 12 + 16, reason: 'nonce + ciphertext + tag');

    final uri = Uri.parse(handle.url);
    expect(uri.origin, relay.baseUrl);
    expect(uri.path, '/d/abcdefghijklmnopqrstuv');
    final fragment = Uri.splitQueryString(uri.fragment);
    expect(fragment['n'], 'my contract.pdf');
    expect(fragment['t'], 'application/pdf');

    // Opening it the way the browser page does gives back the original file.
    final key = base64Url.decode(base64Url.normalize(fragment['k']!));
    final box = SecretBox(
      upload.body.sublist(12, upload.body.length - 16),
      nonce: upload.body.sublist(0, 12),
      mac: Mac(upload.body.sublist(upload.body.length - 16)),
    );
    final plain = await AesGcm.with256bits().decrypt(box, secretKey: SecretKey(key));
    expect(plain, file.readAsBytesSync());

    expect(upload.body.sublist(12, 100), isNot(file.readAsBytesSync().sublist(0, 88)), reason: 'the file is not sent in the clear');
    expect(handle.expiresAt.isAfter(DateTime.now().add(const Duration(minutes: 14))), isTrue);
    await handle.stop();
  });

  test('a password share carries no key; the password and the link salt open it', () async {
    final handle = (await service().start(
      filePath: file.path,
      fileName: 'a.pdf',
      mimeType: 'application/pdf',
      ttl: const Duration(minutes: 5),
      password: 'correct horse',
    )).valueOrNull!;
    final fragment = Uri.splitQueryString(Uri.parse(handle.url).fragment);
    final body = relay.uploads.single.body;

    expect(fragment.containsKey('k'), isFalse, reason: 'the link alone must not open the file');
    expect(fragment['p'], '1');
    expect(int.parse(fragment['i']!), RelayShareService.passwordIterations);
    expect(handle.url, isNot(contains('correct')));

    Future<List<int>> open(String password) async {
      final key = await Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: int.parse(fragment['i']!),
        bits: 256,
      ).deriveKeyFromPassword(password: password, nonce: base64Url.decode(base64Url.normalize(fragment['s']!)));
      final box = SecretBox(body.sublist(12, body.length - 16), nonce: body.sublist(0, 12), mac: Mac(body.sublist(body.length - 16)));
      return AesGcm.with256bits().decrypt(box, secretKey: key);
    }

    expect(await open('correct horse'), file.readAsBytesSync());
    await expectLater(open('wrong horse'), throwsA(isA<SecretBoxAuthenticationError>()));
    await handle.stop();
  });

  test('two password shares of the same file use different salts', () async {
    final a = (await service().start(
      filePath: file.path,
      fileName: 'a.pdf',
      mimeType: 'a/b',
      ttl: const Duration(minutes: 5),
      password: 'same password',
    )).valueOrNull!;
    final b = (await service().start(
      filePath: file.path,
      fileName: 'a.pdf',
      mimeType: 'a/b',
      ttl: const Duration(minutes: 5),
      password: 'same password',
    )).valueOrNull!;
    expect(Uri.splitQueryString(Uri.parse(a.url).fragment)['s'], isNot(Uri.splitQueryString(Uri.parse(b.url).fragment)['s']));
    expect(relay.uploads[0].body, isNot(relay.uploads[1].body));
    await a.stop();
    await b.stop();
  });

  test('every share uses a fresh key', () async {
    final a = (await service().start(filePath: file.path, fileName: 'a.pdf', mimeType: 'application/pdf', ttl: const Duration(minutes: 5))).valueOrNull!;
    final b = (await service().start(filePath: file.path, fileName: 'a.pdf', mimeType: 'application/pdf', ttl: const Duration(minutes: 5))).valueOrNull!;
    expect(Uri.splitQueryString(Uri.parse(a.url).fragment)['k'], isNot(Uri.splitQueryString(Uri.parse(b.url).fragment)['k']));
    await a.stop();
    await b.stop();
  });

  test('stopping sharing deletes the file on the relay once, with the delete token', () async {
    final handle = (await service().start(filePath: file.path, fileName: 'a.pdf', mimeType: 'application/pdf', ttl: const Duration(minutes: 5))).valueOrNull!;
    await handle.stop();
    await handle.stop();
    await handle.done;

    expect(relay.deleted.length, 1);
    expect(relay.deleted.single.path, '/api/file/abcdefghijklmnopqrstuv');
    expect(relay.deleted.single.token, 'tok123');
  });

  test('a file over the limit is refused before anything is uploaded', () async {
    final result = await service(maxBytes: 1000).start(filePath: file.path, fileName: 'a.pdf', mimeType: 'application/pdf', ttl: const Duration(minutes: 5));
    expect(result.isOk, isFalse);
    expect(result.failureOrNull!.message, contains('Same Wi-Fi'));
    expect(relay.uploads, isEmpty);
  });

  test('server refusals and outages turn into readable messages', () async {
    relay.status = 413;
    var result = await service().start(filePath: file.path, fileName: 'a.pdf', mimeType: 'application/pdf', ttl: const Duration(minutes: 5));
    expect(result.failureOrNull!.message, contains('too large'));

    relay.status = 500;
    result = await service().start(filePath: file.path, fileName: 'a.pdf', mimeType: 'application/pdf', ttl: const Duration(minutes: 5));
    expect(result.failureOrNull!.message, contains('not available right now'));
  });

  test('no connection gives advice instead of a crash', () async {
    final closed = RelayShareService(baseUrl: relay.baseUrl);
    await relay.close();
    final result = await closed.start(filePath: file.path, fileName: 'a.pdf', mimeType: 'application/pdf', ttl: const Duration(minutes: 5));
    expect(result.failureOrNull!.message, contains('Could not reach the internet'));
  });

  test('a missing file and an empty address are handled', () async {
    final missing = await service().start(
      filePath: p.join(dir.path, 'nope.pdf'),
      fileName: 'a.pdf',
      mimeType: 'application/pdf',
      ttl: const Duration(minutes: 5),
    );
    expect(missing.failureOrNull!.message, contains('could not be found'));
    expect(RelayShareService(baseUrl: '').isConfigured, isFalse);
    expect(service().isConfigured, isTrue);
  });
}

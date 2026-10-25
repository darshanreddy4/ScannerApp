import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scanvault/features/qr/data/local_share_server.dart';
import 'package:scanvault/features/qr/domain/qr_payloads.dart';

Future<(int, List<int>)> _get(String url) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse(url));
    final res = await req.close();
    final bytes = <int>[];
    await for (final chunk in res) {
      bytes.addAll(chunk);
    }
    return (res.statusCode, bytes);
  } finally {
    client.close(force: true);
  }
}

Future<(int, String)> _post(String url, String body) async {
  final client = HttpClient();
  try {
    final req = await client.postUrl(Uri.parse(url));
    req.headers.contentType = ContentType('application', 'x-www-form-urlencoded');
    req.add(utf8.encode(body));
    final res = await req.close();
    final text = await res.transform(const Utf8Decoder(allowMalformed: true)).join();
    return (res.statusCode, text);
  } finally {
    client.close(force: true);
  }
}

String _form(String password) => 'password=${Uri.encodeQueryComponent(password)}';

void main() {
  late Directory tmp;
  late File file;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sv_qr');
    file = File('${tmp.path}/Contract Q3.pdf')..writeAsBytesSync(List.generate(5000, (i) => i % 251));
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  final server = LocalShareServerImpl(hostResolver: () async => '127.0.0.1');

  test('serves the file at the secret link and counts the download', () async {
    final handle = (await server.start(filePath: file.path, fileName: 'Contract Q3.pdf', mimeType: 'application/pdf')).valueOrNull!;
    final counts = <int>[];
    handle.downloads.listen(counts.add);

    final (status, body) = await _get(handle.url);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(status, 200);
    expect(body, file.readAsBytesSync());
    expect(counts, [1]);
    await handle.stop();
  });

  test('wrong token, wrong name and the bare root all return 404 without leaking the file', () async {
    final handle = (await server.start(filePath: file.path, fileName: 'a.pdf', mimeType: 'application/pdf')).valueOrNull!;
    final uri = Uri.parse(handle.url);

    expect((await _get('http://127.0.0.1:${uri.port}/')).$1, 404);
    expect((await _get('http://127.0.0.1:${uri.port}/deadbeef/a.pdf')).$1, 404);
    expect((await _get('http://127.0.0.1:${uri.port}${uri.pathSegments.first.isEmpty ? '' : '/${uri.pathSegments.first}'}/other.pdf')).$1, 404);
    await handle.stop();
  });

  test('each share gets a different unguessable token', () async {
    final a = (await server.start(filePath: file.path, fileName: 'a.pdf', mimeType: 'application/pdf')).valueOrNull!;
    final b = (await server.start(filePath: file.path, fileName: 'a.pdf', mimeType: 'application/pdf')).valueOrNull!;
    expect(Uri.parse(a.url).pathSegments.first.length, 32);
    expect(Uri.parse(a.url).pathSegments.first, isNot(Uri.parse(b.url).pathSegments.first));
    await a.stop();
    await b.stop();
  });

  test('the share stops by itself when the time runs out', () async {
    final handle = (await server.start(
      filePath: file.path,
      fileName: 'a.pdf',
      mimeType: 'application/pdf',
      ttl: const Duration(milliseconds: 200),
    )).valueOrNull!;
    await handle.done.timeout(const Duration(seconds: 3));
    await expectLater(_get(handle.url), throwsA(isA<SocketException>()));
  });

  test('stopping closes the port immediately', () async {
    final handle = (await server.start(filePath: file.path, fileName: 'a.pdf', mimeType: 'application/pdf')).valueOrNull!;
    final url = handle.url;
    await handle.stop();
    await expectLater(_get(url), throwsA(isA<SocketException>()));
  });

  test('reports a clear error when there is no Wi-Fi address', () async {
    final offline = LocalShareServerImpl(hostResolver: () async => null);
    final result = await offline.start(filePath: file.path, fileName: 'a.pdf', mimeType: 'application/pdf');
    expect(result.failureOrNull?.message, contains('Wi-Fi'));
  });

  test('reports an error for a missing file', () async {
    final result = await server.start(filePath: '${tmp.path}/nope.pdf', fileName: 'nope.pdf', mimeType: 'application/pdf');
    expect(result.isOk, isFalse);
  });

  group('password protection', () {
    Future<dynamic> protectedShare() async =>
        (await server.start(filePath: file.path, fileName: 'Contract Q3.pdf', mimeType: 'application/pdf', password: 'open sesame')).valueOrNull!;

    test('opening the link shows a password page and never the file', () async {
      final handle = await protectedShare();
      final (status, body) = await _get(handle.url);
      final page = utf8.decode(body, allowMalformed: true);

      expect(status, 200);
      expect(page, contains('type="password"'));
      expect(page, contains('Contract Q3.pdf'));
      expect(body.length, lessThan(3000), reason: 'the file is not in the response');
      await handle.stop();
    });

    test('the right password releases the file and counts one download', () async {
      final handle = await protectedShare();
      final counts = <int>[];
      handle.downloads.listen(counts.add);

      final client = HttpClient();
      final req = await client.postUrl(Uri.parse(handle.url));
      req.headers.contentType = ContentType('application', 'x-www-form-urlencoded');
      req.add(utf8.encode(_form('open sesame')));
      final res = await req.close();
      final bytes = <int>[];
      await for (final c in res) {
        bytes.addAll(c);
      }
      client.close(force: true);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(res.statusCode, 200);
      expect(res.headers.value('content-disposition'), contains('attachment'));
      expect(bytes, file.readAsBytesSync());
      expect(counts, [1]);
      await handle.stop();
    });

    test('a wrong password shows how many tries are left and does not leak the file', () async {
      final handle = await protectedShare();
      final (status, body) = await _post(handle.url, _form('nope'));

      expect(status, 200);
      expect(body, contains('Wrong password'));
      expect(body, contains('4 tries left'));
      expect(body.length, lessThan(3000));
      await handle.stop();
    });

    test('five wrong guesses lock the link, even for the right password', () async {
      final handle = await protectedShare();
      for (var i = 0; i < 5; i++) {
        await _post(handle.url, _form('guess$i'));
      }
      final (status, body) = await _post(handle.url, _form('open sesame'));

      expect(status, 403);
      expect(body, contains('Too many wrong attempts'));
      expect(body, isNot(contains('type="password"')));
      final (getStatus, _) = await _get(handle.url);
      expect(getStatus, 403);
      await handle.stop();
    });

    test('an oversized or missing password counts as wrong', () async {
      final handle = await protectedShare();
      expect((await _post(handle.url, _form('x' * 2000))).$2, contains('Wrong password'));
      expect((await _post(handle.url, 'other=1')).$2, contains('Wrong password'));
      await handle.stop();
    });

    test('POST is refused on a share without a password', () async {
      final open = (await server.start(filePath: file.path, fileName: 'a.pdf', mimeType: 'application/pdf')).valueOrNull!;
      expect((await _post(open.url, _form('x'))).$1, 404);
      await open.stop();
    });

    test('a file name is escaped in the page', () async {
      final handle = (await server.start(filePath: file.path, fileName: '<b>x</b>.pdf', mimeType: 'application/pdf', password: 'abcd')).valueOrNull!;
      final (_, body) = await _get(handle.url);
      final page = utf8.decode(body);
      expect(page, contains('&lt;b&gt;x&lt;&#47;b&gt;.pdf'));
      expect(page, isNot(contains('<b>x</b>')));
      await handle.stop();
    });
  });

  group('QrPayloads.wifi', () {
    test('builds the standard payload', () {
      expect(QrPayloads.wifi(ssid: 'Office', password: 'secret'), 'WIFI:T:WPA;S:Office;P:secret;;');
    });

    test('escapes reserved characters', () {
      expect(QrPayloads.wifi(ssid: r'My;Net:1', password: r'pa\ss,"w'), r'WIFI:T:WPA;S:My\;Net\:1;P:pa\\ss\,\"w;;');
    });

    test('open networks have no password and hidden networks are flagged', () {
      expect(QrPayloads.wifi(ssid: 'Guest', security: WifiSecurity.open), 'WIFI:T:nopass;S:Guest;;');
      expect(QrPayloads.wifi(ssid: 'X', password: 'p', hidden: true), 'WIFI:T:WPA;S:X;P:p;H:true;;');
    });
  });
}

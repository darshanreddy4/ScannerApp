import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:doculoom/app/di.dart';
import 'package:doculoom/core/error/result.dart';
import 'package:doculoom/core/theme/app_theme.dart';
import 'package:doculoom/features/contacts/domain/contact_parser.dart';
import 'package:doculoom/features/contacts/domain/contact_saver.dart';
import 'package:doculoom/features/export/domain/repositories/export_repository.dart';
import 'package:doculoom/features/qr/data/scan_history_store.dart';
import 'package:doculoom/features/qr/domain/qr_payloads.dart';
import 'package:doculoom/features/qr/domain/scan_services.dart';
import 'package:doculoom/features/qr/domain/scanned_code.dart';
import 'package:doculoom/features/qr/presentation/qr_scan_cubits.dart';
import 'package:doculoom/features/qr/presentation/qr_scan_page.dart';
import 'package:doculoom/features/scanner/data/datasources/camera_access.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _History implements ScanHistory {
  final items = <ScanRecord>[];
  var enabled = true;

  @override
  Future<List<ScanRecord>> list() async => [...items];

  @override
  Future<void> add(DetectedCode code, DateTime at) async {
    if (!enabled) return;
    items.removeWhere((r) => r.raw == code.raw);
    items.insert(0, ScanRecord(raw: code.raw, format: code.format, at: at));
  }

  @override
  Future<void> delete(String raw) async => items.removeWhere((r) => r.raw == raw);

  @override
  Future<void> clear() async => items.clear();

  @override
  Future<bool> isEnabled() async => enabled;

  @override
  Future<void> setEnabled(bool value) async => enabled = value;
}

class _Reader implements CodeImageReader {
  List<DetectedCode> result = const [];
  final paths = <String>[];

  @override
  Future<List<DetectedCode>> read(String path) async {
    paths.add(path);
    return result;
  }
}

class _Wifi implements WifiJoiner {
  WifiJoinResult result = WifiJoinResult.added;
  WifiNetwork? joined;

  @override
  Future<WifiJoinResult> join(WifiNetwork network) async {
    joined = network;
    return result;
  }
}

class _Opener implements LinkOpener {
  final opened = <String>[];
  bool ok = true;

  @override
  Future<bool> open(String uri) async {
    opened.add(uri);
    return ok;
  }
}

class _Contacts implements ContactSaver {
  ContactDraft? inserted;

  @override
  Future<bool> insert(ContactDraft draft) async {
    inserted = draft;
    return true;
  }
}

class _Share implements ShareService {
  String? text;

  @override
  Future<Result<void>> shareText({required String text, String? subject}) async {
    this.text = text;
    return const Ok(null);
  }

  @override
  Future<Result<void>> shareFile({required String path, required String mimeType, String? subject}) async => const Ok(null);

  @override
  Future<Result<void>> shareFiles({required List<String> paths, required String mimeType, String? subject}) async => const Ok(null);
}

class _Access implements CameraAccess {
  _Access(this.status0);
  CameraAccessStatus status0;
  var settingsOpened = 0;

  @override
  Future<CameraAccessStatus> status() async => status0;

  @override
  Future<CameraAccessStatus> request() async => status0;

  @override
  Future<bool> openSettings() async {
    settingsOpened++;
    return true;
  }
}

void main() {
  group('parseCode', () {
    test('web addresses become links; unsafe schemes stay text', () {
      expect(parseCode('https://example.com/a?b=1').kind, CodeKind.link);
      expect(parseCode('http://example.com').link, 'http://example.com');
      expect(parseCode('www.example.com/x').link, 'https://www.example.com/x');
      expect(parseCode('  https://example.com  ').link, 'https://example.com');
      expect(parseCode('https://example.com').host, 'example.com');
      for (final bad in [
        'javascript:alert(1)',
        'intent://x#Intent;end',
        'file:///etc/passwd',
        'https://exa mple.com',
        'see https://example.com now',
        'ftp://example.com',
      ]) {
        expect(parseCode(bad).kind, CodeKind.text, reason: bad);
        expect(parseCode(bad).link, isNull, reason: bad);
      }
    });

    test('Wi-Fi codes give the name, password, security and hidden flag', () {
      final c = parseCode('WIFI:T:WPA;S:Home Net;P:pass123;H:true;;');
      expect(c.kind, CodeKind.wifi);
      expect(c.wifi!.ssid, 'Home Net');
      expect(c.wifi!.password, 'pass123');
      expect(c.wifi!.security, WifiSecurity.wpa);
      expect(c.wifi!.hidden, isTrue);
      expect(c.summary, 'Home Net');
    });

    test('Wi-Fi codes handle escapes, other orders, open and WEP networks, and refuse a missing name', () {
      final escaped = parseCode(r'WIFI:S:My\;Net\:1;T:WPA;P:a\\b\"c;;').wifi!;
      expect(escaped.ssid, 'My;Net:1');
      expect(escaped.password, r'a\b"c');
      expect(parseCode('WIFI:T:nopass;S:Cafe;;').wifi!.security, WifiSecurity.open);
      expect(parseCode('WIFI:S:Cafe;;').wifi!.security, WifiSecurity.open);
      expect(parseCode('WIFI:S:Cafe;P:x;;').wifi!.security, WifiSecurity.wpa);
      expect(parseCode('WIFI:T:WEP;S:Old;P:12345;;').wifi!.security, WifiSecurity.wep);
      expect(parseCode('WIFI:T:WPA2-EAP;S:Work;P:x;;').wifi!.security, WifiSecurity.wpa);
      expect(parseCode('wifi:t:wpa;s:Lower;p:x;;').wifi!.ssid, 'Lower');
      expect(parseCode('WIFI:T:WPA;P:nope;;').kind, CodeKind.text);
      expect(parseCode('WIFI:S:"quoted";T:WPA;P:x;;').wifi!.ssid, 'quoted');
    });

    test('the Wi-Fi code the generator makes is read back the same', () {
      final payload = QrPayloads.wifi(ssid: r'A;B:C\D', password: 'p"w,d', security: WifiSecurity.wpa, hidden: true);
      final w = parseCode(payload).wifi!;
      expect((w.ssid, w.password, w.security, w.hidden), (r'A;B:C\D', 'p"w,d', WifiSecurity.wpa, true));
    });

    test('MECARD and vCard contacts', () {
      final m = parseCode(r'MECARD:N:Doe,John;TEL:+1 555 0100;TEL:555 0101;EMAIL:j@x.com;URL:https://x.com;ORG:Acme\; Inc;ADR:,,1 Main St,Town;;').contact!;
      expect(m.name, 'John Doe');
      expect(m.phones, ['+1 555 0100', '555 0101']);
      expect(m.emails, ['j@x.com']);
      expect(m.websites, ['https://x.com']);
      expect(m.organization, 'Acme; Inc');
      expect(m.address, '1 Main St, Town');

      final v = parseCode(
        'BEGIN:VCARD\r\nVERSION:3.0\r\nN:Roe;Jane;;;\r\nFN:Jane Roe\r\nORG:Globex;Sales\r\nTITLE:Manager\r\nTEL;TYPE=CELL:+44 20 7946 0000\r\nitem1.EMAIL:jane@globex.com\r\nURL:https://globex.com\r\nADR;TYPE=WORK:;;5 High St;Leeds;;LS1;UK\r\nNOTE:a long\r\n  note\r\nEND:VCARD',
      );
      expect(v.kind, CodeKind.contact);
      expect(v.contact!.name, 'Jane Roe');
      expect(v.contact!.organization, 'Globex, Sales');
      expect(v.contact!.title, 'Manager');
      expect(v.contact!.phones, ['+44 20 7946 0000']);
      expect(v.contact!.emails, ['jane@globex.com']);
      expect(v.contact!.address, '5 High St, Leeds, LS1, UK');
      expect(parseCode('BEGIN:VCARD\nEND:VCARD').kind, CodeKind.text);
      expect(parseCode('BEGIN:VCARD\nN:Only;Name;;;\nEND:VCARD').contact!.name, 'Name Only');
      expect(parseCode('MECARD:;;').kind, CodeKind.text);
    });

    test('email, phone, text message and location', () {
      final e = parseCode('mailto:me@x.com?subject=Hi%20there&body=Hello%0AWorld');
      expect((e.kind, e.address, e.subject, e.body), (CodeKind.email, 'me@x.com', 'Hi there', 'Hello\nWorld'));
      expect(parseCode('someone@example.org').kind, CodeKind.email);
      expect(parseCode('mailto:not an address').kind, CodeKind.text);

      expect(parseCode('tel:+1 (555) 010-0200').number, '+1 (555) 010-0200');
      expect(parseCode('tel:abc').kind, CodeKind.text);

      final s = parseCode('SMSTO:+15550100:Call me: soon');
      expect((s.kind, s.number, s.body), (CodeKind.sms, '+15550100', 'Call me: soon'));
      final s2 = parseCode('sms:+15550100?body=Hi%20you');
      expect((s2.number, s2.body), ('+15550100', 'Hi you'));
      expect(parseCode('sms:+15550100').body, isNull);

      final g = parseCode('geo:12.9716,77.5946?q=Bengaluru');
      expect((g.kind, g.latitude, g.longitude), (CodeKind.location, 12.9716, 77.5946));
      expect(g.geoUri, 'geo:12.9716,77.5946');
      expect(g.summary, '12.9716, 77.5946');
      expect(parseCode('geo:91,10').kind, CodeKind.text);
      expect(parseCode('geo:nonsense').kind, CodeKind.text);
    });

    test('product barcodes and plain text', () {
      expect(parseCode('5901234123457', format: 'ean13').kind, CodeKind.product);
      expect(parseCode('A123', format: 'code128').kind, CodeKind.product);
      expect(parseCode('hello', format: 'qrCode').kind, CodeKind.text);
      expect(parseCode('hello').kind, CodeKind.text);
      expect(parseCode('   ').kind, CodeKind.text);
      expect(parseCode('hello', format: 'qrCode').summary, 'hello');
    });
  });

  group('history store', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('keeps newest first, moves a repeat to the top and can be switched off', () async {
      final h = SharedPrefsScanHistory();
      expect(await h.list(), isEmpty);
      expect(await h.isEnabled(), isTrue);
      await h.add(const DetectedCode(raw: 'a', format: 'qrCode'), DateTime(2025, 1, 1));
      await h.add(const DetectedCode(raw: 'b'), DateTime(2025, 1, 2));
      await h.add(const DetectedCode(raw: 'a', format: 'qrCode'), DateTime(2025, 1, 3));
      final list = await h.list();
      expect([for (final r in list) r.raw], ['a', 'b']);
      expect(list.first.at, DateTime(2025, 1, 3));
      expect(list.first.format, 'qrCode');
      await h.setEnabled(false);
      await h.add(const DetectedCode(raw: 'c'), DateTime(2025, 1, 4));
      expect((await h.list()).length, 2);
      await h.setEnabled(true);
      await h.delete('a');
      expect([for (final r in await h.list()) r.raw], ['b']);
      await h.clear();
      expect(await h.list(), isEmpty);
    });

    test('is capped and ignores empty codes and damaged data', () async {
      final h = SharedPrefsScanHistory();
      for (var i = 0; i < ScanHistory.maxKept + 5; i++) {
        await h.add(DetectedCode(raw: 'c$i'), DateTime(2025, 1, 1).add(Duration(minutes: i)));
      }
      final list = await h.list();
      expect(list.length, ScanHistory.maxKept);
      expect(list.first.raw, 'c${ScanHistory.maxKept + 4}');
      await h.add(const DetectedCode(raw: '  '), DateTime(2025));
      expect((await h.list()).length, ScanHistory.maxKept);
      SharedPreferences.setMockInitialValues({'qr_scan_history': 'not json'});
      expect(await SharedPrefsScanHistory().list(), isEmpty);
    });
  });

  group('scan cubit', () {
    late _History history;
    late _Reader reader;
    late QrScanCubit cubit;

    setUp(() {
      history = _History();
      reader = _Reader();
      cubit = QrScanCubit(history: history, reader: reader, now: () => DateTime(2025, 5, 1));
    });
    tearDown(() => cubit.close());

    test('a detected code is understood, shown and kept in the history', () async {
      await cubit.onDetected(const [DetectedCode(raw: 'https://example.com', format: 'qrCode')]);
      expect(cubit.state.current!.kind, CodeKind.link);
      expect(history.items.single.raw, 'https://example.com');
      expect(history.items.single.at, DateTime(2025, 5, 1));
    });

    test('other codes are ignored while one is shown, and empty frames do nothing', () async {
      await cubit.onDetected(const []);
      await cubit.onDetected(const [DetectedCode(raw: '  ')]);
      expect(cubit.state.current, isNull);
      await cubit.onDetected(const [DetectedCode(raw: 'one')]);
      await cubit.onDetected(const [DetectedCode(raw: 'two')]);
      expect(cubit.state.current!.raw, 'one');
      expect(history.items.length, 1);
      cubit.dismiss();
      expect(cubit.state.current, isNull);
      await cubit.onDetected(const [DetectedCode(raw: 'two')]);
      expect(cubit.state.current!.raw, 'two');
    });

    test('nothing is kept when the history is off, but the code is still shown', () async {
      history.enabled = false;
      await cubit.onDetected(const [DetectedCode(raw: 'x')]);
      expect(cubit.state.current!.raw, 'x');
      expect(history.items, isEmpty);
    });

    test('a picture with a code shows it; one without says so', () async {
      reader.result = const [DetectedCode(raw: 'WIFI:S:a;;', format: 'qrCode')];
      await cubit.scanImage('/p.png');
      expect(reader.paths, ['/p.png']);
      expect(cubit.state.current!.kind, CodeKind.wifi);
      cubit.dismiss();
      reader.result = const [];
      await cubit.scanImage('/q.png');
      expect(cubit.state.current, isNull);
      expect(cubit.state.notice, contains('No QR code'));
      cubit.dismiss();
      expect(cubit.state.notice, isNull);
    });
  });

  group('pages', () {
    late _History history;
    late _Reader reader;
    late _Wifi wifi;
    late _Opener opener;
    late _Contacts contacts;
    late _Share share;
    late _Access access;
    final copied = <String>[];
    void Function(List<DetectedCode>)? detect;

    Widget fakeCamera(BuildContext context, void Function(List<DetectedCode>) onDetect) {
      detect = onDetect;
      return const ColoredBox(color: Colors.black);
    }

    Future<void> open(WidgetTester tester, Widget page, {double width = 400, CameraAccessStatus camera = CameraAccessStatus.granted}) async {
      tester.view.physicalSize = Size(width * 3, 800 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      history = _History();
      reader = _Reader();
      wifi = _Wifi();
      opener = _Opener();
      contacts = _Contacts();
      share = _Share();
      access = _Access(camera);
      copied.clear();
      detect = null;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await sl.reset();
      sl
        ..registerSingleton<ScanHistory>(history)
        ..registerSingleton<CodeImageReader>(reader)
        ..registerSingleton<WifiJoiner>(wifi)
        ..registerSingleton<LinkOpener>(opener)
        ..registerSingleton<ContactSaver>(contacts)
        ..registerSingleton<ShareService>(share)
        ..registerSingleton<CameraAccess>(access);
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: page));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }

    Future<void> scan(WidgetTester tester, String raw, {String format = 'qrCode'}) async {
      detect!([DetectedCode(raw: raw, format: format)]);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pumpAndSettle();
    }

    Future<void> tapAction(WidgetTester tester, String label) async {
      final f = find.text(label);
      await tester.ensureVisible(f);
      await tester.pump();
      await tester.tap(f);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pumpAndSettle();
    }

    testWidgets('a link is shown with its address and opened on request', (tester) async {
      await open(tester, QrScanPage(cameraBuilder: fakeCamera));
      expect(find.textContaining('Point the camera'), findsOneWidget);
      await scan(tester, 'https://example.com/pay');
      expect(find.text('Web link'), findsOneWidget);
      expect(find.text('https://example.com/pay'), findsOneWidget);
      expect(find.textContaining('goes to example.com'), findsOneWidget);
      await tapAction(tester, 'Open link');
      expect(opener.opened, ['https://example.com/pay']);
      await tapAction(tester, 'Copy link');
      expect(copied, ['https://example.com/pay']);
      expect(history.items.single.raw, 'https://example.com/pay');
    });

    testWidgets('an unencrypted link is warned about, and a failure to open is explained', (tester) async {
      await open(tester, QrScanPage(cameraBuilder: fakeCamera));
      await scan(tester, 'http://example.com');
      expect(find.textContaining('not encrypted'), findsOneWidget);
      opener.ok = false;
      await tapAction(tester, 'Open link');
      expect(find.text('Could not open the link.'), findsOneWidget);
    });

    testWidgets('closing the result lets the next code be scanned', (tester) async {
      await open(tester, QrScanPage(cameraBuilder: fakeCamera));
      await scan(tester, 'first');
      expect(find.text('Text'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text('Text'), findsNothing);
      await scan(tester, 'second');
      expect(find.text('second'), findsOneWidget);
      expect(history.items.map((r) => r.raw), ['second', 'first']);
    });

    testWidgets('a Wi-Fi code joins the network, and hides the password until asked', (tester) async {
      await open(tester, QrScanPage(cameraBuilder: fakeCamera));
      await scan(tester, 'WIFI:T:WPA;S:Home;P:secret99;;');
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('secret99'), findsNothing);
      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      expect(find.text('secret99'), findsOneWidget);
      await tapAction(tester, 'Join network');
      expect(wifi.joined!.ssid, 'Home');
      expect(wifi.joined!.password, 'secret99');
      expect(find.textContaining('Network added'), findsOneWidget);
      await tapAction(tester, 'Copy password');
      expect(copied, ['secret99']);
    });

    testWidgets('where the phone only opens Wi-Fi settings, the password is copied for pasting', (tester) async {
      await open(tester, QrScanPage(cameraBuilder: fakeCamera));
      wifi.result = WifiJoinResult.openedSettings;
      await scan(tester, 'WIFI:T:WPA;S:Home;P:secret99;;');
      await tapAction(tester, 'Join network');
      expect(copied, ['secret99']);
      expect(find.textContaining('password is copied'), findsOneWidget);
    });

    testWidgets('a failed or cancelled join says what to do, or nothing', (tester) async {
      await open(tester, QrScanPage(cameraBuilder: fakeCamera));
      wifi.result = WifiJoinResult.failed;
      await scan(tester, 'WIFI:S:Open;;');
      await tapAction(tester, 'Join network');
      expect(find.textContaining('could not add the network'), findsOneWidget);
      expect(find.text('Copy name'), findsOneWidget);
    });

    testWidgets('a contact code adds a contact', (tester) async {
      await open(tester, QrScanPage(cameraBuilder: fakeCamera));
      await scan(tester, 'MECARD:N:Doe,John;TEL:555 0100;EMAIL:j@x.com;;');
      expect(find.text('John Doe'), findsOneWidget);
      await tapAction(tester, 'Add contact');
      expect(contacts.inserted!.name, 'John Doe');
      expect(contacts.inserted!.phones, ['555 0100']);
    });

    testWidgets('phone numbers can be called, texted or saved', (tester) async {
      await open(tester, QrScanPage(cameraBuilder: fakeCamera));
      await scan(tester, 'tel:+1 (555) 010-0200');
      await tapAction(tester, 'Call');
      await tapAction(tester, 'Send message');
      await tapAction(tester, 'Add contact');
      expect(opener.opened, ['tel:+15550100200', 'sms:+15550100200']);
      expect(contacts.inserted!.phones, ['+1 (555) 010-0200']);
    });

    testWidgets('email and text message codes are opened with their subject and body', (tester) async {
      await open(tester, QrScanPage(cameraBuilder: fakeCamera));
      await scan(tester, 'mailto:me@x.com?subject=Hi%20there&body=A%26B');
      await tapAction(tester, 'Write email');
      expect(opener.opened.single, 'mailto:me@x.com?subject=Hi%20there&body=A%26B');
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      await scan(tester, 'SMSTO:+15550100:On my way');
      await tapAction(tester, 'Send message');
      expect(opener.opened.last, 'sms:+15550100?body=On%20my%20way');
    });

    testWidgets('a location opens in maps, with a web map as a fallback', (tester) async {
      await open(tester, QrScanPage(cameraBuilder: fakeCamera));
      await scan(tester, 'geo:12.5,77.25');
      await tapAction(tester, 'Open in maps');
      expect(opener.opened, ['geo:12.5,77.25']);
      opener.ok = false;
      await tapAction(tester, 'Open in maps');
      expect(opener.opened.last, 'https://www.google.com/maps?q=12.5,77.25');
    });

    testWidgets('text and product barcodes can be copied and shared', (tester) async {
      await open(tester, QrScanPage(cameraBuilder: fakeCamera));
      await scan(tester, '5901234123457', format: 'ean13');
      expect(find.text('Product barcode'), findsOneWidget);
      expect(find.text('EAN-13'), findsOneWidget);
      await tapAction(tester, 'Copy');
      expect(copied, ['5901234123457']);
      await tapAction(tester, 'Share');
      expect(share.text, '5901234123457');
    });

    testWidgets('a picture from the gallery is read, and one without a code is explained', (tester) async {
      var path = '/a.png';
      await open(tester, QrScanPage(cameraBuilder: fakeCamera, pickPicture: () async => path));
      reader.result = const [DetectedCode(raw: 'https://example.com', format: 'qrCode')];
      await tester.tap(find.byTooltip('Read from a picture'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pumpAndSettle();
      expect(reader.paths, ['/a.png']);
      expect(find.text('Web link'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      reader.result = const [];
      path = '/b.png';
      await tester.tap(find.byTooltip('Read from a picture'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pumpAndSettle();
      expect(find.textContaining('No QR code or barcode was found'), findsOneWidget);
    });

    testWidgets('without the camera the page explains and still offers pictures', (tester) async {
      await open(tester, QrScanPage(cameraBuilder: fakeCamera), camera: CameraAccessStatus.denied);
      expect(detect, isNull);
      expect(find.text('The camera is needed to read codes.'), findsOneWidget);
      expect(find.byTooltip('Read from a picture'), findsOneWidget);
      access.status0 = CameraAccessStatus.granted;
      await tester.tap(find.text('Allow camera'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
      expect(detect, isNotNull);
    });

    testWidgets('a blocked camera sends the person to Settings', (tester) async {
      await open(tester, QrScanPage(cameraBuilder: fakeCamera), camera: CameraAccessStatus.blocked);
      await tester.tap(find.text('Open Settings'));
      await tester.pump();
      expect(access.settingsOpened, 1);
    });

    for (final width in [320.0, 400.0, 900.0]) {
      testWidgets('long results fit and scroll at ${width.toInt()} px', (tester) async {
        await open(tester, QrScanPage(cameraBuilder: fakeCamera), width: width);
        await scan(
          tester,
          'BEGIN:VCARD\nFN:A Person With A Very Long Name Indeed\nORG:An Organisation With A Long Name Ltd\nTITLE:Chief Executive And Head Of Everything\nTEL:+44 20 7946 0000\nTEL:+44 20 7946 0001\nEMAIL:a.very.long.address@a-very-long-domain-name.example.com\nURL:https://a-very-long-domain-name.example.com/with/a/long/path\nADR:;;12 A Long Street Name;A Town With A Long Name;;AB1 2CD;United Kingdom\nEND:VCARD',
        );
        expect(find.text('Add contact'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the history page shows kept scans and the switch', (tester) async {
      await open(tester, const QrHistoryPage());
      history.items
        ..add(ScanRecord(raw: 'https://example.com', format: 'qrCode', at: DateTime(2025, 3, 4, 9, 5)))
        ..add(ScanRecord(raw: 'WIFI:S:Home;P:x;;', format: 'qrCode', at: DateTime(2025, 3, 3)));
      final cubit = tester.element(find.byType(Scaffold).first).read<QrHistoryCubit>();
      await tester.runAsync(cubit.load);
      await tester.pump();
      expect(find.text('https://example.com'), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      expect(find.textContaining('Web link'), findsOneWidget);

      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(find.text('Join network'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Switch));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
      expect(history.enabled, isFalse);
    });

    testWidgets('deleting one scan, or clearing all, updates the list', (tester) async {
      await open(tester, const QrHistoryPage());
      history.items
        ..add(ScanRecord(raw: 'one', format: 'qrCode', at: DateTime(2025, 3, 4)))
        ..add(ScanRecord(raw: 'two', format: 'qrCode', at: DateTime(2025, 3, 3)));
      final cubit = tester.element(find.byType(Scaffold).first).read<QrHistoryCubit>();
      await tester.runAsync(cubit.load);
      await tester.pump();
      await tester.tap(find.byTooltip('Delete').first);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
      expect(history.items.map((r) => r.raw), ['two']);
      await tester.tap(find.byTooltip('Clear history'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Clear'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pumpAndSettle();
      expect(history.items, isEmpty);
      expect(find.textContaining('No scans yet'), findsOneWidget);
    });
  });
}

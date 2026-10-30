import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:doculoom/app/di.dart';
import 'package:doculoom/core/error/failures.dart';
import 'package:doculoom/core/error/result.dart';
import 'package:doculoom/core/theme/app_theme.dart';
import 'package:doculoom/features/contacts/domain/contact_parser.dart';
import 'package:doculoom/features/contacts/domain/contact_saver.dart';
import 'package:doculoom/features/contacts/presentation/contact_page.dart';
import 'package:doculoom/features/export/domain/repositories/export_repository.dart';

class _Share implements ShareService {
  final shared = <({String path, String mime, String content})>[];
  Failure? failure;

  @override
  Future<Result<void>> shareFile({required String path, required String mimeType, String? subject}) async {
    if (failure != null) return Err(failure!);
    shared.add((path: path, mime: mimeType, content: File(path).readAsStringSync()));
    return const Ok(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Saver implements ContactSaver {
  final saved = <ContactDraft>[];
  bool available = true;

  @override
  Future<bool> insert(ContactDraft draft) async {
    saved.add(draft);
    return available;
  }
}

const _card = '''
Blue Ocean Consulting
Tara Dsouza
Head of Sales
+971 4 123 4567
tara@blueocean.ae
www.blueocean.ae
''';

void main() {
  late Directory work;
  late _Share share;
  late _Saver saver;

  setUp(() async {
    work = Directory.systemTemp.createTempSync('sv_contact');
    share = _Share();
    await sl.reset();
    saver = _Saver();
    sl.registerSingleton<ShareService>(share);
    sl.registerSingleton<ContactSaver>(saver);
  });
  tearDown(() => work.deleteSync(recursive: true));

  Future<void> open(WidgetTester tester, String text) async {
    tester.view.physicalSize = const Size(400 * 3, 1000 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ContactPage(text: text, workDir: () async => work),
      ),
    );
    await tester.pump();
  }

  String value(WidgetTester tester, String key) => tester.widget<TextField>(find.byKey(ValueKey(key))).controller!.text;

  Future<void> pumpAsync(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await tester.pump();
    }
  }

  testWidgets('the card is read into the fields', (tester) async {
    await open(tester, _card);
    expect(value(tester, 'contact-name'), 'Tara Dsouza');
    expect(value(tester, 'contact-title'), 'Head of Sales');
    expect(value(tester, 'contact-org'), 'Blue Ocean Consulting');
    expect(value(tester, 'contact-phones'), '+971 4 123 4567');
    expect(value(tester, 'contact-emails'), 'tara@blueocean.ae');
    expect(value(tester, 'contact-sites'), 'https://www.blueocean.ae');
    expect(find.textContaining('Check what was read'), findsOneWidget);
  });

  testWidgets('corrections are used, and the contact is shared as a vCard file named after the person', (tester) async {
    await open(tester, _card);
    await tester.enterText(find.byKey(const ValueKey('contact-name')), 'Tara D\'Souza');
    await tester.enterText(find.byKey(const ValueKey('contact-phones')), '+971 4 123 4567\n+971 50 765 4321');
    await tester.ensureVisible(find.byKey(const ValueKey('contact-share')));
    await tester.tap(find.byKey(const ValueKey('contact-share')));
    await pumpAsync(tester);

    final sent = share.shared.single;
    expect(sent.mime, 'text/vcard');
    expect(p.basename(sent.path), 'Tara_DSouza.vcf');
    expect(p.dirname(sent.path), p.join(work.path, 'exports'));
    expect(sent.content, contains('FN:Tara D\'Souza'));
    expect(sent.content, contains('TEL;TYPE=VOICE:+971 4 123 4567\r\n'));
    expect(sent.content, contains('TEL;TYPE=VOICE:+971 50 765 4321\r\n'));
    expect(sent.content, contains('EMAIL;TYPE=INTERNET:tara@blueocean.ae'));
    expect(sent.content, contains('ORG:Blue Ocean Consulting'));
  });

  testWidgets('text with no contact details says so, and sharing nothing is refused', (tester) async {
    await open(tester, 'Welcome to the annual meeting');
    expect(find.textContaining('No name, number or email was found'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('contact-org')), '');
    for (final k in ['contact-name', 'contact-title', 'contact-org', 'contact-phones', 'contact-emails', 'contact-sites', 'contact-address']) {
      await tester.enterText(find.byKey(ValueKey(k)), '');
    }
    await tester.ensureVisible(find.byKey(const ValueKey('contact-share')));
    await tester.tap(find.byKey(const ValueKey('contact-share')));
    await pumpAsync(tester);
    expect(share.shared, isEmpty);
    expect(find.textContaining('Add a name, a phone number or an email first'), findsOneWidget);
  });

  testWidgets('details typed by hand can still be shared when nothing was read', (tester) async {
    await open(tester, '');
    await tester.enterText(find.byKey(const ValueKey('contact-phones')), '+1 212 555 0100');
    await tester.ensureVisible(find.byKey(const ValueKey('contact-share')));
    await tester.tap(find.byKey(const ValueKey('contact-share')));
    await pumpAsync(tester);
    expect(share.shared.single.content, contains('FN:+1 212 555 0100'));
    expect(p.basename(share.shared.single.path), 'contact.vcf');
  });

  testWidgets('Save to phone contacts hands the corrected details to the phone, without sharing a file', (tester) async {
    await open(tester, _card);
    await tester.enterText(find.byKey(const ValueKey('contact-name')), 'Tara D\'Souza');
    await tester.enterText(find.byKey(const ValueKey('contact-phones')), '+971 4 123 4567\n+971 50 765 4321');
    await tester.ensureVisible(find.byKey(const ValueKey('contact-save')));
    await tester.tap(find.byKey(const ValueKey('contact-save')));
    await pumpAsync(tester);

    final d = saver.saved.single;
    expect(d.name, 'Tara D\'Souza');
    expect(d.phones, ['+971 4 123 4567', '+971 50 765 4321']);
    expect(d.emails, ['tara@blueocean.ae']);
    expect(d.organization, 'Blue Ocean Consulting');
    expect(share.shared, isEmpty);
  });

  testWidgets('Save to phone contacts with nothing filled in is refused', (tester) async {
    await open(tester, '');
    await tester.ensureVisible(find.byKey(const ValueKey('contact-save')));
    await tester.tap(find.byKey(const ValueKey('contact-save')));
    await pumpAsync(tester);
    expect(saver.saved, isEmpty);
    expect(find.textContaining('Add a name, a phone number or an email first'), findsOneWidget);
  });

  testWidgets('when the phone cannot open a Contacts screen the contact file is shared instead, and says so', (tester) async {
    saver.available = false;
    await open(tester, _card);
    await tester.ensureVisible(find.byKey(const ValueKey('contact-save')));
    await tester.tap(find.byKey(const ValueKey('contact-save')));
    await pumpAsync(tester);
    expect(saver.saved, hasLength(1));
    expect(share.shared.single.mime, 'text/vcard');
    expect(find.textContaining('No Contacts app could be opened'), findsOneWidget);
  });

  testWidgets('a failure from the share sheet is shown', (tester) async {
    share.failure = const ExportFailure('Sharing is not available.');
    await open(tester, _card);
    await tester.ensureVisible(find.byKey(const ValueKey('contact-share')));
    await tester.tap(find.byKey(const ValueKey('contact-share')));
    await pumpAsync(tester);
    expect(find.textContaining('Sharing is not available'), findsOneWidget);
  });

  testWidgets('Copy details puts the plain details on the clipboard', (tester) async {
    String? clip;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clip = (call.arguments as Map)['text'] as String?;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await open(tester, _card);
    await tester.ensureVisible(find.byKey(const ValueKey('contact-copy')));
    await tester.tap(find.byKey(const ValueKey('contact-copy')));
    await tester.pump();
    expect(clip, allOf(contains('Tara Dsouza'), contains('+971 4 123 4567'), contains('tara@blueocean.ae')));
  });

  testWidgets('fits a small phone with large text', (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 568 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(320, 568), textScaler: TextScaler.linear(1.3)),
        child: MaterialApp(
          theme: AppTheme.light(),
          home: ContactPage(text: _card, workDir: () async => work),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

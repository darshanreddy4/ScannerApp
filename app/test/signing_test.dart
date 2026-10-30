import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:doculoom/features/signing/data/cms.dart';
import 'package:doculoom/features/signing/data/pdf_signing.dart';
import 'package:doculoom/features/signing/data/pkcs12.dart';
import 'package:doculoom/features/signing/data/signing_service.dart';
import 'package:doculoom/features/signing/presentation/certificate_sign_page.dart';

const _dir = 'test/fixtures/signing';

Uint8List _fixture(String name) => File('$_dir/$name').readAsBytesSync();
SigningCredentials _cred(String name) => readPkcs12(_fixture('$name.p12'), 'secret');

Future<Uint8List> _tablePdf() async {
  final doc = pw.Document();
  doc.addPage(pw.Page(build: (_) => pw.Text('Contract')));
  doc.addPage(pw.Page(build: (_) => pw.Text('Page two')));
  return Uint8List.fromList(await doc.save());
}

void main() {
  group('PKCS#12', () {
    for (final f in ['rsa_legacy', 'rsa_aes', 'ec_legacy', 'ec384', 'java']) {
      test('reads $f and rejects a wrong password', () {
        final c = _cred(f);
        expect(c.key.matches(c.certificate), isTrue);
        expect(c.certificate.validAt(DateTime.now()), isTrue);
        expect(() => readPkcs12(_fixture('$f.p12'), 'wrong'), throwsA(isA<WrongCertificatePasswordException>()));
      });
    }

    test('describes the certificate', () {
      final c = _cred('rsa_legacy');
      expect(c.certificate.subject.display, 'Max Mustermann');
      expect(c.certificate.subject.country, 'DE');
      expect(c.certificate.selfSigned, isTrue);
      expect(c.certificate.publicKey.description, 'RSA 2048 bit');
      expect(_cred('ec384').certificate.publicKey.description, 'ECDSA P-384');
    });

    test('a file that is not a certificate is refused', () {
      expect(() => readPkcs12(Uint8List.fromList([1, 2, 3, 4]), 'x'), throwsA(isA<Pkcs12Exception>()));
    });
  });

  group('CMS', () {
    for (final f in ['rsa_legacy', 'ec_legacy', 'ec384', 'java']) {
      test('$f signs and verifies', () {
        final content = Uint8List.fromList(List.generate(5000, (i) => (i * 7) % 251));
        final sig = createCadesSignature([content.sublist(0, 2000), content.sublist(2000)], _cred(f));
        final parsed = CmsSignature.parse(sig);
        final r = parsed.verify([content]);
        expect((r.digestMatches, r.signatureValid), (true, true));
        final other = Uint8List.fromList(content)..[10] ^= 1;
        expect(parsed.verify([other]).digestMatches, isFalse);
      });
    }
  });

  group('signing a PDF', () {
    late Uint8List table;
    final stream = _fixture('xrefstream.pdf');
    final sources = <String, Uint8List>{
      'xref stream': stream,
      'object streams': File('test/fixtures/pdf_security/plain_objstm.pdf').readAsBytesSync(),
      'linearized': File('test/fixtures/pdf_security/plain_linearized.pdf').readAsBytesSync(),
    };

    setUpAll(() async => table = await _tablePdf());

    test('an unsigned PDF has no signatures and two pages', () {
      expect(checkPdfSignatures(table), isEmpty);
      expect(pdfPageCount(table), 2);
    });

    for (final f in ['rsa_legacy', 'ec_legacy', 'ec384']) {
      test('$f: sign, then sign again', () {
        final one = signPdf(
          table,
          _cred(f),
          options: const PdfSignOptions(reason: 'I agree', location: 'Berlin'),
        );
        expect(one.sublist(0, table.length), table, reason: 'the original bytes are untouched');
        final r = checkPdfSignatures(one).single;
        expect(r.state, SignatureState.valid);
        expect(r.reason, 'I agree');
        expect(r.location, 'Berlin');
        expect(r.signer, _cred(f).certificate.subject.display);
        expect(r.selfSigned, isTrue);
        expect(r.certificateValidWhenSigned, isTrue);

        final two = signPdf(one, _cred(f), options: const PdfSignOptions(pageIndex: 0, position: SignaturePosition.topLeft, visible: false));
        expect(checkPdfSignatures(two).map((e) => e.state), [SignatureState.changedAfter, SignatureState.valid]);
      });
    }

    for (final e in sources.entries) {
      test('signs a PDF with ${e.key}', () {
        final out = signPdf(e.value, _cred('rsa_legacy'));
        expect(checkPdfSignatures(out).single.state, SignatureState.valid);
        expect(pdfPageCount(out), pdfPageCount(e.value));
      });
    }

    test('a changed file is noticed', () {
      final one = signPdf(table, _cred('ec_legacy'));
      final altered = Uint8List.fromList(one)..[12] ^= 0xFF;
      expect(checkPdfSignatures(altered).single.state, SignatureState.altered);
      final appended = Uint8List.fromList([...one, ...'\n% more'.codeUnits]);
      expect(checkPdfSignatures(appended).single.state, SignatureState.changedAfter);
    });

    test('a signature made by another program is read, and its change noticed', () {
      final bytes = _fixture('pyh_signed.pdf');
      final r = checkPdfSignatures(bytes).single;
      expect(r.state, SignatureState.valid);
      expect(r.signer, 'Max Mustermann');
      expect(r.reason, 'Third party');
      expect(r.location, 'Test');
      expect(r.hash, 'SHA-256');
      expect(checkPdfSignatures(Uint8List.fromList(bytes)..[100] ^= 0xFF).single.state, isNot(SignatureState.valid));
    });

    test('the page can be chosen from the end or the start; a missing page is refused', () {
      final one = signPdf(table, _cred('rsa_legacy'), options: const PdfSignOptions(pageIndex: 0));
      expect(checkPdfSignatures(one).single.state, SignatureState.valid);
      expect(() => signPdf(table, _cred('rsa_legacy'), options: const PdfSignOptions(pageIndex: 5)), throwsA(isA<SigningException>()));
    });

    test('a password protected PDF is refused, and not read as signed', () {
      final locked = File('test/fixtures/pdf_security/aes256.pdf').readAsBytesSync();
      expect(() => signPdf(locked, _cred('rsa_legacy')), throwsA(isA<SigningException>()));
      expect(pdfPageCount(locked), 0);
    });

    test('something that is not a PDF is refused', () {
      expect(() => signPdf(Uint8List.fromList('hello'.codeUnits), _cred('rsa_legacy')), throwsA(isA<SigningException>()));
    });
  });

  group('service', () {
    test('unlock tells wrong passwords from other problems', () {
      final ok = unlockCertificate(UnlockRequest(_fixture('rsa_aes.p12'), 'secret'));
      expect(ok.info!.subject, 'Max Mustermann');
      expect(ok.info!.validNow, isTrue);
      final wrong = unlockCertificate(UnlockRequest(_fixture('rsa_aes.p12'), 'nope'));
      expect((wrong.info, wrong.wrongPassword), (null, true));
      final junk = unlockCertificate(UnlockRequest(Uint8List.fromList([9, 9, 9]), 'x'));
      expect(junk.info, isNull);
      expect(junk.wrongPassword, isFalse);
      expect(junk.problem, isNotNull);
    });

    test('signing with a wrong password gives a message, not an exception', () {
      final r = signWithCertificate(
        SignRequest(pdf: _fixture('xrefstream.pdf'), certificate: _fixture('ec384.p12'), password: 'bad', options: const PdfSignOptions()),
      );
      expect(r.bytes, isNull);
      expect(r.problem, 'The password is not right.');
    });

    test('check reports an unreadable file as a problem', () {
      expect(checkPdf(Uint8List.fromList([1, 2, 3])).problem, isNotNull);
    });
  });

  group('page', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('sv_sign'));
    tearDown(() => tmp.deleteSync(recursive: true));

    Future<void> settle(WidgetTester tester, bool Function() done) async {
      for (var i = 0; i < 400 && !done(); i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
    }

    Future<void> tapKey(WidgetTester tester, String key) async {
      final f = find.byKey(ValueKey(key));
      await tester.scrollUntilVisible(f, 150, scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(f);
      await tester.pump();
      await tester.tap(f);
    }

    for (final size in [const Size(320, 700), const Size(900, 1600)]) {
      testWidgets('check, unlock and sign at ${size.width.toInt()} px', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            home: CertificateSignPage(
              pickPdf: () async => '$_dir/pyh_signed.pdf',
              pickCertificate: () async => '$_dir/ec_legacy.p12',
              workDir: () async => tmp,
            ),
          ),
        );
        await tester.tap(find.byKey(const ValueKey('choose-pdf')));
        await settle(tester, () => find.text('Signatures in this PDF').evaluate().isNotEmpty);
        expect(find.text('Signature intact. The file has not changed since it was signed.'), findsOneWidget);
        expect(find.text('Max Mustermann'), findsOneWidget);

        await tapKey(tester, 'choose-certificate');
        await settle(tester, () => find.byKey(const ValueKey('certificate-password')).evaluate().isNotEmpty);

        await tester.enterText(find.byKey(const ValueKey('certificate-password')), 'wrong');
        await tapKey(tester, 'unlock-certificate');
        await settle(tester, () => find.text('The password is not right.').evaluate().isNotEmpty);
        expect(find.text('The password is not right.'), findsOneWidget);

        await tester.enterText(find.byKey(const ValueKey('certificate-password')), 'secret');
        await tapKey(tester, 'unlock-certificate');
        await settle(tester, () => find.byKey(const ValueKey('sign-pdf')).evaluate().isNotEmpty && find.text('How the signature looks').evaluate().isNotEmpty);
        expect(find.text('How the signature looks'), findsOneWidget);

        await tapKey(tester, 'sign-pdf');
        final out = File('${tmp.path}/signed/pyh_signed.pdf');
        await settle(tester, () => out.existsSync());
        for (var i = 0; i < 40; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
          await tester.pump();
        }
        await tester.scrollUntilVisible(find.text('Signed. The new file:'), 200, scrollable: find.byType(Scrollable).first);
        expect(find.text('Signed. The new file:'), findsOneWidget);

        expect(out.existsSync(), isTrue);
        final reports = checkPdfSignatures(out.readAsBytesSync());
        expect(reports.map((e) => e.state), [SignatureState.changedAfter, SignatureState.valid]);
        expect(reports.last.signer, isNotEmpty);
        await tester.scrollUntilVisible(find.byKey(const ValueKey('certificate-password')), -200, scrollable: find.byType(Scrollable).first);
        expect(tester.widget<TextField>(find.byKey(const ValueKey('certificate-password'))).controller!.text, isEmpty);
        expect(tester.takeException(), isNull);
      });
    }
  });
}

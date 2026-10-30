import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:doculoom/app/di.dart';
import 'package:doculoom/core/error/result.dart';
import 'package:doculoom/core/theme/app_theme.dart';
import 'package:doculoom/features/export/domain/repositories/export_repository.dart';
import 'package:doculoom/features/qr/domain/payments.dart';
import 'package:doculoom/features/qr/domain/scan_services.dart';
import 'package:doculoom/features/qr/domain/scanned_code.dart';
import 'package:doculoom/features/qr/presentation/code_result_card.dart';
import 'package:doculoom/features/qr/presentation/qr_generator_page.dart';
import 'package:qr_flutter/qr_flutter.dart';

const _epc = 'BCD\n001\n1\nSCT\nBHBLDEHHXXX\nWikimedia Fördergesellschaft\nDE33100205000001194700\nEUR123.45\n\n\nSpenden und Mitgliedsbeiträge';

String _swiss({String amount = '1949.75'}) => [
  'SPC',
  '0200',
  '1',
  'CH4431999123000889012',
  'S',
  'Robert Schneider AG',
  'Rue du Lac',
  '1268',
  '2501',
  'Biel',
  'CH',
  '',
  '',
  '',
  '',
  '',
  '',
  '',
  amount,
  'CHF',
  '',
  '',
  '',
  '',
  '',
  '',
  '',
  'QRR',
  '210000000003139471430009017',
  'Order of 15 June 2020',
  'EPD',
].join('\n');

class _Opener implements LinkOpener {
  @override
  Future<bool> open(String uri) async => true;
}

class _Share implements ShareService {
  @override
  Future<Result<void>> shareText({required String text, String? subject}) async => const Ok(null);
  @override
  Future<Result<void>> shareFile({required String path, required String mimeType, String? subject}) async => const Ok(null);
  @override
  Future<Result<void>> shareFiles({required List<String> paths, required String mimeType, String? subject}) async => const Ok(null);
}

void main() {
  group('IBAN', () {
    test('valid and invalid numbers', () {
      for (final ok in [
        'DE33100205000001194700',
        'de33 1002 0500 0001 1947 00',
        'CH4431999123000889012',
        'GB82WEST12345698765432',
        'FR1420041010050500013M02606',
        'SA0380000000608010167519',
      ]) {
        expect(isValidIban(ok), isTrue, reason: ok);
      }
      for (final bad in [
        '',
        'DE33100205000001194701',
        'DE3310020500000119470',
        'XX00',
        'GB82WEST1234569876543',
        '12345678901234',
        'DE89 3704 0044 0532 0130 0X',
      ]) {
        expect(isValidIban(bad), isFalse, reason: bad);
      }
    });

    test('is checked as it is typed, and the problem is named', () {
      IbanCheck c(String s) => checkIban(s);
      expect(c('').status, IbanStatus.empty);
      expect(c('D').status, IbanStatus.tooShort);
      expect(c('1').status, IbanStatus.badStart);
      expect(c('DE').status, IbanStatus.tooShort);
      expect(c('DEXX').status, IbanStatus.badStart);
      expect(c('PT50 0033 1234 5678 9012 3456').status, IbanStatus.tooShort, reason: 'a Portuguese IBAN has 25 characters');
      expect(c('PT50 0033 1234 5678 9012 3456 7').status, IbanStatus.badCheck);
      expect(c('PT50 0033 1234 5678 9012 3456 78').status, IbanStatus.tooLong);
      expect(c('DE89 3704 0044 0532 0130 00').valid, isTrue);
      expect(c('DE89 3704 0044 0532 0130 01').status, IbanStatus.badCheck);
      expect(c('de89-3704-0044-0532-0130-00').valid, isTrue, reason: 'dashes and capitals do not matter');
      expect((c('DE89 3704 0044 0532 0130 00').countryName, c('DE89 3704 0044 0532 0130 00').expectedLength), ('Germany', 22));
      expect(c('DE89 3704 0044 0532 0130 00').sepa, isTrue);
      expect(c('SA0380000000608010167519').sepa, isFalse);
      expect(c('SA0380000000608010167519').valid, isTrue);
      expect(c('XX12 3456 7890 1234').expectedLength, isNull);
      expect(ibanProblemValues('PT50 0033 1234 5678 9012 3456'), {'country': 'Portugal', 'n': 25, 'm': 24});
      expect(ibanProblem('PT50 0033 1234 5678 9012 3456'), 'An IBAN from {country} has {n} characters; you typed {m}.');
      expect(ibanProblem('DE89 3704 0044 0532 0130 00'), isNull);
      expect(ibanProblem(''), 'Enter the IBAN.');
    });

    test('is written in groups of four', () {
      expect(formatIban('de33100205000001194700'), 'DE33 1002 0500 0001 1947 00');
      expect(formatIban('AB12'), 'AB12');
    });
  });

  group('amounts', () {
    test('are cleaned to two decimals, or refused', () {
      expect(normalizeAmount('12'), '12.00');
      expect(normalizeAmount('12,5'), '12.50');
      expect(normalizeAmount(' 1234.56 '), '1234.56');
      expect(normalizeAmount('0.01'), '0.01');
      for (final bad in ['', '0', '0.00', '-5', '12.345', 'abc', '1000000000', '1.234', '1,234', '1,23.45', '12,', '1..2']) {
        expect(normalizeAmount(bad), isNull, reason: bad);
      }
    });

    test('thousands separators are understood when they cannot be mistaken for cents', () {
      expect(normalizeAmount('1,234.56'), '1234.56');
      expect(normalizeAmount('1.234,56'), '1234.56');
      expect(normalizeAmount('1 234,50'), '1234.50');
      expect(normalizeAmount('12,345,678.9'), '12345678.90');
      expect(normalizeAmount('1.234.567'), '1234567.00');
      expect(normalizeAmount('999999999.99'), '999999999.99');
    });

    test('a bad amount is explained, an empty one is fine', () {
      expect(amountProblem(''), isNull);
      expect(amountProblem('12,50'), isNull);
      expect(amountProblem('1.234'), contains('not valid'));
    });

    test('a BIC has 8 or 11 characters', () {
      for (final ok in ['', 'DEUTDEFF', 'deutdeff500', 'BHBLDEHHXXX']) {
        expect(bicProblem(ok), isNull, reason: ok);
      }
      for (final bad in ['DEUT', 'DEUTDEFF5', '1EUTDEFF', 'DEUT DEFF']) {
        expect(bicProblem(bad), isNotNull, reason: bad);
      }
    });

    test('a creditor reference is told from other text', () {
      expect(isCreditorReference('RF18 5390 0754 7034'), isTrue);
      expect(isCreditorReference('rf18539007547034'), isTrue);
      expect(isCreditorReference('RF19539007547034'), isFalse, reason: 'wrong check digits');
      expect(isCreditorReference('INV-77'), isFalse);
      expect(splitRemittance('RF18 5390 0754 7034'), (reference: 'RF18539007547034', message: ''));
      expect(splitRemittance('  Invoice\n 77 '), (reference: '', message: 'Invoice 77'));
    });
  });

  group('making a Girocode', () {
    test('writes the standard lines', () {
      final p = sepaPayload(name: ' Muster GmbH ', iban: 'de33 1002 0500 0001 1947 00', bic: 'bhbldehhxxx', amount: '12,5', message: 'Invoice 7');
      expect(p.split('\n'), ['BCD', '002', '1', 'SCT', 'BHBLDEHHXXX', 'Muster GmbH', 'DE33100205000001194700', 'EUR12.50', '', '', 'Invoice 7']);
    });

    test('leaves out an amount that was not given', () {
      final lines = sepaPayload(name: 'A', iban: 'DE33100205000001194700').split('\n');
      expect(lines[7], '');
    });

    test('says what is wrong', () {
      const ok = 'DE33100205000001194700';
      expect(sepaProblem(name: '', iban: ok), isNotNull);
      expect(sepaProblem(name: 'A' * 71, iban: ok), contains('too long'));
      expect(sepaProblem(name: 'A', iban: 'DE00'), contains('IBAN'));
      expect(sepaProblem(name: 'A', iban: ok, bic: 'XYZ'), contains('BIC'));
      expect(sepaProblem(name: 'A', iban: ok, amount: 'x'), contains('amount'));
      expect(sepaProblem(name: 'A', iban: ok, reference: 'R1', message: 'M'), contains('either'));
      expect(sepaProblem(name: 'A', iban: ok, message: 'm' * 141), contains('too long'));
      expect(sepaProblem(name: 'A', iban: ok, bic: 'BHBLDEHH', amount: '1', reference: 'RF18'), isNull);
      expect(sepaProblem(name: 'A', iban: ok, message: 'm' * 140 + 'é' * 0), isNull);
    });

    test('keeps within what the standard allows', () {
      const ok = 'DE33100205000001194700';
      expect(sepaMaxBytes, 331);
      expect(sepaProblem(name: 'é' * 70, iban: ok, bic: 'BHBLDEHHXXX', amount: '1', message: 'é' * 140), contains('Too much text'));
      expect(sepaProblem(name: 'A' * 70, iban: ok, message: 'm' * 140), isNull);
    });

    test('a line break typed or pasted cannot break the code', () {
      final lines = sepaPayload(name: 'Muster\nGmbH\r\n', iban: 'DE33100205000001194700', message: 'a\nb').split('\n');
      expect(lines.length, 11);
      expect((lines[5], lines[10]), ('Muster GmbH', 'a b'));
    });

    test('what is made is read back the same', () {
      final p = parseEpc(sepaPayload(name: 'Muster GmbH', iban: 'DE33100205000001194700', bic: 'BHBLDEHHXXX', amount: '99,9', reference: 'RF18539007547034'))!;
      expect(
        (p.name, p.iban, p.bic, p.currency, p.amount, p.reference),
        ('Muster GmbH', 'DE33100205000001194700', 'BHBLDEHHXXX', 'EUR', '99.90', 'RF18539007547034'),
      );
    });
  });

  group('reading payment codes', () {
    test('a Girocode', () {
      final c = parseCode(_epc, format: 'qrCode');
      expect(c.kind, CodeKind.payment);
      final p = c.payment!;
      expect(p.scheme, 'SEPA');
      expect(p.name, 'Wikimedia Fördergesellschaft');
      expect(p.ibanText, 'DE33 1002 0500 0001 1947 00');
      expect(p.bic, 'BHBLDEHHXXX');
      expect((p.currency, p.amount), ('EUR', '123.45'));
      expect(p.message, 'Spenden und Mitgliedsbeiträge');
      expect(p.ibanValid, isTrue);
      expect(c.summary, 'Wikimedia Fördergesellschaft, EUR 123.45');
    });

    test('a Girocode with Windows line breaks, no amount and an invalid IBAN', () {
      final c = parseCode('BCD\r\n002\r\n1\r\nSCT\r\n\r\nShop\r\nDE00100205000001194700\r\n\r\n\r\nRF18\r\n');
      final p = c.payment!;
      expect((p.amount, p.reference, p.ibanValid), ('', 'RF18', false));
      expect(c.summary, 'Shop');
    });

    test('a Swiss QR-bill', () {
      final c = parseCode(_swiss());
      expect(c.kind, CodeKind.payment);
      final p = c.payment!;
      expect(p.scheme, 'Swiss QR-bill');
      expect(p.name, 'Robert Schneider AG');
      expect(p.address, 'Rue du Lac, 1268, 2501 Biel, CH');
      expect((p.currency, p.amount), ('CHF', '1949.75'));
      expect(p.reference, '210000000003139471430009017');
      expect(p.message, 'Order of 15 June 2020');
      expect(p.ibanValid, isTrue);
      expect(parseCode(_swiss(amount: '')).payment!.amount, '');
    });

    test('text that only starts like a payment code stays text', () {
      expect(parseCode('BCD is a nice word').kind, CodeKind.text);
      expect(parseCode('BCD\n001\n1\nSCT').kind, CodeKind.text);
      expect(parseCode('SPC\n0200\n1\nCH44').kind, CodeKind.text);
      expect(parseCode('BCD\n001\n1\nXXX\nB\nName\nDE33100205000001194700').kind, CodeKind.text);
    });
  });

  group('screens', () {
    final copied = <String>[];

    Future<void> pump(WidgetTester tester, Widget page, {double width = 400}) async {
      tester.view.physicalSize = Size(width * 3, 800 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      copied.clear();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await sl.reset();
      sl
        ..registerSingleton<LinkOpener>(_Opener())
        ..registerSingleton<ShareService>(_Share());
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: page));
      await tester.pump();
    }

    testWidgets('a scanned payment shows its details and copies the IBAN', (tester) async {
      await pump(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            child: CodeResultCard(code: parseCode(_epc, format: 'qrCode')),
          ),
        ),
      );
      expect(find.text('Payment'), findsOneWidget);
      expect(find.text('DE33 1002 0500 0001 1947 00'), findsOneWidget);
      expect(find.text('EUR 123.45'), findsOneWidget);
      expect(find.textContaining('does not make payments'), findsOneWidget);
      await tester.tap(find.text('Copy IBAN'));
      await tester.pump();
      expect(copied, ['DE33100205000001194700']);
      await tester.tap(find.text('Copy amount'));
      await tester.pump();
      expect(copied.last, '123.45');
    });

    testWidgets('an IBAN that fails the check is called out', (tester) async {
      await pump(
        tester,
        Scaffold(
          body: SingleChildScrollView(child: CodeResultCard(code: parseCode('BCD\n002\n1\nSCT\n\nShop\nDE00100205000001194700\nEUR5.00'))),
        ),
      );
      expect(find.textContaining('does not pass the check'), findsOneWidget);
    });

    testWidgets('the generator makes a Girocode only from valid details', (tester) async {
      await pump(tester, const QrGeneratorPage(payment: true));
      expect(find.byType(QrImageView), findsNothing);
      expect(find.text('Before the code can be made:'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Who is paid *'), 'Muster GmbH');
      await tester.enterText(find.widgetWithText(TextField, 'IBAN *'), 'DE33 1002 0500 0001 1947 01');
      await tester.pump();
      expect(find.textContaining('check digits do not match'), findsOneWidget);
      expect(find.byType(QrImageView), findsNothing);
      await tester.enterText(find.widgetWithText(TextField, 'IBAN *'), 'de33100205000001194700');
      await tester.enterText(find.widgetWithText(TextField, 'Amount in euros (optional)'), '12,5');
      await tester.pump();
      expect(
        tester.widget<TextField>(find.widgetWithText(TextField, 'IBAN *')).controller!.text,
        'DE33 1002 0500 0001 1947 00',
        reason: 'grouped and in capitals',
      );
      expect(find.text('Valid IBAN from Germany'), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.byKey(const ValueKey('BCD\n002\n1\nSCT\n\nMuster GmbH\nDE33100205000001194700\nEUR12.50\n\n\n')), findsOneWidget);
      expect(find.text('\u20AC 12.50'), findsOneWidget);
    });

    testWidgets('a number that is a digit short says how long it should be', (tester) async {
      await pump(tester, const QrGeneratorPage(payment: true));
      await tester.enterText(find.widgetWithText(TextField, 'Who is paid *'), 'drahs');
      await tester.enterText(find.widgetWithText(TextField, 'IBAN *'), 'PT50000331234567890123456');
      await tester.pump();
      expect(tester.widget<TextField>(find.widgetWithText(TextField, 'IBAN *')).controller!.text, 'PT50 0003 3123 4567 8901 2345 6');
      await tester.enterText(find.widgetWithText(TextField, 'IBAN *'), 'PT50 0033 1234 5678 9012 3456');
      await tester.pump();
      expect(find.text('Portugal: 24 of 25 characters'), findsOneWidget);
      expect(find.byType(QrImageView), findsNothing);
      // The field is called out once it has been left.
      await tester.ensureVisible(find.widgetWithText(TextField, 'Amount in euros (optional)'));
      await tester.pump();
      await tester.tap(find.widgetWithText(TextField, 'Amount in euros (optional)'));
      await tester.pump();
      expect(find.text('An IBAN from Portugal has 25 characters; you typed 24.'), findsOneWidget);
    });

    testWidgets('amount, BIC and the reference are checked', (tester) async {
      await pump(tester, const QrGeneratorPage(payment: true));
      await tester.enterText(find.widgetWithText(TextField, 'Who is paid *'), 'Muster GmbH');
      await tester.enterText(find.widgetWithText(TextField, 'IBAN *'), 'DE33100205000001194700');
      await tester.enterText(find.widgetWithText(TextField, 'BIC (optional)'), 'bhbl');
      await tester.pump();
      expect(find.byType(QrImageView), findsNothing);
      expect(find.textContaining('The BIC is not valid'), findsOneWidget, reason: 'listed as what is left, not yet marked on the field');
      expect(find.byType(TextField).evaluate().length, greaterThan(3));
      await tester.enterText(find.widgetWithText(TextField, 'BIC (optional)'), 'bhbldehh');
      expect(tester.widget<TextField>(find.widgetWithText(TextField, 'BIC (optional)')).controller!.text, 'BHBLDEHH');
      await tester.pump();
      expect(find.byType(QrImageView), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Reference or message (optional)'), 'RF18 5390 0754 7034');
      await tester.pump();
      expect(find.byKey(const ValueKey('BCD\n002\n1\nSCT\nBHBLDEHH\nMuster GmbH\nDE33100205000001194700\n\n\nRF18539007547034\n')), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Reference or message (optional)'), 'Invoice 7');
      await tester.enterText(find.widgetWithText(TextField, 'Amount in euros (optional)'), '1.234');
      await tester.pump();
      expect(find.byType(QrImageView), findsNothing);
      expect(find.textContaining('The amount is not valid'), findsOneWidget, reason: 'it is also shown in the list of what is left');
    });

    testWidgets('an example can be filled in', (tester) async {
      await pump(tester, const QrGeneratorPage(payment: true));
      await tester.tap(find.byKey(const ValueKey('fill-example')));
      await tester.pump();
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text('Max Mustermann'), findsWidgets);
    });

    testWidgets('the three kinds are chips that wrap, and the Wi-Fi details are checked', (tester) async {
      await pump(tester, const QrGeneratorPage(), width: 320);
      expect(find.byKey(const ValueKey('kind-payment')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('kind-wifi')));
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextField, 'Network name (SSID) *'), 'Home');
      await tester.enterText(find.widgetWithText(TextField, 'Password *'), 'short');
      await tester.pump();
      expect(find.byType(QrImageView), findsNothing);
      expect(find.text('A WPA password has 8 to 63 characters.'), findsWidgets);
      await tester.enterText(find.widgetWithText(TextField, 'Password *'), 'long enough password');
      await tester.pump();
      expect(find.byType(QrImageView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final width in [320.0, 400.0, 900.0]) {
      testWidgets('the payment tab fits at ${width.toInt()} px', (tester) async {
        await pump(tester, const QrGeneratorPage(payment: true), width: width);
        expect(tester.takeException(), isNull);
        await tester.enterText(find.widgetWithText(TextField, 'Who is paid *'), 'A very long name of an organisation that is paid by this code');
        await tester.enterText(find.widgetWithText(TextField, 'IBAN *'), 'PT50 0033 1234 5678 9012 3456');
        await tester.enterText(find.widgetWithText(TextField, 'BIC (optional)'), 'XXXXXXXXXXX');
        await tester.enterText(find.widgetWithText(TextField, 'Amount in euros (optional)'), '1.234');
        await tester.tap(find.widgetWithText(TextField, 'Reference or message (optional)'));
        await tester.pump();
        expect(find.textContaining('An IBAN from Portugal'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}

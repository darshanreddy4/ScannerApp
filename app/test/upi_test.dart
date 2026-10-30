import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:doculoom/app/di.dart';
import 'package:doculoom/core/error/result.dart';
import 'package:doculoom/core/theme/app_theme.dart';
import 'package:doculoom/features/export/domain/repositories/export_repository.dart';
import 'package:doculoom/features/qr/domain/scan_services.dart';
import 'package:doculoom/features/qr/domain/scanned_code.dart';
import 'package:doculoom/features/qr/domain/upi.dart';
import 'package:doculoom/features/qr/presentation/code_result_card.dart';
import 'package:doculoom/features/qr/presentation/qr_generator_page.dart';

const _code = 'upi://pay?pa=testshop@okaxis&pn=Test%20Shop%20%26%20Sons&am=250.50&cu=INR&tn=Order%201042&tr=T123';

class _Opener implements LinkOpener {
  final opened = <String>[];
  bool result = true;
  @override
  Future<bool> open(String uri) async {
    opened.add(uri);
    return result;
  }
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
  group('UPI IDs', () {
    test('valid and invalid', () {
      for (final ok in ['name@okaxis', '9876543210@ybl', 'first.last-1@oksbi', 'a_b@paytm', ' shop@upi ']) {
        expect(isUpiId(ok), isTrue, reason: ok);
        expect(upiIdProblem(ok), isNull, reason: ok);
      }
      for (final bad in ['', 'name', 'name@', '@upi', 'a@upi', 'na me@upi', 'name@ok axis', 'name@@upi', 'name@1upi', 'name#1@upi']) {
        expect(isUpiId(bad), isFalse, reason: bad);
      }
      expect(upiIdProblem(''), 'Enter the UPI ID.');
      expect(upiIdProblem('name'), contains('name@bank'));
    });

    test('an unknown bank handle is a warning, not an error', () {
      expect(isKnownUpiHandle('shop@OKAXIS'), isTrue);
      expect(upiIdWarning('shop@okaxis'), isNull);
      expect(upiIdWarning('shop@okaxs'), contains('not one Doculoom knows'));
      expect(upiIdWarning('shop'), isNull, reason: 'a wrong form is an error, not a warning');
    });
  });

  group('amounts', () {
    test('up to the most UPI allows', () {
      expect(upiAmountProblem(''), isNull);
      expect(upiAmountProblem('250'), isNull);
      expect(upiAmountProblem('0,5'), isNull);
      expect(upiAmountProblem('500000'), isNull);
      expect(upiAmountProblem('500000.01'), contains('5,00,000'));
      expect(upiAmountProblem('0'), contains('not valid'));
      expect(upiAmountProblem('abc'), contains('not valid'));
      expect(upiAmountWarning('100000'), isNull);
      expect(upiAmountWarning('100001'), contains('1,00,000'));
      expect(upiAmountWarning(''), isNull);
    });

    test('what is missing is named', () {
      expect(upiProblem(id: '', name: 'A'), 'Enter the UPI ID.');
      expect(upiProblem(id: 'ab@upi', name: ' '), 'Enter who is paid.');
      expect(upiProblem(id: 'ab@upi', name: 'A' * 51), contains('too long'));
      expect(upiProblem(id: 'ab@upi', name: 'A', note: 'n' * 51), contains('note is too long'));
      expect(upiProblem(id: 'ab@upi', name: 'A', amount: 'x'), contains('not valid'));
      expect(upiProblem(id: 'ab@upi', name: 'A', amount: '12', note: 'ok'), isNull);
    });
  });

  group('the code', () {
    test('is written and read back', () {
      final text = upiPayload(id: ' shop@okaxis ', name: ' Test Shop & Sons ', amount: '250,5', note: 'Order 1042');
      expect(text, 'upi://pay?pa=shop@okaxis&pn=Test%20Shop%20%26%20Sons&am=250.50&cu=INR&tn=Order%201042');
      final p = parseUpi(text)!;
      expect((p.scheme, p.name, p.vpa, p.amount, p.currency, p.message), ('UPI', 'Test Shop & Sons', 'shop@okaxis', '250.50', 'INR', 'Order 1042'));
      expect(upiPayload(id: 'a@upi', name: 'A'), 'upi://pay?pa=a@upi&pn=A&cu=INR');
    });

    test('a scanned code is read', () {
      final p = parseUpi(_code)!;
      expect((p.name, p.vpa, p.amount, p.reference, p.message, p.isUpi), ('Test Shop & Sons', 'testshop@okaxis', '250.50', 'T123', 'Order 1042', true));
      final c = parseCode(_code, format: 'qrCode');
      expect(c.kind, CodeKind.payment);
      expect(c.summary, 'Test Shop & Sons, INR 250.50');
    });

    test('odd codes', () {
      expect(parseUpi('UPI://PAY?PA=a@upi&PN=X')?.vpa, 'a@upi');
      expect(parseUpi('upi://pay?pn=NoId'), isNull);
      expect(parseUpi('upi://mandate?pa=a@upi'), isNull);
      expect(parseUpi('https://example.com/upi://pay?pa=a@upi'), isNull);
      expect(parseUpi('upi://pay?pa=not-valid&pn=X')?.vpa, 'not-valid', reason: 'kept as written so the card can warn');
      expect(parseUpi('upi://pay?pa=a@upi&am=abc')?.amount, '');
      expect(parseUpi('upi://pay?pa=a@upi&am=12.345')?.amount, '');
      expect(parseUpi('upi://pay?pa=a@upi')?.currency, 'INR');
      expect(parseCode('upi://pay?pa=').kind, isNot(CodeKind.payment));
    });
  });

  group('screens', () {
    late _Opener opener;
    final copied = <String>[];

    Future<void> pump(WidgetTester tester, Widget page, {double width = 400}) async {
      tester.view.physicalSize = Size(width * 3, 1600 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      copied.clear();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      opener = _Opener();
      await sl.reset();
      sl
        ..registerSingleton<LinkOpener>(opener)
        ..registerSingleton<ShareService>(_Share());
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: page));
      await tester.pump();
    }

    Widget card(String raw) => Scaffold(
      body: SingleChildScrollView(
        child: CodeResultCard(code: parseCode(raw, format: 'qrCode')),
      ),
    );

    testWidgets('a scanned UPI code shows who is paid, and opens the UPI app on request', (tester) async {
      await pump(tester, card(_code));
      expect(find.text('UPI payment'), findsOneWidget);
      expect(find.text('Test Shop & Sons'), findsOneWidget);
      expect(find.text('testshop@okaxis'), findsOneWidget);
      expect(find.text('\u20B9 250.50'), findsOneWidget);
      expect(find.text('Order 1042'), findsOneWidget);
      expect(find.textContaining('never enter your UPI PIN to receive money'), findsOneWidget);
      expect(find.textContaining('not valid'), findsNothing);
      await tester.tap(find.text('Pay with a UPI app'));
      await tester.pump();
      expect(opener.opened, [_code]);
      await tester.tap(find.text('Copy UPI ID'));
      await tester.pump();
      expect(copied.last, 'testshop@okaxis');
    });

    testWidgets('no UPI app on the phone is said plainly', (tester) async {
      await pump(tester, card(_code));
      opener.result = false;
      await tester.tap(find.text('Pay with a UPI app'));
      await tester.pump();
      expect(find.text('No UPI app was found on this phone.'), findsOneWidget);
    });

    testWidgets('an invalid or unknown ID is called out', (tester) async {
      await pump(tester, card('upi://pay?pa=shop&pn=X'));
      expect(find.textContaining('This UPI ID is not valid'), findsOneWidget);
      await pump(tester, card('upi://pay?pa=shop@okaxs&pn=X'));
      expect(find.textContaining('not one Doculoom knows'), findsOneWidget);
      expect(find.text('The payer types it'), findsOneWidget);
    });

    testWidgets('the generator makes a UPI code only from valid details', (tester) async {
      await pump(tester, const QrGeneratorPage(upi: true));
      expect(find.byType(QrImageView), findsNothing);
      expect(find.text('Before the code can be made:'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('upi-id')), 'testshop@okaxis');
      await tester.enterText(find.byKey(const ValueKey('upi-name')), 'Test Shop');
      await tester.pump();
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.byKey(const ValueKey('upi://pay?pa=testshop@okaxis&pn=Test%20Shop&cu=INR')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('upi-amount')), '250');
      await tester.enterText(find.byKey(const ValueKey('upi-note')), 'Order 7');
      await tester.pump();
      expect(find.byKey(const ValueKey('upi://pay?pa=testshop@okaxis&pn=Test%20Shop&am=250.00&cu=INR&tn=Order%207')), findsOneWidget);
      expect(find.text('\u20B9 250.00'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('upi-amount')), '600000');
      await tester.pump();
      expect(find.byType(QrImageView), findsNothing);
      expect(find.textContaining('5,00,000'), findsWidgets);
      await tester.enterText(find.byKey(const ValueKey('upi-amount')), '150000');
      await tester.pump();
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.textContaining('Most UPI apps allow up to 1,00,000'), findsOneWidget);
    });

    testWidgets('a wrong ID is explained once enough is typed, and an unknown handle only warns', (tester) async {
      await pump(tester, const QrGeneratorPage(upi: true));
      await tester.enterText(find.byKey(const ValueKey('upi-id')), 'na');
      await tester.pump();
      expect(find.textContaining('looks like name@bank'), findsNothing, reason: 'not while it is being typed');
      await tester.enterText(find.byKey(const ValueKey('upi-id')), 'name@ok axis');
      await tester.pump();
      expect(tester.widget<TextField>(find.byKey(const ValueKey('upi-id'))).controller!.text, 'name@okaxis', reason: 'spaces are not allowed');
      await tester.enterText(find.byKey(const ValueKey('upi-name')), 'Anna');
      await tester.enterText(find.byKey(const ValueKey('upi-id')), 'anna@okaxs');
      await tester.pump();
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.textContaining('not one Doculoom knows'), findsOneWidget);
    });

    testWidgets('an example can be filled in', (tester) async {
      await pump(tester, const QrGeneratorPage(upi: true));
      await tester.tap(find.byKey(const ValueKey('fill-upi-example')));
      await tester.pump();
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text('testshop@upi'), findsWidgets);
    });

    for (final width in [320.0, 400.0, 900.0]) {
      testWidgets('the UPI tab fits at ${width.toInt()} px', (tester) async {
        await pump(tester, const QrGeneratorPage(upi: true), width: width);
        await tester.enterText(find.byKey(const ValueKey('upi-id')), 'a-very-long-name-with-many-characters@somebankhandle');
        await tester.enterText(find.byKey(const ValueKey('upi-name')), 'A very long name of an organisation that is paid by this code');
        await tester.enterText(find.byKey(const ValueKey('upi-amount')), '150000');
        await tester.pump();
        expect(tester.takeException(), isNull);
        await pump(tester, card('upi://pay?pa=a-very-long-name-with-many-characters@somebankhandle&pn=A%20very%20long%20name&am=150000'), width: width);
        expect(tester.takeException(), isNull);
      });
    }
  });
}

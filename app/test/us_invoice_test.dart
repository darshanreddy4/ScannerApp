import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:doculoom/core/theme/app_theme.dart';
import 'package:doculoom/features/reader/data/pdf_text_extractor.dart';
import 'package:doculoom/features/taxinvoice/data/tax_profile_store.dart';
import 'package:doculoom/features/taxinvoice/data/us_invoice_pdf.dart';
import 'package:doculoom/features/taxinvoice/domain/us_invoice.dart';
import 'package:doculoom/features/taxinvoice/presentation/us_invoice_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Uint8List> _asset(String path) => File(path).readAsBytes();

String _text(Uint8List pdf) => extractPdfText(pdf).map((p) => p.text).join('\n').replaceAll('\u00A0', ' ');

const _seller = UsParty(name: 'Bay Widgets LLC', address: '1 Market St', city: 'San Francisco', state: 'CA', zip: '94105', taxId: '12-3456789');
const _buyer = UsParty(name: 'Acme Corp', address: '9 Main St', city: 'Austin', state: 'TX', zip: '73301');

UsDraft _draft({
  List<UsLine>? items,
  bool percent = true,
  int discount = 0,
  int shipping = 0,
  bool shipTax = false,
  int rate = 82500,
  bool exempt = false,
  int paid = 0,
  int terms = 30,
}) => UsDraft(
  seller: _seller,
  buyer: _buyer,
  number: 'INV-1001',
  date: DateTime(2026, 6, 1),
  termsDays: terms,
  items:
      items ??
      const [
        UsLine(description: 'Widget', quantity: 2, unitPriceCents: 5000),
        UsLine(description: 'Training', quantity: 1, unitPriceCents: 2000, taxable: false),
      ],
  discountIsPercent: percent,
  discountValue: discount,
  shippingCents: shipping,
  shippingTaxable: shipTax,
  taxRate: rate,
  exempt: exempt,
  paidCents: paid,
);

void main() {
  group('rates', () {
    test('a rate has up to four decimals and is kept in millionths', () {
      expect(parseUsRate('8.25'), 82500);
      expect(parseUsRate('8,875'), 88750);
      expect(parseUsRate('4.5625'), 45625);
      expect(parseUsRate('0'), 0);
      expect(parseUsRate('20'), 200000);
      for (final bad in ['20.0001', '21', '8.12345', 'x', '', '-1']) {
        expect(parseUsRate(bad), isNull, reason: bad);
      }
    });

    test('a rate is written without trailing zeros', () {
      expect(usRateText(68750), '6.875');
      expect(usRateText(80000), '8');
      expect(usRateText(72500), '7.25');
      expect(usRateText(45625), '4.5625');
      expect(usRateText(0), '0');
    });

    test('tax is rounded half up to the cent', () {
      expect(usTaxOf(10000, 82500), 825);
      expect(usTaxOf(9000, 82500), 743, reason: '7.425 dollars is 7.43');
      expect(usTaxOf(1, 82500), 0);
      expect(usTaxOf(61, 82500), 5);
      expect(usTaxOf(0, 82500), 0);
    });

    test('the state table has 50 states and the District of Columbia, each once', () {
      expect(usStates.length, 51);
      expect(usStates.map((s) => s.code).toSet().length, 51);
      expect(usStates.map((s) => s.name).toSet().length, 51);
      expect(usStateOf('CA')!.baseRate, 72500);
      expect(usStateOf('NY')!.baseRate, 40000);
      expect(usStateOf('MO')!.baseRate, 42250);
      expect(usStateOf('XX'), isNull);
      expect(usStates.where((s) => s.baseRate == 0).map((s) => s.code), unorderedEquals(['AK', 'DE', 'MT', 'NH', 'OR']));
      expect(usStates.every((s) => s.baseRate >= 0 && s.baseRate <= 72500), isTrue);
    });
  });

  group('numbers', () {
    test('ZIP codes and EINs', () {
      expect(isValidZip('94105'), isTrue);
      expect(isValidZip('94105-1234'), isTrue);
      expect(isValidZip('9410'), isFalse);
      expect(isValidZip('94105-12'), isFalse);
      expect(isValidEin('12-3456789'), isTrue);
      expect(isValidEin('123456789'), isTrue);
      expect(isValidEin('12-345678'), isFalse);
    });

    test('the next invoice number counts up', () {
      expect(nextUsInvoiceNumber(''), '1001');
      expect(nextUsInvoiceNumber('INV-0042'), 'INV-0043');
      expect(nextUsInvoiceNumber('999'), '1000');
      expect(nextUsInvoiceNumber('abc'), 'abc-1');
    });

    test('terms and the due date', () {
      expect(usTermsText(0), 'Due on receipt');
      expect(usTermsText(30), 'Net 30');
      expect(_draft().dueDate, DateTime(2026, 7, 1));
      expect(_draft(terms: 0).dueDate, DateTime(2026, 6, 1));
    });
  });

  group('totals', () {
    test('only the taxed lines carry tax', () {
      final t = computeUs(_draft());
      expect((t.subtotal, t.taxableBase, t.tax, t.total, t.balance), (12000, 10000, 825, 12825, 12825));
    });

    test('a percent discount comes off the taxed part in proportion', () {
      final t = computeUs(_draft(discount: 1000));
      expect((t.discount, t.taxableBase, t.tax, t.total), (1200, 9000, 743, 11543));
    });

    test('an amount discount is shared in the same way, and cannot be more than the items', () {
      final t = computeUs(_draft(percent: false, discount: 1200));
      expect((t.discount, t.taxableBase), (1200, 9000));
      final all = computeUs(_draft(percent: false, discount: 99999));
      expect((all.discount, all.tax, all.total), (12000, 0, 0));
    });

    test('shipping is taxed only when asked', () {
      expect(computeUs(_draft(shipping: 1000)).tax, 825);
      final t = computeUs(_draft(shipping: 1000, shipTax: true));
      expect((t.taxableBase, t.tax, t.total), (11000, 908, 12000 + 1000 + 908));
    });

    test('an exempt customer pays no tax', () {
      final t = computeUs(_draft(exempt: true));
      expect((t.tax, t.taxableBase, t.total), (0, 0, 12000));
    });

    test('a payment already made comes off the balance', () {
      final t = computeUs(_draft(paid: 5000));
      expect((t.total, t.paid, t.balance), (12825, 5000, 7825));
    });

    test('a fraction of a unit', () {
      expect(const UsLine(description: 'Hours', quantity: 1.5, unitPriceCents: 8000).amountCents, 12000);
      expect(const UsLine(description: 'Foot', quantity: 0.333, unitPriceCents: 1000).amountCents, 333);
    });
  });

  group('checks', () {
    List<String> fields(UsDraft d) => usIssues(d).map((i) => i.field).toList();

    test('a complete invoice has no problems', () => expect(usIssues(_draft()), isEmpty));

    test('what is missing is named by field', () {
      final f = fields(UsDraft(date: DateTime(2026)));
      expect(f, containsAll(['seller.name', 'seller.address', 'seller.city', 'seller.state', 'seller.zip', 'buyer.name', 'number', 'items']));
    });

    test('wrong shapes are called out', () {
      final f = fields(
        UsDraft(
          seller: const UsParty(name: 'A', address: 'B', city: 'C', state: 'CA', zip: '12', taxId: '!!', email: 'nope'),
          buyer: const UsParty(name: 'K', zip: 'abc'),
          number: 'bad number!',
          date: DateTime(2026),
          items: const [UsLine(description: ' ', quantity: 1, unitPriceCents: 100)],
          discountValue: 20000,
          paidCents: 999999,
        ),
      );
      expect(f, containsAll(['seller.zip', 'seller.taxId', 'seller.email', 'buyer.zip', 'number', 'item.0.description', 'discount', 'paid']));
    });
  });

  group('the PDF', () {
    test('it shows the parties, the lines, the tax and the balance', () async {
      final text = _text(await buildUsInvoicePdf(_draft(discount: 1000, shipping: 995, paid: 3000), loadAsset: _asset));
      for (final s in [
        'INVOICE',
        'Bay Widgets LLC',
        'San Francisco, CA 94105',
        'Acme Corp',
        'Austin, TX 73301',
        'INV-1001',
        '06/01/2026',
        'Net 30',
        '07/01/2026',
        'Widget',
        'Training (not taxed)',
        '\$120.00',
        'Discount (10%)',
        'Shipping',
        '\$9.95',
        'Sales tax (8.25%)',
        'Total',
        'Amount paid',
        'Balance due',
        'Items marked (not taxed)',
      ]) {
        expect(text, contains(s), reason: s);
      }
    });

    test('an exempt customer is shown with the certificate', () async {
      final d = UsDraft(
        seller: _seller,
        buyer: const UsParty(name: 'School', taxId: 'R-123'),
        number: '7',
        date: DateTime(2026, 6, 1),
        exempt: true,
        items: const [UsLine(description: 'Books', quantity: 3, unitPriceCents: 1000)],
      );
      final text = _text(await buildUsInvoicePdf(d, loadAsset: _asset));
      expect(text, contains('Tax exempt'));
      expect(text, contains('Exemption certificate: R-123'));
      expect(text, contains('Sales tax (exempt)'));
      expect(text, isNot(contains('Balance due')));
    });

    test('a long list goes on to more pages', () async {
      final d = UsDraft(
        seller: _seller,
        buyer: _buyer,
        number: '9',
        date: DateTime(2026, 6, 1),
        items: [for (var i = 0; i < 80; i++) UsLine(description: 'Line number $i of the order', quantity: 1, unitPriceCents: 100 + i)],
      );
      final pages = extractPdfText(await buildUsInvoicePdf(d, loadAsset: _asset));
      expect(pages.length, greaterThan(1));
      expect(pages.map((p) => p.text).join(' '), contains('Line number 79'));
    });
  });

  group('the page', () {
    late Directory work;
    setUp(() {
      work = Directory.systemTemp.createTempSync('sv_us');
      SharedPreferences.setMockInitialValues({});
    });
    tearDown(() => work.deleteSync(recursive: true));

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 12; i++) {
        await tester.pump();
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      }
      await tester.pump();
    }

    Future<void> open(WidgetTester tester, {double width = 400}) async {
      tester.view.physicalSize = Size(width * 3, 6000 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: UsInvoicePage(workDir: () async => work, loadAsset: _asset, now: DateTime(2026, 6, 1)),
        ),
      );
      await settle(tester);
    }

    Future<void> type(WidgetTester tester, String label, String text) async {
      final f = find.widgetWithText(TextField, label).first;
      await tester.ensureVisible(f);
      await tester.pump();
      await tester.enterText(f, text);
      await tester.pump();
    }

    Future<void> pick(WidgetTester tester, String key, String stateName) async {
      await tester.ensureVisible(find.byKey(ValueKey(key)));
      await tester.pump();
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining(stateName).last);
      await tester.pumpAndSettle();
    }

    Future<void> tapKey(WidgetTester tester, String key) async {
      await tester.ensureVisible(find.byKey(ValueKey(key)));
      await tester.pump();
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pump();
    }

    Future<void> fill(WidgetTester tester) async {
      await type(tester, 'Business name *', 'Bay Widgets LLC');
      await type(tester, 'Street address *', '1 Market St');
      await type(tester, 'City *', 'San Francisco');
      await pick(tester, 'us-seller-state', 'California');
      await type(tester, 'ZIP code *', '94105');
      await type(tester, 'Customer name *', 'Acme Corp');
      await type(tester, 'Description *', 'Widget');
      await type(tester, 'Quantity *', '2');
      await type(tester, 'Price each *', '50');
    }

    testWidgets('the state rate is offered, and one tap uses it', (tester) async {
      await open(tester);
      expect(find.byKey(const ValueKey('us-state-rate')), findsNothing);
      await pick(tester, 'us-buyer-state', 'New York');
      await tester.ensureVisible(find.byKey(const ValueKey('us-state-rate')));
      expect(find.textContaining('New York state rate: 4% (January 2026)'), findsOneWidget);
      await tapKey(tester, 'us-use-state-rate');
      expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Sales tax rate (%)')).controller!.text, '4');
    });

    testWidgets('the totals follow the items, the rate and the exemption', (tester) async {
      await open(tester);
      await type(tester, 'Description *', 'Widget');
      await type(tester, 'Quantity *', '2');
      await type(tester, 'Price each *', '50');
      await type(tester, 'Sales tax rate (%)', '8.25');
      await tester.ensureVisible(find.byKey(const ValueKey('us-summary')));
      await tester.pump();
      expect(find.text('Sales tax (8.25%)'), findsOneWidget);
      expect(find.text('\$108.25'), findsOneWidget);
      await tapKey(tester, 'us-taxable-0');
      expect(find.text('\$100.00'), findsWidgets);
      expect(find.text('\$0.00'), findsOneWidget, reason: 'nothing is taxed, so the tax is 0');
      await tapKey(tester, 'us-taxable-0');
      await tapKey(tester, 'us-exempt');
      expect(find.text('Sales tax (exempt)'), findsOneWidget);
      expect(find.text('Sales tax rate (%)'), findsNothing);
    });

    testWidgets('missing and wrong values are shown at their fields', (tester) async {
      await open(tester);
      await type(tester, 'Sales tax rate (%)', '25');
      await tapKey(tester, 'us-create');
      await settle(tester);
      expect(find.text('Fix the marked fields, then try again.'), findsOneWidget);
      expect(find.text('Enter your business name.'), findsOneWidget);
      expect(find.text('Choose your state.'), findsOneWidget);
      expect(find.text('The tax rate must be a percent from 0 to 20, such as 8.25.'), findsOneWidget);
      expect(find.text('Item 1: the price must be an amount, for example 125.50.'), findsOneWidget);
      expect(work.listSync(), isEmpty);
    });

    testWidgets('a good invoice is made, the seller is remembered and the next number follows', (tester) async {
      await open(tester);
      await fill(tester);
      await type(tester, 'Sales tax rate (%)', '8.25');
      await tester.ensureVisible(find.byKey(const ValueKey('us-create')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('us-create')));
      await settle(tester);
      await settle(tester);
      final file = Directory('${work.path}/invoices').listSync().whereType<File>().single;
      expect(file.path, endsWith('Invoice_1001.pdf'));
      final text = _text(file.readAsBytesSync());
      for (final s in ['INVOICE', 'Bay Widgets LLC', 'Acme Corp', '\$100.00', 'Sales tax (8.25%)', '\$8.25', '\$108.25']) {
        expect(text, contains(s), reason: s);
      }
      expect(find.byKey(const ValueKey('pdf-result'), skipOffstage: false), findsOneWidget);
      final saved = await const TaxProfileStore(usInvoiceProfileKey).load();
      expect((saved['name'], saved['state'], saved['zip'], saved['lastNumber']), ('Bay Widgets LLC', 'CA', '94105', '1001'));

      await tester.pumpWidget(const SizedBox());
      await open(tester);
      expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Business name *')).controller!.text, 'Bay Widgets LLC');
      expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Invoice number *')).controller!.text, '1002');
    });

    for (final w in [320.0, 900.0]) {
      testWidgets('fits a ${w.toInt()} px wide screen', (tester) async {
        await open(tester, width: w);
        await pick(tester, 'us-buyer-state', 'New York');
        await tapKey(tester, 'us-create');
        await settle(tester);
        expect(tester.takeException(), isNull);
      });
    }
  });
}

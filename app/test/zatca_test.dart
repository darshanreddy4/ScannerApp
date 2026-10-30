import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:doculoom/core/theme/app_theme.dart';
import 'package:doculoom/features/reader/data/pdf_text_extractor.dart';
import 'package:doculoom/features/taxinvoice/data/tax_profile_store.dart';
import 'package:doculoom/features/taxinvoice/data/zatca_pdf.dart';
import 'package:doculoom/features/taxinvoice/domain/zatca.dart';
import 'package:doculoom/features/taxinvoice/presentation/zatca_invoice_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Uint8List> _asset(String path) => File(path).readAsBytes();

String _text(Uint8List pdf) => extractPdfText(pdf).map((p) => p.text).join('\n').replaceAll('\u00A0', ' ');

const _seller = ZatcaParty(
  name: 'Al Noor Trading',
  vat: '300000000000003',
  address: '1234 King Fahd Road',
  district: 'Al Olaya',
  city: 'Riyadh',
  postcode: '12211',
  cr: '1010123456',
);
const _buyer = ZatcaParty(name: 'Al Amal Trading', vat: '399999999900003', address: '55 Prince Sultan St', city: 'Jeddah', postcode: '21442');

ZatcaDraft _draft({ZatcaDocument doc = ZatcaDocument.simplified, List<ZatcaLine>? items, bool inclusive = false, ZatcaParty buyer = const ZatcaParty()}) =>
    ZatcaDraft(
      document: doc,
      seller: _seller,
      buyer: buyer,
      number: 'INV-1',
      issuedAt: DateTime(2026, 6, 1, 14, 30),
      items: items ?? const [ZatcaLine(description: 'Laptop bag', quantity: 2, unitPriceCents: 5000)],
      pricesIncludeVat: inclusive,
    );

void main() {
  group('numbers', () {
    test('a VAT number has 15 digits and starts and ends with 3', () {
      for (final v in ['300000000000003', '310122393500003', ' 399999999900003 ']) {
        expect(isValidSaudiVat(v), isTrue, reason: v);
      }
      for (final v in ['300000000000004', '30000000000003', '400000000000003', '3000000000000033', '30000000000000A', '']) {
        expect(isValidSaudiVat(v), isFalse, reason: v);
      }
      expect(isValidSaudiPostcode('12211'), isTrue);
      expect(isValidSaudiPostcode('1221'), isFalse);
    });
  });

  group('VAT', () {
    test('15 percent on prices without VAT', () {
      final t = computeZatca(_draft());
      expect((t.taxable, t.vat, t.total, t.discount), (10000, 1500, 11500, 0));
    });

    test('prices with VAT are split into the amount and the VAT, and still add up', () {
      final a = computeZatca(_draft(inclusive: true, items: const [ZatcaLine(description: 'A', quantity: 1, unitPriceCents: 11500)]));
      expect((a.taxable, a.vat, a.total), (10000, 1500, 11500));
      final b = computeZatca(_draft(inclusive: true, items: const [ZatcaLine(description: 'A', quantity: 1, unitPriceCents: 10000)]));
      expect((b.taxable, b.vat, b.total), (8696, 1304, 10000));
    });

    test('a discount comes off before VAT, and is shown without VAT when prices include it', () {
      final ex = computeZatca(_draft(items: const [ZatcaLine(description: 'A', quantity: 2, unitPriceCents: 5000, discountCents: 1000)]));
      expect((ex.discount, ex.taxable, ex.vat, ex.total), (1000, 9000, 1350, 10350));
      final inc = computeZatca(_draft(inclusive: true, items: const [ZatcaLine(description: 'A', quantity: 1, unitPriceCents: 11500, discountCents: 1150)]));
      expect((inc.discount, inc.taxable, inc.vat, inc.total), (1000, 9000, 1350, 10350));
    });

    test('a discount cannot be more than the line', () {
      final t = computeZatca(_draft(items: const [ZatcaLine(description: 'A', quantity: 1, unitPriceCents: 1000, discountCents: 5000)]));
      expect((t.taxable, t.total), (0, 0));
    });

    test('zero-rated and exempt items carry no VAT', () {
      final t = computeZatca(
        _draft(
          items: const [
            ZatcaLine(description: 'A', quantity: 1, unitPriceCents: 10000),
            ZatcaLine(description: 'Export', quantity: 1, unitPriceCents: 20000, category: VatCategory.zero),
            ZatcaLine(description: 'Rent', quantity: 1, unitPriceCents: 30000, category: VatCategory.exempt),
          ],
        ),
      );
      expect((t.taxable, t.vat, t.total), (60000, 1500, 61500));
      expect(t.lines.map((l) => l.vat), [1500, 0, 0]);
    });

    test('the lines add up to the totals', () {
      final d = _draft(
        items: [for (var i = 1; i <= 9; i++) ZatcaLine(description: 'L$i', quantity: 1.5, unitPriceCents: 333 * i + 7)],
      );
      final t = computeZatca(d);
      expect(t.lines.fold(0, (a, l) => a + l.net), t.taxable);
      expect(t.lines.fold(0, (a, l) => a + l.vat), t.vat);
      expect(t.total, t.taxable + t.vat);
    });
  });

  group('the QR code', () {
    test('the time and amounts are written as the code needs them', () {
      expect(zatcaTimestamp(DateTime(2026, 6, 1, 9, 5, 7)), '2026-06-01T09:05:07Z');
      expect(zatcaAmount(100000), '1000.00');
      expect(zatcaAmount(5), '0.05');
    });

    test('it matches the payload worked out by hand for the same five facts', () {
      final bytes = zatcaTlv(
        sellerName: 'Bobs Records',
        vatNumber: '310122393500003',
        issuedAt: DateTime(2022, 4, 25, 15, 30),
        totalCents: 100000,
        vatCents: 15000,
      );
      expect(base64Encode(bytes), 'AQxCb2JzIFJlY29yZHMCDzMxMDEyMjM5MzUwMDAwMwMUMjAyMi0wNC0yNVQxNTozMDowMFoEBzEwMDAuMDAFBjE1MC4wMA==');
    });

    test('the payload of an invoice holds its own facts, and an Arabic name is UTF-8', () {
      const arabic = ZatcaParty(name: 'شركة النور', vat: '300000000000003', address: 'x', city: 'y');
      final d = ZatcaDraft(
        seller: arabic,
        number: '1',
        issuedAt: DateTime(2026, 6, 1, 14, 30),
        items: const [ZatcaLine(description: 'A', quantity: 2, unitPriceCents: 5000)],
      );
      final facts = decodeZatcaQr(zatcaQrPayload(d))!;
      expect(facts, {1: 'شركة النور', 2: '300000000000003', 3: '2026-06-01T14:30:00Z', 4: '115.00', 5: '15.00'});
    });

    test('text that is not a payload is refused, and a name that is too long is not coded', () {
      expect(decodeZatcaQr('not base64!'), isNull);
      expect(decodeZatcaQr(base64Encode([1, 9, 65])), isNull);
      expect(decodeZatcaQr(''), isNull);
      expect(() => zatcaTlv(sellerName: 'x' * 256, vatNumber: '300000000000003', issuedAt: DateTime(2026), totalCents: 1, vatCents: 0), throwsArgumentError);
    });
  });

  group('checks', () {
    List<String> fields(ZatcaDraft d) => zatcaIssues(d).map((i) => i.field).toList();

    test('a complete simplified invoice needs nothing about the customer', () {
      expect(zatcaIssues(_draft()), isEmpty);
    });

    test('a tax invoice needs the customer VAT number, name and address', () {
      expect(fields(_draft(doc: ZatcaDocument.standard)), containsAll(['buyer.name', 'buyer.vat', 'buyer.address']));
      expect(zatcaIssues(_draft(doc: ZatcaDocument.standard, buyer: _buyer)), isEmpty);
    });

    test('what is missing or wrong is named by field', () {
      final f = fields(
        ZatcaDraft(
          seller: const ZatcaParty(name: '', vat: '123', postcode: '1'),
          buyer: const ZatcaParty(vat: '9'),
          number: '#!',
          issuedAt: DateTime(2026),
          items: const [ZatcaLine(description: ' ', quantity: 1, unitPriceCents: 100, discountCents: 500)],
        ),
      );
      expect(
        f,
        containsAll([
          'seller.name',
          'seller.vat',
          'seller.address',
          'seller.city',
          'seller.postcode',
          'buyer.vat',
          'number',
          'item.0.description',
          'item.0.discount',
        ]),
      );
    });
  });

  group('the PDF', () {
    test('a simplified invoice has the seller, the lines, the totals and the amount in words', () async {
      final text = _text(await buildZatcaPdf(_draft(), loadAsset: _asset));
      for (final s in [
        'Simplified Tax Invoice',
        'Invoice number',
        'INV-1',
        '2026-06-01 14:30',
        'Al Noor Trading',
        '300000000000003',
        '1234 King Fahd Road, Al Olaya, Riyadh 12211',
        '1010123456',
        'Laptop bag',
        '100.00',
        '15%',
        '115.00',
        'Total VAT',
        'Total amount due (SAR)',
        'One Hundred Fifteen Riyals Only',
      ]) {
        expect(text, contains(s), reason: s);
      }
      expect(text, isNot(contains('Customer')), reason: 'a simplified invoice may have no customer');
    });

    test('a tax invoice shows the customer', () async {
      final text = _text(
        await buildZatcaPdf(
          _draft(doc: ZatcaDocument.standard, buyer: _buyer),
          loadAsset: _asset,
        ),
      );
      for (final s in ['Tax Invoice', 'Customer', 'Al Amal Trading', '399999999900003', '55 Prince Sultan St, Jeddah 21442']) {
        expect(text, contains(s), reason: s);
      }
      expect(text, isNot(contains('Simplified')));
    });

    test('item rows show the discount, the VAT class and a note when prices include VAT', () async {
      final d = _draft(
        inclusive: true,
        items: const [
          ZatcaLine(description: 'A', quantity: 1, unitPriceCents: 11500, discountCents: 1150),
          ZatcaLine(description: 'B', quantity: 1, unitPriceCents: 1000, category: VatCategory.zero),
          ZatcaLine(description: 'C', quantity: 1, unitPriceCents: 2000, category: VatCategory.exempt),
        ],
      );
      final text = _text(await buildZatcaPdf(d, loadAsset: _asset));
      for (final s in ['10.00', '0%', 'Exempt', 'Prices include VAT', 'Discount']) {
        expect(text, contains(s), reason: s);
      }
    });

    test('Arabic names and notes are accepted', () async {
      final d = ZatcaDraft(
        seller: const ZatcaParty(name: 'شركة النور للتجارة', vat: '300000000000003', address: 'طريق الملك فهد', city: 'الرياض'),
        number: '5',
        issuedAt: DateTime(2026, 6, 1, 9, 0),
        items: const [ZatcaLine(description: 'خدمة استشارات', quantity: 1, unitPriceCents: 10000)],
        notes: 'شكرا لتعاملكم معنا',
      );
      final bytes = await buildZatcaPdf(d, loadAsset: _asset);
      expect(bytes.length, greaterThan(5000));
      expect(_text(bytes), contains('300000000000003'));
    });

    test('a long list goes on to more pages', () async {
      final d = _draft(
        items: [for (var i = 0; i < 70; i++) ZatcaLine(description: 'Item number $i', quantity: 1, unitPriceCents: 100 + i)],
      );
      final pages = extractPdfText(await buildZatcaPdf(d, loadAsset: _asset));
      expect(pages.length, greaterThan(1));
      expect(pages.map((p) => p.text).join(' '), contains('Item number 69'));
    });
  });

  group('the page', () {
    late Directory work;
    setUp(() {
      work = Directory.systemTemp.createTempSync('sv_sa');
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
          home: ZatcaInvoicePage(workDir: () async => work, loadAsset: _asset, now: DateTime(2026, 6, 1, 14, 30)),
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

    Future<void> tapKey(WidgetTester tester, String key) async {
      await tester.ensureVisible(find.byKey(ValueKey(key)));
      await tester.pump();
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pump();
    }

    Future<void> fill(WidgetTester tester) async {
      await type(tester, 'Business name *', 'Al Noor Trading');
      await type(tester, 'VAT registration number *', '300000000000003');
      await type(tester, 'Building number and street *', '1234 King Fahd Road');
      await type(tester, 'City *', 'Riyadh');
      await type(tester, 'Description *', 'Laptop bag');
      await type(tester, 'Quantity *', '2');
      await type(tester, 'Price each, before VAT *', '50');
    }

    testWidgets('the notice says plainly that the second phase is not done', (tester) async {
      await open(tester);
      expect(find.textContaining('does not connect to ZATCA'), findsOneWidget);
      expect(find.textContaining('second phase'), findsOneWidget);
    });

    testWidgets('the totals follow the items, the VAT class and the VAT-inclusive switch', (tester) async {
      await open(tester);
      await type(tester, 'Quantity *', '2');
      await type(tester, 'Price each, before VAT *', '50');
      await tester.ensureVisible(find.byKey(const ValueKey('sa-summary')));
      await tester.pump();
      expect(find.text('SAR 115.00'), findsOneWidget);
      expect(find.text('SAR 15.00'), findsOneWidget);
      await tapKey(tester, 'sa-vat-0-zero');
      expect(find.text('SAR 100.00'), findsWidgets);
      expect(find.text('SAR 0.00'), findsOneWidget);
      await tapKey(tester, 'sa-vat-0-standard');
      await tapKey(tester, 'sa-inclusive');
      expect(find.text('Price each, with VAT *'), findsOneWidget);
      expect(find.text('SAR 100.00'), findsWidgets);
      expect(find.text('SAR 13.04'), findsOneWidget);
    });

    testWidgets('a tax invoice asks for the customer details, a simplified one does not', (tester) async {
      await open(tester);
      expect(find.text('Customer name (optional)'), findsOneWidget);
      await tester.tap(find.text('Tax invoice'));
      await tester.pump();
      expect(find.text('Customer name *'), findsOneWidget);
      expect(find.text('Customer VAT number *'), findsOneWidget);
    });

    testWidgets('missing and wrong values are shown at their fields', (tester) async {
      await open(tester);
      await type(tester, 'VAT registration number *', '123');
      await tapKey(tester, 'sa-create');
      await settle(tester);
      expect(find.text('Fix the marked fields, then try again.'), findsOneWidget);
      expect(find.text('Enter your business name.'), findsOneWidget);
      expect(find.text('A VAT registration number has 15 digits and starts and ends with 3.'), findsOneWidget);
      expect(find.text('Item 1: the price must be an amount, for example 125.50.'), findsOneWidget);
      expect(work.listSync(), isEmpty);
    });

    testWidgets('a good invoice is made, the seller is remembered and the next number follows', (tester) async {
      await open(tester);
      await fill(tester);
      await tapKey(tester, 'sa-create');
      await settle(tester);
      await settle(tester);
      final file = Directory('${work.path}/invoices').listSync().whereType<File>().single;
      expect(file.path, endsWith('Saudi_1001.pdf'));
      final text = _text(file.readAsBytesSync());
      for (final s in ['Simplified Tax Invoice', 'Al Noor Trading', '300000000000003', '2026-06-01 14:30', '115.00', 'Laptop bag']) {
        expect(text, contains(s), reason: s);
      }
      expect(find.byKey(const ValueKey('pdf-result'), skipOffstage: false), findsOneWidget);
      final saved = await const TaxProfileStore(zatcaProfileKey).load();
      expect((saved['name'], saved['vat'], saved['city'], saved['lastNumber']), ('Al Noor Trading', '300000000000003', 'Riyadh', '1001'));

      await tester.pumpWidget(const SizedBox());
      await open(tester);
      expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Business name *')).controller!.text, 'Al Noor Trading');
      expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Invoice number *')).controller!.text, '1002');
    });

    for (final w in [320.0, 900.0]) {
      testWidgets('fits a ${w.toInt()} px wide screen', (tester) async {
        await open(tester, width: w);
        await tapKey(tester, 'sa-create');
        await settle(tester);
        expect(tester.takeException(), isNull);
      });
    }
  });
}

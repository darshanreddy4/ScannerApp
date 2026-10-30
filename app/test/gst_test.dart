import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:doculoom/core/theme/app_theme.dart';
import 'package:doculoom/features/reader/data/pdf_text_extractor.dart';
import 'package:doculoom/features/taxinvoice/data/gst_pdf.dart';
import 'package:doculoom/features/taxinvoice/data/tax_profile_store.dart';
import 'package:doculoom/features/taxinvoice/domain/gst.dart';
import 'package:doculoom/features/taxinvoice/domain/tax_common.dart';
import 'package:doculoom/features/taxinvoice/presentation/gst_invoice_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Uint8List> _asset(String path) => File(path).readAsBytes();

String _text(Uint8List pdf) => extractPdfText(pdf).map((p) => p.text).join('\n').replaceAll('\u00A0', ' ');

const _seller = GstParty(name: 'Sharma Traders', address: '14 MG Road', city: 'Pune', pin: '411001', stateCode: '27', gstin: '27AAPFU0939F1ZV');
const _buyer = GstParty(name: 'Kumar Electronics', address: '22 Brigade Road', city: 'Ahmedabad', pin: '380001', stateCode: '24', gstin: '24AAACC1206D1ZM');

GstDraft _draft({
  String place = '27',
  List<GstLine>? items,
  GstDocument doc = GstDocument.taxInvoice,
  GstParty seller = _seller,
  GstParty buyer = _buyer,
  String number = 'INV/25-26/001',
}) => GstDraft(
  document: doc,
  seller: seller,
  buyer: buyer,
  number: number,
  date: DateTime(2026, 6, 1),
  placeOfSupply: place,
  items: items ?? const [GstLine(description: 'Item', quantity: 1, unitPriceCents: 100000, rateHundredths: 1800)],
);

void main() {
  group('GSTIN and other numbers', () {
    test('real GSTINs pass, and the check character is worked out', () {
      expect(gstinIssue('g', '27AAPFU0939F1ZV'), isNull);
      expect(gstinIssue('g', '24AAACC1206D1ZM'), isNull);
      expect(gstinIssue('g', ' 27aapfu0939f1zv '), isNull, reason: 'case and spaces do not matter');
      expect(gstinCheckChar('27AAPFU0939F1Z'), 'V');
      expect(gstinCheckChar('24AAACC1206D1Z'), 'M');
    });

    test('a wrong GSTIN says what is wrong', () {
      expect(gstinIssue('g', '27AAPFU0939F1Z')!.text, contains('15 characters'));
      expect(gstinIssue('g', '27AAPFU0939F1ZX')!.text, contains('last character'));
      expect(gstinIssue('g', '27AAPFU0939F2ZV')!.text, contains('last character'), reason: 'one digit changed');
      expect(gstinIssue('g', 'AAAAAAAAAAAAAAA')!.text, contains('shape'));
      expect(gstinIssue('g', '40AAPFU0939F1ZV')!.text, contains('40 is not'));
    });

    test('the PAN, PIN, IFSC, HSN and invoice number have their shapes', () {
      expect(panOfGstin('27AAPFU0939F1ZV'), 'AAPFU0939F');
      expect(isValidPan('AAPFU0939F'), isTrue);
      expect(isValidPan('AAPF0939FU'), isFalse);
      expect(isValidPin('411001'), isTrue);
      expect(isValidPin('011001'), isFalse);
      expect(isValidPin('41100'), isFalse);
      expect(isValidIfsc('HDFC0001234'), isTrue);
      expect(isValidIfsc('HDFC1001234'), isFalse);
      for (final h in ['8528', '854442', '85444200']) {
        expect(isValidHsn(h), isTrue, reason: h);
      }
      for (final h in ['85', '85284', '852A', '']) {
        expect(isValidHsn(h), isFalse, reason: h);
      }
      expect(isValidGstInvoiceNumber('INV/25-26/0001'), isTrue);
      expect(isValidGstInvoiceNumber('INV/2025-26/000001X'), isFalse, reason: '17 characters');
      expect(isValidGstInvoiceNumber('INV 001'), isFalse);
      expect(isValidGstInvoiceNumber(''), isFalse);
    });

    test('the states and union territories', () {
      expect(gstStateOf('27')!.name, 'Maharashtra');
      expect(gstStateOf('07')!.unionTerritory, isFalse, reason: 'Delhi has a legislature');
      expect(gstStateOf('04')!.unionTerritory, isTrue);
      expect(gstStateOf('25'), isNull);
      expect(gstStates.map((s) => s.code).toSet().length, gstStates.length);
    });
  });

  group('invoice numbers and the financial year', () {
    test('April starts the year', () {
      expect(financialYear(DateTime(2026, 3, 31)), '25-26');
      expect(financialYear(DateTime(2026, 4, 1)), '26-27');
      expect(financialYear(DateTime(2026, 12, 31)), '26-27');
    });

    test('the next number counts up and starts again in a new year', () {
      expect(nextGstInvoiceNumber('', DateTime(2026, 6, 1)), 'INV/26-27/001');
      expect(nextGstInvoiceNumber('INV/26-27/009', DateTime(2026, 6, 1)), 'INV/26-27/010');
      expect(nextGstInvoiceNumber('INV/25-26/120', DateTime(2026, 6, 1)), 'INV/26-27/001');
      expect(nextGstInvoiceNumber('B-102', DateTime(2026, 6, 1)), 'B-103');
    });
  });

  group('amounts', () {
    test('Indian grouping, with lakhs and crores', () {
      expect(groupIndian(5), '0.05');
      expect(groupIndian(99999), '999.99');
      expect(groupIndian(123456), '1,234.56');
      expect(groupIndian(12345678), '1,23,456.78');
      expect(groupIndian(1000000000), '1,00,00,000.00');
      expect(groupIndian(-12345678), '-1,23,456.78');
      expect(groupWestern(12345678), '123,456.78');
    });

    test('rates in hundredths of a percent', () {
      expect(rateHundredths('18'), 1800);
      expect(rateHundredths('2,5'), 250);
      expect(rateHundredths('0.25'), 25);
      expect(rateHundredths('0'), 0);
      expect(rateHundredths('1.234'), isNull);
      expect(rateHundredths('abc'), isNull);
      expect(rateText(1800), '18');
      expect(rateText(250), '2.5');
      expect(rateText(25), '0.25');
      expect(percentOf(100000, 1800), 18000);
    });
  });

  group('tax', () {
    test('inside a state the rate is split in two halves, CGST and SGST', () {
      final t = computeGst(_draft());
      expect((t.taxable, t.cgst, t.sgst, t.igst, t.total, t.roundOff, t.grand), (100000, 9000, 9000, 0, 118000, 0, 118000));
    });

    test('between states the whole rate is IGST', () {
      final t = computeGst(_draft(place: '24'));
      expect((t.cgst, t.sgst, t.igst, t.grand), (0, 0, 18000, 118000));
    });

    test('half rates, and a rate of nothing', () {
      final t = computeGst(
        _draft(
          items: const [
            GstLine(description: 'A', quantity: 1, unitPriceCents: 100000, rateHundredths: 250),
            GstLine(description: 'B', quantity: 2, unitPriceCents: 5000),
          ],
        ),
      );
      expect(t.lines[0].cgst, 1250, reason: '1.25% each');
      expect(t.lines[1].tax, 0);
      expect(t.taxable, 110000);
    });

    test('the total is rounded to the rupee and the difference is shown', () {
      GstTotals one(int price) => computeGst(
        _draft(
          items: [GstLine(description: 'A', quantity: 1, unitPriceCents: price, rateHundredths: 0)],
        ),
      );
      expect(one(100040).roundOff, -40);
      expect(one(100050).roundOff, 50);
      expect(one(100051).roundOff, 49, reason: '1000.51 goes up to 1001');
      expect(one(100000).roundOff, 0);
      expect(one(100040).grand, 100000);
    });

    test('the quantity can be a fraction', () {
      expect(const GstLine(description: 'A', quantity: 2.5, unitPriceCents: 10000).taxableCents, 25000);
      expect(const GstLine(description: 'A', quantity: 0.333, unitPriceCents: 10000).taxableCents, 3330);
    });

    test('a bill of supply has no tax whatever the rate says', () {
      final t = computeGst(_draft(doc: GstDocument.billOfSupply));
      expect((t.tax, t.grand), (0, 100000));
    });

    test('the summary adds lines with the same code and rate', () {
      final d = _draft(
        items: const [
          GstLine(description: 'A', hsn: '8528', quantity: 1, unitPriceCents: 100000, rateHundredths: 1800),
          GstLine(description: 'B', hsn: '8528', quantity: 1, unitPriceCents: 50000, rateHundredths: 1800),
          GstLine(description: 'C', hsn: '8528', quantity: 1, unitPriceCents: 10000, rateHundredths: 500),
        ],
      );
      final rows = hsnSummary(d, computeGst(d));
      expect(rows.length, 2);
      expect((rows.first.taxable, rows.first.cgst, rows.first.rateHundredths), (150000, 13500, 1800));
    });

    test('a union territory without a legislature charges UTGST', () {
      expect(_draft(seller: const GstParty(stateCode: '04')).sellerIsUt, isTrue);
      expect(_draft().sellerIsUt, isFalse);
    });
  });

  group('checks', () {
    List<String> fields(GstDraft d) => gstIssues(d).map((i) => i.field).toList();

    test('a complete invoice has no problems', () {
      expect(gstIssues(_draft()), isEmpty);
    });

    test('what is missing is named by field', () {
      final f = fields(GstDraft(date: DateTime(2026), items: const []));
      expect(f, containsAll(['seller.name', 'seller.address', 'seller.state', 'seller.gstin', 'buyer.name', 'place', 'number', 'items']));
    });

    test('a tax invoice needs a GSTIN, a bill of supply does not', () {
      const noGstin = GstParty(name: 'Devi', address: 'Bazaar', stateCode: '27');
      expect(fields(_draft(seller: noGstin)), contains('seller.gstin'));
      expect(fields(_draft(seller: noGstin, doc: GstDocument.billOfSupply)), isNot(contains('seller.gstin')));
    });

    test('a GSTIN of one state with another state chosen is called out', () {
      final i = gstIssues(
        _draft(
          seller: const GstParty(name: 'A', address: 'B', stateCode: '29', gstin: '27AAPFU0939F1ZV'),
        ),
      ).firstWhere((i) => i.field == 'seller.gstin');
      expect(i.text, contains('Maharashtra'));
      expect(i.text, contains('Karnataka'));
      final b = gstIssues(
        _draft(
          buyer: const GstParty(name: 'K', stateCode: '29', gstin: '24AAACC1206D1ZM'),
        ),
      ).firstWhere((i) => i.field == 'buyer.gstin');
      expect(b.text, contains('Gujarat'));
    });

    test('items, numbers and payment details are checked', () {
      final f = fields(
        GstDraft(
          seller: _seller,
          buyer: _buyer,
          number: 'INV 1',
          date: DateTime(2026),
          placeOfSupply: '27',
          items: const [GstLine(description: ' ', hsn: '85', quantity: 1, unitPriceCents: 100, rateHundredths: 4100)],
          upiId: 'nobank',
          ifsc: 'X',
          accountNumber: '12',
        ),
      );
      expect(f, containsAll(['number', 'item.0.description', 'item.0.hsn', 'item.0.rate', 'upi', 'ifsc', 'account']));
    });

    test('the messages can be translated before the values go in', () {
      final i = gstIssues(
        _draft(
          seller: const GstParty(name: 'A', address: 'B', stateCode: '29', gstin: '27AAPFU0939F1ZV'),
        ),
      ).first;
      expect(i.template, contains('{code}'));
    });
  });

  group('the PDF', () {
    test('a tax invoice inside a state shows CGST and SGST, the tax summary and the amount in words', () async {
      final text = _text(
        await buildGstPdf(
          _draft(
            items: const [GstLine(description: 'LED TV', hsn: '8528', quantity: 2, unit: 'Nos', unitPriceCents: 3299900, rateHundredths: 1800)],
          ),
          loadAsset: _asset,
        ),
      );
      for (final s in [
        'TAX INVOICE',
        'Sharma Traders',
        '27AAPFU0939F1ZV',
        'Maharashtra (27)',
        'INV/25-26/001',
        '01/06/2026',
        'LED TV',
        '8528',
        '65,998.00',
        '5,939.82',
        'CGST',
        'SGST',
        'Tax summary',
        'Rupees',
        'Authorised signatory',
      ]) {
        expect(text, contains(s), reason: s);
      }
      expect(text, contains('Total'));
      expect(text, isNot(contains('IGST')));
    });

    test('between states it shows IGST only', () async {
      final text = _text(await buildGstPdf(_draft(place: '24'), loadAsset: _asset));
      expect(text, contains('IGST'));
      expect(text, isNot(contains('CGST')));
      expect(text, contains('Gujarat (24)'));
    });

    test('a bill of supply has no tax columns', () async {
      final text = _text(await buildGstPdf(_draft(doc: GstDocument.billOfSupply), loadAsset: _asset));
      expect(text, contains('BILL OF SUPPLY'));
      for (final s in ['CGST', 'IGST', 'Tax summary', 'Reverse charge']) {
        expect(text, isNot(contains(s)), reason: s);
      }
    });

    test('bank details and the UPI ID are on it, and a long list goes on to more pages', () async {
      final d = GstDraft(
        seller: _seller,
        buyer: _buyer,
        number: 'A1',
        date: DateTime(2026, 6, 1),
        placeOfSupply: '27',
        bankName: 'HDFC Bank',
        accountNumber: '50100123456789',
        ifsc: 'HDFC0001234',
        upiId: 'sharma@hdfcbank',
        items: [
          for (var i = 0; i < 60; i++)
            GstLine(
              description: 'Part number $i with a longer description to fill the line',
              hsn: '8528',
              quantity: 1,
              unitPriceCents: 10000 + i,
              rateHundredths: 1800,
            ),
        ],
      );
      final pages = extractPdfText(await buildGstPdf(d, loadAsset: _asset));
      expect(pages.length, greaterThan(1));
      final all = pages.map((p) => p.text).join(' ');
      expect(all, contains('Part number 59'));
      for (final s in ['HDFC Bank', '50100123456789', 'HDFC0001234', 'sharma@hdfcbank']) {
        expect(all, contains(s), reason: s);
      }
    });
  });

  group('the page', () {
    late Directory work;
    setUp(() {
      work = Directory.systemTemp.createTempSync('sv_gst');
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
          home: GstInvoicePage(workDir: () async => work, loadAsset: _asset, now: DateTime(2026, 6, 1)),
        ),
      );
      await settle(tester);
    }

    Future<void> type(WidgetTester tester, String label, String text, {int index = 0}) async {
      final f = find.widgetWithText(TextField, label);
      await tester.ensureVisible(f.at(index));
      await tester.pump();
      await tester.enterText(f.at(index), text);
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

    Future<void> fill(WidgetTester tester) async {
      await type(tester, 'Business name *', 'Sharma Traders');
      await type(tester, 'Address *', '14 MG Road');
      await type(tester, 'Your GSTIN *', '27AAPFU0939F1ZV');
      await type(tester, 'Customer name *', 'Kumar Electronics');
      await pick(tester, 'gst-buyer-state', 'Karnataka');
      await type(tester, 'Description *', 'LED TV');
      await type(tester, 'HSN or SAC code', '8528');
      await type(tester, 'Price each, before tax *', '32999');
    }

    testWidgets('the state follows the GSTIN, and the page says which tax will be charged', (tester) async {
      await open(tester);
      await type(tester, 'Your GSTIN *', '27AAPFU0939F1ZV');
      await tester.pump();
      expect(find.textContaining('Maharashtra (27)'), findsWidgets);
      await pick(tester, 'gst-buyer-state', 'Karnataka');
      expect(find.text('Between states: IGST is charged.'), findsOneWidget);
      await pick(tester, 'gst-buyer-state', 'Maharashtra');
      expect(find.text('Inside the state: CGST and SGST are charged.'), findsOneWidget);
    });

    testWidgets('the running totals follow the items', (tester) async {
      await open(tester);
      await type(tester, 'Your GSTIN *', '27AAPFU0939F1ZV');
      await pick(tester, 'gst-buyer-state', 'Maharashtra');
      await type(tester, 'Price each, before tax *', '1000');
      await tester.ensureVisible(find.byKey(const ValueKey('gst-summary')));
      await tester.pump();
      expect(find.text('\u20B9 1,180.00'), findsOneWidget);
      expect(find.text('CGST'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('gst-rate-0-5')));
      await tester.pump();
      expect(find.text('\u20B9 1,050.00'), findsOneWidget);
    });

    testWidgets('missing and wrong values are shown at their fields', (tester) async {
      await open(tester);
      await type(tester, 'Your GSTIN *', '27AAPFU0939F1ZX');
      await tester.ensureVisible(find.byKey(const ValueKey('gst-create')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('gst-create')));
      await settle(tester);
      expect(find.text('Fix the marked fields, then try again.'), findsOneWidget);
      expect(find.textContaining('The last character of this GSTIN is not right'), findsOneWidget);
      expect(find.text('Enter your business name.'), findsOneWidget);
      expect(find.text('Enter the customer\'s name.'), findsOneWidget);
      expect(find.text('Item 1: the price must be an amount, for example 125.50.'), findsOneWidget);
      expect(work.listSync(), isEmpty);
    });

    testWidgets('a good invoice is made, the seller is remembered and the next number follows', (tester) async {
      await open(tester);
      await fill(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('gst-create')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('gst-create')));
      await settle(tester);
      await settle(tester);
      final file = Directory('${work.path}/invoices').listSync().whereType<File>().single;
      expect(file.path, endsWith('GST_INV_26-27_001.pdf'));
      final text = _text(file.readAsBytesSync());
      for (final s in ['TAX INVOICE', 'Sharma Traders', 'Kumar Electronics', 'Karnataka (29)', 'IGST', '8528', '38,938.82']) {
        expect(text, contains(s), reason: s);
      }
      expect(find.byKey(const ValueKey('pdf-result'), skipOffstage: false), findsOneWidget);

      final saved = await const TaxProfileStore(gstProfileKey).load();
      expect((saved['name'], saved['gstin'], saved['state'], saved['lastNumber']), ('Sharma Traders', '27AAPFU0939F1ZV', '27', 'INV/26-27/001'));

      await tester.pumpWidget(const SizedBox());
      await open(tester);
      expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Business name *')).controller!.text, 'Sharma Traders');
      expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Invoice number *')).controller!.text, 'INV/26-27/002');
    });

    testWidgets('a bill of supply hides the tax rate and the tax columns', (tester) async {
      await open(tester);
      expect(find.text('GST rate % *'), findsOneWidget);
      await tester.tap(find.text('Bill of supply'));
      await tester.pump();
      expect(find.text('GST rate % *'), findsNothing);
      expect(find.byKey(const ValueKey('gst-reverse')), findsNothing);
      expect(find.text('Create bill of supply'), findsOneWidget);
    });

    for (final w in [320.0, 900.0]) {
      testWidgets('fits a ${w.toInt()} px wide screen', (tester) async {
        await open(tester, width: w);
        await tester.ensureVisible(find.byKey(const ValueKey('gst-create')));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('gst-create')));
        await settle(tester);
        expect(tester.takeException(), isNull);
      });
    }
  });
}

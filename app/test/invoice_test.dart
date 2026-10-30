import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:doculoom/app/di.dart';
import 'package:doculoom/core/theme/app_theme.dart';
import 'package:doculoom/features/einvoice/domain/einvoice.dart';
import 'package:doculoom/features/invoice/data/invoice_pdf.dart';
import 'package:doculoom/features/invoice/data/invoice_profile_store.dart';
import 'package:doculoom/features/invoice/domain/invoice.dart';
import 'package:doculoom/features/invoice/domain/invoice_labels.dart';
import 'package:doculoom/features/invoice/presentation/invoice_page.dart';
import 'package:doculoom/features/reader/data/pdf_text_extractor.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Uint8List> _asset(String path) => File(path).readAsBytes();

InvoiceDraft _draft({List<InvoiceItem>? items, String currency = 'EUR', String lang = 'de', bool reverse = false}) => InvoiceDraft(
  seller: const InvoiceParty(
    name: 'Müller & Söhne GmbH',
    street: 'Hauptstraße 1',
    postcode: '10115',
    city: 'Berlin',
    country: 'DE',
    vatId: 'DE123456789',
    email: 'rechnung@mueller.example',
  ),
  sellerIban: 'DE33100205000001194700',
  sellerBic: 'BHBLDEHHXXX',
  buyer: const InvoiceParty(name: 'Kunde AG', street: 'Rue 5', postcode: '75001', city: 'Paris', country: 'FR', vatId: 'FR12345678901'),
  number: '2025-007',
  issueDate: DateTime(2025, 3, 15),
  dueDate: DateTime(2025, 3, 29),
  currency: currency,
  items: items ?? const [InvoiceItem(description: 'Entwurf für Logo', quantity: 10, unit: 'Std.', unitPriceCents: 9000, vatRate: 19)],
  language: lang,
  reverseCharge: reverse,
);

String _text(Uint8List pdf) => extractPdfText(pdf).map((p) => p.text).join('\n').replaceAll('\u00A0', ' ');

void main() {
  group('amounts', () {
    test('a line is rounded half up in cents', () {
      expect(const InvoiceItem(description: 'a', quantity: 3, unitPriceCents: 1999, vatRate: 19).netCents, 5997);
      expect(const InvoiceItem(description: 'a', quantity: 1.5, unitPriceCents: 333, vatRate: 19).netCents, 500);
      expect(const InvoiceItem(description: 'a', quantity: 0.001, unitPriceCents: 500, vatRate: 19).netCents, 1);
    });

    test('VAT is worked out once per rate, highest rate first', () {
      final t = computeTotals(const [
        InvoiceItem(description: 'a', quantity: 1, unitPriceCents: 333, vatRate: 19),
        InvoiceItem(description: 'b', quantity: 1, unitPriceCents: 333, vatRate: 19),
        InvoiceItem(description: 'c', quantity: 2, unitPriceCents: 1000, vatRate: 7),
      ]);
      expect([for (final g in t.groups) g.rate], [19, 7]);
      expect(t.groups[0].netCents, 666);
      expect(t.groups[0].vatCents, 127, reason: '666 x 19% = 126.54 cents of a euro: 1.27');
      expect(t.groups[1].vatCents, 140);
      expect((t.netCents, t.vatCents, t.grossCents), (2666, 267, 2933));
    });

    test('reverse charge has no VAT at all', () {
      final t = computeTotals(const [InvoiceItem(description: 'a', quantity: 1, unitPriceCents: 10000, vatRate: 19)], reverseCharge: true);
      expect((t.vatCents, t.grossCents, t.groups.single.rate), (0, 10000, 0));
    });

    test('typed numbers', () {
      expect(parseCents('12'), 1200);
      expect(parseCents('12,5'), 1250);
      expect(parseCents('0'), 0);
      expect(parseCents('1.234,56'), isNull);
      expect(parseCents('-1'), isNull);
      expect(parseQuantity('1,5'), 1.5);
      expect(parseQuantity('0'), isNull);
      expect(parseQuantity('x'), isNull);
      expect(parseVatRate('5,5'), 5.5);
      expect(parseVatRate('100'), 100);
      expect(parseVatRate('101'), isNull);
      expect(parseVatRate('-1'), isNull);
    });

    test('money is written the way the country writes it', () {
      expect(formatMoney(123456, 'EUR', country: 'DE'), '1.234,56\u00A0\u20AC');
      expect(formatMoney(123456, 'EUR', country: 'FR'), '1\u00A0234,56\u00A0\u20AC');
      expect(formatMoney(123456, 'GBP', country: 'GB'), '\u00A31,234.56');
      expect(formatMoney(123456, 'CHF', country: 'CH'), '1\u2019234.56\u00A0CHF');
      expect(formatMoney(5, 'EUR'), '0,05\u00A0\u20AC');
      expect(formatMoney(-250, 'PLN', country: 'PL'), '-2,50\u00A0z\u0142');
      expect(formatMoney(100000000, 'SEK', country: 'SE'), '1\u00A0000\u00A0000,00\u00A0kr');
    });
  });

  group('numbers and defaults', () {
    test('the next invoice number', () {
      final now = DateTime(2025, 6, 1);
      expect(nextInvoiceNumber('2025-007', now), '2025-008');
      expect(nextInvoiceNumber('2025-099', now), '2025-100');
      expect(nextInvoiceNumber('2024-120', now), '2025-001');
      expect(nextInvoiceNumber('RE-0042', now), 'RE-0043');
      expect(nextInvoiceNumber('INV9', now), 'INV10');
      expect(nextInvoiceNumber('', now), '2025-001');
      expect(nextInvoiceNumber('abc', now), '2025-001');
    });

    test('language and VAT rates follow the country', () {
      expect(invoiceLanguageFor('de'), 'de');
      expect(invoiceLanguageFor('AT'), 'de');
      expect(invoiceLanguageFor('FR'), 'fr');
      expect(invoiceLanguageFor('SE'), 'en');
      expect(invoiceLanguageFor(null), 'en');
      expect(commonVatRates('DE'), [19, 7, 0]);
      expect(commonVatRates('xx'), [20, 10, 0]);
      for (final code in InvoiceLabels.supported.keys) {
        for (final key in [
          'invoice',
          'number',
          'date',
          'due',
          'description',
          'quantity',
          'unitPrice',
          'vat',
          'net',
          'payable',
          'payBy',
          'reverse',
          'thanks',
          'page',
          'of',
        ]) {
          expect(InvoiceLabels.of(code)[key], isNotEmpty, reason: '$code $key');
        }
        expect(InvoiceLabels.of(code)['payBy'], contains('{amount}'));
        expect(InvoiceLabels.of(code)['payBy'], contains('{date}'));
      }
      expect(InvoiceLabels.of('xx')['invoice'], 'Invoice');
    });

    test('what is missing is named', () {
      expect(invoiceProblem(_draft()), isNull);
      expect(invoiceProblem(InvoiceDraft(seller: const InvoiceParty(), issueDate: DateTime(2025), dueDate: DateTime(2025))), contains('name'));
      final base = _draft();
      InvoiceDraft with_({InvoiceParty? buyer, String? number, List<InvoiceItem>? items, String? iban, DateTime? due}) => InvoiceDraft(
        seller: base.seller,
        sellerIban: iban ?? base.sellerIban,
        buyer: buyer ?? base.buyer,
        number: number ?? base.number,
        issueDate: base.issueDate,
        dueDate: due ?? base.dueDate,
        items: items ?? base.items,
      );
      expect(invoiceProblem(with_(buyer: const InvoiceParty())), contains('customer'));
      expect(invoiceProblem(with_(number: ' ')), contains('number'));
      expect(invoiceProblem(with_(items: const [])), contains('item'));
      expect(invoiceProblem(with_(items: const [InvoiceItem(description: ' ', quantity: 1, unitPriceCents: 1, vatRate: 0)])), contains('description'));
      expect(invoiceProblem(with_(iban: 'DE00')), contains('IBAN'));
      expect(invoiceProblem(with_(due: DateTime(2025, 3, 1))), contains('due date'));
    });
  });

  group('the PDF', () {
    test('has the invoice, with accents, euro sign and payment details', () async {
      final bytes = await buildInvoicePdf(_draft(), loadAsset: _asset);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      final text = _text(bytes);
      for (final s in [
        'Rechnung 2025-007',
        'Müller & Söhne GmbH',
        'Entwurf für Logo',
        'Kunde AG',
        'FR',
        'USt-IdNr. DE123456789',
        'DE33 1002 0500 0001 1947 00',
        'BHBLDEHHXXX',
        '15.03.2025',
        '29.03.2025',
      ]) {
        expect(text, contains(s), reason: s);
      }
      // 10 x 90 EUR + 19 % VAT.
      expect(text, contains('900,00 \u20AC'));
      expect(text, contains('171,00 \u20AC'));
      expect(text, contains('1.071,00 \u20AC'));
      expect(text, contains('Seite 1 von 1'));
    });

    test('is written in the chosen language', () async {
      final fr = _text(await buildInvoicePdf(_draft(lang: 'fr'), loadAsset: _asset));
      expect(fr, contains('Facture 2025-007'));
      expect(fr, contains('Net \u00E0 payer'));
      final en = _text(await buildInvoicePdf(_draft(lang: 'en'), loadAsset: _asset));
      expect(en, contains('Invoice 2025-007'));
      expect(en, contains('Amount due'));
    });

    test('reverse charge says why there is no VAT', () async {
      final text = _text(await buildInvoicePdf(_draft(reverse: true, lang: 'en'), loadAsset: _asset));
      expect(text, contains('Reverse charge'));
      expect(text, isNot(contains('171,00')));
    });

    test('other currencies, and no payment QR text outside euro', () async {
      final gbp = await buildInvoicePdf(
        _draft(currency: 'GBP', lang: 'en'),
        loadAsset: _asset,
      );
      final text = _text(gbp);
      expect(text, contains('\u00A3'));
      expect(text, isNot(contains('Scan to pay')));
      expect(_text(await buildInvoicePdf(_draft(lang: 'en'), loadAsset: _asset)), contains('Scan to pay'));
    });

    test('a long invoice runs over to a second page with its footer', () async {
      final items = [for (var i = 1; i <= 60; i++) InvoiceItem(description: 'Position $i', quantity: 1, unitPriceCents: 1000 + i, vatRate: 19)];
      final pages = extractPdfText(await buildInvoicePdf(_draft(items: items), loadAsset: _asset));
      expect(pages.length, greaterThan(1));
      expect(pages.last.text, contains('Seite ${pages.length} von ${pages.length}'));
      expect(pages.map((p) => p.text).join(' '), contains('Position 60'));
    });
  });

  group('page', () {
    late Directory dir;
    final shared = <String>[];

    setUp(() => dir = Directory.systemTemp.createTempSync('sv_invoice'));
    tearDown(() => dir.deleteSync(recursive: true));

    Future<void> open(WidgetTester tester, {double width = 400}) async {
      tester.view.physicalSize = Size(width * 3, 3600 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await sl.reset();
      // A fresh page, as when the screen is opened again.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: InvoicePage(workDir: () async => dir, loadAsset: _asset, now: DateTime(2025, 3, 15)),
        ),
      );
      await settle(tester);
    }

    Future<void> enter(WidgetTester tester, String label, String text, {int index = 0}) async {
      await tester.enterText(find.widgetWithText(TextField, label).at(index), text);
      await tester.pump();
    }

    testWidgets('makes a PDF, keeps the details and counts the number up next time', (tester) async {
      SharedPreferences.setMockInitialValues({});
      shared.clear();
      await open(tester);
      await enter(tester, 'Name or company', 'Müller GmbH');
      await enter(tester, 'Street and number', 'Hauptstraße 1');
      await enter(tester, 'Town', 'Berlin');
      await enter(tester, 'Name or company', 'Kunde AG', index: 1);
      await enter(tester, 'Description', 'Beratung');
      await enter(tester, 'Price each, without VAT', '100');
      await enter(tester, 'VAT %', '19');
      expect(find.text('119,00\u00A0\u20AC'), findsWidgets);

      await tester.ensureVisible(find.byKey(const ValueKey('create-invoice')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('create-invoice')));
      await settle(tester);
      final files = Directory('${dir.path}/invoices').listSync().whereType<File>().toList();
      expect(files.single.path, endsWith('Invoice_2025-001.pdf'));
      expect(_text(files.single.readAsBytesSync()), contains('Beratung'));
      expect(find.text('Invoice_2025-001.pdf'), findsOneWidget);

      final saved = await const InvoiceProfileStore().load();
      expect((saved.seller.name, saved.seller.city, saved.lastNumber), ('Müller GmbH', 'Berlin', '2025-001'));

      await open(tester);
      expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Invoice number')).controller!.text, '2025-002');
      expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Name or company').first).controller!.text, 'Müller GmbH');
    });

    testWidgets('says what is missing instead of making an empty invoice', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await open(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('create-invoice')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('create-invoice')));
      await settle(tester);
      expect(find.textContaining('Item 1: the price'), findsOneWidget);
      expect(Directory('${dir.path}/invoices').existsSync(), isFalse);
    });

    for (final width in [320.0, 400.0, 900.0]) {
      testWidgets('fits at ${width.toInt()} px', (tester) async {
        SharedPreferences.setMockInitialValues({});
        await open(tester, width: width);
        await tester.tap(find.text('Add an item'));
        await tester.pump();
        expect(find.text('Item 2'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}

/// Pages that read files and build PDFs wait on the real event loop between steps.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 16; i++) {
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
  }
  await tester.pump();
}

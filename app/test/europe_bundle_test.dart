import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:doculoom/features/cv/data/cv_pdf.dart';
import 'package:doculoom/features/cv/domain/cv.dart';
import 'package:doculoom/features/einvoice/domain/einvoice.dart';
import 'package:doculoom/features/invoice/data/invoice_pdf.dart';
import 'package:doculoom/features/invoice/domain/invoice.dart';
import 'package:doculoom/features/signing/data/pdf_signing.dart';
import 'package:doculoom/features/signing/data/pkcs12.dart';

// Loads fonts the way the app does on a phone, from the asset bundle that pubspec.yaml declares.
Future<Uint8List> _bundle(String path) async => (await rootBundle.load(path)).buffer.asUint8List();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the CV is made from the fonts in the app bundle', () async {
    final pdf = await buildCvPdf(
      const CvData(name: 'Anna Rossi', email: 'a@b.eu', summary: 'Hello'),
      loadAsset: _bundle,
    );
    expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
  });

  test('the invoice is made from the fonts in the app bundle', () async {
    final draft = InvoiceDraft(
      seller: const InvoiceParty(name: 'Müller GmbH', street: 'Hauptstraße 1', postcode: '10115', city: 'Berlin', country: 'DE'),
      sellerIban: 'DE33100205000001194700',
      buyer: const InvoiceParty(name: 'Kunde AG', street: 'Rue 5', postcode: '75001', city: 'Paris', country: 'FR'),
      number: '2025-007',
      issueDate: DateTime(2025, 3, 15),
      dueDate: DateTime(2025, 3, 29),
      items: const [InvoiceItem(description: 'Work', quantity: 1, unitPriceCents: 10000, vatRate: 19)],
    );
    final pdf = await buildInvoicePdf(draft, loadAsset: _bundle);
    expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
  });

  test('opening a certificate and signing take a few seconds at most, even when the code is not optimised', () {
    final file = File('test/fixtures/signing/rsa_aes.p12').readAsBytesSync();
    final pdf = File('test/fixtures/signing/xrefstream.pdf').readAsBytesSync();
    final t = Stopwatch()..start();
    final cred = readPkcs12(file, 'secret');
    final opened = t.elapsedMilliseconds;
    signPdf(pdf, cred);
    // ignore: avoid_print
    print('TIMING open ${opened}ms, sign ${t.elapsedMilliseconds - opened}ms');
    expect(t.elapsedMilliseconds, lessThan(20000));
  });
}

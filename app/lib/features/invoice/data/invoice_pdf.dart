import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../qr/domain/payments.dart';
import '../domain/invoice.dart';
import '../domain/invoice_labels.dart';

double _mm(double v) => v * PdfPageFormat.mm;

/// Makes the invoice as an A4 PDF laid out to DIN 5008 (form B): address in the window of a DL envelope, fold and punch marks,
/// information block, table, totals, payment details with a SEPA QR code, and the footer. Text is Roboto, so accents and the euro sign print.
Future<Uint8List> buildInvoicePdf(InvoiceDraft d, {required Future<Uint8List> Function(String asset) loadAsset}) async {
  final regular = pw.Font.ttf((await loadAsset('assets/fonts/Roboto-Regular.ttf')).buffer.asByteData());
  final bold = pw.Font.ttf((await loadAsset('assets/fonts/Roboto-Bold.ttf')).buffer.asByteData());
  final theme = pw.ThemeData.withFont(base: regular, bold: bold);
  final l = InvoiceLabels.of(d.language);
  final country = d.seller.country;
  String money(int c) => formatMoney(c, d.currency, country: country);
  String date(DateTime t) => '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}.${t.year}';
  final totals = computeTotals(d.items, reverseCharge: d.reverseCharge);
  final grey = PdfColor.fromInt(0xFF64748B);
  final line = PdfColor.fromInt(0xFFCBD5E1);

  pw.TextStyle small([PdfColor? c]) => pw.TextStyle(fontSize: 8, color: c ?? grey);

  final sellerLine = [
    d.seller.name,
    d.seller.street,
    [d.seller.postcode, d.seller.city].where((s) => s.isNotEmpty).join(' '),
  ].where((s) => s.isNotEmpty).join(' \u00B7 ');
  final recipient = [
    d.buyer.name,
    d.buyer.street,
    [d.buyer.postcode, d.buyer.city].where((s) => s.isNotEmpty).join(' '),
    if (d.buyer.country.isNotEmpty && d.buyer.country.toUpperCase() != d.seller.country.toUpperCase()) d.buyer.country.toUpperCase(),
  ].where((s) => s.isNotEmpty).toList();

  final info = <(String, String)>[
    (l['number'], d.number),
    (l['date'], date(d.issueDate)),
    (l['due'], date(d.dueDate)),
    if (d.buyer.vatId.isNotEmpty) (l['customerVat'], d.buyer.vatId),
  ];

  final payload = d.currency == 'EUR' && d.sellerIban.trim().isNotEmpty && totals.grossCents > 0
      ? (sepaProblem(
                  name: d.seller.name,
                  iban: d.sellerIban,
                  bic: d.sellerBic,
                  amount: (totals.grossCents / 100).toStringAsFixed(2),
                  message: '${l['invoice']} ${d.number}',
                ) ==
                null
            ? sepaPayload(
                name: d.seller.name,
                iban: d.sellerIban,
                bic: d.sellerBic,
                amount: (totals.grossCents / 100).toStringAsFixed(2),
                message: '${l['invoice']} ${d.number}',
              )
            : null)
      : null;

  pw.Widget foldMarks() => pw.Stack(
    children: [
      for (final (y, w) in [(105.0, 5.0), (148.5, 8.0), (210.0, 5.0)])
        pw.Positioned(
          left: 0,
          top: _mm(y),
          child: pw.Container(width: _mm(w), height: 0.6, color: grey),
        ),
    ],
  );

  pw.Widget header() => pw.SizedBox(
    height: _mm(98.5 - 20),
    child: pw.Stack(
      children: [
        pw.Positioned(
          left: 0,
          top: 0,
          child: pw.Text(d.seller.name, style: pw.TextStyle(font: bold, fontSize: 15)),
        ),
        pw.Positioned(
          left: 0,
          top: _mm(45 - 20),
          child: pw.Container(
            width: _mm(85),
            height: _mm(5),
            alignment: pw.Alignment.bottomLeft,
            child: pw.Text(sellerLine, style: small(), maxLines: 1),
          ),
        ),
        pw.Positioned(
          left: 0,
          top: _mm(50 - 20),
          child: pw.SizedBox(
            width: _mm(85),
            height: _mm(40),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [for (final r in recipient) pw.Text(r, style: const pw.TextStyle(fontSize: 11))],
            ),
          ),
        ),
        pw.Positioned(
          left: _mm(125 - 25),
          top: _mm(50 - 20),
          child: pw.SizedBox(
            width: _mm(65),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                for (final (k, v) in info)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 4),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(k, style: small()),
                        pw.Text(v, style: const pw.TextStyle(fontSize: 10)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  pw.Widget cell(String text, {pw.Alignment align = pw.Alignment.centerLeft, bool head = false, bool strong = false}) => pw.Container(
    alignment: align,
    padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 3),
    child: pw.Text(
      text,
      style: pw.TextStyle(fontSize: head ? 8.5 : 9.5, font: head || strong ? bold : null, color: head ? grey : null),
    ),
  );

  pw.Widget table() => pw.Table(
    columnWidths: {
      0: pw.FixedColumnWidth(_mm(9)),
      1: const pw.FlexColumnWidth(),
      2: pw.FixedColumnWidth(_mm(20)),
      3: pw.FixedColumnWidth(_mm(24)),
      4: pw.FixedColumnWidth(_mm(13)),
      5: pw.FixedColumnWidth(_mm(26)),
    },
    border: pw.TableBorder(
      horizontalInside: pw.BorderSide(color: line, width: 0.5),
      bottom: pw.BorderSide(color: line, width: 0.5),
    ),
    children: [
      pw.TableRow(
        decoration: pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: grey, width: 0.8)),
        ),
        children: [
          cell(l['pos'], head: true),
          cell(l['description'], head: true),
          cell(l['quantity'], head: true, align: pw.Alignment.centerRight),
          cell(l['unitPrice'], head: true, align: pw.Alignment.centerRight),
          cell('${l['vat']} %', head: true, align: pw.Alignment.centerRight),
          cell(l['net'], head: true, align: pw.Alignment.centerRight),
        ],
      ),
      for (final (i, it) in d.items.indexed)
        pw.TableRow(
          children: [
            cell('${i + 1}'),
            cell(it.description),
            cell('${_qty(it.quantity)}${it.unit.isEmpty ? '' : ' ${it.unit}'}', align: pw.Alignment.centerRight),
            cell(money(it.unitPriceCents), align: pw.Alignment.centerRight),
            cell(d.reverseCharge ? '0' : _rate(it.vatRate), align: pw.Alignment.centerRight),
            cell(money(it.netCents), align: pw.Alignment.centerRight),
          ],
        ),
    ],
  );

  pw.Widget totalsBox() {
    pw.Widget row(String k, String v, {bool strong = false}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            k,
            style: pw.TextStyle(fontSize: strong ? 11 : 9.5, font: strong ? bold : null),
          ),
          pw.Text(
            v,
            style: pw.TextStyle(fontSize: strong ? 11 : 9.5, font: strong ? bold : null),
          ),
        ],
      ),
    );
    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.SizedBox(
        width: _mm(80),
        child: pw.Column(
          children: [
            row(l['subtotal'], money(totals.netCents)),
            for (final g in totals.groups)
              if (!d.reverseCharge) row('${l['vat']} ${_rate(g.rate)} %', money(g.vatCents)),
            pw.Divider(color: grey, thickness: 0.8, height: 8),
            row(l['payable'], money(totals.grossCents), strong: true),
          ],
        ),
      ),
    );
  }

  pw.Widget payment() => pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(l['payment'], style: pw.TextStyle(font: bold, fontSize: 10)),
            pw.SizedBox(height: 3),
            pw.Text(
              l['payBy'].replaceAll('{amount}', money(totals.grossCents)).replaceAll('{date}', date(d.dueDate)),
              style: const pw.TextStyle(fontSize: 9.5),
            ),
            if (d.sellerIban.trim().isNotEmpty) ...[
              pw.SizedBox(height: 3),
              pw.Text(
                'IBAN ${formatIban(d.sellerIban)}${d.sellerBic.isEmpty ? '' : '   BIC ${d.sellerBic.toUpperCase()}'}',
                style: const pw.TextStyle(fontSize: 9.5),
              ),
            ],
            pw.Text('${l['invoice']} ${d.number}', style: const pw.TextStyle(fontSize: 9.5)),
          ],
        ),
      ),
      if (payload != null)
        pw.Column(
          children: [
            pw.BarcodeWidget(
              barcode: pw.Barcode.qrCode(errorCorrectLevel: pw.BarcodeQRCorrectionLevel.medium),
              data: payload,
              width: _mm(28),
              height: _mm(28),
              drawText: false,
            ),
            pw.SizedBox(height: 2),
            pw.SizedBox(
              width: _mm(34),
              child: pw.Text(l['scanToPay'], style: small(), textAlign: pw.TextAlign.center),
            ),
          ],
        ),
    ],
  );

  pw.Widget footer(pw.Context c) {
    final col = [
      [
        d.seller.name,
        d.seller.street,
        [d.seller.postcode, d.seller.city].where((s) => s.isNotEmpty).join(' '),
      ],
      [if (d.seller.vatId.isNotEmpty) '${l['vatId']} ${d.seller.vatId}', if (d.seller.email.isNotEmpty) d.seller.email],
      [if (d.sellerIban.trim().isNotEmpty) 'IBAN ${formatIban(d.sellerIban)}', if (d.sellerBic.isNotEmpty) 'BIC ${d.sellerBic.toUpperCase()}'],
    ];
    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Divider(color: line, thickness: 0.5, height: 6),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            for (final lines in col)
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [for (final s in lines.where((s) => s.isNotEmpty)) pw.Text(s, style: small())],
                ),
              ),
            pw.Text('${l['page']} ${c.pageNumber} ${l['of']} ${c.pagesCount}', style: small()),
          ],
        ),
      ],
    );
  }

  final doc = pw.Document(theme: theme, title: '${l['invoice']} ${d.number}', author: d.seller.name, creator: 'Doculoom');
  doc.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        theme: theme,
        margin: pw.EdgeInsets.fromLTRB(_mm(25), _mm(20), _mm(20), _mm(12)),
        buildBackground: (c) => c.pageNumber == 1 ? foldMarks() : pw.SizedBox(),
      ),
      footer: footer,
      build: (c) => [
        header(),
        pw.Text('${l['invoice']} ${d.number}', style: pw.TextStyle(font: bold, fontSize: 13)),
        pw.SizedBox(height: 8),
        table(),
        pw.SizedBox(height: 10),
        totalsBox(),
        pw.SizedBox(height: 16),
        if (d.reverseCharge)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 8),
            child: pw.Text(l['reverse'], style: const pw.TextStyle(fontSize: 9.5)),
          ),
        payment(),
        if (d.notes.trim().isNotEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 12),
            child: pw.Text(d.notes.trim(), style: const pw.TextStyle(fontSize: 9.5)),
          ),
        pw.SizedBox(height: 10),
        pw.Text(l['thanks'], style: const pw.TextStyle(fontSize: 9.5)),
      ],
    ),
  );
  return doc.save();
}

String _qty(double q) => q == q.roundToDouble() ? q.round().toString() : q.toString().replaceAll('.', ',');

String _rate(double r) => r == r.roundToDouble() ? r.round().toString() : r.toString().replaceAll('.', ',');

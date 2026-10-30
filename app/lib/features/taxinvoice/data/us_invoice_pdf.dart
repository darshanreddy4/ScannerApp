import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/tax_common.dart';
import '../domain/us_invoice.dart';

String _money(int cents) => '${cents < 0 ? '-' : ''}\$${groupWestern(cents.abs())}';

String _date(DateTime d) => '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}/${d.year}';

String _qty(double q) => q == q.roundToDouble() ? q.toInt().toString() : q.toString();

/// A US invoice on Letter paper: who sold, who pays, the lines with a taxable mark, the discount, shipping, sales tax at the one
/// combined rate the seller entered, the amount paid and the balance due, payment instructions and notes.
Future<Uint8List> buildUsInvoicePdf(UsDraft d, {required Future<Uint8List> Function(String asset) loadAsset}) async {
  final regular = pw.Font.ttf((await loadAsset('assets/fonts/Roboto-Regular.ttf')).buffer.asByteData());
  final bold = pw.Font.ttf((await loadAsset('assets/fonts/Roboto-Bold.ttf')).buffer.asByteData());
  final totals = computeUs(d);
  const ink = PdfColor.fromInt(0xFF0F172A);
  const grey = PdfColor.fromInt(0xFF475569);
  const line = PdfColor.fromInt(0xFFCBD5E1);
  const head = PdfColor.fromInt(0xFF1E3A8A);

  pw.TextStyle t(double size, {bool strong = false, PdfColor color = ink}) => pw.TextStyle(font: strong ? bold : regular, fontSize: size, color: color);

  pw.Widget cell(String text, {bool strong = false, pw.TextAlign align = pw.TextAlign.left, PdfColor color = ink, PdfColor? fill}) => pw.Container(
    color: fill,
    padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
    child: pw.Text(
      text,
      style: t(9, strong: strong, color: color),
      textAlign: align,
    ),
  );

  pw.Widget partyBlock(String title, UsParty p, {bool seller = false}) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(title, style: t(8, strong: true, color: grey)),
      pw.SizedBox(height: 3),
      pw.Text(p.name.trim(), style: t(seller ? 12 : 10.5, strong: true)),
      if (p.address.trim().isNotEmpty) pw.Text(p.address.trim(), style: t(9.2)),
      if (p.cityLine.isNotEmpty) pw.Text(p.cityLine, style: t(9.2)),
      if (p.phone.trim().isNotEmpty) pw.Text(p.phone.trim(), style: t(9.2)),
      if (p.email.trim().isNotEmpty) pw.Text(p.email.trim(), style: t(9.2)),
      if (p.taxId.trim().isNotEmpty) pw.Text('${seller ? 'EIN / permit' : 'Certificate'}: ${p.taxId.trim()}', style: t(9.2, color: grey)),
    ],
  );

  pw.Widget meta(String label, String value) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 3),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: t(9, color: grey)),
        pw.Text(value, style: t(9, strong: true)),
      ],
    ),
  );

  pw.Widget totalLine(String label, String value, {bool strong = false, double size = 9.6, PdfColor color = ink}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          label,
          style: t(size, strong: strong, color: color),
        ),
        pw.Text(
          value,
          style: t(size, strong: strong, color: color),
        ),
      ],
    ),
  );

  final taxLabel = d.exempt
      ? '${d.taxName.trim().isEmpty ? 'Sales tax' : d.taxName.trim()} (exempt)'
      : '${d.taxName.trim().isEmpty ? 'Sales tax' : d.taxName.trim()} (${usRateText(d.taxRate)}%)';
  final anyNonTaxable = d.items.any((l) => !l.taxable);

  final doc = pw.Document(
    theme: pw.ThemeData.withFont(base: regular, bold: bold),
    title: 'Invoice ${d.number}',
    author: d.seller.name,
    creator: 'Doculoom',
  );
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.fromLTRB(40, 40, 40, 44),
      footer: (c) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Invoice ${d.number.trim()}', style: t(8, color: grey)),
          pw.Text('Page ${c.pageNumber} of ${c.pagesCount}', style: t(8, color: grey)),
        ],
      ),
      build: (c) => [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(child: partyBlock('FROM', d.seller, seller: true)),
            pw.SizedBox(width: 24),
            pw.SizedBox(
              width: 190,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('INVOICE', style: t(24, strong: true, color: head)),
                  pw.SizedBox(height: 6),
                  meta('Invoice no.', d.number.trim()),
                  meta('Date', _date(d.date)),
                  meta('Terms', usTermsText(d.termsDays)),
                  if (d.termsDays > 0) meta('Due date', _date(d.dueDate)),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 16),
        partyBlock('BILL TO', d.buyer),
        pw.SizedBox(height: 16),
        pw.Table(
          border: pw.TableBorder(
            horizontalInside: pw.BorderSide(color: line, width: 0.5),
            bottom: pw.BorderSide(color: line, width: 0.5),
          ),
          columnWidths: {0: const pw.FlexColumnWidth(), 1: const pw.FixedColumnWidth(48), 2: const pw.FixedColumnWidth(72), 3: const pw.FixedColumnWidth(78)},
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: head),
              children: [
                cell('Description', strong: true, color: PdfColors.white),
                cell('Qty', strong: true, color: PdfColors.white, align: pw.TextAlign.right),
                cell('Unit price', strong: true, color: PdfColors.white, align: pw.TextAlign.right),
                cell('Amount', strong: true, color: PdfColors.white, align: pw.TextAlign.right),
              ],
            ),
            for (final l in d.items)
              pw.TableRow(
                verticalAlignment: pw.TableCellVerticalAlignment.top,
                children: [
                  cell('${l.description.trim()}${l.taxable ? '' : '  (not taxed)'}'),
                  cell(_qty(l.quantity), align: pw.TextAlign.right),
                  cell(_money(l.unitPriceCents), align: pw.TextAlign.right),
                  cell(_money(l.amountCents), align: pw.TextAlign.right),
                ],
              ),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (d.exempt) ...[
                    pw.Text('Tax exempt', style: t(9, strong: true)),
                    pw.Text(
                      d.buyer.taxId.trim().isEmpty ? 'The customer is exempt from sales tax.' : 'Exemption certificate: ${d.buyer.taxId.trim()}',
                      style: t(9, color: grey),
                    ),
                    pw.SizedBox(height: 8),
                  ] else if (anyNonTaxable && d.taxRate > 0) ...[
                    pw.Text('Items marked (not taxed) are not charged sales tax.', style: t(8.6, color: grey)),
                    pw.SizedBox(height: 8),
                  ],
                  if (d.payment.trim().isNotEmpty) ...[
                    pw.Text('Payment instructions', style: t(9, strong: true)),
                    pw.Text(d.payment.trim(), style: t(9)),
                    pw.SizedBox(height: 8),
                  ],
                  if (d.notes.trim().isNotEmpty) ...[pw.Text('Notes', style: t(9, strong: true)), pw.Text(d.notes.trim(), style: t(9))],
                ],
              ),
            ),
            pw.SizedBox(width: 24),
            pw.SizedBox(
              width: 200,
              child: pw.Column(
                children: [
                  totalLine('Subtotal', _money(totals.subtotal)),
                  if (totals.discount > 0)
                    totalLine(d.discountIsPercent ? 'Discount (${usRateText(d.discountValue * 100)}%)' : 'Discount', _money(-totals.discount)),
                  if (totals.shipping > 0) totalLine('Shipping', _money(totals.shipping)),
                  if (d.taxRate > 0 || d.exempt) totalLine(taxLabel, _money(totals.tax)),
                  pw.Divider(color: line, thickness: 0.7, height: 10),
                  totalLine('Total', _money(totals.total), strong: true, size: 11),
                  if (totals.paid > 0) ...[
                    totalLine('Amount paid', _money(-totals.paid)),
                    pw.Divider(color: line, thickness: 0.7, height: 10),
                    totalLine('Balance due', _money(totals.balance), strong: true, size: 12, color: head),
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    ),
  );
  return doc.save();
}

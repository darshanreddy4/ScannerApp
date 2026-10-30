import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../amount_words/domain/amount_words.dart';
import '../../qr/domain/upi.dart';
import '../domain/gst.dart';
import '../domain/tax_common.dart';

String _cents(int c) => '${c ~/ 100}.${(c % 100).toString().padLeft(2, '0')}';

String _qty(double q) => q == q.roundToDouble() ? q.toInt().toString() : q.toString();

/// The tax invoice or bill of supply as a PDF in the layout Indian businesses use: seller and recipient, place of supply, the lines
/// with HSN and CGST/SGST or IGST, a tax summary, the amount in words, bank details, a UPI code and a signature line.
/// It is not an e-invoice: there is no IRN or signed QR code from the Invoice Registration Portal.
Future<Uint8List> buildGstPdf(GstDraft d, {required Future<Uint8List> Function(String asset) loadAsset}) async {
  final regular = pw.Font.ttf((await loadAsset('assets/fonts/Roboto-Regular.ttf')).buffer.asByteData());
  final bold = pw.Font.ttf((await loadAsset('assets/fonts/Roboto-Bold.ttf')).buffer.asByteData());
  final totals = computeGst(d);
  const ink = PdfColor.fromInt(0xFF0F172A);
  const grey = PdfColor.fromInt(0xFF475569);
  const line = PdfColor.fromInt(0xFF94A3B8);
  const head = PdfColor.fromInt(0xFFE2E8F0);

  pw.TextStyle t(double size, {bool strong = false, PdfColor color = ink}) => pw.TextStyle(font: strong ? bold : regular, fontSize: size, color: color);

  pw.Widget cell(String text, {bool strong = false, pw.TextAlign align = pw.TextAlign.left, double size = 7.6, PdfColor? fill, PdfColor color = ink}) =>
      pw.Container(
        color: fill,
        padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3),
        child: pw.Text(
          text,
          style: t(size, strong: strong, color: color),
          textAlign: align,
        ),
      );

  pw.Widget labelled(String label, String value) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 2),
    child: pw.RichText(
      text: pw.TextSpan(
        children: [
          pw.TextSpan(
            text: '$label: ',
            style: t(8.4, color: grey),
          ),
          pw.TextSpan(text: value, style: t(8.4, strong: true)),
        ],
      ),
    ),
  );

  pw.Widget party(String title, GstParty p, {bool seller = false}) => pw.Container(
    padding: const pw.EdgeInsets.all(6),
    decoration: pw.BoxDecoration(border: pw.Border.all(color: line, width: 0.6)),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(title, style: t(7.5, color: grey)),
        pw.SizedBox(height: 2),
        pw.Text(p.name.trim(), style: t(seller ? 11.5 : 10, strong: true)),
        if (p.addressText.isNotEmpty) pw.Text(p.addressText, style: t(8.6)),
        pw.SizedBox(height: 3),
        if (p.gstin.trim().isNotEmpty) labelled('GSTIN', p.gstin.trim().toUpperCase()),
        if (p.stateCode.isNotEmpty) labelled('State', '${p.stateName} (${p.stateCode})'),
        if (p.phone.trim().isNotEmpty) labelled('Phone', p.phone.trim()),
        if (p.email.trim().isNotEmpty) labelled('Email', p.email.trim()),
      ],
    ),
  );

  final inter = d.interState;
  final stateLabel = d.sellerIsUt ? 'UTGST' : 'SGST';
  final showTax = d.isTax;

  // Items
  final headers = <String>['Sr.', 'Description', 'HSN/SAC', 'Qty', 'Rate', 'Taxable value'];
  final widths = <int, pw.TableColumnWidth>{
    0: const pw.FixedColumnWidth(20),
    1: const pw.FlexColumnWidth(),
    2: const pw.FixedColumnWidth(44),
    3: const pw.FixedColumnWidth(36),
    4: const pw.FixedColumnWidth(48),
    5: const pw.FixedColumnWidth(58),
  };
  if (showTax) {
    if (inter) {
      headers.addAll(['IGST %', 'IGST amt']);
      widths[6] = const pw.FixedColumnWidth(28);
      widths[7] = const pw.FixedColumnWidth(48);
    } else {
      headers.addAll(['CGST %', 'CGST amt', '$stateLabel %', '$stateLabel amt']);
      widths[6] = const pw.FixedColumnWidth(26);
      widths[7] = const pw.FixedColumnWidth(40);
      widths[8] = const pw.FixedColumnWidth(30);
      widths[9] = const pw.FixedColumnWidth(40);
    }
    headers.add('Total');
    widths[headers.length - 1] = const pw.FixedColumnWidth(54);
  }

  final rows = <pw.TableRow>[
    pw.TableRow(
      decoration: const pw.BoxDecoration(color: head),
      children: [for (final (i, h) in headers.indexed) cell(h, strong: true, size: 7.2, align: i <= 2 ? pw.TextAlign.left : pw.TextAlign.right)],
    ),
  ];
  for (final (n, item) in d.items.indexed) {
    final lt = totals.lines[n];
    final half = item.rateHundredths / 2;
    rows.add(
      pw.TableRow(
        verticalAlignment: pw.TableCellVerticalAlignment.top,
        children: [
          cell('${n + 1}'),
          cell(item.description.trim()),
          cell(item.hsn.trim()),
          cell('${_qty(item.quantity)}${item.unit.trim().isEmpty ? '' : ' ${item.unit.trim()}'}', align: pw.TextAlign.right),
          cell(groupIndian(item.unitPriceCents), align: pw.TextAlign.right),
          cell(groupIndian(lt.taxable), align: pw.TextAlign.right),
          if (showTax && inter) ...[cell(rateText(item.rateHundredths), align: pw.TextAlign.right), cell(groupIndian(lt.igst), align: pw.TextAlign.right)],
          if (showTax && !inter) ...[
            cell(rateText(half.round()), align: pw.TextAlign.right),
            cell(groupIndian(lt.cgst), align: pw.TextAlign.right),
            cell(rateText(half.round()), align: pw.TextAlign.right),
            cell(groupIndian(lt.sgst), align: pw.TextAlign.right),
          ],
          if (showTax) cell(groupIndian(lt.total), align: pw.TextAlign.right),
        ],
      ),
    );
  }

  // Tax summary by HSN and rate
  final summary = hsnSummary(d, totals);
  pw.Widget summaryTable() {
    final sh = <String>[
      'HSN/SAC',
      'Taxable value',
      if (inter) 'IGST' else ...['CGST', stateLabel],
      'Total tax',
    ];
    return pw.Table(
      border: pw.TableBorder.all(color: line, width: 0.5),
      columnWidths: {0: const pw.FlexColumnWidth(1.3), for (var i = 1; i < sh.length; i++) i: const pw.FlexColumnWidth()},
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: head),
          children: [for (final (i, h) in sh.indexed) cell(h, strong: true, size: 7.2, align: i == 0 ? pw.TextAlign.left : pw.TextAlign.right)],
        ),
        for (final r in summary)
          pw.TableRow(
            children: [
              cell('${r.hsn.isEmpty ? '-' : r.hsn} @ ${rateText(r.rateHundredths)}%'),
              cell(groupIndian(r.taxable), align: pw.TextAlign.right),
              if (inter)
                cell(groupIndian(r.igst), align: pw.TextAlign.right)
              else ...[
                cell(groupIndian(r.cgst), align: pw.TextAlign.right),
                cell(groupIndian(r.sgst), align: pw.TextAlign.right),
              ],
              cell(groupIndian(r.cgst + r.sgst + r.igst), align: pw.TextAlign.right),
            ],
          ),
      ],
    );
  }

  pw.Widget totalLine(String label, String value, {bool strong = false, double size = 8.8}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: t(size, strong: strong)),
        pw.Text(value, style: t(size, strong: strong)),
      ],
    ),
  );

  final words = amountInWords(_cents(totals.grand), language: WordsLanguage.enIn, currency: 'INR', only: true) ?? '';
  final upi = d.upiId.trim();
  final upiData = upi.isEmpty
      ? null
      : upiPayload(
          id: upi,
          name: d.seller.name.trim().length > upiMaxName ? d.seller.name.trim().substring(0, upiMaxName) : d.seller.name.trim(),
          amount: _cents(totals.grand),
          note: 'Invoice ${d.number.trim()}',
        );
  final hasBank = d.bankName.trim().isNotEmpty || d.accountNumber.trim().isNotEmpty || d.ifsc.trim().isNotEmpty;

  final doc = pw.Document(
    theme: pw.ThemeData.withFont(base: regular, bold: bold),
    title: '${gstTitle(d)} ${d.number}',
    author: d.seller.name,
    creator: 'Doculoom',
  );
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(26, 26, 26, 30),
      footer: (c) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('This is a computer-generated ${d.isTax ? 'invoice' : 'bill'}.', style: t(7, color: grey)),
          pw.Text('Page ${c.pageNumber} of ${c.pagesCount}', style: t(7, color: grey)),
        ],
      ),
      build: (c) => [
        pw.Row(
          children: [
            pw.Expanded(child: pw.SizedBox()),
            pw.Text(gstTitle(d), style: t(15, strong: true)),
            pw.Expanded(
              child: pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text('Original for Recipient', style: t(7.5, color: grey)),
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(flex: 3, child: party('SOLD BY', d.seller, seller: true)),
            pw.SizedBox(width: 8),
            pw.Expanded(
              flex: 2,
              child: pw.Container(
                padding: const pw.EdgeInsets.all(6),
                decoration: pw.BoxDecoration(border: pw.Border.all(color: line, width: 0.6)),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    labelled('Invoice No.', d.number.trim()),
                    labelled('Date', '${d.date.day.toString().padLeft(2, '0')}/${d.date.month.toString().padLeft(2, '0')}/${d.date.year}'),
                    if (d.placeOfSupply.isNotEmpty) labelled('Place of supply', '${gstStateOf(d.placeOfSupply)?.name ?? ''} (${d.placeOfSupply})'),
                    if (d.isTax) labelled('Reverse charge', d.reverseCharge ? 'Yes' : 'No'),
                  ],
                ),
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 6),
        party('BILLED TO', d.buyer),
        pw.SizedBox(height: 8),
        pw.Table(
          border: pw.TableBorder.all(color: line, width: 0.5),
          columnWidths: widths,
          children: rows,
        ),
        pw.SizedBox(height: 6),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              flex: 3,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Amount in words', style: t(7.5, color: grey)),
                  pw.Text(words, style: t(9, strong: true)),
                ],
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Expanded(
              flex: 2,
              child: pw.Container(
                padding: const pw.EdgeInsets.all(6),
                decoration: pw.BoxDecoration(border: pw.Border.all(color: line, width: 0.6)),
                child: pw.Column(
                  children: [
                    totalLine('Taxable value', groupIndian(totals.taxable)),
                    if (showTax && !inter) ...[totalLine('CGST', groupIndian(totals.cgst)), totalLine(stateLabel, groupIndian(totals.sgst))],
                    if (showTax && inter) totalLine('IGST', groupIndian(totals.igst)),
                    if (totals.roundOff != 0) totalLine('Round off', '${totals.roundOff < 0 ? '-' : ''}${groupIndian(totals.roundOff.abs())}'),
                    pw.Divider(color: line, thickness: 0.6, height: 8),
                    totalLine('Total (\u20B9)', groupIndian(totals.grand), strong: true, size: 10.5),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (showTax && summary.isNotEmpty) ...[
          pw.SizedBox(height: 10),
          pw.Text('Tax summary', style: t(8, strong: true)),
          pw.SizedBox(height: 3),
          summaryTable(),
        ],
        pw.SizedBox(height: 10),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (hasBank) ...[
                    pw.Text('Bank details', style: t(8, strong: true)),
                    pw.SizedBox(height: 2),
                    if (d.bankName.trim().isNotEmpty) labelled('Bank', d.bankName.trim()),
                    if (d.accountNumber.trim().isNotEmpty) labelled('Account no.', d.accountNumber.trim()),
                    if (d.ifsc.trim().isNotEmpty) labelled('IFSC', d.ifsc.trim().toUpperCase()),
                    if (upi.isNotEmpty) labelled('UPI', upi),
                  ] else if (upi.isNotEmpty)
                    labelled('UPI', upi),
                  if (d.notes.trim().isNotEmpty) ...[
                    pw.SizedBox(height: 6),
                    pw.Text('Notes', style: t(8, strong: true)),
                    pw.Text(d.notes.trim(), style: t(8.4)),
                  ],
                ],
              ),
            ),
            if (upiData != null)
              pw.Column(
                children: [
                  pw.BarcodeWidget(
                    barcode: pw.Barcode.qrCode(errorCorrectLevel: pw.BarcodeQRCorrectionLevel.medium),
                    data: upiData,
                    width: 72,
                    height: 72,
                    drawText: false,
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text('Scan to pay with UPI', style: t(7, color: grey)),
                ],
              ),
          ],
        ),
        pw.SizedBox(height: 14),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Expanded(
              child: pw.Text(
                'We declare that this ${d.isTax ? 'invoice' : 'bill'} shows the actual price of the goods or services described and that all particulars are true and correct.',
                style: t(7.6, color: grey),
              ),
            ),
            pw.SizedBox(width: 16),
            pw.Column(
              children: [
                pw.SizedBox(height: 28),
                pw.Container(width: 140, height: 0.6, color: line),
                pw.SizedBox(height: 2),
                pw.Text('For ${d.seller.name.trim()}', style: t(8, strong: true)),
                pw.Text('Authorised signatory', style: t(7.5, color: grey)),
              ],
            ),
          ],
        ),
      ],
    ),
  );
  return doc.save();
}

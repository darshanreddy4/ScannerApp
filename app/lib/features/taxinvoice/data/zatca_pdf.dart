import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../amount_words/domain/amount_words.dart';
import '../domain/tax_common.dart';
import '../domain/zatca.dart';

String _money(int cents) => groupWestern(cents);

String _qty(double q) => q == q.roundToDouble() ? q.toInt().toString() : q.toString();

final _arabic = RegExp(r'[\u0600-\u06FF]');

bool hasArabic(String s) => _arabic.hasMatch(s);

String zatcaTitleEn(ZatcaDraft d) => d.document == ZatcaDocument.simplified ? 'Simplified Tax Invoice' : 'Tax Invoice';

String zatcaTitleAr(ZatcaDraft d) => d.document == ZatcaDocument.simplified ? 'فاتورة ضريبية مبسطة' : 'فاتورة ضريبية';

/// A bilingual Saudi invoice, Arabic and English side by side, with the first-phase QR code on a simplified tax invoice. It is
/// made without ZATCA integration: there is no XML, cryptographic stamp or clearance, so it is not a second-phase e-invoice.
Future<Uint8List> buildZatcaPdf(ZatcaDraft d, {required Future<Uint8List> Function(String asset) loadAsset}) async {
  final regular = pw.Font.ttf((await loadAsset('assets/fonts/Roboto-Regular.ttf')).buffer.asByteData());
  final bold = pw.Font.ttf((await loadAsset('assets/fonts/Roboto-Bold.ttf')).buffer.asByteData());
  final arRegular = pw.Font.ttf((await loadAsset('assets/fonts/Tajawal-Regular.ttf')).buffer.asByteData());
  final arBold = pw.Font.ttf((await loadAsset('assets/fonts/Tajawal-Bold.ttf')).buffer.asByteData());
  final totals = computeZatca(d);
  const ink = PdfColor.fromInt(0xFF0F172A);
  const grey = PdfColor.fromInt(0xFF475569);
  const line = PdfColor.fromInt(0xFF94A3B8);
  const head = PdfColor.fromInt(0xFFE2E8F0);

  /// Arabic text is set in the Arabic font, and anything else in Roboto; each falls back on the other for the odd character.
  pw.TextStyle t(double size, {bool strong = false, PdfColor color = ink, bool arabic = false}) => arabic
      ? pw.TextStyle(font: strong ? arBold : arRegular, fontFallback: [strong ? bold : regular], fontSize: size, color: color)
      : pw.TextStyle(font: strong ? bold : regular, fontFallback: [strong ? arBold : arRegular], fontSize: size, color: color);

  /// Text that reads right to left when it holds Arabic.
  pw.Widget text(String s, double size, {bool strong = false, PdfColor color = ink, pw.TextAlign? align}) {
    final rtl = hasArabic(s);
    return pw.Text(
      s,
      style: t(size, strong: strong, color: color, arabic: rtl),
      textDirection: rtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
      textAlign: align ?? (rtl ? pw.TextAlign.right : pw.TextAlign.left),
    );
  }

  pw.Widget cell(String s, {bool strong = false, pw.TextAlign align = pw.TextAlign.right, double size = 7.8, PdfColor? fill}) => pw.Container(
    color: fill,
    padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3),
    child: text(s, size, strong: strong, align: align),
  );

  pw.Widget headCell(String ar, String en, {pw.TextAlign align = pw.TextAlign.right}) => pw.Container(
    color: head,
    padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3),
    child: pw.Column(
      crossAxisAlignment: align == pw.TextAlign.left ? pw.CrossAxisAlignment.start : pw.CrossAxisAlignment.end,
      children: [
        text(ar, 7, strong: true, align: align),
        text(en, 6.8, strong: true, align: align),
      ],
    ),
  );

  /// English label on the left, the value in the middle and the Arabic label on the right.
  pw.Widget row(String en, String value, String ar) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 84,
          child: text(en, 8, color: grey, align: pw.TextAlign.left),
        ),
        pw.Expanded(
          child: pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6),
            child: text(value, 9, strong: true, align: pw.TextAlign.center),
          ),
        ),
        pw.SizedBox(
          width: 84,
          child: text(ar, 8, color: grey, align: pw.TextAlign.right),
        ),
      ],
    ),
  );

  pw.Widget box(String titleEn, String titleAr, List<pw.Widget> children) => pw.Container(
    padding: const pw.EdgeInsets.all(6),
    decoration: pw.BoxDecoration(border: pw.Border.all(color: line, width: 0.6)),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [text(titleEn, 8.6, strong: true), text(titleAr, 8.6, strong: true)]),
        pw.Divider(color: line, thickness: 0.5, height: 6),
        ...children,
      ],
    ),
  );

  pw.Widget party(ZatcaParty p, {required bool seller}) => pw.Column(
    children: [
      row(seller ? 'Seller name' : 'Customer name', p.name.trim(), seller ? 'اسم البائع' : 'اسم العميل'),
      if (p.addressLine.isNotEmpty) row('Address', p.addressLine, 'العنوان'),
      if (p.vat.trim().isNotEmpty) row('VAT number', p.vat.trim(), 'الرقم الضريبي'),
      if (p.cr.trim().isNotEmpty) row('CR number', p.cr.trim(), 'السجل التجاري'),
    ],
  );

  pw.Widget totalRow(String en, String ar, String value, {bool strong = false}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(
      children: [
        pw.Expanded(
          flex: 4,
          child: text(en, strong ? 9 : 8.4, strong: strong, align: pw.TextAlign.left),
        ),
        pw.SizedBox(width: 62, child: text(value, strong ? 9.6 : 8.8, strong: true, align: pw.TextAlign.center)),
        pw.Expanded(
          flex: 4,
          child: text(ar, strong ? 9 : 8.4, strong: strong, align: pw.TextAlign.right),
        ),
      ],
    ),
  );

  final simplified = d.document == ZatcaDocument.simplified;
  final cents = zatcaAmount(totals.total);
  final wordsEn = amountInWords(cents, language: WordsLanguage.en, currency: 'SAR', only: true) ?? '';
  final wordsAr = amountInWords(cents, language: WordsLanguage.ar, currency: 'SAR', only: true) ?? '';
  final stamp = d.issuedAt;
  String two(int n) => n.toString().padLeft(2, '0');
  final dateText = '${stamp.year}-${two(stamp.month)}-${two(stamp.day)}  ${two(stamp.hour)}:${two(stamp.minute)}';

  final widths = <int, pw.TableColumnWidth>{
    0: const pw.FixedColumnWidth(16),
    1: const pw.FlexColumnWidth(),
    2: const pw.FixedColumnWidth(48),
    3: const pw.FixedColumnWidth(30),
    4: const pw.FixedColumnWidth(40),
    5: const pw.FixedColumnWidth(54),
    6: const pw.FixedColumnWidth(36),
    7: const pw.FixedColumnWidth(44),
    8: const pw.FixedColumnWidth(54),
  };

  final doc = pw.Document(
    theme: pw.ThemeData.withFont(base: regular, bold: bold, fontFallback: [arRegular]),
    title: '${zatcaTitleEn(d)} ${d.number}',
    author: d.seller.name,
    creator: 'Doculoom',
  );
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 32),
      footer: (c) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          text('Page ${c.pageNumber} of ${c.pagesCount}', 7, color: grey),
          text('Doculoom', 7, color: grey),
        ],
      ),
      build: (c) => [
        pw.Center(child: text(zatcaTitleAr(d), 17, strong: true, align: pw.TextAlign.center)),
        pw.Center(child: text(zatcaTitleEn(d), 12, strong: true, align: pw.TextAlign.center)),
        pw.SizedBox(height: 8),
        box('Invoice', 'الفاتورة', [row('Invoice number', d.number.trim(), 'رقم الفاتورة'), row('Date and time', dateText, 'تاريخ ووقت الإصدار')]),
        pw.SizedBox(height: 6),
        box('Seller', 'البائع', [party(d.seller, seller: true)]),
        pw.SizedBox(height: 6),
        if (d.buyer.name.trim().isNotEmpty || !simplified) box('Customer', 'العميل', [party(d.buyer, seller: false)]),
        pw.SizedBox(height: 8),
        pw.Table(
          border: pw.TableBorder.all(color: line, width: 0.5),
          columnWidths: widths,
          children: [
            pw.TableRow(
              children: [
                headCell('#', 'No.', align: pw.TextAlign.center),
                headCell('الوصف', 'Description', align: pw.TextAlign.left),
                headCell('سعر الوحدة', 'Unit price'),
                headCell('الكمية', 'Qty'),
                headCell('الخصم', 'Discount'),
                headCell('الخاضع للضريبة', 'Taxable'),
                headCell('نسبة الضريبة', 'VAT %'),
                headCell('الضريبة', 'VAT'),
                headCell('الإجمالي', 'Total'),
              ],
            ),
            for (final (n, l) in d.items.indexed)
              pw.TableRow(
                verticalAlignment: pw.TableCellVerticalAlignment.top,
                children: [
                  cell('${n + 1}', align: pw.TextAlign.center),
                  cell(l.description.trim(), align: hasArabic(l.description) ? pw.TextAlign.right : pw.TextAlign.left),
                  cell(_money(l.unitPriceCents)),
                  cell(_qty(l.quantity)),
                  cell(totals.lines[n].discount == 0 ? '-' : _money(totals.lines[n].discount)),
                  cell(_money(totals.lines[n].net)),
                  cell(switch (l.category) {
                    VatCategory.standard => '15%',
                    VatCategory.zero => '0%',
                    VatCategory.exempt => 'Exempt',
                  }, align: pw.TextAlign.center),
                  cell(_money(totals.lines[n].vat)),
                  cell(_money(totals.lines[n].total)),
                ],
              ),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              flex: 3,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (simplified) ...[
                    pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(errorCorrectLevel: pw.BarcodeQRCorrectionLevel.medium),
                      data: zatcaQrPayload(d),
                      width: 92,
                      height: 92,
                      drawText: false,
                    ),
                    pw.SizedBox(height: 4),
                  ],
                  if (d.pricesIncludeVat) ...[
                    text('Prices include VAT', 7.6, color: grey, align: pw.TextAlign.left),
                    text('الأسعار شاملة ضريبة القيمة المضافة', 7.6, color: grey, align: pw.TextAlign.left),
                  ],
                ],
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Expanded(
              flex: 4,
              child: box('Totals', 'الإجماليات', [
                totalRow('Total (excluding VAT)', 'الإجمالي (غير شامل الضريبة)', _money(totals.taxable + totals.discount)),
                if (totals.discount > 0) totalRow('Discount', 'الخصم', _money(totals.discount)),
                totalRow('Total taxable amount', 'إجمالي المبلغ الخاضع للضريبة', _money(totals.taxable)),
                totalRow('Total VAT', 'إجمالي ضريبة القيمة المضافة', _money(totals.vat)),
                pw.Divider(color: line, thickness: 0.6, height: 8),
                totalRow('Total amount due (SAR)', 'إجمالي المبلغ المستحق (ريال)', _money(totals.total), strong: true),
              ]),
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        if (wordsEn.isNotEmpty) text(wordsEn, 8.4, color: grey, align: pw.TextAlign.left),
        if (wordsAr.isNotEmpty) text(wordsAr, 8.8, color: grey, align: pw.TextAlign.right),
        if (d.notes.trim().isNotEmpty) ...[
          pw.SizedBox(height: 8),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [text('Notes', 8, strong: true), text('ملاحظات', 8, strong: true)]),
          text(d.notes.trim(), 8.6),
        ],
      ],
    ),
  );
  return doc.save();
}

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/pdf_comparison.dart';
import '../domain/text_compare.dart';

String _pageLabel(TextChange c) {
  final a = c.originalPage, b = c.revisedPage;
  if (a != null && b != null) return a == b ? 'Page ${a + 1}' : 'Original page ${a + 1}, revised page ${b + 1}';
  if (a != null) return 'Original page ${a + 1}';
  return 'Revised page ${b! + 1}';
}

/// The comparison as plain text: what was removed is in [-square brackets-] and what was added in {+braces+}.
String comparisonText(PdfComparison c, {required String nameA, required String nameB}) {
  final b = StringBuffer()
    ..writeln('Comparison of "$nameA" (original, ${c.pagesA} pages) and "$nameB" (revised, ${c.pagesB} pages)')
    ..writeln();
  final t = c.text;
  if (t.tooDifferent) {
    b.writeln('The two files have very little text in common.');
  } else if (t.changes.isEmpty) {
    b.writeln(c.noText ? 'No text to compare.' : 'The text is the same.');
  } else {
    b.writeln('Text: ${t.changes.length} ${t.changes.length == 1 ? 'change' : 'changes'}, ${t.removedWords} words removed, ${t.addedWords} words added.');
    b.writeln();
    for (final (i, ch) in t.changes.indexed) {
      b.writeln('${i + 1}. ${_pageLabel(ch)}');
      b.writeln('   ${ch.plain}');
    }
  }
  final only = [
    for (final p in c.pages)
      if (p.onlyInOriginal)
        'Original page ${p.pageA! + 1} is not in the revised file.'
      else if (p.onlyInRevised)
        'Revised page ${p.pageB! + 1} is not in the original.',
  ];
  final looks = [
    for (final p in c.pages)
      if (p.pageA != null && p.pageB != null && (p.visual.isNotEmpty || p.sizeChanged))
        p.pageA == p.pageB
            ? 'Page ${p.pageA! + 1} looks different${p.sizeChanged ? ' (another page size)' : ''}.'
            : 'Original page ${p.pageA! + 1} and revised page ${p.pageB! + 1} look different${p.sizeChanged ? ' (another page size)' : ''}.',
  ];
  if (only.isNotEmpty || looks.isNotEmpty) {
    b
      ..writeln()
      ..writeln('Pages');
    for (final line in [...only, ...looks]) {
      b.writeln('- $line');
    }
  }
  return b.toString();
}

const _red = 0xFFE11D48, _green = 0xFF16A34A, _orange = 0xFFF59E0B;

void _mark(img.Image image, TextRect r, int argb, {int dx = 0}) {
  final w = image.width.toDouble(), h = image.height.toDouble();
  img.drawRect(
    image,
    x1: (r.left * w).round() + dx,
    y1: (r.top * h).round(),
    x2: (r.right * w).round() + dx,
    y2: (r.bottom * h).round(),
    color: img.ColorRgb8((argb >> 16) & 0xFF, (argb >> 8) & 0xFF, argb & 0xFF),
    thickness: 3,
  );
}

/// A PDF of the pages that differ: the original and the revised page side by side, text taken out marked red on the original,
/// text put in marked green on the revised, and other differences marked orange on both.
Future<Uint8List?> buildComparisonPdf(PdfComparison c) async {
  final doc = pw.Document();
  var pages = 0;
  for (final page in c.pages) {
    final left = page.imageA == null ? null : img.decodeImage(page.imageA!);
    final right = page.imageB == null ? null : img.decodeImage(page.imageB!);
    if (left == null && right == null) continue;
    final w = math.max(left?.width ?? 0, right?.width ?? 0), h = math.max(left?.height ?? 0, right?.height ?? 0);
    const gap = 24;
    final canvas = img.Image(width: w * 2 + gap, height: h);
    img.fill(canvas, color: img.ColorRgb8(226, 232, 240));
    img.Image blank(String text) {
      final b = img.Image(width: w, height: h);
      img.fill(b, color: img.ColorRgb8(255, 255, 255));
      img.drawString(b, text, font: img.arial24, x: 20, y: h ~/ 2, color: img.ColorRgb8(100, 116, 139));
      return b;
    }

    final a = left ?? blank('Not in the original');
    final b = right ?? blank('Not in the revised');
    for (final r in page.removed) {
      _mark(a, r, _red);
    }
    for (final r in page.visual) {
      _mark(a, r, _orange);
      _mark(b, r, _orange);
    }
    for (final r in page.added) {
      _mark(b, r, _green);
    }
    img.compositeImage(canvas, a, dstX: 0, dstY: 0);
    img.compositeImage(canvas, b, dstX: w + gap, dstY: 0);
    final jpg = Uint8List.fromList(img.encodeJpg(canvas, quality: 85));
    pages++;
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(canvas.width * 0.6, canvas.height * 0.6),
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Image(pw.MemoryImage(jpg), fit: pw.BoxFit.fill),
      ),
    );
  }
  return pages == 0 ? null : doc.save();
}

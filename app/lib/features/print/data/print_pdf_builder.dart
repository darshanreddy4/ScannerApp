import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../export/data/document_builders.dart';
import '../domain/print_options.dart';

/// Thrown when the options cannot produce a valid print job.
class PrintOptionsException implements Exception {
  const PrintOptionsException(this.message);
  final String message;
  @override
  String toString() => message;
}

PdfPageFormat sheetFormat(PrintOptions o, {required bool firstPageIsLandscape}) {
  final base = PdfPageFormat(o.paper.widthMm * PdfPageFormat.mm, o.paper.heightMm * PdfPageFormat.mm);
  final landscape = switch (o.orientation) {
    PrintOrientation.portrait => false,
    PrintOrientation.landscape => true,
    PrintOrientation.auto => switch (o.pagesPerSheet) {
      1 => firstPageIsLandscape,
      2 => true, // two portrait pages side by side
      _ => false,
    },
  };
  return landscape ? base.landscape : base;
}

pw.MemoryImage _loadImage(PageSource page, bool color, int maxSide) {
  final raw = File(page.path).readAsBytesSync();
  if (color && math.max(page.width, page.height) <= maxSide) return pw.MemoryImage(raw);

  var decoded = img.decodeImage(raw);
  if (decoded == null) throw const PrintOptionsException('A page image could not be read.');
  if (math.max(decoded.width, decoded.height) > maxSide) {
    decoded = decoded.width >= decoded.height
        ? img.copyResize(decoded, width: maxSide, interpolation: img.Interpolation.average)
        : img.copyResize(decoded, height: maxSide, interpolation: img.Interpolation.average);
  }
  if (!color) decoded = img.grayscale(decoded);
  return pw.MemoryImage(Uint8List.fromList(img.encodeJpg(decoded, quality: 90)));
}

/// Builds the print-ready PDF: chosen pages, paper size, orientation, colour mode, pages per sheet and copies.
/// Pass a smaller [maxSide] for a quick preview.
Future<Uint8List> buildPrintPdf({required List<PageSource> pages, required PrintOptions options, int maxSide = 3508}) async {
  final selected = PageRange.parse(options.pageRange, pages.length);
  if (selected == null || selected.isEmpty) {
    throw const PrintOptionsException('Check the page range. Use numbers like 1-3, 5.');
  }

  final n = options.pagesPerSheet;
  final doc = pw.Document(compress: true);
  final images = <int, pw.MemoryImage>{};
  pw.MemoryImage image(int i) => images[i] ??= _loadImage(pages[i], options.color, maxSide);
  final margin = options.margin.mm * PdfPageFormat.mm;

  // Each copy is printed in full before the next starts (collated).
  for (var copy = 0; copy < options.copies; copy++) {
    for (var s = 0; s < selected.length; s += n) {
      final chunk = selected.sublist(s, math.min(s + n, selected.length));
      final first = pages[chunk.first];
      final format = sheetFormat(options, firstPageIsLandscape: first.width > first.height * 1.05);
      final landscape = format.width > format.height;
      final (cols, rows) = switch (n) {
        1 => (1, 1),
        2 => landscape ? (2, 1) : (1, 2),
        _ => (2, 2),
      };
      final cellPad = n > 1 ? 3 * PdfPageFormat.mm : 0.0;
      final imgs = [for (final i in chunk) image(i)];

      pw.Widget cell(int index) {
        if (index >= imgs.length) return pw.SizedBox();
        final provider = imgs[index];
        return pw.Padding(
          padding: pw.EdgeInsets.all(cellPad),
          child: pw.LayoutBuilder(
            builder: (_, c) => pw.Center(
              child: pw.Image(
                provider,
                fit: options.fill ? pw.BoxFit.cover : pw.BoxFit.contain,
                width: options.fill ? c?.maxWidth : null,
                height: options.fill ? c?.maxHeight : null,
              ),
            ),
          ),
        );
      }

      doc.addPage(
        pw.Page(
          pageFormat: format,
          margin: pw.EdgeInsets.all(margin),
          build: (_) => pw.Column(
            children: [
              for (var r = 0; r < rows; r++)
                pw.Expanded(
                  child: pw.Row(children: [for (var c = 0; c < cols; c++) pw.Expanded(child: cell(r * cols + c))]),
                ),
            ],
          ),
        ),
      );
    }
  }
  return doc.save();
}

/// How many sheets of paper the job uses, or 0 when the options are invalid.
int sheetsFor(PrintOptions o, int totalPages) {
  final selected = PageRange.parse(o.pageRange, totalPages);
  if (selected == null || selected.isEmpty) return 0;
  return (selected.length / o.pagesPerSheet).ceil() * o.copies;
}

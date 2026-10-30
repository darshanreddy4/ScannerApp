import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../export/data/document_builders.dart' show PageSource;
import '../domain/packet.dart';

class PacketRequest {
  const PacketRequest({required this.pages, required this.outputPath, this.cover, this.numbers = true, this.limitBytes, this.letter = false});
  final List<PageSource> pages;
  final String outputPath;

  /// The cover as a PNG picture, or null for no cover.
  final Uint8List? cover;
  final bool numbers;
  final int? limitBytes;
  final bool letter;
}

class PacketResult {
  const PacketResult({required this.path, required this.bytes, required this.pageCount, required this.step, required this.fits});
  final String path;
  final int bytes;
  final int pageCount;

  /// The index in [qualitySteps] that was used; 0 keeps the pictures as they are.
  final int step;

  /// False when even the smallest picture quality is above the limit.
  final bool fits;

  bool get reduced => step > 0;
}

abstract interface class PacketBuilder {
  Future<PacketResult> build(PacketRequest request);
}

/// Builds the packet in another isolate so the screen stays smooth.
class SystemPacketBuilder implements PacketBuilder {
  const SystemPacketBuilder();

  @override
  Future<PacketResult> build(PacketRequest request) => Isolate.run(() => buildPacketFile(request));
}

class _Encoded {
  const _Encoded(this.bytes, this.width, this.height);
  final Uint8List bytes;
  final int width;
  final int height;
}

_Encoded _encode(PageSource page, QualityStep step) {
  final raw = File(page.path).readAsBytesSync();
  final maxSide = step.maxSide;
  if (maxSide == null) return _Encoded(raw, page.width, page.height);
  final decoded = img.decodeImage(raw);
  if (decoded == null) throw const FormatException('Corrupted page image');
  var out = decoded;
  if (math.max(decoded.width, decoded.height) > maxSide) {
    out = decoded.width >= decoded.height
        ? img.copyResize(decoded, width: maxSide, interpolation: img.Interpolation.average)
        : img.copyResize(decoded, height: maxSide, interpolation: img.Interpolation.average);
  }
  final bytes = Uint8List.fromList(img.encodeJpg(out, quality: step.jpegQuality));
  // A picture that is already small can come out larger.
  return bytes.length < raw.length ? _Encoded(bytes, out.width, out.height) : _Encoded(raw, page.width, page.height);
}

/// Makes the PDF of the packet. With a size limit, the pictures are made smaller step by step until the file fits.
Future<PacketResult> buildPacketFile(PacketRequest r) async {
  final limit = r.limitBytes;
  final coverSize = r.cover?.length ?? 0;
  final last = qualitySteps.length - 1;
  final total = r.pages.length + (r.cover == null ? 0 : 1);
  final shortSide = r.letter ? 612.0 : 595.0, longSide = r.letter ? 792.0 : 842.0;

  for (var s = 0; s < qualitySteps.length; s++) {
    if (limit == null && s > 0) break;
    final encoded = <_Encoded>[];
    var sum = coverSize;
    var tooBig = false;
    for (final page in r.pages) {
      final e = _encode(page, qualitySteps[s]);
      encoded.add(e);
      sum += e.bytes.length;
      // The pictures alone are already over the limit: no need to encode the rest at this quality.
      if (limit != null && sum > limit && s < last) {
        tooBig = true;
        break;
      }
    }
    if (tooBig) continue;

    final doc = pw.Document(compress: true);
    var number = 1;
    if (r.cover != null) {
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(shortSide, longSide),
          margin: pw.EdgeInsets.zero,
          build: (_) => pw.Image(pw.MemoryImage(r.cover!), fit: pw.BoxFit.fill),
        ),
      );
      number++;
    }
    for (final e in encoded) {
      final landscape = e.width > e.height;
      final boxW = landscape ? longSide : shortSide;
      final boxH = landscape ? shortSide : longSide;
      final scale = math.min(boxW / e.width, boxH / e.height);
      final image = pw.MemoryImage(e.bytes);
      final n = number++;
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(e.width * scale, e.height * scale),
          margin: pw.EdgeInsets.zero,
          build: (_) => pw.Stack(
            fit: pw.StackFit.expand,
            children: [
              pw.Image(image, fit: pw.BoxFit.fill),
              if (r.numbers)
                pw.Positioned(
                  right: 12,
                  bottom: 8,
                  child: pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: pw.BoxDecoration(color: const PdfColor(1, 1, 1, 0.85), borderRadius: pw.BorderRadius.circular(3)),
                    child: pw.Text('$n / $total', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey800)),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    final bytes = await doc.save();
    if (limit == null || bytes.length <= limit || s == last) {
      await File(r.outputPath).writeAsBytes(bytes, flush: true);
      return PacketResult(path: r.outputPath, bytes: bytes.length, pageCount: total, step: s, fits: limit == null || bytes.length <= limit);
    }
  }
  throw StateError('unreachable');
}

/// The words on the cover, already in the language of the person.
class CoverText {
  const CoverText({
    required this.title,
    required this.purpose,
    required this.applicant,
    required this.contents,
    required this.summary,
    required this.date,
    this.pageHeading = '',
  });
  final String title;
  final String purpose;
  final String applicant;
  final String contents;
  final String summary;
  final String date;
  final String pageHeading;
}

/// Draws the cover page, with the contents, as a picture, so names in any script come out right.
Future<Uint8List> renderCover(CoverText text, List<ContentsLine> lines, {bool letter = false, bool rtl = false}) async {
  final w = letter ? 612.0 : 595.0, h = letter ? 792.0 : 842.0;
  const scale = 2.0;
  const margin = 52.0;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)..scale(scale);
  canvas.drawRect(ui.Rect.fromLTWH(0, 0, w, h), ui.Paint()..color = const ui.Color(0xFFFFFFFF));
  final dir = rtl ? TextDirection.rtl : TextDirection.ltr;
  const ink = ui.Color(0xFF0F172A), muted = ui.Color(0xFF64748B), accent = ui.Color(0xFF1D4ED8);

  TextPainter paint(
    String s,
    double size,
    ui.Color color, {
    FontWeight weight = FontWeight.w400,
    double? width,
    int maxLines = 1,
    TextAlign align = TextAlign.start,
  }) {
    final p = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(fontSize: size, color: color, fontWeight: weight, height: 1.25),
      ),
      textDirection: dir,
      textAlign: align,
      maxLines: maxLines,
      ellipsis: '\u2026',
    )..layout(minWidth: width ?? w - margin * 2, maxWidth: width ?? w - margin * 2);
    return p;
  }

  var y = margin;
  canvas.drawRect(ui.Rect.fromLTWH(rtl ? w - margin - 36 : margin, y, 36, 4), ui.Paint()..color = accent);
  y += 22;
  final title = paint(text.title, 28, ink, weight: FontWeight.w800, maxLines: 3)..paint(canvas, ui.Offset(margin, y));
  y += title.height + 8;
  for (final line in [text.purpose, text.applicant]) {
    if (line.trim().isEmpty) continue;
    final p = paint(line, 13, muted, maxLines: 2)..paint(canvas, ui.Offset(margin, y));
    y += p.height + 4;
  }
  y += 14;
  canvas.drawLine(ui.Offset(margin, y), ui.Offset(w - margin, y), ui.Paint()..color = const ui.Color(0xFFE2E8F0));
  y += 16;
  final heading = paint(text.contents.toUpperCase(), 10.5, muted, weight: FontWeight.w700)..paint(canvas, ui.Offset(margin, y));
  y += heading.height + 8;

  const pagesW = 64.0;
  const footerH = 40.0;
  final room = h - margin - footerH - y;
  final rowH = lines.isEmpty ? 22.0 : math.min(24.0, room / lines.length);
  final size = math.min(12.0, math.max(7.0, rowH * 0.55));
  for (final l in lines) {
    final titleBox = paint(l.title, size, ink, width: w - margin * 2 - pagesW - 8);
    final pagesBox = paint(l.pages, size, muted, width: pagesW, align: TextAlign.end);
    final titleX = rtl ? margin + pagesW + 8 : margin;
    final pagesX = rtl ? margin : w - margin - pagesW;
    titleBox.paint(canvas, ui.Offset(titleX, y));
    pagesBox.paint(canvas, ui.Offset(pagesX, y));
    y += rowH;
  }
  final footer = paint(text.summary, 10, muted)..paint(canvas, ui.Offset(margin, h - margin - 26));
  paint(text.date, 10, muted).paint(canvas, ui.Offset(margin, h - margin - 26 + footer.height));

  final picture = recorder.endRecording();
  final image = await picture.toImage((w * scale).round(), (h * scale).round());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

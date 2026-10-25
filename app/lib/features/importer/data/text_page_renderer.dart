import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:path/path.dart' as p;

/// Text laid out on pages, kept so that a search can find where each word is.
class LaidOutText {
  LaidOutText({required this.files, required this.painter, required this.starts});
  final List<String> files;
  final TextPainter painter;

  /// Where each page begins, as a height from the top of the laid out text.
  final List<double> starts;
}

/// Lays out plain text onto A4-proportioned white pages and saves each page as a PNG.
/// Used for text-only parts of Word documents; formatting is not preserved.
class TextPageRenderer {
  static const pageW = 1240.0;
  static const pageH = 1754.0;
  static const margin = 110.0;
  static const maxPages = 60;

  Future<List<String>> render({required String text, required String outDir, required String prefix}) async {
    final laid = await renderLaidOut(text: text, outDir: outDir, prefix: prefix);
    laid.painter.dispose();
    return laid.files;
  }

  /// Like [render], but the caller keeps the layout (and must dispose [LaidOutText.painter]).
  Future<LaidOutText> renderLaidOut({required String text, required String outDir, required String prefix}) async {
    const contentW = pageW - 2 * margin;
    const contentH = pageH - 2 * margin;

    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(color: Color(0xFF111111), fontSize: 30, height: 1.45),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: contentW);

    // Break only between lines so no line is cut in half.
    final starts = <double>[0];
    for (final line in painter.computeLineMetrics()) {
      final top = line.baseline - line.ascent;
      final bottom = line.baseline + line.descent;
      if (bottom - starts.last > contentH && top > starts.last) starts.add(top);
    }
    if (starts.length > maxPages) starts.removeRange(maxPages, starts.length);

    final files = <String>[];
    for (var i = 0; i < starts.length; i++) {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, pageW, pageH));
      canvas.drawRect(const Rect.fromLTWH(0, 0, pageW, pageH), Paint()..color = const Color(0xFFFFFFFF));
      canvas.clipRect(const Rect.fromLTWH(margin, margin, contentW, contentH));
      painter.paint(canvas, Offset(margin, margin - starts[i]));

      final image = await recorder.endRecording().toImage(pageW.toInt(), pageH.toInt());
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) continue;
      final file = File(p.join(outDir, '$prefix-text${i + 1}.png'));
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
      files.add(file.path);
    }
    return LaidOutText(files: files, painter: painter, starts: starts);
  }
}

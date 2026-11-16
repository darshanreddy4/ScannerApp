import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// Text drawn as a transparent picture, for words the PDF's built-in fonts cannot show (Hindi, Arabic, Chinese and so on).
/// The phone's own text engine does the shaping, so every script it can show comes out right.
class TextPicture {
  const TextPicture({required this.bytes, required this.widthPt, required this.heightPt});

  /// A PNG with a see-through background.
  final Uint8List bytes;

  /// Size on the page, in points.
  final double widthPt;
  final double heightPt;

  double get aspect => widthPt / heightPt;
}

bool _isRtl(String text) {
  for (final r in text.runes) {
    if ((r >= 0x0590 && r <= 0x08FF) || (r >= 0xFB1D && r <= 0xFEFC)) return true;
    if ((r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A) || (r >= 0x900 && r <= 0x1FFF) || r >= 0x3040) return false;
  }
  return false;
}

/// Draws [text] at [sizePt] in the colour [rgb] (0xRRGGBB), four times larger than needed so it stays sharp when printed.
Future<TextPicture> renderTextPicture(String text, {required double sizePt, int rgb = 0, bool bold = false, bool italic = false, String family = 'sans'}) async {
  const scale = 4.0;
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontSize: sizePt * scale,
        height: 1.2,
        color: Color(0xFF000000 | (rgb & 0xFFFFFF)),
        fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        fontFamily: switch (family) {
          'serif' => 'serif',
          'mono' => 'monospace',
          _ => null,
        },
      ),
    ),
    textDirection: _isRtl(text) ? TextDirection.rtl : TextDirection.ltr,
  )..layout();
  final pad = sizePt * scale * 0.1;
  final w = (painter.width + pad * 2).ceil(), h = (painter.height + pad * 2).ceil();
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), Offset(pad, pad));
  final image = await recorder.endRecording().toImage(w, h);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  painter.dispose();
  return TextPicture(bytes: data!.buffer.asUint8List(), widthPt: w / scale, heightPt: h / scale);
}

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../domain/watermark.dart';

/// The watermark as a small transparent picture, ready to be laid over photos.
class Stamp {
  const Stamp({required this.width, required this.height, required this.rgba});
  final int width;
  final int height;

  /// Straight (not premultiplied) RGBA bytes.
  final Uint8List rgba;
}

/// Draws the text and logo with Flutter's text engine, so every script the phone can show (Hindi, Arabic, Tamil and
/// so on) works, then hands back pixels for the photo pipeline.
class WatermarkStampRenderer {
  const WatermarkStampRenderer();

  static const maxStampSide = 4096;

  /// [text] already has its placeholders filled in. [shortSide] is the shorter side of the picture in pixels.
  Future<Stamp?> render({required WatermarkStyle style, required String text, required int shortSide}) async {
    final image = await renderImage(style: style, text: text, shortSide: shortSide);
    if (image == null) return null;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    final stamp = data == null ? null : Stamp(width: image.width, height: image.height, rgba: data.buffer.asUint8List());
    image.dispose();
    return stamp;
  }

  /// The same stamp as a picture for the screen preview. The caller disposes it.
  Future<ui.Image?> renderImage({required WatermarkStyle style, required String text, required int shortSide}) async {
    final trimmed = text.trim();
    final hasLogo = style.logoPath != null && File(style.logoPath!).existsSync();
    if (trimmed.isEmpty && !hasLogo) return null;

    final fontSize = (style.size * shortSide).clamp(8.0, 700.0);
    final color = Color(style.color.argb).withValues(alpha: style.opacity);
    TextPainter? painter;
    if (trimmed.isNotEmpty) {
      painter = TextPainter(
        text: TextSpan(
          text: trimmed,
          style: TextStyle(fontSize: fontSize, fontWeight: style.bold ? FontWeight.w700 : FontWeight.w500, color: color, height: 1.15),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        textWidthBasis: TextWidthBasis.longestLine,
        maxLines: 6,
      )..layout(maxWidth: math.max(shortSide * 0.9, fontSize * 4));
    }

    ui.Image? logo;
    var logoW = 0.0, logoH = 0.0;
    if (hasLogo) {
      final target = (painter == null ? fontSize * 4 : fontSize * 2.6).round().clamp(16, 1200);
      final codec = await ui.instantiateImageCodec(await File(style.logoPath!).readAsBytes(), targetHeight: target);
      logo = (await codec.getNextFrame()).image;
      codec.dispose();
      logoW = logo.width.toDouble();
      logoH = logo.height.toDouble();
    }

    final gap = painter != null && logo != null ? fontSize * 0.3 : 0.0;
    final textW = painter?.width ?? 0.0, textH = painter?.height ?? 0.0;
    final w = math.max(textW, logoW), h = logoH + gap + textH;

    final angle = style.rotation * math.pi / 180;
    final cosA = math.cos(angle).abs(), sinA = math.sin(angle).abs();
    var boxW = w * cosA + h * sinA, boxH = w * sinA + h * cosA;
    // Keep the stamp within a sane size; the layout simply uses fewer pixels for huge text.
    final fit = math.min(1.0, maxStampSide / math.max(boxW, boxH));
    boxW *= fit;
    boxH *= fit;
    final width = math.max(1, boxW.ceil() + 2), height = math.max(1, boxH.ceil() + 2);

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.translate(width / 2, height / 2);
    canvas.scale(fit);
    canvas.rotate(angle);
    canvas.translate(-w / 2, -h / 2);
    if (logo != null) {
      canvas.drawImage(
        logo,
        Offset((w - logoW) / 2, 0),
        Paint()
          ..color = Color.fromRGBO(255, 255, 255, style.opacity)
          ..filterQuality = FilterQuality.high,
      );
    }
    painter?.paint(canvas, Offset((w - textW) / 2, logoH + gap));

    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    picture.dispose();
    logo?.dispose();
    painter?.dispose();
    return image;
  }
}

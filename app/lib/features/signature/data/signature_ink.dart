import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Cuts a transparent PNG to the ink: removes empty space around it and keeps a small margin.
({Uint8List png, int width, int height}) cropToInk(Uint8List rgba, int width, int height, {required int margin}) {
  var minX = width, minY = height, maxX = -1, maxY = -1;
  for (var y = 0; y < height; y++) {
    final row = y * width * 4;
    for (var x = 0; x < width; x++) {
      if (rgba[row + x * 4 + 3] > 12) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  if (maxX < 0) throw const FormatException('No ink found');
  final x0 = math.max(0, minX - margin), y0 = math.max(0, minY - margin);
  final x1 = math.min(width - 1, maxX + margin), y1 = math.min(height - 1, maxY + margin);
  final w = x1 - x0 + 1, h = y1 - y0 + 1;
  final out = img.Image(width: w, height: h, numChannels: 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final s = ((y + y0) * width + (x + x0)) * 4;
      out.setPixelRgba(x, y, rgba[s], rgba[s + 1], rgba[s + 2], rgba[s + 3]);
    }
  }
  return (png: Uint8List.fromList(img.encodePng(out)), width: w, height: h);
}

/// Lifts the ink of a signature written on white paper off a photo and saves it as a transparent PNG.
/// Uneven light and shadows on the paper are evened out first. Runs in a background isolate.
({int width, int height}) extractInkSync(String sourcePath, String outputPath, double sensitivity, int? inkArgb) {
  var image = img.decodeImage(File(sourcePath).readAsBytesSync());
  if (image == null) throw const FormatException('Unsupported or damaged image');
  image = img.bakeOrientation(image);
  const maxSide = 1600;
  if (math.max(image.width, image.height) > maxSide) {
    image = image.width >= image.height
        ? img.copyResize(image, width: maxSide, interpolation: img.Interpolation.average)
        : img.copyResize(image, height: maxSide, interpolation: img.Interpolation.average);
  }
  final w = image.width, h = image.height;
  final lum = Float32List(w * h);
  final rgb = Uint8List(w * h * 3);
  var i = 0;
  for (final p in image) {
    final r = p.r.toDouble(), g = p.g.toDouble(), b = p.b.toDouble();
    final a = p.a / p.maxChannelValue;
    // Transparent areas count as white paper.
    final rr = r * a + 255 * (1 - a), gg = g * a + 255 * (1 - a), bb = b * a + 255 * (1 - a);
    lum[i] = 0.299 * rr + 0.587 * gg + 0.114 * bb;
    rgb[i * 3] = rr.round();
    rgb[i * 3 + 1] = gg.round();
    rgb[i * 3 + 2] = bb.round();
    i++;
  }

  // The paper's own brightness at every spot: the brightest value in each block, smoothed.
  const cell = 48;
  final gx = (w / cell).ceil(), gy = (h / cell).ceil();
  var grid = Float32List(gx * gy);
  for (var cy = 0; cy < gy; cy++) {
    for (var cx = 0; cx < gx; cx++) {
      var best = 0.0;
      final yEnd = math.min(h, (cy + 1) * cell), xEnd = math.min(w, (cx + 1) * cell);
      for (var y = cy * cell; y < yEnd; y++) {
        for (var x = cx * cell; x < xEnd; x++) {
          final v = lum[y * w + x];
          if (v > best) best = v;
        }
      }
      grid[cy * gx + cx] = best;
    }
  }
  final smooth = Float32List(gx * gy);
  for (var cy = 0; cy < gy; cy++) {
    for (var cx = 0; cx < gx; cx++) {
      var sum = 0.0, n = 0;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final x = cx + dx, y = cy + dy;
          if (x < 0 || y < 0 || x >= gx || y >= gy) continue;
          sum += grid[y * gx + x];
          n++;
        }
      }
      smooth[cy * gx + cx] = sum / n;
    }
  }
  grid = smooth;

  double paperAt(int x, int y) {
    final fx = ((x + 0.5) / cell - 0.5).clamp(0.0, gx - 1.0), fy = ((y + 0.5) / cell - 0.5).clamp(0.0, gy - 1.0);
    final x0 = fx.floor(), y0 = fy.floor();
    final x1 = math.min(gx - 1, x0 + 1), y1 = math.min(gy - 1, y0 + 1);
    final tx = fx - x0, ty = fy - y0;
    final top = grid[y0 * gx + x0] * (1 - tx) + grid[y0 * gx + x1] * tx;
    final bottom = grid[y1 * gx + x0] * (1 - tx) + grid[y1 * gx + x1] * tx;
    return math.max(1.0, top * (1 - ty) + bottom * ty);
  }

  // Brightness compared with the paper, 0 (black) to 255 (as bright as the paper).
  final norm = Float32List(w * h);
  final histogram = List<int>.filled(256, 0);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final v = math.min(255.0, lum[y * w + x] * 255 / paperAt(x, y));
      norm[y * w + x] = v;
      histogram[v.round().clamp(0, 255)]++;
    }
  }
  // Darkest 1% of the picture stands for full-strength ink.
  var low = 0, seen = 0;
  final onePercent = (w * h * 0.01).round();
  for (var v = 0; v < 256; v++) {
    seen += histogram[v];
    if (seen >= onePercent) {
      low = v;
      break;
    }
  }
  final span = 255 - low;
  if (span < 40) throw const FormatException('No ink found');

  final s = sensitivity.clamp(0.0, 1.0);
  final start = 255 - span * (0.40 - 0.28 * s); // ink starts to show below this
  final full = low + span * 0.25; // fully solid below this
  final rgba = Uint8List(w * h * 4);
  for (var p = 0; p < w * h; p++) {
    final v = norm[p];
    final a = v >= start ? 0.0 : (v <= full ? 1.0 : (start - v) / (start - full));
    final o = p * 4;
    if (inkArgb != null) {
      rgba[o] = (inkArgb >> 16) & 0xFF;
      rgba[o + 1] = (inkArgb >> 8) & 0xFF;
      rgba[o + 2] = inkArgb & 0xFF;
    } else {
      // Keep the pen's own colour, made as dark as the paper-relative reading.
      final scale = 255 / math.max(1.0, lum[p]) * (v / 255);
      rgba[o] = (rgb[p * 3] * scale).round().clamp(0, 255);
      rgba[o + 1] = (rgb[p * 3 + 1] * scale).round().clamp(0, 255);
      rgba[o + 2] = (rgb[p * 3 + 2] * scale).round().clamp(0, 255);
    }
    rgba[o + 3] = (a * 255).round();
  }
  final cut = cropToInk(rgba, w, h, margin: math.max(4, (math.min(w, h) * 0.015).round()));
  File(outputPath).writeAsBytesSync(cut.png, flush: true);
  return (width: cut.width, height: cut.height);
}

/// The same signature in another ink colour: the shape and the softness of its edges are kept, only the colour changes.
Uint8List recolorPng(Uint8List png, int argb) {
  final image = img.decodePng(png);
  if (image == null) throw const FormatException('Not a PNG');
  final r = (argb >> 16) & 0xFF, g = (argb >> 8) & 0xFF, b = argb & 0xFF;
  final rgba = image.convert(format: img.Format.uint8, numChannels: 4);
  for (final px in rgba) {
    if (px.a > 0) {
      px
        ..r = r
        ..g = g
        ..b = b;
    }
  }
  return Uint8List.fromList(img.encodePng(rgba));
}

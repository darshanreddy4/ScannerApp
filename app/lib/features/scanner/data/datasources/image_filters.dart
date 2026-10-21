import 'dart:math' as math;
import 'dart:typed_data';

import '../../domain/entities/filter_settings.dart';
import 'rgb_buffer.dart';

/// CPU image filters. Pure functions over [RgbBuffer]; run them in an isolate.
abstract final class ImageFilters {
  static RgbBuffer apply(RgbBuffer src, FilterSettings s) {
    final adjusted = _brightnessContrast(src, s.brightness, s.contrast);
    return switch (s.filter) {
      ScanFilter.original => adjusted,
      ScanFilter.grayscale => _grayscale(adjusted),
      ScanFilter.documentBw => _documentBw(adjusted),
      ScanFilter.magicColor => _magicColor(adjusted),
    };
  }

  static RgbBuffer _brightnessContrast(RgbBuffer src, double brightness, double contrast) {
    if (brightness == 0 && contrast == 0) return src;
    final c = contrast.clamp(-100, 100) * 2.55;
    final factor = (259 * (c + 255)) / (255 * (259 - c));
    final offset = brightness.clamp(-100, 100) * 2.55;

    final lut = Uint8List(256);
    for (var i = 0; i < 256; i++) {
      lut[i] = (factor * (i - 128) + 128 + offset).round().clamp(0, 255);
    }
    final out = RgbBuffer.blank(src.width, src.height);
    for (var i = 0; i < src.data.length; i++) {
      out.data[i] = lut[src.data[i]];
    }
    return out;
  }

  static RgbBuffer _grayscale(RgbBuffer src) {
    final gray = src.toGray();
    final out = RgbBuffer.blank(src.width, src.height);
    for (var i = 0, p = 0; i < gray.length; i++, p += 3) {
      out.data[p] = out.data[p + 1] = out.data[p + 2] = gray[i];
    }
    return out;
  }

  /// Adaptive (local-mean) threshold: crisp black text on white, robust to shadows.
  static RgbBuffer _documentBw(RgbBuffer src) {
    final w = src.width, h = src.height;
    final gray = src.toGray();
    final integral = _integral(gray, w, h);
    final radius = math.max(8, math.min(w, h) ~/ 24);
    const bias = 0.92;

    final out = RgbBuffer.blank(w, h);
    for (var y = 0; y < h; y++) {
      final y0 = math.max(0, y - radius), y1 = math.min(h - 1, y + radius);
      for (var x = 0; x < w; x++) {
        final x0 = math.max(0, x - radius), x1 = math.min(w - 1, x + radius);
        final area = (x1 - x0 + 1) * (y1 - y0 + 1);
        final sum = _rectSum(integral, w, x0, y0, x1, y1);
        final mean = sum / area;
        final v = gray[y * w + x] > mean * bias ? 255 : 0;
        final p = (y * w + x) * 3;
        out.data[p] = out.data[p + 1] = out.data[p + 2] = v;
      }
    }
    return out;
  }

  /// Flattens uneven lighting, whitens paper and boosts colour vibrancy.
  static RgbBuffer _magicColor(RgbBuffer src) {
    final w = src.width, h = src.height;
    final gray = src.toGray();

    const cell = 8;
    final sw = math.max(1, w ~/ cell), sh = math.max(1, h ~/ cell);
    final small = Uint8List(sw * sh);
    for (var y = 0; y < sh; y++) {
      for (var x = 0; x < sw; x++) {
        small[y * sw + x] = gray[math.min(h - 1, y * cell) * w + math.min(w - 1, x * cell)];
      }
    }
    final bgSmall = _dilateMax(small, sw, sh, 3);
    final bg = _boxBlurSmall(bgSmall, sw, sh, 2);

    final out = RgbBuffer.blank(w, h);
    for (var y = 0; y < h; y++) {
      final fy = math.min(sh - 1.0, y / cell);
      final y0 = fy.floor(), y1 = math.min(sh - 1, y0 + 1);
      final ty = fy - y0;
      for (var x = 0; x < w; x++) {
        final fx = math.min(sw - 1.0, x / cell);
        final x0 = fx.floor(), x1 = math.min(sw - 1, x0 + 1);
        final tx = fx - x0;
        final top = bg[y0 * sw + x0] * (1 - tx) + bg[y0 * sw + x1] * tx;
        final bot = bg[y1 * sw + x0] * (1 - tx) + bg[y1 * sw + x1] * tx;
        final local = math.max(40.0, top * (1 - ty) + bot * ty);
        final gain = 245.0 / local;

        final p = (y * w + x) * 3;
        final r = src.data[p] * gain, g = src.data[p + 1] * gain, b = src.data[p + 2] * gain;
        final lum = 0.299 * r + 0.587 * g + 0.114 * b;
        const sat = 1.25;
        out.data[p] = _curve(lum + (r - lum) * sat);
        out.data[p + 1] = _curve(lum + (g - lum) * sat);
        out.data[p + 2] = _curve(lum + (b - lum) * sat);
      }
    }
    return out;
  }

  static int _curve(double v) {
    final n = (v / 255).clamp(0.0, 1.0);
    // Gentle S-curve to deepen ink while keeping paper white.
    final s = n * n * (3 - 2 * n);
    return ((n * 0.5 + s * 0.5) * 255).round().clamp(0, 255);
  }

  static Int64List _integral(Uint8List gray, int w, int h) {
    final integral = Int64List((w + 1) * (h + 1));
    for (var y = 1; y <= h; y++) {
      var row = 0;
      for (var x = 1; x <= w; x++) {
        row += gray[(y - 1) * w + (x - 1)];
        integral[y * (w + 1) + x] = integral[(y - 1) * (w + 1) + x] + row;
      }
    }
    return integral;
  }

  static int _rectSum(Int64List integral, int w, int x0, int y0, int x1, int y1) {
    final stride = w + 1;
    return integral[(y1 + 1) * stride + (x1 + 1)] -
        integral[y0 * stride + (x1 + 1)] -
        integral[(y1 + 1) * stride + x0] +
        integral[y0 * stride + x0];
  }

  static Uint8List _dilateMax(Uint8List src, int w, int h, int r) {
    final out = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var m = 0;
        for (var dy = -r; dy <= r; dy++) {
          final yy = y + dy;
          if (yy < 0 || yy >= h) continue;
          for (var dx = -r; dx <= r; dx++) {
            final xx = x + dx;
            if (xx < 0 || xx >= w) continue;
            m = math.max(m, src[yy * w + xx]);
          }
        }
        out[y * w + x] = m;
      }
    }
    return out;
  }

  static Float64List _boxBlurSmall(Uint8List src, int w, int h, int r) {
    final out = Float64List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var sum = 0.0;
        var n = 0;
        for (var dy = -r; dy <= r; dy++) {
          final yy = y + dy;
          if (yy < 0 || yy >= h) continue;
          for (var dx = -r; dx <= r; dx++) {
            final xx = x + dx;
            if (xx < 0 || xx >= w) continue;
            sum += src[yy * w + xx];
            n++;
          }
        }
        out[y * w + x] = sum / n;
      }
    }
    return out;
  }
}

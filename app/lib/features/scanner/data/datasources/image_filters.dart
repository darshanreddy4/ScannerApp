import 'dart:math' as math;
import 'dart:typed_data';

import '../../domain/entities/filter_settings.dart';
import 'rgb_buffer.dart';

/// CPU image filters. Pure functions over [RgbBuffer]; run them in an isolate.
///
/// Every setting is relative to the picture size, so a small preview and the full-size result look the same.
/// The recipes follow common practice in document scanning and photo grading:
///  * Levels from histogram percentiles (clip 0.5% at each end) instead of fixed numbers.
///  * Lighting flattening: the paper colour is estimated on a coarse grid (local maximum, then blur) and divided out.
///  * Soft S-curves (a blend of the identity and smoothstep) for contrast instead of a straight slope.
///  * Vibrance rather than saturation: weak colours are lifted more than strong ones and skin tones less.
///  * Unsharp mask on luminance only, so colours do not fringe.
abstract final class ImageFilters {
  static RgbBuffer apply(RgbBuffer src, FilterSettings s) {
    final adjusted = _brightnessContrast(src, s.brightness, s.contrast);
    return switch (s.filter) {
      ScanFilter.original => adjusted,
      ScanFilter.auto => _auto(adjusted),
      ScanFilter.magicColor => _clean(adjusted),
      ScanFilter.documentBw => _softBw(adjusted),
      ScanFilter.sharpBw => _sharpBw(adjusted),
      ScanFilter.grayscale => _gray(adjusted),
      ScanFilter.whiteboard => _whiteboard(adjusted),
      ScanFilter.vivid => _vivid(adjusted),
      ScanFilter.warm => _tint(adjusted, r: 1.07, g: 1.012, b: 0.91),
      ScanFilter.cool => _tint(adjusted, r: 0.93, g: 0.995, b: 1.09),
      ScanFilter.noir => _noir(adjusted),
      ScanFilter.handwriting => _handwriting(adjusted),
      ScanFilter.pencil => _pencil(adjusted),
      ScanFilter.notebook => _notebook(adjusted),
    };
  }

  // Brightness and contrast

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

  // Filters

  /// Auto: levels per channel from the histogram (half-strength, so a warm lamp stays a little warm), a gentle brightness
  /// correction towards a middle grey of 50%, a light S-curve and a touch of vibrance. Good for most photos and papers.
  static RgbBuffer _auto(RgbBuffer src) {
    final lv = _Levels(src);
    final lumLo = lv.low(lv.l, 0.005).toDouble();
    final lumHi = lv.high(lv.l, 0.995).toDouble();
    final channels = [lv.r, lv.g, lv.b];
    final lows = <double>[], highs = <double>[];
    for (final h in channels) {
      var lo = lumLo + (lv.low(h, 0.005) - lumLo) * 0.5;
      var hi = lumHi + (lv.high(h, 0.995) - lumHi) * 0.5;
      // A flat picture is not stretched beyond what it can bear.
      if (hi - lo < 90) {
        final mid = (hi + lo) / 2;
        lo = math.max(0, mid - 45);
        hi = math.min(255, mid + 45);
      }
      lows.add(lo);
      highs.add(hi);
    }
    final mean = ((lv.meanLuma - lumLo) / math.max(1, lumHi - lumLo)).clamp(0.05, 0.95);
    final raw = (math.log(0.5) / math.log(mean)).clamp(0.8, 1.2);
    final gamma = 1 + (raw - 1) * 0.7;

    final luts = [for (var c = 0; c < 3; c++) _lut256((i) => _sCurve(math.pow(((i - lows[c]) / (highs[c] - lows[c])).clamp(0.0, 1.0), gamma).toDouble(), 0.2))];
    final out = _mapChannels(src, luts[0], luts[1], luts[2]);
    _vibrance(out.data, 0.22);
    return out;
  }

  /// Clean (colour document): lighting flattened to an even white, ink deepened, colours kept, text sharpened.
  static RgbBuffer _clean(RgbBuffer src) => _flatten(src, target: 246, minLocal: 80, black: 20, white: 232, gamma: 1.0, curve: 0.3, sat: 1.12, sharpen: 0.5);

  /// Whiteboard: like Clean, but whiter, with the marker colours pushed and the ink darker.
  static RgbBuffer _whiteboard(RgbBuffer src) =>
      _flatten(src, target: 252, minLocal: 70, black: 35, white: 230, gamma: 1.1, curve: 0.4, sat: 1.5, sharpen: 0.8);

  /// B&W: even lighting, then a soft threshold. Text is black and the paper white, but edges stay smooth and pale pencil, stamps and
  /// photos keep their grey.
  static RgbBuffer _softBw(RgbBuffer src) {
    final w = src.width, h = src.height;
    final gray = src.toGray();
    final bg = _Background(w, h, gray);
    final lut = Uint8List(768);
    for (var v = 0; v < 768; v++) {
      lut[v] = (_sCurve(((v - 75) / (205 - 75)).clamp(0.0, 1.0), 0.3) * 255).round();
    }
    final out = RgbBuffer.blank(w, h);
    final gains = Int32List(w);
    for (var y = 0; y < h; y++) {
      bg.row(y, 246, 80, 3.2, gains);
      for (var x = 0, i = y * w; x < w; x++, i++) {
        final v = lut[math.min(767, (gray[i] * gains[x]) >> 8)];
        final p = i * 3;
        out.data[p] = out.data[p + 1] = out.data[p + 2] = v;
      }
    }
    _sharpenLuma(out, 0.6, 900);
    return out;
  }

  /// Sharp B&W: pure black and white by comparing each pixel with its neighbourhood. Smallest files, hardest look.
  static RgbBuffer _sharpBw(RgbBuffer src) {
    final w = src.width, h = src.height;
    final gray = src.toGray();
    // Anything much darker than the paper is ink, even inside a large dark area where the neighbourhood is equally dark.
    final hist = _Levels(src);
    final darkBelow = hist.high(hist.l, 0.9) * 0.42;
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
        final g = gray[y * w + x];
        final v = g > darkBelow && g * area > sum * bias ? 255 : 0;
        final p = (y * w + x) * 3;
        out.data[p] = out.data[p + 1] = out.data[p + 2] = v;
      }
    }
    return out;
  }

  /// Grey: neutral luminance with levels from the histogram and a light S-curve.
  static RgbBuffer _gray(RgbBuffer src) {
    final lv = _Levels(src);
    var lo = lv.low(lv.l, 0.003).toDouble();
    var hi = lv.high(lv.l, 0.997).toDouble();
    if (hi - lo < 100) {
      final mid = (hi + lo) / 2;
      lo = math.max(0, mid - 50);
      hi = math.min(255, mid + 50);
    }
    final lut = _lut256((i) => _sCurve(((i - lo) / (hi - lo)).clamp(0.0, 1.0), 0.15));
    final out = RgbBuffer.blank(src.width, src.height);
    final d = src.data, o = out.data;
    for (var p = 0; p < d.length; p += 3) {
      final v = lut[(d[p] * 77 + d[p + 1] * 150 + d[p + 2] * 29) >> 8];
      o[p] = o[p + 1] = o[p + 2] = v;
    }
    return out;
  }

  /// Vivid: S-curve, vibrance and a little clarity (a wide, weak unsharp mask that adds local contrast).
  static RgbBuffer _vivid(RgbBuffer src) {
    final lut = _lut256((i) => _sCurve(math.pow(i / 255, 0.97).toDouble(), 0.32));
    final out = _mapChannels(src, lut, lut, lut);
    _vibrance(out.data, 0.5);
    _sharpenLuma(out, 0.22, 60);
    return out;
  }

  /// Warm / Cool: a white-balance shift of roughly +-8% in red and blue. The shift fades out in the highlights so white stays white.
  static RgbBuffer _tint(RgbBuffer src, {required double r, required double g, required double b}) {
    Uint8List lut(double mult) => _lut256((i) {
      final x = i / 255;
      final highlight = math.pow(x, 4).toDouble();
      final shifted = x * mult;
      final y = shifted + (x - shifted) * highlight * 0.8;
      return _sCurve(y.clamp(0.0, 1.0), 0.15);
    });
    final out = _mapChannels(src, lut(r), lut(g), lut(b));
    _vibrance(out.data, 0.12);
    return out;
  }

  /// Noir: red-weighted black and white (as with a red filter on film), strong S-curve, slightly deeper blacks.
  static RgbBuffer _noir(RgbBuffer src) {
    final lut = _lut256((i) {
      final n = ((i / 255 - 0.04) / 0.92).clamp(0.0, 1.0);
      return _sCurve(math.pow(n, 1.05).toDouble(), 0.55);
    });
    final out = RgbBuffer.blank(src.width, src.height);
    final d = src.data, o = out.data;
    for (var p = 0; p < d.length; p += 3) {
      final v = lut[(d[p] * 115 + d[p + 1] * 115 + d[p + 2] * 26) >> 8];
      o[p] = o[p + 1] = o[p + 2] = v;
    }
    return out;
  }

  // Handwriting

  /// Handwriting: the lighting is flattened to a clean white page, the ink is made darker and crisper, and the colour of the pen stays.
  static RgbBuffer _handwriting(RgbBuffer src) =>
      _flatten(src, target: 250, minLocal: 70, black: 50, white: 220, gamma: 1.15, curve: 0.5, sat: 1.35, sharpen: 0.7);

  /// Pencil: faint graphite is pulled out of the paper into clear grey lines, and thin strokes are made a little bolder.
  static RgbBuffer _pencil(RgbBuffer src) {
    final flat = _flatten(src, target: 250, minLocal: 70, black: 110, white: 235, gamma: 1.2, curve: 0.55, sat: 0, sharpen: 0.8);
    final w = flat.width, h = flat.height;
    final gray = Uint8List(w * h);
    for (var i = 0, p = 0; i < gray.length; i++, p += 3) {
      gray[i] = flat.data[p];
    }
    final bolder = _min3(gray, w, h);
    for (var i = 0, p = 0; i < gray.length; i++, p += 3) {
      final v = (gray[i] * 62 + bolder[i] * 38) ~/ 100;
      flat.data[p] = flat.data[p + 1] = flat.data[p + 2] = v;
    }
    return flat;
  }

  /// Notebook: ruled lines are taken away, then the page is treated like Handwriting. A line is anything lighter than the writing that runs
  /// a long way across the page: it is found per colour with a horizontal opening and subtracted, so writing that crosses a line stays whole.
  static RgbBuffer _notebook(RgbBuffer src) => _handwriting(_removeRules(src));

  static RgbBuffer _removeRules(RgbBuffer src) {
    final w = src.width, h = src.height;
    // Long enough to pass over a letter, short enough to follow a line on a slightly tilted page.
    final half = math.min((w - 1) ~/ 2, math.max(6, w ~/ 20));
    if (half < 1) return RgbBuffer(w, h, Uint8List.fromList(src.data));
    final out = RgbBuffer.blank(w, h);
    final dark = Uint8List(w * h);
    for (var c = 0; c < 3; c++) {
      for (var i = 0, p = c; i < dark.length; i++, p += 3) {
        dark[i] = 255 - src.data[p];
      }
      final opened = _slideRows(_slideRows(dark, w, h, half, max: false), w, h, half, max: true);
      for (var i = 0, p = c; i < dark.length; i++, p += 3) {
        // value + the part of the darkness that belongs to a long horizontal structure
        final v = src.data[p] + opened[i];
        out.data[p] = v > 255 ? 255 : v;
      }
    }
    return out;
  }

  /// Local minimum or maximum along every row over a window of 2 * [half] + 1 pixels (a sliding window, so the cost does not depend on its size).
  static Uint8List _slideRows(Uint8List src, int w, int h, int half, {required bool max}) {
    final out = Uint8List(w * h);
    final q = Int32List(w);
    for (var y = 0; y < h; y++) {
      final row = y * w;
      var head = 0, tail = 0, next = 0;
      for (var x = 0; x < w; x++) {
        final hi = math.min(w - 1, x + half);
        while (next <= hi) {
          final v = src[row + next];
          while (tail > head && (max ? src[row + q[tail - 1]] <= v : src[row + q[tail - 1]] >= v)) {
            tail--;
          }
          q[tail++] = next++;
        }
        while (q[head] < x - half) {
          head++;
        }
        out[row + x] = src[row + q[head]];
      }
    }
    return out;
  }

  /// The darkest value in the 3 x 3 neighbourhood of every pixel.
  static Uint8List _min3(Uint8List g, int w, int h) {
    final tmp = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      final r = y * w;
      for (var x = 0; x < w; x++) {
        var m = g[r + x];
        if (x > 0 && g[r + x - 1] < m) m = g[r + x - 1];
        if (x < w - 1 && g[r + x + 1] < m) m = g[r + x + 1];
        tmp[r + x] = m;
      }
    }
    final out = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var m = tmp[y * w + x];
        if (y > 0 && tmp[(y - 1) * w + x] < m) m = tmp[(y - 1) * w + x];
        if (y < h - 1 && tmp[(y + 1) * w + x] < m) m = tmp[(y + 1) * w + x];
        out[y * w + x] = m;
      }
    }
    return out;
  }

  // Lighting flattening for documents and boards

  static RgbBuffer _flatten(
    RgbBuffer src, {
    required double target,
    required double minLocal,
    required double black,
    required double white,
    required double gamma,
    required double curve,
    required double sat,
    required double sharpen,
  }) {
    final w = src.width, h = src.height;
    final bg = _Background(w, h, src.toGray());
    // The gain can raise a pixel to 3x its value, so the table covers 0..767.
    final lut = Uint8List(768);
    for (var v = 0; v < 768; v++) {
      final n = math.pow(((v - black) / (white - black)).clamp(0.0, 1.0), gamma).toDouble();
      lut[v] = (_sCurve(n, curve) * 255).round();
    }
    final sat256 = (sat * 256).round();
    final out = RgbBuffer.blank(w, h);
    final d = src.data, o = out.data;
    final gains = Int32List(w);
    for (var y = 0; y < h; y++) {
      bg.row(y, target, minLocal, 3.4, gains);
      var p = y * w * 3;
      for (var x = 0; x < w; x++, p += 3) {
        final g = gains[x];
        var r = lut[math.min(767, (d[p] * g) >> 8)];
        var gr = lut[math.min(767, (d[p + 1] * g) >> 8)];
        var b = lut[math.min(767, (d[p + 2] * g) >> 8)];
        if (sat256 != 256) {
          final lum = (r * 77 + gr * 150 + b * 29) >> 8;
          r = _clamp8(lum + (((r - lum) * sat256) >> 8));
          gr = _clamp8(lum + (((gr - lum) * sat256) >> 8));
          b = _clamp8(lum + (((b - lum) * sat256) >> 8));
        }
        o[p] = r;
        o[p + 1] = gr;
        o[p + 2] = b;
      }
    }
    _sharpenLuma(out, sharpen, 900);
    return out;
  }

  // Building blocks

  static int _clamp8(int v) => v < 0 ? 0 : (v > 255 ? 255 : v);

  /// Blend of the identity and smoothstep: [amount] 0 leaves the tone alone, 1 is a full S-curve.
  static double _sCurve(double n, double amount) {
    final s = n * n * (3 - 2 * n);
    return n * (1 - amount) + s * amount;
  }

  static Uint8List _lut256(double Function(int) f) {
    final lut = Uint8List(256);
    for (var i = 0; i < 256; i++) {
      lut[i] = (f(i).clamp(0.0, 1.0) * 255).round();
    }
    return lut;
  }

  static RgbBuffer _mapChannels(RgbBuffer src, Uint8List lr, Uint8List lg, Uint8List lb) {
    final out = RgbBuffer.blank(src.width, src.height);
    final d = src.data, o = out.data;
    for (var p = 0; p < d.length; p += 3) {
      o[p] = lr[d[p]];
      o[p + 1] = lg[d[p + 1]];
      o[p + 2] = lb[d[p + 2]];
    }
    return out;
  }

  /// Lifts weak colours more than strong ones, and skin tones half as much. Greys do not change.
  static void _vibrance(Uint8List d, double amount) {
    final a256 = (amount * 256).round();
    for (var p = 0; p < d.length; p += 3) {
      final r = d[p], g = d[p + 1], b = d[p + 2];
      final mx = math.max(r, math.max(g, b));
      final mn = math.min(r, math.min(g, b));
      final spread = mx - mn;
      if (spread == 0) continue;
      var boost = (a256 * (255 - spread)) ~/ 255;
      if (r > 95 && g > 40 && b > 20 && r > g && r > b && r - g > 15) boost >>= 1;
      final k = 256 + boost;
      final lum = (r * 77 + g * 150 + b * 29) >> 8;
      d[p] = _clamp8(lum + (((r - lum) * k) >> 8));
      d[p + 1] = _clamp8(lum + (((g - lum) * k) >> 8));
      d[p + 2] = _clamp8(lum + (((b - lum) * k) >> 8));
    }
  }

  /// Unsharp mask on luminance: [radiusDiv] sets the radius as a share of the long side (900 for text, 60 for clarity).
  static void _sharpenLuma(RgbBuffer buf, double amount, int radiusDiv) {
    if (amount <= 0) return;
    final w = buf.width, h = buf.height;
    final gray = buf.toGray();
    final radius = math.max(1, math.max(w, h) ~/ radiusDiv);
    final blur = _boxBlur(gray, w, h, radius);
    final a256 = (amount * 256).round();
    final d = buf.data;
    for (var i = 0, p = 0; i < gray.length; i++, p += 3) {
      final delta = ((gray[i] - blur[i]) * a256) >> 8;
      if (delta == 0) continue;
      d[p] = _clamp8(d[p] + delta);
      d[p + 1] = _clamp8(d[p + 1] + delta);
      d[p + 2] = _clamp8(d[p + 2] + delta);
    }
  }

  /// Separable box blur with running sums, so the cost does not depend on the radius. Edges repeat.
  static Uint8List _boxBlur(Uint8List src, int w, int h, int r) {
    final win = 2 * r + 1;
    final tmp = Uint8List(w * h);
    final out = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      final base = y * w;
      var sum = 0;
      for (var k = -r; k <= r; k++) {
        sum += src[base + k.clamp(0, w - 1)];
      }
      for (var x = 0; x < w; x++) {
        tmp[base + x] = (sum + (win >> 1)) ~/ win;
        sum += src[base + math.min(w - 1, x + r + 1)] - src[base + math.max(0, x - r)];
      }
    }
    for (var x = 0; x < w; x++) {
      var sum = 0;
      for (var k = -r; k <= r; k++) {
        sum += tmp[k.clamp(0, h - 1) * w + x];
      }
      for (var y = 0; y < h; y++) {
        out[y * w + x] = (sum + (win >> 1)) ~/ win;
        sum += tmp[math.min(h - 1, y + r + 1) * w + x] - tmp[math.max(0, y - r) * w + x];
      }
    }
    return out;
  }

  static Uint32List _integral(Uint8List gray, int w, int h) {
    final integral = Uint32List((w + 1) * (h + 1));
    for (var y = 1; y <= h; y++) {
      var row = 0;
      for (var x = 1; x <= w; x++) {
        row += gray[(y - 1) * w + (x - 1)];
        integral[y * (w + 1) + x] = integral[(y - 1) * (w + 1) + x] + row;
      }
    }
    return integral;
  }

  static int _rectSum(Uint32List integral, int w, int x0, int y0, int x1, int y1) {
    final stride = w + 1;
    return integral[(y1 + 1) * stride + (x1 + 1)] - integral[y0 * stride + (x1 + 1)] - integral[(y1 + 1) * stride + x0] + integral[y0 * stride + x0];
  }
}

/// Percentile levels from a sample of the picture (at most about 200,000 pixels, so it is quick at any size).
class _Levels {
  _Levels(RgbBuffer src) {
    final n = src.width * src.height;
    final step = math.max(1, n ~/ 200000);
    final d = src.data;
    var sum = 0;
    for (var i = 0; i < n; i += step) {
      final p = i * 3;
      final rr = d[p], gg = d[p + 1], bb = d[p + 2];
      r[rr]++;
      g[gg]++;
      b[bb]++;
      final lum = (rr * 77 + gg * 150 + bb * 29) >> 8;
      l[lum]++;
      sum += lum;
      count++;
    }
    meanLuma = count == 0 ? 128 : sum / count;
  }

  final r = Uint32List(256), g = Uint32List(256), b = Uint32List(256), l = Uint32List(256);
  var count = 0;
  late final double meanLuma;

  /// The value below which about [frac] of the pixels lie, counted from the dark end.
  int low(Uint32List h, double frac) {
    final target = count * frac;
    var acc = 0;
    for (var i = 0; i < 256; i++) {
      acc += h[i];
      if (acc > target) return i;
    }
    return 255;
  }

  /// The value that [frac] of the pixels do not exceed.
  int high(Uint32List h, double frac) {
    final target = count * frac;
    var acc = 0;
    for (var i = 0; i < 256; i++) {
      acc += h[i];
      if (acc >= target) return i;
    }
    return 255;
  }
}

/// The colour of the paper (or board) at every point, estimated on a coarse grid: average a few samples per cell, then a grey-scale
/// closing so ink, writing and large dark areas drop out, then a light blur. [row] turns that into a fixed-point gain (256 = 1x) that brings the paper to a target level.
class _Background {
  _Background(this.w, this.h, Uint8List gray) {
    final cell = math.max(4, math.max(w, h) ~/ 200);
    sw = math.max(1, (w + cell - 1) ~/ cell);
    sh = math.max(1, (h + cell - 1) ~/ cell);
    final small = Uint8List(sw * sh);
    for (var cy = 0; cy < sh; cy++) {
      for (var cx = 0; cx < sw; cx++) {
        var sum = 0, n = 0;
        for (var j = 0; j < 3; j++) {
          final y = math.min(h - 1, cy * cell + (cell * (2 * j + 1)) ~/ 6);
          for (var i = 0; i < 3; i++) {
            final x = math.min(w - 1, cx * cell + (cell * (2 * i + 1)) ~/ 6);
            sum += gray[y * w + x];
            n++;
          }
        }
        small[cy * sw + cx] = sum ~/ n;
      }
    }
    // A grey-scale closing (local maximum, then local minimum, over a window wider than any logo or photo) removes everything darker than
    // the paper and narrower than the window, yet follows smooth shadows exactly. So ink and large dark areas stay dark, and shadows go.
    final longCells = math.max(sw, sh);
    final r = (longCells * 0.14).round().clamp(4, 60);
    bg = _blurGrid(_erode(_dilate(small, sw, sh, r), sw, sh, r), sw, sh, 2);
    this.cell = cell;
    xi0 = Int32List(w);
    xi1 = Int32List(w);
    xt = Float32List(w);
    for (var x = 0; x < w; x++) {
      final fx = ((x + 0.5) / cell - 0.5).clamp(0.0, sw - 1.0);
      final i0 = fx.floor();
      xi0[x] = i0;
      xi1[x] = math.min(sw - 1, i0 + 1);
      xt[x] = fx - i0;
    }
  }

  final int w, h;
  late final int sw, sh, cell;
  late final Float32List bg;
  late final Int32List xi0, xi1;
  late final Float32List xt;

  /// Fills [out] with the gain for row [y]: [target] / paper level, with the level never below [minLocal] and the gain never above [maxGain].
  void row(int y, double target, double minLocal, double maxGain, Int32List out) {
    final fy = ((y + 0.5) / cell - 0.5).clamp(0.0, sh - 1.0);
    final y0 = fy.floor();
    final y1 = math.min(sh - 1, y0 + 1);
    final ty = fy - y0;
    final r0 = y0 * sw, r1 = y1 * sw;
    final cap = (maxGain * 256).round();
    for (var x = 0; x < w; x++) {
      final a = xi0[x], b = xi1[x];
      final t = xt[x];
      final top = bg[r0 + a] * (1 - t) + bg[r0 + b] * t;
      final bot = bg[r1 + a] * (1 - t) + bg[r1 + b] * t;
      final local = math.max(minLocal, top * (1 - ty) + bot * ty);
      final g = (target * 256 / local).round();
      out[x] = g > cap ? cap : g;
    }
  }

  static Uint8List _dilate(Uint8List src, int w, int h, int r) {
    // Separable local maximum.
    final tmp = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var m = 0;
        for (var k = math.max(0, x - r); k <= math.min(w - 1, x + r); k++) {
          final v = src[y * w + k];
          if (v > m) m = v;
        }
        tmp[y * w + x] = m;
      }
    }
    final out = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var m = 0;
        for (var k = math.max(0, y - r); k <= math.min(h - 1, y + r); k++) {
          final v = tmp[k * w + x];
          if (v > m) m = v;
        }
        out[y * w + x] = m;
      }
    }
    return out;
  }

  static Uint8List _erode(Uint8List src, int w, int h, int r) {
    final tmp = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var m = 255;
        for (var k = math.max(0, x - r); k <= math.min(w - 1, x + r); k++) {
          final v = src[y * w + k];
          if (v < m) m = v;
        }
        tmp[y * w + x] = m;
      }
    }
    final out = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var m = 255;
        for (var k = math.max(0, y - r); k <= math.min(h - 1, y + r); k++) {
          final v = tmp[k * w + x];
          if (v < m) m = v;
        }
        out[y * w + x] = m;
      }
    }
    return out;
  }

  static Float32List _blurGrid(Uint8List src, int w, int h, int r) {
    final tmp = Float32List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var sum = 0.0;
        var n = 0;
        for (var k = math.max(0, x - r); k <= math.min(w - 1, x + r); k++) {
          sum += src[y * w + k];
          n++;
        }
        tmp[y * w + x] = sum / n;
      }
    }
    final out = Float32List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var sum = 0.0;
        var n = 0;
        for (var k = math.max(0, y - r); k <= math.min(h - 1, y + r); k++) {
          sum += tmp[k * w + x];
          n++;
        }
        out[y * w + x] = sum / n;
      }
    }
    return out;
  }
}

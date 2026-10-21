import 'dart:math' as math;
import 'dart:typed_data';

import '../../domain/entities/quad.dart';

/// Region-based document detector working on a small grayscale grid.
///
/// Segments the frame with Otsu thresholding, keeps the largest compact region
/// that is not the frame background, and takes its four extreme points as corners.
/// Pure Dart: usable for live camera frames and still images alike.
class DocumentEdgeDetector {
  const DocumentEdgeDetector({this.minAreaRatio = 0.12, this.maxBorderTouch = 0.4});

  final double minAreaRatio;
  final double maxBorderTouch;

  Quad? detect(Uint8List gray, int w, int h) {
    if (w < 16 || h < 16 || gray.length < w * h) return null;

    final blurred = _boxBlur(gray, w, h);
    final threshold = _otsu(blurred);

    Quad? best;
    var bestScore = 0.0;
    for (final bright in const [true, false]) {
      final mask = Uint8List(w * h);
      for (var i = 0; i < mask.length; i++) {
        mask[i] = (bright ? blurred[i] > threshold : blurred[i] <= threshold) ? 1 : 0;
      }
      final candidate = _largestRegionQuad(mask, w, h);
      if (candidate != null && candidate.$2 > bestScore) {
        best = candidate.$1;
        bestScore = candidate.$2;
      }
    }
    return best;
  }

  (Quad, double)? _largestRegionQuad(Uint8List mask, int w, int h) {
    final total = w * h;
    final visited = Uint8List(total);
    final stack = Int32List(total);
    final borderPerimeter = 2 * (w + h);

    Quad? bestQuad;
    var bestScore = 0.0;

    for (var start = 0; start < total; start++) {
      if (mask[start] == 0 || visited[start] == 1) continue;

      var sp = 0;
      stack[sp++] = start;
      visited[start] = 1;

      var area = 0;
      var borderTouch = 0;
      var tlVal = 1 << 30, brVal = -(1 << 30), trVal = -(1 << 30), blVal = 1 << 30;
      var tlX = 0, tlY = 0, brX = 0, brY = 0, trX = 0, trY = 0, blX = 0, blY = 0;

      while (sp > 0) {
        final idx = stack[--sp];
        final x = idx % w;
        final y = idx ~/ w;
        area++;
        if (x == 0 || y == 0 || x == w - 1 || y == h - 1) borderTouch++;

        final s = x + y;
        final d = x - y;
        if (s < tlVal) { tlVal = s; tlX = x; tlY = y; }
        if (s > brVal) { brVal = s; brX = x; brY = y; }
        if (d > trVal) { trVal = d; trX = x; trY = y; }
        if (d < blVal) { blVal = d; blX = x; blY = y; }

        if (x > 0 && mask[idx - 1] == 1 && visited[idx - 1] == 0) { visited[idx - 1] = 1; stack[sp++] = idx - 1; }
        if (x < w - 1 && mask[idx + 1] == 1 && visited[idx + 1] == 0) { visited[idx + 1] = 1; stack[sp++] = idx + 1; }
        if (y > 0 && mask[idx - w] == 1 && visited[idx - w] == 0) { visited[idx - w] = 1; stack[sp++] = idx - w; }
        if (y < h - 1 && mask[idx + w] == 1 && visited[idx + w] == 0) { visited[idx + w] = 1; stack[sp++] = idx + w; }
      }

      if (area < total * minAreaRatio || area > total * 0.97) continue;
      if (borderTouch > borderPerimeter * maxBorderTouch) continue;

      final quad = Quad(
        NormPoint((tlX + 0.5) / w, (tlY + 0.5) / h),
        NormPoint((trX + 0.5) / w, (trY + 0.5) / h),
        NormPoint((brX + 0.5) / w, (brY + 0.5) / h),
        NormPoint((blX + 0.5) / w, (blY + 0.5) / h),
      );

      if (!quad.isConvex) continue;
      final quadArea = quad.area * total;
      // A real document fills most of its own bounding quad.
      final fill = area / quadArea;
      if (fill < 0.6 || fill > 1.05) continue;
      if (_minSide(quad) < 0.12) continue;

      final score = area * fill;
      if (score > bestScore) {
        bestScore = score;
        bestQuad = quad;
      }
    }

    return bestQuad == null ? null : (bestQuad, bestScore / total);
  }

  double _minSide(Quad q) {
    final p = q.points;
    var m = double.infinity;
    for (var i = 0; i < 4; i++) {
      m = math.min(m, p[i].distanceTo(p[(i + 1) % 4]));
    }
    return m;
  }

  Uint8List _boxBlur(Uint8List src, int w, int h) {
    final out = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var sum = 0, n = 0;
        for (var dy = -1; dy <= 1; dy++) {
          final yy = y + dy;
          if (yy < 0 || yy >= h) continue;
          for (var dx = -1; dx <= 1; dx++) {
            final xx = x + dx;
            if (xx < 0 || xx >= w) continue;
            sum += src[yy * w + xx];
            n++;
          }
        }
        out[y * w + x] = sum ~/ n;
      }
    }
    return out;
  }

  int _otsu(Uint8List data) {
    final hist = List<int>.filled(256, 0);
    for (final v in data) {
      hist[v]++;
    }
    final total = data.length;
    var sumAll = 0.0;
    for (var i = 0; i < 256; i++) {
      sumAll += i * hist[i];
    }
    var sumB = 0.0, wB = 0, best = 0.0, threshold = 127;
    for (var t = 0; t < 256; t++) {
      wB += hist[t];
      if (wB == 0) continue;
      final wF = total - wB;
      if (wF == 0) break;
      sumB += t * hist[t];
      final mB = sumB / wB;
      final mF = (sumAll - sumB) / wF;
      final between = wB * wF * (mB - mF) * (mB - mF);
      if (between > best) {
        best = between;
        threshold = t;
      }
    }
    return threshold;
  }
}

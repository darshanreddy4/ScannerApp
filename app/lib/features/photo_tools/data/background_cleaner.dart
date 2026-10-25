import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Replaces a plain, evenly lit wall behind a person with a chosen colour.
///
/// It grows a region outward from the picture's edges across pixels that look like the wall, so it works on plain
/// backgrounds only; a busy background is left mostly as it is.
img.Image cleanBackground(img.Image photo, {required int backgroundArgb, int strength = 50}) {
  final w = photo.width, h = photo.height;
  final seed = _wallColor(photo);
  final level = strength.clamp(0, 100);
  final fromWall = 16.0 + level * 0.6; // how far from the wall colour a pixel may be
  final fromNeighbour = 10.0 + level * 0.2; // how fast the colour may change from one pixel to the next

  final inside = Uint8List(w * h);
  final queue = Queue<int>();

  bool wall(int x, int y) => _distance(photo.getPixel(x, y), seed[0], seed[1], seed[2]) <= fromWall;

  void start(int x, int y) {
    final i = y * w + x;
    if (inside[i] == 0 && wall(x, y)) {
      inside[i] = 1;
      queue.add(i);
    }
  }

  for (var x = 0; x < w; x++) {
    start(x, 0);
    start(x, h - 1);
  }
  for (var y = 0; y < h; y++) {
    start(0, y);
    start(w - 1, y);
  }

  const steps = [(1, 0), (-1, 0), (0, 1), (0, -1)];
  while (queue.isNotEmpty) {
    final i = queue.removeFirst();
    final x = i % w, y = i ~/ w;
    final here = photo.getPixel(x, y);
    for (final (dx, dy) in steps) {
      final nx = x + dx, ny = y + dy;
      if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
      final j = ny * w + nx;
      if (inside[j] != 0) continue;
      final p = photo.getPixel(nx, ny);
      if (_distance(p, seed[0], seed[1], seed[2]) <= fromWall && _distance(p, here.r.toInt(), here.g.toInt(), here.b.toInt()) <= fromNeighbour) {
        inside[j] = 1;
        queue.add(j);
      }
    }
  }

  final alpha = _feather(inside, w, h, math.max(1, (math.min(w, h) * 0.004).round()));
  final r = (backgroundArgb >> 16) & 0xFF, g = (backgroundArgb >> 8) & 0xFF, b = backgroundArgb & 0xFF;
  final out = img.Image(width: w, height: h, numChannels: 3);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = photo.getPixel(x, y);
      final a = alpha[y * w + x];
      out.setPixelRgb(x, y, (p.r * (1 - a) + r * a).round(), (p.g * (1 - a) + g * a).round(), (p.b * (1 - a) + b * a).round());
    }
  }
  return out;
}

/// The median colour of the top and upper side edges, where the wall is visible and the person is not.
List<int> _wallColor(img.Image photo) {
  final w = photo.width, h = photo.height;
  final band = math.max(2, (math.min(w, h) * 0.04).round());
  final rs = <int>[], gs = <int>[], bs = <int>[];
  void add(int x, int y) {
    final p = photo.getPixel(x, y);
    rs.add(p.r.toInt());
    gs.add(p.g.toInt());
    bs.add(p.b.toInt());
  }

  for (var y = 0; y < band; y++) {
    for (var x = 0; x < w; x += 2) {
      add(x, y);
    }
  }
  for (var y = 0; y < h * 0.6; y += 2) {
    for (var x = 0; x < band; x++) {
      add(x, y);
      add(w - 1 - x, y);
    }
  }
  int median(List<int> v) => (v..sort())[v.length ~/ 2];
  return [median(rs), median(gs), median(bs)];
}

double _distance(img.Pixel p, int r, int g, int b) {
  final dr = p.r - r, dg = p.g - g, db = p.b - b;
  return math.sqrt(dr * dr + dg * dg + db * db);
}

/// Softens the mask edge with two box blurs so the person does not look cut out.
Float32List _feather(Uint8List mask, int w, int h, int radius) {
  var a = Float32List.fromList([for (final m in mask) m.toDouble()]);
  for (var pass = 0; pass < 2; pass++) {
    final horizontal = Float32List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var sum = 0.0;
        var n = 0;
        for (var k = -radius; k <= radius; k++) {
          final xx = x + k;
          if (xx < 0 || xx >= w) continue;
          sum += a[y * w + xx];
          n++;
        }
        horizontal[y * w + x] = sum / n;
      }
    }
    final vertical = Float32List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var sum = 0.0;
        var n = 0;
        for (var k = -radius; k <= radius; k++) {
          final yy = y + k;
          if (yy < 0 || yy >= h) continue;
          sum += horizontal[yy * w + x];
          n++;
        }
        vertical[y * w + x] = sum / n;
      }
    }
    a = vertical;
  }
  return a;
}

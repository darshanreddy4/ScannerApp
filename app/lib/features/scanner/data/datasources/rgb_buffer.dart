import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../domain/entities/quad.dart';

/// Packed 8-bit RGB raster used by all pixel pipelines.
class RgbBuffer {
  RgbBuffer(this.width, this.height, this.data);

  RgbBuffer.blank(this.width, this.height) : data = Uint8List(width * height * 3);

  final int width;
  final int height;
  final Uint8List data;

  factory RgbBuffer.fromImage(img.Image image) {
    final rgb = image.convert(format: img.Format.uint8, numChannels: 3);
    final bytes = rgb.getBytes(order: img.ChannelOrder.rgb);
    return RgbBuffer(rgb.width, rgb.height, Uint8List.fromList(bytes));
  }

  img.Image toImage() => img.Image.fromBytes(
        width: width,
        height: height,
        bytes: data.buffer,
        bytesOffset: data.offsetInBytes,
        numChannels: 3,
      );

  Uint8List encodeJpeg({int quality = 90}) => img.encodeJpg(toImage(), quality: quality);

  Uint8List toGray() {
    final out = Uint8List(width * height);
    for (var i = 0, p = 0; i < out.length; i++, p += 3) {
      out[i] = (data[p] * 77 + data[p + 1] * 150 + data[p + 2] * 29) >> 8;
    }
    return out;
  }

  RgbBuffer rotate90Clockwise() {
    final out = RgbBuffer.blank(height, width);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final s = (y * width + x) * 3;
        final d = (x * height + (height - 1 - y)) * 3;
        out.data[d] = data[s];
        out.data[d + 1] = data[s + 1];
        out.data[d + 2] = data[s + 2];
      }
    }
    return out;
  }

  /// Nearest-neighbour downscale of luminance, for detection grids.
  static Uint8List grayThumbnail(RgbBuffer src, int targetW, int targetH) {
    final gray = src.toGray();
    final out = Uint8List(targetW * targetH);
    for (var y = 0; y < targetH; y++) {
      final sy = math.min(src.height - 1, (y * src.height / targetH).floor());
      for (var x = 0; x < targetW; x++) {
        final sx = math.min(src.width - 1, (x * src.width / targetW).floor());
        out[y * targetW + x] = gray[sy * src.width + sx];
      }
    }
    return out;
  }
}

/// Perspective correction: maps an arbitrary document quad onto an upright rectangle.
abstract final class PerspectiveTransform {
  static const _maxSide = 3000;

  static RgbBuffer warp(RgbBuffer src, Quad quad) {
    final p = [
      for (final q in quad.points) (q.x * src.width, q.y * src.height),
    ];

    double len((double, double) a, (double, double) b) => math.sqrt(math.pow(a.$1 - b.$1, 2) + math.pow(a.$2 - b.$2, 2));

    var outW = math.max(len(p[0], p[1]), len(p[3], p[2]));
    var outH = math.max(len(p[0], p[3]), len(p[1], p[2]));
    final scale = math.min(1.0, _maxSide / math.max(outW, outH));
    outW *= scale;
    outH *= scale;
    final w = math.max(1, outW.round());
    final h = math.max(1, outH.round());

    // Homography from destination rectangle to source quad.
    final dst = [(0.0, 0.0), (w - 1.0, 0.0), (w - 1.0, h - 1.0), (0.0, h - 1.0)];
    final hm = _solveHomography(dst, p);

    final out = RgbBuffer.blank(w, h);
    final sw = src.width, sh = src.height;
    final sd = src.data;
    final od = out.data;

    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final denom = hm[6] * x + hm[7] * y + 1.0;
        final sx = (hm[0] * x + hm[1] * y + hm[2]) / denom;
        final sy = (hm[3] * x + hm[4] * y + hm[5]) / denom;

        final fx = sx.clamp(0.0, sw - 1.001);
        final fy = sy.clamp(0.0, sh - 1.001);
        final x0 = fx.floor(), y0 = fy.floor();
        final tx = fx - x0, ty = fy - y0;
        final i00 = (y0 * sw + x0) * 3;
        final i10 = i00 + 3;
        final i01 = i00 + sw * 3;
        final i11 = i01 + 3;
        final o = (y * w + x) * 3;
        for (var c = 0; c < 3; c++) {
          final top = sd[i00 + c] * (1 - tx) + sd[i10 + c] * tx;
          final bot = sd[i01 + c] * (1 - tx) + sd[i11 + c] * tx;
          od[o + c] = (top * (1 - ty) + bot * ty).round();
        }
      }
    }
    return out;
  }

  /// Solves the 8 homography coefficients mapping [from] points to [to] points.
  static List<double> _solveHomography(List<(double, double)> from, List<(double, double)> to) {
    final a = List.generate(8, (_) => List<double>.filled(9, 0));
    for (var i = 0; i < 4; i++) {
      final (x, y) = from[i];
      final (u, v) = to[i];
      a[2 * i] = [x, y, 1, 0, 0, 0, -u * x, -u * y, u];
      a[2 * i + 1] = [0, 0, 0, x, y, 1, -v * x, -v * y, v];
    }

    for (var col = 0; col < 8; col++) {
      var pivot = col;
      for (var r = col + 1; r < 8; r++) {
        if (a[r][col].abs() > a[pivot][col].abs()) pivot = r;
      }
      if (a[pivot][col].abs() < 1e-12) {
        throw StateError('Degenerate crop region');
      }
      final tmp = a[col];
      a[col] = a[pivot];
      a[pivot] = tmp;

      for (var r = 0; r < 8; r++) {
        if (r == col) continue;
        final f = a[r][col] / a[col][col];
        for (var c = col; c < 9; c++) {
          a[r][c] -= f * a[col][c];
        }
      }
    }
    return [for (var i = 0; i < 8; i++) a[i][8] / a[i][i]];
  }
}

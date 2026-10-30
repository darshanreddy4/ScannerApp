import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'text_compare.dart' show TextRect;

/// Where two renderings of a page differ.
class PageVisualDiff {
  const PageVisualDiff({required this.regions, required this.similarity, this.sizeChanged = false});

  /// Boxes as shares of the page around what looks different.
  final List<TextRect> regions;

  /// 1 for pages that look the same, lower the more of the page differs.
  final double similarity;

  /// The two pages are not the same shape.
  final bool sizeChanged;

  bool get same => regions.isEmpty && !sizeChanged;
}

/// Compares two pictures of a page: both are brought to the same small size and compared block by block, and neighbouring blocks that
/// differ make one box. Small shifts of anti-aliasing do not count; a new word, a moved line or a different picture do.
PageVisualDiff diffPageImages(Uint8List a, Uint8List b, {int width = 360, int block = 9, int maxRegions = 40}) {
  final ia = img.decodeImage(a), ib = img.decodeImage(b);
  if (ia == null || ib == null) return const PageVisualDiff(regions: [], similarity: 1);
  final sizeChanged = (ia.width / ia.height - ib.width / ib.height).abs() > 0.02;
  final height = math.max(block * 2, (width * ib.height / ib.width).round());
  final sa = img.copyResize(ia, width: width, height: height, interpolation: img.Interpolation.average);
  final sb = img.copyResize(ib, width: width, height: height, interpolation: img.Interpolation.average);

  final cols = (width / block).ceil(), rows = (height / block).ceil();
  final changed = List<bool>.filled(cols * rows, false);
  var count = 0;
  for (var cy = 0; cy < rows; cy++) {
    for (var cx = 0; cx < cols; cx++) {
      var strong = 0;
      final x1 = math.min(width, (cx + 1) * block), y1 = math.min(height, (cy + 1) * block);
      for (var y = cy * block; y < y1; y++) {
        for (var x = cx * block; x < x1; x++) {
          final pa = sa.getPixel(x, y), pb = sb.getPixel(x, y);
          final la = 0.299 * pa.r + 0.587 * pa.g + 0.114 * pa.b;
          final lb = 0.299 * pb.r + 0.587 * pb.g + 0.114 * pb.b;
          if ((la - lb).abs() > 60) strong++;
        }
      }
      if (strong >= math.max(3, (block * block * 0.04).round())) {
        changed[cy * cols + cx] = true;
        count++;
      }
    }
  }

  // Blocks that touch (also at the corners) belong to one box.
  final seen = List<bool>.filled(cols * rows, false);
  final regions = <TextRect>[];
  for (var start = 0; start < changed.length; start++) {
    if (!changed[start] || seen[start]) continue;
    var minX = cols, minY = rows, maxX = 0, maxY = 0;
    final stack = [start];
    seen[start] = true;
    while (stack.isNotEmpty) {
      final at = stack.removeLast();
      final x = at % cols, y = at ~/ cols;
      minX = math.min(minX, x);
      maxX = math.max(maxX, x);
      minY = math.min(minY, y);
      maxY = math.max(maxY, y);
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final nx = x + dx, ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= cols || ny >= rows) continue;
          final n = ny * cols + nx;
          if (changed[n] && !seen[n]) {
            seen[n] = true;
            stack.add(n);
          }
        }
      }
    }
    regions.add(
      TextRect(
        math.max(0, (minX * block - block / 2) / width),
        math.max(0, (minY * block - block / 2) / height),
        math.min(1, ((maxX + 1) * block + block / 2) / width),
        math.min(1, ((maxY + 1) * block + block / 2) / height),
      ),
    );
  }
  // Too many scattered boxes help nobody: keep the biggest.
  if (regions.length > maxRegions) {
    regions.sort((p, q) => (q.width * q.height).compareTo(p.width * p.height));
    regions.removeRange(maxRegions, regions.length);
  }
  return PageVisualDiff(regions: regions, similarity: 1 - count / (cols * rows), sizeChanged: sizeChanged);
}

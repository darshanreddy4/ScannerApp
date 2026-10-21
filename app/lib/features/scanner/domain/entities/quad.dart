import 'dart:math' as math;

import 'package:equatable/equatable.dart';

/// Point in normalized image space: both axes in [0, 1].
class NormPoint extends Equatable {
  const NormPoint(this.x, this.y);

  final double x;
  final double y;

  NormPoint clamp() => NormPoint(x.clamp(0.0, 1.0), y.clamp(0.0, 1.0));
  NormPoint translate(double dx, double dy) => NormPoint(x + dx, y + dy);
  double distanceTo(NormPoint o) => math.sqrt(math.pow(x - o.x, 2) + math.pow(y - o.y, 2));

  @override
  List<Object?> get props => [x, y];
}

/// Document outline. Corner order: top-left, top-right, bottom-right, bottom-left.
class Quad extends Equatable {
  const Quad(this.tl, this.tr, this.br, this.bl);

  static const fullFrame = Quad(NormPoint(0, 0), NormPoint(1, 0), NormPoint(1, 1), NormPoint(0, 1));

  /// Slightly inset rectangle used as the initial crop when nothing is detected.
  static const defaultInset = Quad(
    NormPoint(0.08, 0.08),
    NormPoint(0.92, 0.08),
    NormPoint(0.92, 0.92),
    NormPoint(0.08, 0.92),
  );

  final NormPoint tl;
  final NormPoint tr;
  final NormPoint br;
  final NormPoint bl;

  List<NormPoint> get points => [tl, tr, br, bl];

  Quad withPoint(int index, NormPoint p) {
    final pts = [...points]..[index] = p.clamp();
    return Quad(pts[0], pts[1], pts[2], pts[3]);
  }

  /// Moves the edge between corner [index] and the next corner.
  Quad withEdgeShift(int index, double dx, double dy) {
    final pts = [...points];
    final a = index;
    final b = (index + 1) % 4;
    pts[a] = pts[a].translate(dx, dy).clamp();
    pts[b] = pts[b].translate(dx, dy).clamp();
    return Quad(pts[0], pts[1], pts[2], pts[3]);
  }

  /// Shoelace area in normalized units.
  double get area {
    final p = points;
    var s = 0.0;
    for (var i = 0; i < 4; i++) {
      final a = p[i];
      final b = p[(i + 1) % 4];
      s += a.x * b.y - b.x * a.y;
    }
    return s.abs() / 2;
  }

  /// True when every turn has the same sign (no bow-tie or concave shape).
  bool get isConvex {
    final p = points;
    double? sign;
    for (var i = 0; i < 4; i++) {
      final a = p[i];
      final b = p[(i + 1) % 4];
      final c = p[(i + 2) % 4];
      final cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x);
      if (cross == 0) continue;
      sign ??= cross.sign;
      if (cross.sign != sign) return false;
    }
    return true;
  }

  /// Quad after rotating the underlying image 90 degrees clockwise.
  Quad rotatedClockwise() {
    NormPoint r(NormPoint p) => NormPoint(1 - p.y, p.x);
    return Quad(r(bl), r(tl), r(tr), r(br));
  }

  double maxCornerDelta(Quad other) {
    var m = 0.0;
    for (var i = 0; i < 4; i++) {
      m = math.max(m, points[i].distanceTo(other.points[i]));
    }
    return m;
  }

  @override
  List<Object?> get props => [tl, tr, br, bl];
}

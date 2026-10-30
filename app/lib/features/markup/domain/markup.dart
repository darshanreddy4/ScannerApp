import 'dart:math' as math;
import 'dart:ui';

/// Pen styles for freehand lines.
enum PenKind { pen, pencil, highlighter }

enum ShapeKind { line, arrow, rectangle, ellipse }

/// Things drawn on a page. Positions are shares of the page (0 to 1) and widths are shares of the page width,
/// so the same marks fit a small preview and the full size page.
sealed class MarkupItem {
  const MarkupItem(this.id);
  final int id;
}

class MarkupStroke extends MarkupItem {
  const MarkupStroke({required int id, required this.kind, required this.points, required this.color, required this.width}) : super(id);

  final PenKind kind;
  final List<Offset> points;

  /// ARGB, the opacity is part of the colour.
  final int color;
  final double width;

  MarkupStroke copyWith({int? id, List<Offset>? points, int? color, double? width}) =>
      MarkupStroke(id: id ?? this.id, kind: kind, points: points ?? this.points, color: color ?? this.color, width: width ?? this.width);
}

class MarkupShape extends MarkupItem {
  const MarkupShape({
    required int id,
    required this.kind,
    required this.from,
    required this.to,
    required this.color,
    required this.width,
    this.filled = false,
    this.redact = false,
  }) : super(id);

  final ShapeKind kind;
  final Offset from;
  final Offset to;
  final int color;
  final double width;
  final bool filled;

  /// A solid black box that hides what is under it. Colour and see-through settings never apply to it.
  final bool redact;

  MarkupShape copyWith({int? id, Offset? from, Offset? to, int? color, double? width, bool? filled}) => MarkupShape(
    id: id ?? this.id,
    kind: kind,
    from: from ?? this.from,
    to: to ?? this.to,
    color: color ?? this.color,
    width: width ?? this.width,
    filled: filled ?? this.filled,
    redact: redact,
  );
}

/// An emoji or short text placed on the page.
class MarkupSticker extends MarkupItem {
  const MarkupSticker({required int id, required this.text, required this.center, required this.size, this.rotation = 0}) : super(id);

  final String text;
  final Offset center;

  /// Height of the symbol as a share of the page width.
  final double size;

  /// Radians, clockwise.
  final double rotation;

  static const minSize = 0.03;
  static const maxSize = 0.8;

  MarkupSticker copyWith({int? id, Offset? center, double? size, double? rotation}) =>
      MarkupSticker(id: id ?? this.id, text: text, center: center ?? this.center, size: size ?? this.size, rotation: rotation ?? this.rotation);
}

/// Text typed onto the page, in one colour. Lines are broken where the writer pressed enter.
class MarkupText extends MarkupItem {
  const MarkupText({
    required int id,
    required this.text,
    required this.center,
    required this.size,
    required this.color,
    this.bold = false,
    this.rotation = 0,
    this.framed = false,
  }) : super(id);

  final String text;
  final Offset center;

  /// Font size as a share of the page width.
  final double size;

  /// ARGB.
  final int color;
  final bool bold;

  /// Radians, clockwise.
  final double rotation;

  /// Drawn inside a frame, like a rubber stamp.
  final bool framed;

  static const minSize = 0.015;
  static const maxSize = 0.3;
  static const defaultSize = 0.05;

  MarkupText copyWith({int? id, String? text, Offset? center, double? size, int? color, bool? bold, double? rotation}) => MarkupText(
    id: id ?? this.id,
    text: text ?? this.text,
    center: center ?? this.center,
    size: size ?? this.size,
    color: color ?? this.color,
    bold: bold ?? this.bold,
    rotation: rotation ?? this.rotation,
    framed: framed,
  );
}

/// The space between a framed text (a stamp) and its frame, in pixels on a page [pageWidth] pixels wide.
double markupTextPad(MarkupText t, double pageWidth) => t.framed ? t.size * pageWidth * 0.4 : 0;

/// The laid out text of [t] on a page [pageWidth] pixels wide. Drawing and touching both use it, so they agree on where the text is.
Paragraph markupTextParagraph(MarkupText t, double pageWidth) {
  Paragraph build(double width) {
    final builder = ParagraphBuilder(ParagraphStyle(textAlign: TextAlign.center))
      ..pushStyle(TextStyle(color: Color(t.color), fontSize: t.size * pageWidth, fontWeight: t.bold ? FontWeight.w700 : FontWeight.w400, height: 1.2))
      ..addText(t.text);
    return builder.build()..layout(ParagraphConstraints(width: width));
  }

  final probe = build(1e6);
  final natural = probe.longestLine.ceilToDouble() + 1;
  probe.dispose();
  return build(natural);
}

/// What a tap or drag on the page does.
enum MarkupTool { pen, pencil, highlighter, eraser, line, arrow, rectangle, ellipse, redact, sticker, stamp, text, select, hand }

extension MarkupToolInfo on MarkupTool {
  String get label => switch (this) {
    MarkupTool.pen => 'Pen',
    MarkupTool.pencil => 'Pencil',
    MarkupTool.highlighter => 'Highlight',
    MarkupTool.eraser => 'Eraser',
    MarkupTool.line => 'Line',
    MarkupTool.arrow => 'Arrow',
    MarkupTool.rectangle => 'Square',
    MarkupTool.ellipse => 'Circle',
    MarkupTool.redact => 'Hide',
    MarkupTool.sticker => 'Emoji',
    MarkupTool.stamp => 'Stamp',
    MarkupTool.text => 'Text',
    MarkupTool.select => 'Move',
    MarkupTool.hand => 'Zoom',
  };

  PenKind? get penKind => switch (this) {
    MarkupTool.pen => PenKind.pen,
    MarkupTool.pencil => PenKind.pencil,
    MarkupTool.highlighter => PenKind.highlighter,
    _ => null,
  };

  ShapeKind? get shapeKind => switch (this) {
    MarkupTool.line => ShapeKind.line,
    MarkupTool.arrow => ShapeKind.arrow,
    MarkupTool.rectangle => ShapeKind.rectangle,
    MarkupTool.ellipse => ShapeKind.ellipse,
    MarkupTool.redact => ShapeKind.rectangle,
    _ => null,
  };

  /// Tools that have a colour and a thickness.
  bool get hasInk => this != MarkupTool.redact && (penKind != null || shapeKind != null);
}

/// Where each item is on a page of [page] pixels, for touching, selecting and moving.
abstract final class MarkupGeometry {
  static Offset _px(Offset n, Size page) => Offset(n.dx * page.width, n.dy * page.height);

  static double _distanceToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 == 0) return (p - a).distance;
    final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(0.0, 1.0);
    return (p - (a + ab * t)).distance;
  }

  /// The smallest box around the item, in page pixels.
  static Rect bounds(MarkupItem item, Size page) {
    switch (item) {
      case MarkupStroke():
        final pts = [for (final p in item.points) _px(p, page)];
        var r = Rect.fromPoints(pts.first, pts.first);
        for (final p in pts) {
          r = r.expandToInclude(Rect.fromPoints(p, p));
        }
        return r.inflate(item.width * page.width / 2);
      case MarkupShape():
        return Rect.fromPoints(_px(item.from, page), _px(item.to, page)).inflate(item.width * page.width / 2);
      case MarkupSticker():
        final half = item.size * page.width * 0.6;
        final c = _px(item.center, page);
        final spread = half * (item.rotation == 0 ? 1 : (math.cos(item.rotation).abs() + math.sin(item.rotation).abs()));
        return Rect.fromCenter(center: c, width: spread * 2, height: spread * 2);
      case MarkupText():
        final para = markupTextParagraph(item, page.width);
        final pad = markupTextPad(item, page.width) * 2;
        final w = para.width + pad, h = para.height + pad;
        para.dispose();
        final cosA = math.cos(item.rotation).abs(), sinA = math.sin(item.rotation).abs();
        return Rect.fromCenter(center: _px(item.center, page), width: w * cosA + h * sinA, height: w * sinA + h * cosA);
    }
  }

  static Offset center(MarkupItem item, Size page) {
    final b = bounds(item, page);
    return Offset(b.center.dx / page.width, b.center.dy / page.height);
  }

  /// True when [point] (a share of the page) touches the item, give or take [tolerance] (a share of the page width).
  static bool hit(MarkupItem item, Offset point, Size page, {double tolerance = 0.02}) {
    final p = _px(point, page);
    final tol = tolerance * page.width;
    switch (item) {
      case MarkupStroke():
        final reach = tol + item.width * page.width / 2;
        final pts = [for (final q in item.points) _px(q, page)];
        if (pts.length == 1) return (p - pts.first).distance <= reach;
        for (var i = 0; i < pts.length - 1; i++) {
          if (_distanceToSegment(p, pts[i], pts[i + 1]) <= reach) return true;
        }
        return false;
      case MarkupShape():
        final a = _px(item.from, page), b = _px(item.to, page);
        final reach = tol + item.width * page.width / 2;
        switch (item.kind) {
          case ShapeKind.line:
          case ShapeKind.arrow:
            return _distanceToSegment(p, a, b) <= reach;
          case ShapeKind.rectangle:
            final r = Rect.fromPoints(a, b);
            if (item.filled) return r.inflate(reach).contains(p);
            final outer = r.inflate(reach), inner = r.deflate(reach);
            return outer.contains(p) && (inner.width <= 0 || inner.height <= 0 || !inner.contains(p));
          case ShapeKind.ellipse:
            final r = Rect.fromPoints(a, b);
            final rx = math.max(r.width / 2, 1.0), ry = math.max(r.height / 2, 1.0);
            final d = math.sqrt(math.pow((p.dx - r.center.dx) / rx, 2) + math.pow((p.dy - r.center.dy) / ry, 2));
            if (item.filled) return d <= 1 + reach / math.min(rx, ry);
            return (d - 1).abs() * math.min(rx, ry) <= reach;
        }
      case MarkupSticker():
        final c = _px(item.center, page);
        final d = p - c;
        final cosA = math.cos(-item.rotation), sinA = math.sin(-item.rotation);
        final local = Offset(d.dx * cosA - d.dy * sinA, d.dx * sinA + d.dy * cosA);
        final half = item.size * page.width * 0.6 + tol / 2;
        return local.dx.abs() <= half && local.dy.abs() <= half;
      case MarkupText():
        final para = markupTextParagraph(item, page.width);
        final pad = markupTextPad(item, page.width);
        final halfW = para.width / 2 + pad + tol / 2, halfH = para.height / 2 + pad + tol / 2;
        para.dispose();
        final d = p - _px(item.center, page);
        final cosA = math.cos(-item.rotation), sinA = math.sin(-item.rotation);
        final local = Offset(d.dx * cosA - d.dy * sinA, d.dx * sinA + d.dy * cosA);
        return local.dx.abs() <= halfW && local.dy.abs() <= halfH;
    }
  }

  /// The item moved by [delta] (shares of the page), then scaled about its middle, then turned (stickers only).
  static MarkupItem transform(MarkupItem item, Size page, {Offset delta = Offset.zero, double scale = 1, double rotation = 0}) {
    final pivot = center(item, page);
    Offset map(Offset p) => Offset(pivot.dx + (p.dx - pivot.dx) * scale, pivot.dy + (p.dy - pivot.dy) * scale) + delta;
    switch (item) {
      case MarkupStroke():
        return item.copyWith(points: [for (final p in item.points) map(p)], width: (item.width * scale).clamp(0.001, 0.2));
      case MarkupShape():
        return item.copyWith(from: map(item.from), to: map(item.to), width: (item.width * scale).clamp(0.001, 0.2));
      case MarkupSticker():
        return item.copyWith(
          center: item.center + delta,
          size: (item.size * scale).clamp(MarkupSticker.minSize, MarkupSticker.maxSize),
          rotation: item.rotation + rotation,
        );
      case MarkupText():
        return item.copyWith(
          center: item.center + delta,
          size: (item.size * scale).clamp(MarkupText.minSize, MarkupText.maxSize),
          rotation: item.rotation + rotation,
        );
    }
  }
}

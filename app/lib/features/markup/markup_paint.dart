import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'domain/markup.dart';

/// Draws marks onto [canvas] for a page of [size] pixels. The screen and the saved image use this same code.
void paintMarkup(Canvas canvas, Size size, Iterable<MarkupItem> items) {
  for (final item in items) {
    switch (item) {
      case MarkupStroke():
        _stroke(canvas, size, item);
      case MarkupShape():
        _shape(canvas, size, item);
      case MarkupSticker():
        _sticker(canvas, size, item);
      case MarkupText():
        _text(canvas, size, item);
    }
  }
}

Offset _px(Offset n, Size s) => Offset(n.dx * s.width, n.dy * s.height);

/// Joins the points with smooth curves so handwriting does not look jagged.
Path smoothMarkPath(List<Offset> pts, Size size) {
  final p = [for (final q in pts) _px(q, size)];
  final path = Path()..moveTo(p.first.dx, p.first.dy);
  if (p.length == 2) {
    path.lineTo(p.last.dx, p.last.dy);
    return path;
  }
  for (var i = 1; i < p.length - 1; i++) {
    final mid = (p[i] + p[i + 1]) / 2;
    path.quadraticBezierTo(p[i].dx, p[i].dy, mid.dx, mid.dy);
  }
  path.lineTo(p.last.dx, p.last.dy);
  return path;
}

void _stroke(Canvas canvas, Size size, MarkupStroke s) {
  if (s.points.isEmpty) return;
  final width = s.width * size.width;
  final highlighter = s.kind == PenKind.highlighter;
  if (s.points.length == 1) {
    canvas.drawCircle(
      _px(s.points.first, size),
      width / 2,
      Paint()
        ..color = Color(s.color)
        ..isAntiAlias = true,
    );
    return;
  }
  final paint = Paint()
    ..color = Color(s.color)
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = highlighter ? StrokeCap.square : StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;
  // A highlighter lets the text underneath show through instead of covering it.
  if (highlighter) paint.blendMode = BlendMode.multiply;
  canvas.drawPath(smoothMarkPath(s.points, size), paint);
}

void _shape(Canvas canvas, Size size, MarkupShape s) {
  final a = _px(s.from, size), b = _px(s.to, size);
  final width = s.width * size.width;
  final line = Paint()
    ..color = Color(s.color)
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;
  switch (s.kind) {
    case ShapeKind.line:
      canvas.drawLine(a, b, line);
    case ShapeKind.arrow:
      canvas.drawLine(a, b, line);
      final angle = math.atan2(b.dy - a.dy, b.dx - a.dx);
      final head = math.max(width * 4.5, size.width * 0.025);
      for (final turn in const [0.5, -0.5]) {
        canvas.drawLine(b, Offset(b.dx - head * math.cos(angle - turn), b.dy - head * math.sin(angle - turn)), line);
      }
    case ShapeKind.rectangle:
      final r = Rect.fromPoints(a, b);
      if (s.filled) canvas.drawRect(r, _fill(s.color));
      canvas.drawRect(r, line);
    case ShapeKind.ellipse:
      final r = Rect.fromPoints(a, b);
      if (s.filled) canvas.drawOval(r, _fill(s.color));
      canvas.drawOval(r, line);
  }
}

Paint _fill(int argb) {
  final c = Color(argb);
  return Paint()
    ..color = c.withValues(alpha: c.a * 0.28)
    ..style = PaintingStyle.fill;
}

void _sticker(Canvas canvas, Size size, MarkupSticker s) {
  final painter = TextPainter(
    text: TextSpan(
      text: s.text,
      style: TextStyle(fontSize: s.size * size.width, height: 1.0, color: const Color(0xFF000000)),
    ),
    textDirection: ui.TextDirection.ltr,
  )..layout();
  final c = _px(s.center, size);
  canvas.save();
  canvas.translate(c.dx, c.dy);
  canvas.rotate(s.rotation);
  painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
  canvas.restore();
  painter.dispose();
}

void _text(Canvas canvas, Size size, MarkupText t) {
  final paragraph = markupTextParagraph(t, size.width);
  final c = _px(t.center, size);
  canvas.save();
  canvas.translate(c.dx, c.dy);
  canvas.rotate(t.rotation);
  canvas.drawParagraph(paragraph, Offset(-paragraph.width / 2, -paragraph.height / 2));
  canvas.restore();
  paragraph.dispose();
}

/// A dashed frame around the selected item (shown on screen only).
void paintSelection(Canvas canvas, Size size, MarkupItem item) {
  final r = MarkupGeometry.bounds(item, size).inflate(size.width * 0.008);
  final paint = Paint()
    ..color = const Color(0xFF4C8DFF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(1.5, size.width * 0.003);
  final dash = size.width * 0.012;
  void edge(Offset from, Offset to) {
    final total = (to - from).distance;
    final dir = (to - from) / total;
    for (var d = 0.0; d < total; d += dash * 2) {
      canvas.drawLine(from + dir * d, from + dir * math.min(d + dash, total), paint);
    }
  }

  edge(r.topLeft, r.topRight);
  edge(r.topRight, r.bottomRight);
  edge(r.bottomRight, r.bottomLeft);
  edge(r.bottomLeft, r.topLeft);
}

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show TextAlign, TextDecoration, TextDirection, TextPainter, TextSpan, TextStyle, FontStyle, FontWeight;

import '../domain/slide_model.dart';

const _pt = emuPerPt;

/// Decodes the pictures of [paths] that are not decoded yet into [cache].
Future<void> loadSlideImages(Iterable<String> paths, MediaFiles files, Map<String, ui.Image> cache) async {
  for (final p in paths) {
    if (cache.containsKey(p)) continue;
    final bytes = files[p];
    if (bytes == null) continue;
    try {
      cache[p] = await _decode(bytes);
    } catch (_) {
      // Formats Flutter cannot decode (EMF, WMF) are drawn as a plain box.
    }
  }
}

Future<ui.Image> _decode(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  codec.dispose();
  return frame.image;
}

/// Every picture a slide needs: shapes, backgrounds and template decoration.
Set<String> mediaOf(SlideView view) {
  final out = <String>{};
  void add(ShapeView s) {
    if (s.media != null) out.add(s.media!);
    if (s.fill.media != null) out.add(s.fill.media!);
  }

  view.shapes.forEach(add);
  view.template.forEach(add);
  if (view.background.media != null) out.add(view.background.media!);
  return out;
}

/// Draws a slide. The canvas must already be scaled so one unit is one point (slide width / 12700 EMU).
void paintSlide(ui.Canvas canvas, SlideView view, Map<String, ui.Image> images, double widthPt, double heightPt) {
  final bg = view.background;
  final bgRect = ui.Rect.fromLTWH(0, 0, widthPt, heightPt);
  _fillRect(canvas, bg, bgRect, images, null);
  for (final s in view.template) {
    paintShape(canvas, s, images);
  }
  for (final s in view.shapes) {
    paintShape(canvas, s, images);
  }
}

void _fillRect(ui.Canvas canvas, FillView fill, ui.Rect rect, Map<String, ui.Image> images, ui.Path? path) {
  final paint = _fillPaint(fill, rect);
  if (paint != null) {
    path == null ? canvas.drawRect(rect, paint) : canvas.drawPath(path, paint);
    return;
  }
  if (fill.kind == FillKind.image) {
    final img = images[fill.media];
    if (img == null) return;
    canvas.save();
    if (path != null) canvas.clipPath(path);
    canvas.drawImageRect(img, ui.Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), rect, ui.Paint()..filterQuality = ui.FilterQuality.medium);
    canvas.restore();
  }
}

ui.Paint? _fillPaint(FillView fill, ui.Rect rect) {
  switch (fill.kind) {
    case FillKind.solid:
      return ui.Paint()..color = ui.Color(fill.color);
    case FillKind.gradient:
      final a = fill.angle * math.pi / 180;
      final dx = math.cos(a), dy = math.sin(a);
      final c = rect.center;
      final half = (rect.width * dx.abs() + rect.height * dy.abs()) / 2;
      return ui.Paint()
        ..shader = ui.Gradient.linear(
          ui.Offset(c.dx - dx * half, c.dy - dy * half),
          ui.Offset(c.dx + dx * half, c.dy + dy * half),
          [for (final s in fill.stops) ui.Color(s)],
          [for (var i = 0; i < fill.stops.length; i++) i / (fill.stops.length - 1)],
        );
    default:
      return null;
  }
}

/// Draws one shape with its fill, outline and text.
void paintShape(ui.Canvas canvas, ShapeView s, Map<String, ui.Image> images) {
  final f = s.frame;
  final w = f.w / _pt, h = f.h / _pt;
  if (w <= 0 && h <= 0) return;
  canvas.save();
  canvas.translate(f.cx / _pt, f.cy / _pt);
  if (f.rot != 0) canvas.rotate(f.rot * math.pi / 180);
  final rect = ui.Rect.fromLTWH(-w / 2, -h / 2, w, h);

  switch (s.kind) {
    case ShapeKind.line:
      canvas.save();
      if (f.flipH || f.flipV) canvas.scale(f.flipH ? -1 : 1, f.flipV ? -1 : 1);
      _paintLine(canvas, s, rect);
      canvas.restore();
    case ShapeKind.picture:
      _paintPicture(canvas, s, rect, images);
    case ShapeKind.table:
      if (s.table != null) _paintTable(canvas, s.table!, rect);
    case ShapeKind.chart || ShapeKind.diagram || ShapeKind.other:
      _paintPlaceholderBox(canvas, rect, s.label ?? '');
    case ShapeKind.text:
      canvas.save();
      if (f.flipH || f.flipV) canvas.scale(f.flipH ? -1 : 1, f.flipV ? -1 : 1);
      final path = _geometryPath(s, rect);
      if (s.fill.kind != FillKind.none) _fillRect(canvas, s.fill, rect, images, path);
      final line = s.line;
      if (line != null && line.widthPt > 0) canvas.drawPath(path, _linePaint(line));
      canvas.restore();
      if (s.paragraphs.isNotEmpty) _paintText(canvas, s.paragraphs, s.textBox, rect);
  }
  canvas.restore();
}

ui.Paint _linePaint(LineView l) => ui.Paint()
  ..style = ui.PaintingStyle.stroke
  ..strokeWidth = math.max(l.widthPt, 0.25)
  ..color = ui.Color(l.color)
  ..strokeJoin = ui.StrokeJoin.round;

ui.Path _geometryPath(ShapeView s, ui.Rect r) {
  final adj = s.adjust;
  switch (s.geometry) {
    case 'custom':
      final c = s.custom;
      if (c == null) return ui.Path()..addRect(r);
      final p = ui.Path();
      double x(double v) => r.left + v / c.w * r.width;
      double y(double v) => r.top + v / c.h * r.height;
      for (final cmd in c.cmds) {
        final pts = cmd.pts;
        switch (cmd.op) {
          case 'm':
            p.moveTo(x(pts[0]), y(pts[1]));
          case 'l':
            for (var i = 0; i + 1 < pts.length; i += 2) {
              p.lineTo(x(pts[i]), y(pts[i + 1]));
            }
          case 'c':
            for (var i = 0; i + 5 < pts.length; i += 6) {
              p.cubicTo(x(pts[i]), y(pts[i + 1]), x(pts[i + 2]), y(pts[i + 3]), x(pts[i + 4]), y(pts[i + 5]));
            }
          case 'q':
            for (var i = 0; i + 3 < pts.length; i += 4) {
              p.quadraticBezierTo(x(pts[i]), y(pts[i + 1]), x(pts[i + 2]), y(pts[i + 3]));
            }
          case 'z':
            p.close();
        }
      }
      return p;
    case 'ellipse' || 'flowChartConnector' || 'cloud':
      return ui.Path()..addOval(r);
    case 'roundRect' || 'flowChartAlternateProcess':
      return ui.Path()..addRRect(ui.RRect.fromRectAndRadius(r, ui.Radius.circular(math.min(r.width, r.height) * (adj ?? 0.16667).clamp(0, 0.5))));
    case 'flowChartTerminator':
      return ui.Path()..addRRect(ui.RRect.fromRectAndRadius(r, ui.Radius.circular(math.min(r.width, r.height) / 2)));
    case 'triangle':
      return _poly([ui.Offset(r.center.dx, r.top), r.bottomRight, r.bottomLeft]);
    case 'rtTriangle':
      return _poly([r.topLeft, r.bottomRight, r.bottomLeft]);
    case 'diamond' || 'flowChartDecision':
      return _poly([ui.Offset(r.center.dx, r.top), ui.Offset(r.right, r.center.dy), ui.Offset(r.center.dx, r.bottom), ui.Offset(r.left, r.center.dy)]);
    case 'parallelogram':
      final o = r.width * (adj ?? 0.25).clamp(0, 0.9);
      return _poly([ui.Offset(r.left + o, r.top), r.topRight, ui.Offset(r.right - o, r.bottom), r.bottomLeft]);
    case 'trapezoid':
      final o = math.min(r.width, r.height) * (adj ?? 0.25).clamp(0, 0.5);
      return _poly([ui.Offset(r.left + o, r.top), ui.Offset(r.right - o, r.top), r.bottomRight, r.bottomLeft]);
    case 'hexagon':
      final o = r.width * 0.25;
      return _poly([
        ui.Offset(r.left + o, r.top),
        ui.Offset(r.right - o, r.top),
        ui.Offset(r.right, r.center.dy),
        ui.Offset(r.right - o, r.bottom),
        ui.Offset(r.left + o, r.bottom),
        ui.Offset(r.left, r.center.dy),
      ]);
    case 'octagon':
      final o = math.min(r.width, r.height) * 0.29;
      return _poly([
        ui.Offset(r.left + o, r.top),
        ui.Offset(r.right - o, r.top),
        ui.Offset(r.right, r.top + o),
        ui.Offset(r.right, r.bottom - o),
        ui.Offset(r.right - o, r.bottom),
        ui.Offset(r.left + o, r.bottom),
        ui.Offset(r.left, r.bottom - o),
        ui.Offset(r.left, r.top + o),
      ]);
    case 'rightArrow' || 'leftArrow':
      final head = math.min(r.width * 0.5, r.height * 0.5), body = r.height * 0.5, t = r.center.dy - body / 2, b = r.center.dy + body / 2;
      final pts = [
        ui.Offset(r.left, t),
        ui.Offset(r.right - head, t),
        ui.Offset(r.right - head, r.top),
        ui.Offset(r.right, r.center.dy),
        ui.Offset(r.right - head, r.bottom),
        ui.Offset(r.right - head, b),
        ui.Offset(r.left, b),
      ];
      return _poly(s.geometry == 'leftArrow' ? [for (final o in pts) ui.Offset(r.left + r.right - o.dx, o.dy)] : pts);
    case 'upArrow' || 'downArrow':
      final head = math.min(r.height * 0.5, r.width * 0.5), body = r.width * 0.5, l = r.center.dx - body / 2, rr = r.center.dx + body / 2;
      final pts = [
        ui.Offset(l, r.bottom),
        ui.Offset(l, r.top + head),
        ui.Offset(r.left, r.top + head),
        ui.Offset(r.center.dx, r.top),
        ui.Offset(r.right, r.top + head),
        ui.Offset(rr, r.top + head),
        ui.Offset(rr, r.bottom),
      ];
      return _poly(s.geometry == 'downArrow' ? [for (final o in pts) ui.Offset(o.dx, r.top + r.bottom - o.dy)] : pts);
    case 'chevron' || 'homePlate':
      final o = math.min(r.width, r.height) * 0.4;
      return s.geometry == 'chevron'
          ? _poly([
              r.topLeft,
              ui.Offset(r.right - o, r.top),
              ui.Offset(r.right, r.center.dy),
              ui.Offset(r.right - o, r.bottom),
              r.bottomLeft,
              ui.Offset(r.left + o, r.center.dy),
            ])
          : _poly([r.topLeft, ui.Offset(r.right - o, r.top), ui.Offset(r.right, r.center.dy), ui.Offset(r.right - o, r.bottom), r.bottomLeft]);
    case 'star5':
      final pts = <ui.Offset>[];
      for (var i = 0; i < 10; i++) {
        final a = -math.pi / 2 + i * math.pi / 5;
        final k = i.isEven ? 1.0 : 0.382;
        pts.add(ui.Offset(r.center.dx + math.cos(a) * r.width / 2 * k, r.center.dy + math.sin(a) * r.height / 2 * k));
      }
      return _poly(pts);
    case 'plus' || 'mathPlus':
      final t = math.min(r.width, r.height) * 0.33;
      final cx = r.center.dx, cy = r.center.dy;
      return _poly([
        ui.Offset(cx - t / 2, r.top),
        ui.Offset(cx + t / 2, r.top),
        ui.Offset(cx + t / 2, cy - t / 2),
        ui.Offset(r.right, cy - t / 2),
        ui.Offset(r.right, cy + t / 2),
        ui.Offset(cx + t / 2, cy + t / 2),
        ui.Offset(cx + t / 2, r.bottom),
        ui.Offset(cx - t / 2, r.bottom),
        ui.Offset(cx - t / 2, cy + t / 2),
        ui.Offset(r.left, cy + t / 2),
        ui.Offset(r.left, cy - t / 2),
        ui.Offset(cx - t / 2, cy - t / 2),
      ]);
    default:
      return ui.Path()..addRect(r);
  }
}

ui.Path _poly(List<ui.Offset> pts) {
  final p = ui.Path()..addPolygon(pts, true);
  return p;
}

void _paintLine(ui.Canvas canvas, ShapeView s, ui.Rect r) {
  final l = s.line ?? const LineView(widthPt: 1, color: 0xFF000000);
  final paint = _linePaint(l);
  final path = ui.Path();
  if (s.geometry.startsWith('bentConnector')) {
    path
      ..moveTo(r.left, r.top)
      ..lineTo(r.center.dx, r.top)
      ..lineTo(r.center.dx, r.bottom)
      ..lineTo(r.right, r.bottom);
  } else {
    path
      ..moveTo(r.left, r.top)
      ..lineTo(r.right, r.bottom);
  }
  if (l.dash != null && l.dash != 'solid') {
    canvas.drawPath(_dashed(path, l.dash == 'sysDot' || l.dash == 'dot' ? [l.widthPt, l.widthPt * 2] : [l.widthPt * 4, l.widthPt * 2.5]), paint);
  } else {
    canvas.drawPath(path, paint);
  }
  void head(ui.Offset tip, ui.Offset from) {
    final a = math.atan2(tip.dy - from.dy, tip.dx - from.dx);
    final len = math.max(l.widthPt * 4, 6.0);
    final p1 = tip - ui.Offset(math.cos(a - 0.45), math.sin(a - 0.45)) * len;
    final p2 = tip - ui.Offset(math.cos(a + 0.45), math.sin(a + 0.45)) * len;
    canvas.drawPath(_poly([tip, p1, p2]), ui.Paint()..color = ui.Color(l.color));
  }

  final last = s.geometry.startsWith('bentConnector') ? ui.Offset(r.center.dx, r.bottom) : r.topLeft;
  if (l.tailArrow) head(r.bottomRight, last);
  if (l.headArrow) head(r.topLeft, s.geometry.startsWith('bentConnector') ? ui.Offset(r.center.dx, r.top) : r.bottomRight);
}

ui.Path _dashed(ui.Path source, List<double> pattern) {
  final out = ui.Path();
  for (final m in source.computeMetrics()) {
    var d = 0.0;
    var i = 0;
    var draw = true;
    while (d < m.length) {
      final len = pattern[i % pattern.length];
      if (draw) out.addPath(m.extractPath(d, math.min(d + len, m.length)), ui.Offset.zero);
      d += len;
      i++;
      draw = !draw;
    }
  }
  return out;
}

void _paintPicture(ui.Canvas canvas, ShapeView s, ui.Rect rect, Map<String, ui.Image> images) {
  final img = s.media == null ? null : images[s.media];
  if (img == null) {
    _paintPlaceholderBox(canvas, rect, 'Picture');
    return;
  }
  canvas.save();
  if (s.frame.flipH || s.frame.flipV) canvas.scale(s.frame.flipH ? -1 : 1, s.frame.flipV ? -1 : 1);
  final clip = _geometryPath(s, rect);
  if (s.geometry != 'rect') canvas.clipPath(clip);
  final c = s.crop ?? const [0.0, 0.0, 0.0, 0.0];
  final iw = img.width.toDouble(), ih = img.height.toDouble();
  final src = ui.Rect.fromLTRB(iw * c[0], ih * c[1], iw * (1 - c[2]), ih * (1 - c[3]));
  canvas.drawImageRect(img, src, rect, ui.Paint()..filterQuality = ui.FilterQuality.medium);
  canvas.restore();
  final line = s.line;
  if (line != null) canvas.drawPath(clip, _linePaint(line));
}

void _paintPlaceholderBox(ui.Canvas canvas, ui.Rect rect, String label) {
  canvas.drawRect(rect, ui.Paint()..color = const ui.Color(0xFFEEF1F6));
  canvas.drawRect(
    rect,
    ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const ui.Color(0xFFB8C0CC),
  );
  if (label.isEmpty) return;
  final tp = TextPainter(
    text: TextSpan(
      text: label,
      style: const TextStyle(fontSize: 14, color: ui.Color(0xFF64748B)),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 2,
  )..layout(maxWidth: math.max(10, rect.width - 8));
  tp.paint(canvas, ui.Offset(rect.center.dx - tp.width / 2, rect.center.dy - tp.height / 2));
  tp.dispose();
}

TextAlign _align(String a) => switch (a) {
  'ctr' => TextAlign.center,
  'r' => TextAlign.right,
  'just' => TextAlign.justify,
  _ => TextAlign.left,
};

TextPainter _paragraphPainter(ParaView p, double maxWidth, {bool wrap = true}) {
  final spans = <TextSpan>[];
  for (final r in p.runs) {
    spans.add(
      TextSpan(
        text: r.text,
        style: TextStyle(
          fontSize: r.sizePt,
          color: ui.Color(r.color),
          fontWeight: r.bold ? FontWeight.w700 : FontWeight.w400,
          fontStyle: r.italic ? FontStyle.italic : FontStyle.normal,
          decoration: TextDecoration.combine([if (r.underline) TextDecoration.underline, if (r.strike) TextDecoration.lineThrough]),
          fontFamily: r.font,
          height: p.lineSpacing == 1.0 ? null : p.lineSpacing * 1.2,
        ),
      ),
    );
  }
  if (spans.isEmpty || p.text.isEmpty) {
    spans
      ..clear()
      ..add(
        TextSpan(
          text: ' ',
          style: TextStyle(fontSize: p.endSizePt),
        ),
      );
  }
  final tp = TextPainter(
    text: TextSpan(children: spans),
    textDirection: TextDirection.ltr,
    textAlign: _align(p.align),
  );
  tp.layout(minWidth: wrap ? maxWidth : 0, maxWidth: wrap ? maxWidth : 100000);
  return tp;
}

void _paintText(ui.Canvas canvas, List<ParaView> paras, TextBox box, ui.Rect rect) {
  final left = rect.left + box.left / _pt, right = rect.right - box.right / _pt;
  final innerW = math.max(1.0, right - left);
  final painters = <TextPainter>[];
  final marLs = <double>[];
  var total = 0.0;
  for (final p in paras) {
    final marL = p.bullet != null || p.marL > 0 ? p.marL / _pt : 0.0;
    final tp = _paragraphPainter(p, math.max(1.0, innerW - marL), wrap: box.wrap);
    painters.add(tp);
    marLs.add(marL);
    total += p.spaceBefore + tp.height + p.spaceAfter;
  }
  final innerTop = rect.top + box.top / _pt, innerH = rect.height - (box.top + box.bottom) / _pt;
  var y = switch (box.anchor) {
    'ctr' => innerTop + (innerH - total) / 2,
    'b' => innerTop + innerH - total,
    _ => innerTop,
  };
  for (var i = 0; i < paras.length; i++) {
    final p = paras[i], tp = painters[i];
    y += p.spaceBefore;
    var dx = left + marLs[i];
    if (!box.wrap) {
      dx = switch (p.align) {
        'ctr' => rect.center.dx - tp.width / 2,
        'r' => right - tp.width,
        _ => left,
      };
    }
    if (p.bullet != null && p.text.isNotEmpty) {
      final first = p.runs.firstWhere((r) => r.text.isNotEmpty, orElse: () => p.runs.first);
      final bp = TextPainter(
        text: TextSpan(
          text: p.bullet,
          style: TextStyle(fontSize: first.sizePt, color: ui.Color(first.color)),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final bx = left + (marLs[i] + p.indent / _pt).clamp(0, double.infinity);
      bp.paint(canvas, ui.Offset(bx, y));
      bp.dispose();
    }
    tp.paint(canvas, ui.Offset(dx, y));
    y += tp.height + p.spaceAfter;
    tp.dispose();
  }
}

void _paintTable(ui.Canvas canvas, TableData t, ui.Rect rect) {
  if (t.colWidths.isEmpty || t.rows.isEmpty) return;
  final totalW = t.colWidths.fold<double>(0, (a, b) => a + b);
  final totalH = t.rowHeights.fold<double>(0, (a, b) => a + b);
  final sx = totalW == 0 ? 1.0 : rect.width / (totalW / _pt), sy = totalH == 0 ? 1.0 : rect.height / (totalH / _pt);
  final xs = <double>[rect.left];
  for (final w in t.colWidths) {
    xs.add(xs.last + w / _pt * sx);
  }
  final ys = <double>[rect.top];
  for (final h in t.rowHeights) {
    ys.add(ys.last + h / _pt * sy);
  }
  final border = ui.Paint()
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = 0.75
    ..color = const ui.Color(0xFFFFFFFF);
  for (var r = 0; r < t.rows.length && r < ys.length - 1; r++) {
    for (var c = 0; c < t.rows[r].length && c < xs.length - 1; c++) {
      final cell = t.rows[r][c];
      if (cell.merged) continue;
      final endC = math.min(c + cell.gridSpan, xs.length - 1), endR = math.min(r + cell.rowSpan, ys.length - 1);
      final cr = ui.Rect.fromLTRB(xs[c], ys[r], xs[endC], ys[endR]);
      if (cell.fill != null) canvas.drawRect(cr, ui.Paint()..color = ui.Color(cell.fill!));
      canvas.drawRect(cr, border);
      if (cell.paragraphs.isNotEmpty) {
        _paintText(canvas, cell.paragraphs, TextBox(anchor: cell.anchor == 'ctr' ? 'ctr' : 't'), cr);
      }
    }
  }
}

/// Draws [view] into a picture [pixelWidth] pixels wide and returns it as PNG or raw bytes.
Future<ui.Image> renderSlideImage(SlideView view, Map<String, ui.Image> images, double widthEmu, double heightEmu, int pixelWidth) async {
  final wPt = widthEmu / _pt, hPt = heightEmu / _pt;
  final scale = pixelWidth / wPt;
  final pixelHeight = math.max(1, (hPt * scale).round());
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder, ui.Rect.fromLTWH(0, 0, pixelWidth.toDouble(), pixelHeight.toDouble()));
  canvas.scale(scale);
  canvas.clipRect(ui.Rect.fromLTWH(0, 0, wPt, hPt));
  paintSlide(canvas, view, images, wPt, hPt);
  final picture = recorder.endRecording();
  final image = await picture.toImage(pixelWidth, pixelHeight);
  picture.dispose();
  return image;
}

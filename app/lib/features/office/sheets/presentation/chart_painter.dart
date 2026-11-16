import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/chart.dart';

/// Draws a chart of the sheet the way a spreadsheet program would: axes and gridlines, bars, lines, areas or the slices of a pie, a title and a legend.
class ChartPainter extends CustomPainter {
  ChartPainter(this.chart, this.data);

  final SheetChart chart;
  final ChartData data;

  static Color color(int i) => Color(chartPalette[i % chartPalette.length]);

  TextPainter _text(String s, {double size = 11, Color col = const Color(0xFF444444), FontWeight weight = FontWeight.w400, double maxWidth = double.infinity}) {
    return TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(fontSize: size, color: col, fontWeight: weight),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    var top = 8.0, bottom = size.height - 8;
    if (chart.title.isNotEmpty) {
      final t = _text(chart.title, size: 14, weight: FontWeight.w600, maxWidth: size.width - 16, col: const Color(0xFF222222));
      t.paint(canvas, Offset((size.width - t.width) / 2, top));
      top += t.height + 8;
    }
    final showLegend = data.series.length > 1 || chart.kind.isPie;
    if (showLegend) bottom -= _legend(canvas, size, bottom);
    final area = Rect.fromLTRB(8, top, size.width - 8, bottom);
    if (area.width < 40 || area.height < 40 || !data.hasData) {
      final t = _text(data.hasData ? '' : 'No numbers to show', col: const Color(0xFF888888));
      t.paint(canvas, area.center - Offset(t.width / 2, t.height / 2));
      return;
    }
    if (chart.kind.isPie) {
      _pie(canvas, area);
    } else if (chart.kind == ChartKind.scatter) {
      _scatter(canvas, area);
    } else {
      _axes(canvas, area);
    }
  }

  /// Draws the legend along the bottom and returns the height it took.
  double _legend(Canvas canvas, Size size, double bottom) {
    final names = chart.kind.isPie ? data.categories : [for (final s in data.series) s.name];
    final items = [for (var i = 0; i < names.length && i < 12; i++) (names[i], i)];
    var x = 12.0, y = bottom - 14;
    var rows = 1;
    final painters = [for (final it in items) (_text(it.$1, size: 10.5, maxWidth: size.width / 2), it.$2)];
    var widths = 0.0;
    for (final p in painters) {
      widths += p.$1.width + 22;
    }
    final single = widths <= size.width - 16;
    var startX = single ? (size.width - widths) / 2 : 12.0;
    x = startX;
    for (final p in painters) {
      final w = p.$1.width + 22;
      if (x + w > size.width - 8 && x > startX) {
        x = 12;
        y -= 16;
        rows++;
      }
      canvas.drawRect(Rect.fromLTWH(x, y + 2, 9, 9), Paint()..color = chart.kind.isPie ? _pointColor(0, p.$2) : _seriesColor(p.$2));
      p.$1.paint(canvas, Offset(x + 14, y));
      x += w;
    }
    return rows * 16.0 + 6;
  }

  void _pie(Canvas canvas, Rect area) {
    final values = data.series.first.values;
    final total = values.fold<double>(0, (m, v) => m + (v != null && v > 0 ? v : 0));
    if (total <= 0) return;
    final d = math.min(area.width, area.height) - 8;
    final rect = Rect.fromCenter(center: area.center, width: d, height: d);
    final labels = chart.labelsOf(0);
    final ring = chart.kind == ChartKind.doughnut;
    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (v == null || v <= 0) continue;
      final sweep = v / total * 2 * math.pi;
      canvas.drawArc(rect, start, sweep, true, Paint()..color = _pointColor(0, i));
      canvas.drawArc(
        rect,
        start,
        sweep,
        true,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      if (labels != LabelKind.none && sweep > 0.18) {
        final mid = start + sweep / 2;
        final text = labels == LabelKind.value ? _num(v) : '${(v / total * 100).round()}%';
        _label(canvas, rect.center + Offset(math.cos(mid), math.sin(mid)) * (d * (ring ? 0.375 : 0.32)), text, col: Colors.white);
      }
      start += sweep;
    }
    // A doughnut is a pie with its middle taken out.
    if (ring) canvas.drawCircle(rect.center, d * 0.25, Paint()..color = Colors.white);
  }

  /// Round numbers for the value axis: from [lo] to [hi], about five steps.
  static ({double min, double max, double step}) niceScale(double lo, double hi) {
    if (hi == lo) {
      hi = lo + 1;
    }
    final raw = (hi - lo) / 5;
    final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    final f = raw / mag;
    final step = (f <= 1 ? 1 : f <= 2 ? 2 : f <= 5 ? 5 : 10) * mag;
    return (min: (lo / step).floor() * step, max: (hi / step).ceil() * step, step: step);
  }

  static String _num(double v) {
    if (v == v.roundToDouble() && v.abs() < 1e12) return v.toInt().toString();
    return v.abs() >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }

  Color _seriesColor(int i) => Color(i < chart.series.length && chart.series[i].color != null ? chart.series[i].color! : chartPalette[i % chartPalette.length]);

  /// The colour of point [i] of series [s]: its own, or the series colour (the next colour of the set for each slice of a pie).
  Color _pointColor(int s, int i) {
    final own = s < chart.series.length ? chart.series[s].pointColor(i) : null;
    if (own != null) return Color(own);
    return chart.kind.isPie ? color(i) : _seriesColor(s);
  }

  /// Writes [text] centred on [at].
  void _label(Canvas canvas, Offset at, String text, {Color col = const Color(0xFF333333)}) {
    final t = _text(text, size: 10, col: col, weight: FontWeight.w600);
    t.paint(canvas, at - Offset(t.width / 2, t.height / 2));
  }

  /// The equation and R squared of the trend lines that ask for them, in the corner of the plot.
  void _equations(Canvas canvas, Rect plot, List<({String text, Color color})> lines) {
    var y = plot.top + 3;
    for (final l in lines) {
      final t = _text(l.text, size: 10.5, col: l.color, weight: FontWeight.w600);
      final box = Rect.fromLTWH(plot.right - t.width - 10, y - 1, t.width + 8, t.height + 2);
      canvas.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(3)), Paint()..color = Colors.white.withValues(alpha: 0.85));
      t.paint(canvas, Offset(box.left + 4, y));
      y += t.height + 4;
    }
  }

  /// What a trend line says about itself, for the series that show it.
  String? _trendText(int s, List<double> xs, List<double?> ys) {
    if (s >= chart.series.length) return null;
    final c = chart.series[s];
    if (c.trend == TrendKind.none || (!c.showEquation && !c.showR2)) return null;
    final sum = trendSummary(c.trend, xs, ys);
    if (sum == null) return null;
    return [if (c.showEquation) sum.equation, if (c.showR2) 'R² = ${sum.r2.toStringAsFixed(3)}'].join('   ');
  }

  /// Draws [path] as a dashed line.
  void _dashed(Canvas canvas, Path path, Paint paint) {
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + 6, m.length)), paint);
        d += 10;
      }
    }
  }

  void _axes(Canvas canvas, Rect area) {
    final horizontal = chart.kind == ChartKind.bar;
    final n = data.points;
    final count = data.series.length;
    bool second(int i) => !horizontal && chart.secondaryOf(i);
    bool isBar(int i) => chart.kindOf(i) == ChartKind.column || chart.kindOf(i) == ChartKind.bar;
    final stackable = chart.stacked && (chart.kind == ChartKind.column || chart.kind == ChartKind.bar || chart.kind == ChartKind.area);
    bool stackedSeries(int i) => stackable && !second(i) && (isBar(i) || chart.kindOf(i) == ChartKind.area);
    final percent = stackable && chart.percent;

    var series = data.series;
    if (percent) {
      // Every piled point is shown as its share of the total of the piled values.
      final totals = [
        for (var i = 0; i < n; i++)
          [for (var j = 0; j < count; j++) if (stackedSeries(j)) j].fold<double>(0, (m, j) => m + (i < data.series[j].values.length ? (data.series[j].values[i] ?? 0).abs() : 0)),
      ];
      series = [
        for (var j = 0; j < count; j++)
          stackedSeries(j)
              ? (name: data.series[j].name, values: <double?>[for (var i = 0; i < data.series[j].values.length; i++) data.series[j].values[i] == null || totals[i] == 0 ? null : data.series[j].values[i]! / totals[i] * 100])
              : data.series[j],
      ];
    }
    String fmt(double v) => percent ? '${_num(v)}%' : _num(v);
    final hasSecond = !horizontal && [for (var i = 0; i < count; i++) i].any(second);

    ({double min, double max, double step}) scaleOf(bool sec) {
      var lo = 0.0, hi = 0.0;
      final mine = [for (var i = 0; i < count; i++) if (second(i) == sec) i];
      final piled = [for (final i in mine) if (stackedSeries(i)) i];
      for (var p = 0; p < n; p++) {
        var pos = 0.0, neg = 0.0;
        for (final i in piled) {
          final v = p < series[i].values.length ? series[i].values[p] ?? 0 : 0;
          if (v >= 0) {
            pos += v;
          } else {
            neg += v;
          }
        }
        hi = math.max(hi, pos);
        lo = math.min(lo, neg);
      }
      for (final i in mine) {
        if (stackedSeries(i)) continue;
        for (final v in series[i].values) {
          if (v == null) continue;
          hi = math.max(hi, v);
          lo = math.min(lo, v);
        }
      }
      if (mine.isNotEmpty && mine.every((i) => chart.kindOf(i) == ChartKind.line)) {
        // Lines do not have to start at zero when all the numbers are far from it.
        var mn = double.infinity, mx = -double.infinity;
        for (final i in mine) {
          for (final v in series[i].values) {
            if (v == null) continue;
            mn = math.min(mn, v);
            mx = math.max(mx, v);
          }
        }
        if (mn.isFinite && mn > 0 && (mx - mn) < mx * 0.5) lo = mn - (mx - mn) * 0.2;
      }
      return niceScale(lo, hi);
    }

    final scale1 = scaleOf(false);
    final scale2 = hasSecond ? scaleOf(true) : scale1;

    const labelSize = 10.5;
    List<double> labelsOf(({double min, double max, double step}) s) => [for (var v = s.min; v <= s.max + s.step / 2; v += s.step) v];
    var axisW = 0.0, axis2W = 0.0;
    for (final v in labelsOf(scale1)) {
      axisW = math.max(axisW, _text(fmt(v), size: labelSize).width);
    }
    if (hasSecond) {
      for (final v in labelsOf(scale2)) {
        axis2W = math.max(axis2W, _text(_num(v), size: labelSize).width);
      }
    }
    const catLabelH = 16.0;
    // Room for the value labels on the side (or the bottom for sideways bars) and the point labels on the other.
    final plot = horizontal
        ? Rect.fromLTRB(area.left + 4 + math.min(80, _maxCatWidth(labelSize)) + 6, area.top + 4, area.right - 12, area.bottom - catLabelH - 2)
        : Rect.fromLTRB(area.left + axisW + 10, area.top + 6, area.right - 10 - (hasSecond ? axis2W + 6 : 0), area.bottom - catLabelH - 2);
    if (plot.width < 20 || plot.height < 20) return;

    final grid = Paint()
      ..color = const Color(0xFFD9D9D9)
      ..strokeWidth = 1;
    double vToPos(bool sec, double v) {
      final s = sec ? scale2 : scale1;
      final t = (v - s.min) / (s.max - s.min);
      return horizontal ? plot.left + t * plot.width : plot.bottom - t * plot.height;
    }

    for (final v in labelsOf(scale1)) {
      final p = vToPos(false, v);
      final t = _text(fmt(v), size: labelSize);
      if (horizontal) {
        canvas.drawLine(Offset(p, plot.top), Offset(p, plot.bottom), grid);
        t.paint(canvas, Offset(p - t.width / 2, plot.bottom + 2));
      } else {
        canvas.drawLine(Offset(plot.left, p), Offset(plot.right, p), grid);
        t.paint(canvas, Offset(plot.left - t.width - 4, p - t.height / 2));
      }
    }
    if (hasSecond) {
      for (final v in labelsOf(scale2)) {
        final t = _text(_num(v), size: labelSize, col: const Color(0xFF777777));
        t.paint(canvas, Offset(plot.right + 4, vToPos(true, v) - t.height / 2));
      }
    }

    final slot = (horizontal ? plot.height : plot.width) / math.max(1, n);
    final start = horizontal ? plot.top : plot.left;
    double along(int i) => start + slot * (i + 0.5);
    final zero = vToPos(false, 0);

    // Point labels, skipping some when they would touch.
    final every = math.max(1, ((horizontal ? 18 : 48) / slot).ceil());
    for (var i = 0; i < n; i += every) {
      final label = i < data.categories.length ? data.categories[i] : '${i + 1}';
      final t = _text(label, size: labelSize, maxWidth: horizontal ? 80 : math.max(20, slot * every - 2));
      if (horizontal) {
        t.paint(canvas, Offset(plot.left - t.width - 4, along(i) - t.height / 2));
      } else {
        t.paint(canvas, Offset(along(i) - t.width / 2, plot.bottom + 3));
      }
    }

    final axisPaint = Paint()
      ..color = const Color(0xFF888888)
      ..strokeWidth = 1;
    horizontal ? canvas.drawLine(Offset(zero, plot.top), Offset(zero, plot.bottom), axisPaint) : canvas.drawLine(Offset(plot.left, zero), Offset(plot.right, zero), axisPaint);

    final equations = <({String text, Color color})>[];
    for (final sec in [false, true]) {
      if (sec && !hasSecond) continue;
      final mine = [for (var i = 0; i < count; i++) if (second(i) == sec) i];

      // Areas first, then bars, then lines, as spreadsheet programs layer them.
      final areaBase = List<double>.filled(n, 0);
      for (final s in mine.where((i) => chart.kindOf(i) == ChartKind.area)) {
        final top = <Offset>[], bot = <Offset>[];
        for (var i = 0; i < n; i++) {
          final v = (i < series[s].values.length ? series[s].values[i] : null) ?? 0;
          final from = stackedSeries(s) ? areaBase[i] : 0.0;
          final to = from + v;
          if (stackedSeries(s)) areaBase[i] = to;
          top.add(Offset(along(i), vToPos(sec, to)));
          bot.add(Offset(along(i), vToPos(sec, from)));
        }
        if (top.isEmpty) continue;
        final path = Path()..moveTo(top.first.dx, top.first.dy);
        for (final o in top.skip(1)) {
          path.lineTo(o.dx, o.dy);
        }
        for (final o in bot.reversed) {
          path.lineTo(o.dx, o.dy);
        }
        path.close();
        canvas.drawPath(path, Paint()..color = _seriesColor(s).withValues(alpha: stackedSeries(s) ? 0.95 : 0.6));
        if (chart.labelsOf(s) != LabelKind.none) {
          for (var i = 0; i < top.length; i++) {
            final v = i < series[s].values.length ? series[s].values[i] : null;
            if (v != null) _label(canvas, top[i] - const Offset(0, 9), fmt(v));
          }
        }
      }

      final bars = mine.where(isBar).toList();
      if (bars.isNotEmpty) {
        final piled = bars.any(stackedSeries);
        final barSpace = slot * 0.72;
        final barW = barSpace / (piled ? 1 : bars.length);
        for (var i = 0; i < n; i++) {
          var posBase = 0.0, negBase = 0.0;
          for (var k = 0; k < bars.length; k++) {
            final s = bars[k];
            final v = i < series[s].values.length ? series[s].values[i] : null;
            if (v == null) continue;
            double from, to;
            if (piled) {
              from = v >= 0 ? posBase : negBase;
              to = from + v;
              if (v >= 0) {
                posBase = to;
              } else {
                negBase = to;
              }
            } else {
              from = 0;
              to = v;
            }
            final a = vToPos(sec, from), b = vToPos(sec, to);
            final offset = piled ? -barSpace / 2 : -barSpace / 2 + barW * k;
            final rect = horizontal
                ? Rect.fromLTRB(math.min(a, b), along(i) + offset, math.max(a, b), along(i) + offset + barW)
                : Rect.fromLTRB(along(i) + offset, math.min(a, b), along(i) + offset + barW, math.max(a, b));
            canvas.drawRect(rect, Paint()..color = _pointColor(s, i));
            if (chart.labelsOf(s) != LabelKind.none && (horizontal || barW >= 9)) {
              final text = fmt(v);
              final at = piled
                  ? rect.center
                  : horizontal
                  ? Offset(v >= 0 ? rect.right + 4 + text.length * 3 : rect.left - 4 - text.length * 3, rect.center.dy)
                  : Offset(rect.center.dx, v >= 0 ? rect.top - 7 : rect.bottom + 7);
              _label(canvas, at, text, col: piled ? Colors.white : const Color(0xFF333333));
            }
          }
        }
      }

      for (final s in mine.where((i) => chart.kindOf(i) == ChartKind.line)) {
        final path = Path();
        var started = false;
        final dots = <Offset>[];
        final dotValues = <double>[];
        for (var i = 0; i < n; i++) {
          final v = i < series[s].values.length ? series[s].values[i] : null;
          if (v == null) {
            started = false;
            continue;
          }
          final o = Offset(along(i), vToPos(sec, v));
          dots.add(o);
          dotValues.add(v);
          if (started) {
            path.lineTo(o.dx, o.dy);
          } else {
            path.moveTo(o.dx, o.dy);
            started = true;
          }
        }
        canvas.drawPath(
          path,
          Paint()
            ..color = _seriesColor(s)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2
            ..strokeJoin = StrokeJoin.round,
        );
        for (var k = 0; k < dots.length; k++) {
          canvas.drawCircle(dots[k], 3, Paint()..color = _seriesColor(s));
          if (chart.labelsOf(s) != LabelKind.none) _label(canvas, dots[k] - const Offset(0, 11), fmt(dotValues[k]));
        }
      }

      // Trend lines over everything of this scale.
      for (final s in mine) {
        final said = _trendText(s, [for (var i = 0; i < n; i++) i + 1.0], series[s].values);
        if (said != null && !stackedSeries(s)) equations.add((text: said, color: _seriesColor(s)));
        final trend = s < chart.series.length ? chart.series[s].trend : TrendKind.none;
        if (trend == TrendKind.none || stackedSeries(s)) continue;
        final pts = trendPoints(trend, [for (var i = 0; i < n; i++) i + 1.0], series[s].values);
        if (pts.length < 2) continue;
        final path = Path();
        for (var k = 0; k < pts.length; k++) {
          final along1 = start + slot * (pts[k].x - 0.5);
          final across = vToPos(sec, pts[k].y);
          final o = horizontal ? Offset(across, along1) : Offset(along1, across);
          k == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
        }
        _dashed(
          canvas,
          path,
          Paint()
            ..color = _seriesColor(s).withValues(alpha: 0.9)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8,
        );
      }
    }
    _equations(canvas, plot, equations);
  }

  /// Dots at (x, y) with numbers along both edges.
  void _scatter(Canvas canvas, Rect area) {
    final xs = data.xs ?? [for (var i = 0; i < data.points; i++) i + 1.0];
    var xlo = double.infinity, xhi = -double.infinity, ylo = 0.0, yhi = 0.0;
    for (final x in xs) {
      xlo = math.min(xlo, x);
      xhi = math.max(xhi, x);
    }
    var yMin = double.infinity;
    for (final s in data.series) {
      for (final v in s.values) {
        if (v == null) continue;
        yhi = math.max(yhi, v);
        ylo = math.min(ylo, v);
        yMin = math.min(yMin, v);
      }
    }
    if (!xlo.isFinite) return;
    final xs2 = niceScale(math.min(xlo, 0) == xlo || xlo > 0 && xlo < (xhi - xlo) ? math.min(0, xlo) : xlo, xhi);
    final ys2 = niceScale(ylo, yhi);
    const labelSize = 10.5;
    var axisW = 0.0;
    for (var v = ys2.min; v <= ys2.max + ys2.step / 2; v += ys2.step) {
      axisW = math.max(axisW, _text(_num(v), size: labelSize).width);
    }
    final plot = Rect.fromLTRB(area.left + axisW + 10, area.top + 6, area.right - 14, area.bottom - 18);
    if (plot.width < 20 || plot.height < 20) return;
    final grid = Paint()
      ..color = const Color(0xFFD9D9D9)
      ..strokeWidth = 1;
    double px(double x) => plot.left + (x - xs2.min) / (xs2.max - xs2.min) * plot.width;
    double py(double y) => plot.bottom - (y - ys2.min) / (ys2.max - ys2.min) * plot.height;
    for (var v = ys2.min; v <= ys2.max + ys2.step / 2; v += ys2.step) {
      canvas.drawLine(Offset(plot.left, py(v)), Offset(plot.right, py(v)), grid);
      final t = _text(_num(v), size: labelSize);
      t.paint(canvas, Offset(plot.left - t.width - 4, py(v) - t.height / 2));
    }
    for (var v = xs2.min; v <= xs2.max + xs2.step / 2; v += xs2.step) {
      canvas.drawLine(Offset(px(v), plot.top), Offset(px(v), plot.bottom), grid);
      final t = _text(_num(v), size: labelSize);
      t.paint(canvas, Offset(px(v) - t.width / 2, plot.bottom + 2));
    }
    final equations = <({String text, Color color})>[];
    for (var s = 0; s < data.series.length; s++) {
      final values = data.series[s].values;
      final trend = s < chart.series.length ? chart.series[s].trend : TrendKind.none;
      final pts = trendPoints(trend, xs, values);
      final said = _trendText(s, xs, values);
      if (said != null) equations.add((text: said, color: _seriesColor(s)));
      if (pts.length >= 2) {
        final path = Path()..moveTo(px(pts.first.x), py(pts.first.y));
        for (final q in pts.skip(1)) {
          path.lineTo(px(q.x), py(q.y));
        }
        _dashed(
          canvas,
          path,
          Paint()
            ..color = _seriesColor(s).withValues(alpha: 0.9)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8,
        );
      }
      for (var i = 0; i < values.length && i < xs.length; i++) {
        final v = values[i];
        if (v == null) continue;
        canvas.drawCircle(Offset(px(xs[i]), py(v)), 4, Paint()..color = _seriesColor(s));
        if (chart.labelsOf(s) != LabelKind.none) _label(canvas, Offset(px(xs[i]), py(v) - 11), _num(v));
      }
    }
    _equations(canvas, plot, equations);
  }

  double _maxCatWidth(double size) {
    var m = 0.0;
    for (final c in data.categories.take(30)) {
      m = math.max(m, _text(c, size: size).width);
    }
    return m;
  }

  @override
  bool shouldRepaint(ChartPainter old) => true;
}

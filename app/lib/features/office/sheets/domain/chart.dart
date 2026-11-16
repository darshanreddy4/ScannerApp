import 'dart:collection';
import 'dart:math' as math;

import 'sheet_edit.dart';
import 'sheet_model.dart';

/// The kinds of chart the app can make and show.
enum ChartKind { column, bar, line, area, pie, scatter, doughnut }

extension ChartKindShape on ChartKind {
  /// Slices of a whole: a pie or a doughnut.
  bool get isPie => this == ChartKind.pie || this == ChartKind.doughnut;
}

/// What is written next to each point of a series.
enum LabelKind { none, value, percent }

/// Cells a chart reads, with the sheet they are on.
class ChartRef {
  const ChartRef(this.sheet, this.range);

  final String sheet;
  final MergeRange range;

  ChartRef withRange(MergeRange r) => ChartRef(sheet, r);
  ChartRef onSheet(String name) => ChartRef(name, range);

  int get count => (range.lastRow - range.firstRow + 1) * (range.lastCol - range.firstCol + 1);

  /// As written in a file: 'Sheet 1'!$B$2:$B$6
  String get formula {
    final q = "'${sheet.replaceAll("'", "''")}'";
    String a(int r, int c) => '\$${CellRef.columnName(c)}\$${r + 1}';
    return range.isSingle ? '$q!${a(range.firstRow, range.firstCol)}' : '$q!${a(range.firstRow, range.firstCol)}:${a(range.lastRow, range.lastCol)}';
  }

  /// Reads Sheet1!$A$1:$A$5 or 'My sheet'!A1; null for anything else (several areas, names, other files).
  static ChartRef? parse(String text) {
    var t = text.trim();
    if (t.startsWith('(') && t.endsWith(')')) t = t.substring(1, t.length - 1);
    String sheet;
    String rest;
    if (t.startsWith("'")) {
      // A quoted name ends at the first quote that is not doubled.
      var i = 1;
      while (i < t.length) {
        if (t[i] == "'") {
          if (i + 1 < t.length && t[i + 1] == "'") {
            i += 2;
            continue;
          }
          break;
        }
        i++;
      }
      if (i + 1 >= t.length || t[i + 1] != '!') return null;
      sheet = t.substring(1, i).replaceAll("''", "'");
      rest = t.substring(i + 2);
    } else {
      final bang = t.indexOf('!');
      if (bang <= 0) return null;
      sheet = t.substring(0, bang);
      rest = t.substring(bang + 1);
    }
    final range = CellRef.parseRange(rest.replaceAll(r'$', ''));
    if (range == null || sheet.isEmpty) return null;
    return ChartRef(sheet, range);
  }

  @override
  bool operator ==(Object other) => other is ChartRef && other.sheet == sheet && other.range == range;

  @override
  int get hashCode => Object.hash(sheet, range);
}

/// A line drawn through the numbers of a series to show where they are heading.
enum TrendKind { none, linear, exponential, polynomial, movingAverage }

/// One set of values drawn as bars, a line, an area or the slices of a pie.
class ChartSeries {
  const ChartSeries({
    this.name,
    this.nameRef,
    required this.values,
    this.color,
    this.kind,
    this.secondary = false,
    this.trend = TrendKind.none,
    this.showEquation = false,
    this.showR2 = false,
    this.labels,
    this.pointColors = const [],
  });

  /// A name typed in, used when [nameRef] is null.
  final String? name;

  /// The cell that holds the name.
  final ChartRef? nameRef;
  final ChartRef values;

  /// The colour of this series as ARGB, or null for the next colour of the standard set.
  final int? color;

  /// How this series is drawn when it differs from the chart's kind (columns, a line or an area in one chart), or null.
  final ChartKind? kind;

  /// Measured on a second scale at the right edge instead of the first.
  final bool secondary;
  final TrendKind trend;

  /// Write the equation and the R squared of the trend line on the chart.
  final bool showEquation;
  final bool showR2;

  /// What is written by each point, or null for the usual (percentages on a pie, nothing otherwise).
  final LabelKind? labels;

  /// Colours of single points (slices of a pie, bars), by position; null for a point that keeps the series colour.
  final List<int?> pointColors;

  int? pointColor(int i) => i >= 0 && i < pointColors.length ? pointColors[i] : null;

  /// The same series with point [i] in [color], or back to the usual colour when [color] is null.
  ChartSeries withPointColor(int i, int? color) {
    final list = List<int?>.of(pointColors);
    while (list.length <= i) {
      list.add(null);
    }
    list[i] = color;
    while (list.isNotEmpty && list.last == null) {
      list.removeLast();
    }
    return copyWith(pointColors: list);
  }

  ChartSeries withValues(ChartRef v) => copyWith(values: v);
  ChartSeries withNameRef(ChartRef? r) => copyWith(nameRef: r);

  /// A copy with other settings; [nameRef], [color], [kind] and [labels] can be set back to null by passing null.
  ChartSeries copyWith({
    Object? nameRef = _same,
    ChartRef? values,
    Object? color = _same,
    Object? kind = _same,
    bool? secondary,
    TrendKind? trend,
    bool? showEquation,
    bool? showR2,
    Object? labels = _same,
    List<int?>? pointColors,
  }) => ChartSeries(
    name: name,
    nameRef: identical(nameRef, _same) ? this.nameRef : nameRef as ChartRef?,
    values: values ?? this.values,
    color: identical(color, _same) ? this.color : color as int?,
    kind: identical(kind, _same) ? this.kind : kind as ChartKind?,
    secondary: secondary ?? this.secondary,
    trend: trend ?? this.trend,
    showEquation: showEquation ?? this.showEquation,
    showR2: showR2 ?? this.showR2,
    labels: identical(labels, _same) ? this.labels : labels as LabelKind?,
    pointColors: pointColors ?? this.pointColors,
  );

  /// Whether [o] looks the same when drawn.
  bool sameLook(ChartSeries o) =>
      o.color == color &&
      o.kind == kind &&
      o.secondary == secondary &&
      o.trend == trend &&
      o.showEquation == showEquation &&
      o.showR2 == showR2 &&
      o.labels == labels &&
      o.pointColors.length == pointColors.length &&
      [for (var i = 0; i < pointColors.length; i++) pointColors[i] == o.pointColors[i]].every((b) => b);

  static const _same = Object();
}

/// Kinds a single series can be drawn as when a chart mixes them (all share one row of point labels).
const mixableKinds = [ChartKind.column, ChartKind.line, ChartKind.area];

/// A chart on a sheet: what it shows, where it sits and, for charts that came from a file, which part of the file it is.
class SheetChart {
  SheetChart({
    required this.kind,
    this.title = '',
    this.stacked = false,
    this.percent = false,
    this.categories,
    required this.series,
    required this.col,
    required this.row,
    this.cols = 8,
    this.rows = 15,
    this.partPath,
    this.relId,
    this.fromFile = false,
    this.editable = true,
    this.unsupportedKind,
    this.dirty = true,
  });

  ChartKind kind;
  String title;

  /// Bars or areas piled on each other.
  bool stacked;

  /// Piled bars or areas shown as shares of 100%.
  bool percent;

  /// The cells that name the points (the labels under the bars), or null to number them.
  ChartRef? categories;
  List<ChartSeries> series;

  /// Top left cell (zero-based) and the size in cells.
  int col;
  int row;
  int cols;
  int rows;

  /// Where the chart is in the file, once it is there.
  String? partPath;
  String? relId;

  /// The chart was in the file when it was opened, so changing it resets its colours and styling.
  bool fromFile;

  /// False for kinds the app cannot draw or change (scatter, combined charts and so on); they are kept as they are.
  bool editable;
  String? unsupportedKind;

  /// Made or changed in the app, so its part has to be written.
  bool dirty;

  /// Moved or resized in the app, so its place in the file's drawing has to be written again.
  bool moved = false;

  /// How series [i] is drawn: its own kind in a mixed chart, otherwise the chart's.
  ChartKind kindOf(int i) {
    final own = i < series.length ? series[i].kind : null;
    return own != null && mixable && mixableKinds.contains(own) ? own : kind;
  }

  /// Whether series of this chart can be drawn as different kinds or on a second scale.
  bool get mixable => kind == ChartKind.column || kind == ChartKind.line || kind == ChartKind.area;

  /// What is written by the points of series [i]: its own choice, or percentages on a pie and nothing otherwise.
  LabelKind labelsOf(int i) => (i < series.length ? series[i].labels : null) ?? (kind.isPie ? LabelKind.percent : LabelKind.none);

  bool secondaryOf(int i) => mixable && i < series.length && series[i].secondary;

  /// True when the series are not all drawn the same way, or some use the second scale.
  bool get isCombined => mixable && [for (var i = 0; i < series.length; i++) i].any((i) => kindOf(i) != kind || secondaryOf(i));

  /// A name to show in lists.
  String get label => title.isNotEmpty ? title : (editable ? 'Chart' : 'Chart (${unsupportedKind ?? 'other'})');

  SheetChart copy() => SheetChart(
    kind: kind,
    title: title,
    stacked: stacked,
    percent: percent,
    categories: categories,
    series: List.of(series),
    col: col,
    row: row,
    cols: cols,
    rows: rows,
    partPath: partPath,
    relId: relId,
    fromFile: fromFile,
    editable: editable,
    unsupportedKind: unsupportedKind,
    dirty: dirty,
  )..moved = moved;

  /// A copy that is not tied to any part of the file, for a copied sheet.
  SheetChart asNew() => copy()
    ..partPath = null
    ..relId = null
    ..fromFile = false
    ..dirty = true;

  /// The chart with every reference moved by [map]; this same chart when nothing moved, and null when no series is left.
  SheetChart? remapped(ChartRef? Function(ChartRef) map) {
    var changed = false;
    ChartRef? mapped(ChartRef? r) {
      if (r == null) return null;
      final n = map(r);
      if (n != r) changed = true;
      return n;
    }

    final cat = mapped(categories);
    final out = <ChartSeries>[];
    for (final s in series) {
      final v = mapped(s.values);
      if (v == null) continue;
      out.add(s.copyWith(nameRef: mapped(s.nameRef), values: v));
    }
    if (out.isEmpty) return null;
    if (!changed) return this;
    return copy()
      ..categories = cat
      ..series = out
      ..dirty = true;
  }
}

/// What a chart shows right now, worked out from the cells.
class ChartData {
  const ChartData({required this.categories, required this.series, this.xs});
  final List<String> categories;

  /// For a scatter chart, the number of each point along the bottom; null for other charts.
  final List<double>? xs;
  final List<({String name, List<double?> values})> series;

  int get points => series.fold(0, (m, s) => s.values.length > m ? s.values.length : m);
  bool get hasData => series.any((s) => s.values.any((v) => v != null));
}

const _maxPoints = 1000;

/// The values and labels a chart draws, read from the workbook's cells.
ChartData resolveChart(Workbook wb, SheetChart chart) {
  Iterable<SheetCell?> cellsOf(ChartRef ref) sync* {
    final sheet = wb.sheetNamed(ref.sheet);
    final r = ref.range;
    for (var row = r.firstRow; row <= r.lastRow; row++) {
      for (var col = r.firstCol; col <= r.lastCol; col++) {
        yield sheet?.cells[CellRef.key(row, col)];
      }
    }
  }

  double? number(SheetCell? c) {
    final v = c?.value;
    if (v is NumberValue) return v.number;
    if (v is TextValue) return double.tryParse(v.text.trim().replaceAll(',', ''));
    return null;
  }

  String text(SheetCell? c) => displayText(c, wb.styles.at, date1904: wb.date1904);

  final series = <({String name, List<double?> values})>[];
  var n = 0;
  for (final s in chart.series) {
    n++;
    final values = cellsOf(s.values).take(_maxPoints).map(number).toList();
    var name = s.name ?? '';
    final nameRef = s.nameRef;
    if (nameRef != null) name = text(cellsOf(nameRef).firstOrNull);
    series.add((name: name.isEmpty ? 'Series $n' : name, values: values));
  }
  final points = series.fold(0, (m, s) => s.values.length > m ? s.values.length : m);
  final cat = chart.categories;
  final labels = cat == null ? <String>[] : cellsOf(cat).take(_maxPoints).map(text).toList();
  while (labels.length < points) {
    labels.add('${labels.length + 1}');
  }
  List<double>? xs;
  if (chart.kind == ChartKind.scatter) {
    final given = cat == null ? <double?>[] : cellsOf(cat).take(_maxPoints).map(number).toList();
    xs = [for (var i = 0; i < points; i++) i < given.length && given[i] != null ? given[i]! : i + 1.0];
  }
  return ChartData(categories: labels.take(points).toList(), series: series, xs: xs);
}

/// Why a chart could not be made from some cells.
class ChartSelectionException implements Exception {
  const ChartSelectionException(this.message);
  final String message;
}

/// The block of filled cells around ([row], [col]), as a spreadsheet program picks it for a chart.
MergeRange? currentRegion(Sheet sheet, int row, int col) {
  bool filled(int r, int c) {
    final v = sheet.cells[CellRef.key(r, c)]?.value;
    return v != null && v is! EmptyValue;
  }
  if (!filled(row, col)) return null;
  final seen = <int>{CellRef.key(row, col)};
  final queue = Queue<(int, int)>()..add((row, col));
  var r0 = row, r1 = row, c0 = col, c1 = col;
  while (queue.isNotEmpty && seen.length < 20000) {
    final (r, c) = queue.removeFirst();
    for (var dr = -1; dr <= 1; dr++) {
      for (var dc = -1; dc <= 1; dc++) {
        final nr = r + dr, nc = c + dc;
        if (nr < 0 || nc < 0 || nr > sheet.lastRow || nc > sheet.lastCol) continue;
        final k = CellRef.key(nr, nc);
        if (seen.contains(k) || !filled(nr, nc)) continue;
        seen.add(k);
        queue.add((nr, nc));
        if (nr < r0) r0 = nr;
        if (nr > r1) r1 = nr;
        if (nc < c0) c0 = nc;
        if (nc > c1) c1 = nc;
      }
    }
  }
  return MergeRange(r0, c0, r1, c1);
}

/// A chart of the cells in [selection]: a top row of words names the series, a first column of words names the points, and each
/// other column of numbers is a series. A single cell stands for the block of cells around it.
SheetChart chartFromSelection(Sheet sheet, MergeRange selection, ChartKind kind, {String title = ''}) {
  var area = selection;
  if (selection.isSingle) {
    area = currentRegion(sheet, selection.firstRow, selection.firstCol) ?? selection;
  }
  bool isNumber(int r, int c) {
    final v = sheet.cells[CellRef.key(r, c)]?.value;
    return v is NumberValue;
  }

  bool isText(int r, int c) {
    final v = sheet.cells[CellRef.key(r, c)]?.value;
    return v is TextValue && v.text.trim().isNotEmpty;
  }

  bool isEmpty(int r, int c) => sheet.cells[CellRef.key(r, c)]?.value is EmptyValue || sheet.cells[CellRef.key(r, c)] == null;

  final rows = area.lastRow - area.firstRow + 1, cols = area.lastCol - area.firstCol + 1;
  if (rows * cols > 20000) throw const ChartSelectionException('Select fewer cells for a chart.');

  // A top row without numbers, above a row with some, holds the names of the series.
  var header = false;
  if (rows >= 2) {
    var topHasNumber = false, belowHasNumber = false;
    for (var c = area.firstCol; c <= area.lastCol; c++) {
      if (isNumber(area.firstRow, c)) topHasNumber = true;
      if (isNumber(area.firstRow + 1, c)) belowHasNumber = true;
    }
    header = !topHasNumber && belowHasNumber;
  }
  final bodyTop = area.firstRow + (header ? 1 : 0);

  // A first column with any words, or an empty corner above numbers, names the points.
  var hasCategories = false;
  if (cols >= 2) {
    var anyText = false;
    for (var r = bodyTop; r <= area.lastRow; r++) {
      if (isText(r, area.firstCol)) anyText = true;
    }
    // A scatter chart always takes its first column as the numbers along the bottom.
    hasCategories = kind == ChartKind.scatter || anyText || (header && isEmpty(area.firstRow, area.firstCol));
  }
  final firstSeriesCol = area.firstCol + (hasCategories ? 1 : 0);

  final series = <ChartSeries>[];
  for (var c = firstSeriesCol; c <= area.lastCol; c++) {
    var numbers = 0;
    for (var r = bodyTop; r <= area.lastRow; r++) {
      if (isNumber(r, c)) numbers++;
    }
    if (numbers == 0) continue;
    series.add(
      ChartSeries(
        nameRef: header && isText(area.firstRow, c) ? ChartRef(sheet.name, MergeRange(area.firstRow, c, area.firstRow, c)) : null,
        name: header && isText(area.firstRow, c) ? null : 'Series ${series.length + 1}',
        values: ChartRef(sheet.name, MergeRange(bodyTop, c, area.lastRow, c)),
      ),
    );
  }
  if (series.isEmpty) throw const ChartSelectionException('Select cells that hold numbers to make a chart.');
  final shown = kind.isPie ? series.take(1).toList() : series;

  return SheetChart(
    kind: kind,
    title: title,
    categories: hasCategories ? ChartRef(sheet.name, MergeRange(bodyTop, area.firstCol, area.lastRow, area.firstCol)) : null,
    series: shown,
    col: area.lastCol + 2,
    row: area.firstRow,
  );
}

/// The colours of series and slices, in the order spreadsheet programs use them.
const chartPalette = <int>[0xFF4472C4, 0xFFED7D31, 0xFFA5A5A5, 0xFFFFC000, 0xFF5B9BD5, 0xFF70AD47, 0xFF264478, 0xFF9E480E, 0xFF636363, 0xFF997300];


/// Points of the trend line of a series, as (x, y) with x counted from 1 for charts that number their points.
/// [ys] holds a null for a point with no number. A trend needs at least two numbers; otherwise the list is empty.
List<({double x, double y})> trendPoints(TrendKind kind, List<double> xs, List<double?> ys) {
  final px = <double>[], py = <double>[];
  for (var i = 0; i < xs.length && i < ys.length; i++) {
    final y = ys[i];
    if (y != null) {
      px.add(xs[i]);
      py.add(y);
    }
  }
  if (px.length < 2 || kind == TrendKind.none) return const [];
  final lo = px.reduce(math.min), hi = px.reduce(math.max);
  if (hi == lo && kind != TrendKind.movingAverage) return const [];
  List<({double x, double y})> sample(double Function(double) f, int count) => [
    for (var i = 0; i < count; i++) (x: lo + (hi - lo) * i / (count - 1), y: f(lo + (hi - lo) * i / (count - 1))),
  ];

  switch (kind) {
    case TrendKind.none:
      return const [];
    case TrendKind.linear:
      final (a, b) = _fit(px, py);
      return sample((x) => a + b * x, 2);
    case TrendKind.exponential:
      // y = c * e^(b x), fitted on the logarithms of the numbers that are above zero.
      final lx = <double>[], ly = <double>[];
      for (var i = 0; i < px.length; i++) {
        if (py[i] > 0) {
          lx.add(px[i]);
          ly.add(math.log(py[i]));
        }
      }
      if (lx.length < 2 || lx.reduce(math.min) == lx.reduce(math.max)) return const [];
      final (a, b) = _fit(lx, ly);
      return sample((x) => math.exp(a + b * x), 30);
    case TrendKind.polynomial:
      if (px.length < 3) {
        final (a, b) = _fit(px, py);
        return sample((x) => a + b * x, 2);
      }
      final c = _fitQuadratic(px, py);
      if (c == null) return const [];
      return sample((x) => c[0] + c[1] * x + c[2] * x * x, 40);
    case TrendKind.movingAverage:
      const period = 3;
      if (px.length < period) return const [];
      return [
        for (var i = period - 1; i < px.length; i++) (x: px[i], y: py.sublist(i - period + 1, i + 1).reduce((m, v) => m + v) / period),
      ];
  }
}

/// Least squares line: (intercept, slope).
(double, double) _fit(List<double> x, List<double> y) {
  final n = x.length;
  final mx = x.reduce((a, b) => a + b) / n, my = y.reduce((a, b) => a + b) / n;
  var sxx = 0.0, sxy = 0.0;
  for (var i = 0; i < n; i++) {
    sxx += (x[i] - mx) * (x[i] - mx);
    sxy += (x[i] - mx) * (y[i] - my);
  }
  final slope = sxx == 0 ? 0.0 : sxy / sxx;
  return (my - slope * mx, slope);
}

/// Least squares parabola [c0, c1, c2] for y = c0 + c1 x + c2 x^2, or null when the numbers do not fix one.
List<double>? _fitQuadratic(List<double> x, List<double> y) {
  // Work around the middle of the x values so the sums stay well behaved.
  final m = x.reduce((a, b) => a + b) / x.length;
  final t = [for (final v in x) v - m];
  double sum(double Function(double) f) => t.fold<double>(0, (a, v) => a + f(v));
  final s0 = t.length.toDouble(), s1 = sum((v) => v), s2 = sum((v) => v * v), s3 = sum((v) => v * v * v), s4 = sum((v) => v * v * v * v);
  var r0 = 0.0, r1 = 0.0, r2 = 0.0;
  for (var i = 0; i < t.length; i++) {
    r0 += y[i];
    r1 += y[i] * t[i];
    r2 += y[i] * t[i] * t[i];
  }
  final a = [
    [s0, s1, s2, r0],
    [s1, s2, s3, r1],
    [s2, s3, s4, r2],
  ];
  for (var c = 0; c < 3; c++) {
    var pivot = c;
    for (var r = c + 1; r < 3; r++) {
      if (a[r][c].abs() > a[pivot][c].abs()) pivot = r;
    }
    if (a[pivot][c].abs() < 1e-12) return null;
    final tmp = a[c];
    a[c] = a[pivot];
    a[pivot] = tmp;
    for (var r = 0; r < 3; r++) {
      if (r == c) continue;
      final f = a[r][c] / a[c][c];
      for (var k = c; k < 4; k++) {
        a[r][k] -= f * a[c][k];
      }
    }
  }
  final q0 = a[0][3] / a[0][0], q1 = a[1][3] / a[1][1], q2 = a[2][3] / a[2][2];
  // Back from t = x - m to x.
  return [q0 - q1 * m + q2 * m * m, q1 - 2 * q2 * m, q2];
}


String _sig(double v) {
  if (v == 0) return '0';
  if (v.abs() >= 1e5 || v.abs() < 1e-3) return v.toStringAsExponential(2);
  final t = v.toStringAsPrecision(4);
  return t.contains('.') ? t.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '') : t;
}

String _term(double v, String x, {bool first = false}) {
  final sign = v < 0 ? '-' : (first ? '' : '+');
  return first ? '$sign${_sig(v.abs())}$x' : ' $sign ${_sig(v.abs())}$x';
}

/// The equation and the R squared of a trend line, as spreadsheet programs write them, or null when the trend has none (a moving average,
/// or too few numbers). R squared is how much of the ups and downs of the numbers the line explains, from 0 to 1.
({String equation, double r2})? trendSummary(TrendKind kind, List<double> xs, List<double?> ys) {
  final px = <double>[], py = <double>[];
  for (var i = 0; i < xs.length && i < ys.length; i++) {
    final y = ys[i];
    if (y != null) {
      px.add(xs[i]);
      py.add(y);
    }
  }
  if (px.length < 2 || kind == TrendKind.none || kind == TrendKind.movingAverage) return null;
  if (px.reduce(math.min) == px.reduce(math.max)) return null;

  double r2(List<double> actual, List<double> fitted) {
    final mean = actual.reduce((a, b) => a + b) / actual.length;
    var tot = 0.0, res = 0.0;
    for (var i = 0; i < actual.length; i++) {
      tot += (actual[i] - mean) * (actual[i] - mean);
      res += (actual[i] - fitted[i]) * (actual[i] - fitted[i]);
    }
    return tot == 0 ? 1.0 : (1 - res / tot).clamp(0.0, 1.0);
  }

  switch (kind) {
    case TrendKind.linear:
      final (a, b) = _fit(px, py);
      return (equation: 'y = ${_term(b, 'x', first: true)}${_term(a, '')}', r2: r2(py, [for (final x in px) a + b * x]));
    case TrendKind.exponential:
      final lx = <double>[], ly = <double>[];
      for (var i = 0; i < px.length; i++) {
        if (py[i] > 0) {
          lx.add(px[i]);
          ly.add(math.log(py[i]));
        }
      }
      if (lx.length < 2 || lx.reduce(math.min) == lx.reduce(math.max)) return null;
      final (a, b) = _fit(lx, ly);
      return (equation: 'y = ${_sig(math.exp(a))}e^${_sig(b)}x', r2: r2(ly, [for (final x in lx) a + b * x]));
    case TrendKind.polynomial:
      if (px.length < 3) return trendSummary(TrendKind.linear, xs, ys);
      final c = _fitQuadratic(px, py);
      if (c == null) return null;
      return (
        equation: 'y = ${_term(c[2], 'x²', first: true)}${_term(c[1], 'x')}${_term(c[0], '')}',
        r2: r2(py, [for (final x in px) c[0] + c[1] * x + c[2] * x * x]),
      );
    case TrendKind.none || TrendKind.movingAverage:
      return null;
  }
}

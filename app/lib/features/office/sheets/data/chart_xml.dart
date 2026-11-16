import 'dart:convert';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../domain/chart.dart';
import 'xlsx_reader.dart' show resolveTarget;

const _chartNs = 'http://schemas.openxmlformats.org/drawingml/2006/chart';
const _drawNs = 'http://schemas.openxmlformats.org/drawingml/2006/main';
const _relNs = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _xdrNs = 'http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing';

/// Content type of a chart part and of a drawing part.
const chartContentType = 'application/vnd.openxmlformats-officedocument.drawingml.chart+xml';
const drawingContentType = 'application/vnd.openxmlformats-officedocument.drawing+xml';
const chartRelType = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart';
const drawingRelType = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing';

Iterable<XmlElement> _kids(XmlElement? e, String name) => e == null ? const [] : e.childElements.where((c) => c.name.local == name);
XmlElement? _kid(XmlElement? e, String name) => _kids(e, name).firstOrNull;
XmlElement? _path(XmlElement? e, List<String> names) {
  var cur = e;
  for (final n in names) {
    cur = _kid(cur, n);
    if (cur == null) return null;
  }
  return cur;
}

String? _attr(XmlElement? e, String local) => e?.attributes.where((a) => a.name.local == local).map((a) => a.value).firstOrNull;

/// The path of the relationships file that belongs to [part].
String relsPathOf(String part) {
  final slash = part.lastIndexOf('/');
  return '${part.substring(0, slash + 1)}_rels/${part.substring(slash + 1)}.rels';
}

/// Reads the charts that sit on a sheet: the drawing its XML points to, and the chart parts that drawing points to.
List<SheetChart> readSheetCharts(Archive archive, String sheetPath, XmlElement sheetRoot) {
  final out = <SheetChart>[];
  try {
    final drawingRid = _attr(_kid(sheetRoot, 'drawing'), 'id');
    if (drawingRid == null) return out;
    final sheetRels = _readRels(archive, sheetPath);
    final drawingPath = sheetRels[drawingRid]?.target;
    if (drawingPath == null) return out;
    final drawingFile = archive.findFile(drawingPath);
    if (drawingFile == null) return out;
    final drawing = XmlDocument.parse(utf8.decode(drawingFile.readBytes()!, allowMalformed: true));
    final drawingRels = _readRels(archive, drawingPath);
    for (final anchor in drawing.rootElement.childElements) {
      final chartEl = anchor.descendants.whereType<XmlElement>().where((e) => e.name.local == 'chart' && _attr(e, 'id') != null).firstOrNull;
      if (chartEl == null) continue;
      final rid = _attr(chartEl, 'id')!;
      final rel = drawingRels[rid];
      if (rel == null) continue;
      final file = archive.findFile(rel.target);
      if (file == null) continue;
      final from = _kid(anchor, 'from'), to = _kid(anchor, 'to');
      int num(XmlElement? e, String n, int d) => int.tryParse(_kid(e, n)?.innerText ?? '') ?? d;
      final col = num(from, 'col', 0), row = num(from, 'row', 0);
      final cols = to == null ? 8 : (num(to, 'col', col + 8) - col).clamp(1, 60);
      final rows = to == null ? 15 : (num(to, 'row', row + 15) - row).clamp(1, 200);
      SheetChart chart;
      try {
        final doc = XmlDocument.parse(utf8.decode(file.readBytes()!, allowMalformed: true));
        chart = _readChart(doc.rootElement) ?? _unsupported('chart');
      } catch (_) {
        chart = _unsupported('chart');
      }
      chart
        ..col = col
        ..row = row
        ..cols = cols
        ..rows = rows
        ..partPath = rel.target
        ..relId = rid
        ..fromFile = true
        ..dirty = false;
      out.add(chart);
    }
  } catch (_) {
    // A drawing that cannot be read is left as it is in the file.
  }
  return out;
}

SheetChart _unsupported(String kind) => SheetChart(kind: ChartKind.column, series: const [], col: 0, row: 0, editable: false, unsupportedKind: kind);

Map<String, ({String id, String target, String type})> _readRels(Archive archive, String part) {
  final out = <String, ({String id, String target, String type})>{};
  final f = archive.findFile(relsPathOf(part));
  if (f == null) return out;
  final doc = XmlDocument.parse(utf8.decode(f.readBytes()!, allowMalformed: true));
  for (final r in doc.rootElement.childElements) {
    final id = r.getAttribute('Id'), target = r.getAttribute('Target');
    if (id == null || target == null) continue;
    if (r.getAttribute('TargetMode') == 'External') continue;
    out[id] = (id: id, target: resolveTarget(part, target), type: r.getAttribute('Type') ?? '');
  }
  return out;
}

const _supported = {'barChart', 'lineChart', 'areaChart', 'pieChart', 'doughnutChart', 'scatterChart', 'bar3DChart', 'line3DChart', 'area3DChart', 'pie3DChart'};

Set<String> _axisIds(XmlElement e) => {for (final a in _kids(e, 'axId')) a.getAttribute('val') ?? ''};

int? _serColor(XmlElement ser, ChartKind kind) {
  final hex = switch (kind) {
    ChartKind.line => _path(ser, ['spPr', 'ln', 'solidFill', 'srgbClr'])?.getAttribute('val'),
    ChartKind.scatter => _path(ser, ['marker', 'spPr', 'solidFill', 'srgbClr'])?.getAttribute('val'),
    _ => _path(ser, ['spPr', 'solidFill', 'srgbClr'])?.getAttribute('val'),
  };
  final v = hex == null ? null : int.tryParse(hex, radix: 16);
  return v == null ? null : 0xFF000000 | v;
}

bool _flag(XmlElement? e, String name) => _kid(e, name)?.getAttribute('val') == '1';

/// What the series writes by its points, or null when that is the usual for the kind.
LabelKind? _labelsOf(XmlElement ser, ChartKind kind) {
  final d = _kid(ser, 'dLbls');
  final got = d == null || _flag(d, 'delete')
      ? LabelKind.none
      : _flag(d, 'showVal')
      ? LabelKind.value
      : _flag(d, 'showPercent')
      ? LabelKind.percent
      : LabelKind.none;
  return got == (kind.isPie ? LabelKind.percent : LabelKind.none) ? null : got;
}

/// Colours given to single points of a series.
List<int?> _pointColors(XmlElement ser) {
  final out = <int?>[];
  for (final d in _kids(ser, 'dPt')) {
    final i = int.tryParse(_kid(d, 'idx')?.getAttribute('val') ?? '');
    final hex = _path(d, ['spPr', 'solidFill', 'srgbClr'])?.getAttribute('val');
    final v = hex == null ? null : int.tryParse(hex, radix: 16);
    if (i == null || v == null || i < 0 || i > 2000) continue;
    while (out.length <= i) {
      out.add(null);
    }
    out[i] = 0xFF000000 | v;
  }
  return out;
}

TrendKind _trendOf(XmlElement ser) => switch (_path(ser, ['trendline', 'trendlineType'])?.getAttribute('val')) {
  'linear' => TrendKind.linear,
  'exp' => TrendKind.exponential,
  'poly' => TrendKind.polynomial,
  'movingAvg' => TrendKind.movingAverage,
  _ => TrendKind.none,
};

ChartKind _kindOfElement(XmlElement e) => switch (e.name.local.replaceAll('3D', '')) {
  'barChart' => _kid(e, 'barDir')?.getAttribute('val') == 'bar' ? ChartKind.bar : ChartKind.column,
  'lineChart' => ChartKind.line,
  'areaChart' => ChartKind.area,
  'scatterChart' => ChartKind.scatter,
  'doughnutChart' => ChartKind.doughnut,
  _ => ChartKind.pie,
};

SheetChart? _readChart(XmlElement space) {
  final chart = _kid(space, 'chart');
  final plot = _kid(chart, 'plotArea');
  if (plot == null) return null;
  final types = [
    for (final e in plot.childElements)
      if (e.name.local.endsWith('Chart')) e,
  ];
  final names = types.map((e) => e.name.local.replaceAll('Chart', '')).join(' + ');
  if (types.isEmpty) return _unsupported('chart');
  // Bars (upright), lines and areas may be mixed in one chart; everything else is one kind per chart.
  const mixed = {'barChart', 'lineChart', 'areaChart'};
  final combined = types.length > 1;
  if (combined) {
    final ok = types.every((e) => mixed.contains(e.name.local) && _kindOfElement(e) != ChartKind.bar);
    if (!ok) return _unsupported(names);
  } else if (!_supported.contains(types.single.name.local)) {
    return _unsupported(names);
  }
  final t = combined ? types.firstWhere((e) => e.name.local == 'barChart', orElse: () => types.first) : types.single;
  final kind = _kindOfElement(t);
  final grouping = _kid(t, 'grouping')?.getAttribute('val') ?? 'standard';
  final percent = grouping == 'percentStacked';
  final stacked = grouping == 'stacked' || percent;
  final primaryAxes = _axisIds(t);

  final found = <({int order, ChartSeries series})>[];
  ChartRef? categories;
  for (final e in types) {
    final ek = _kindOfElement(e);
    final secondary = combined && !_axisIds(e).containsAll(primaryAxes);
    for (final ser in _kids(e, 'ser')) {
      final values = ChartRef.parse(_path(ser, [ek == ChartKind.scatter ? 'yVal' : 'val', 'numRef', 'f'])?.innerText ?? '');
      if (values == null) return _unsupported('chart with typed-in values');
      final nameRef = ChartRef.parse(_path(ser, ['tx', 'strRef', 'f'])?.innerText ?? '');
      final literal = _path(ser, ['tx', 'v'])?.innerText;
      found.add((
        order: int.tryParse(_kid(ser, 'order')?.getAttribute('val') ?? '') ?? found.length,
        series: ChartSeries(
          name: nameRef == null ? literal : null,
          nameRef: nameRef,
          values: values,
          color: _serColor(ser, ek),
          kind: combined && ek != kind ? ek : null,
          secondary: secondary,
          trend: ek.isPie ? TrendKind.none : _trendOf(ser),
          showEquation: _flag(_kid(ser, 'trendline'), 'dispEq'),
          showR2: _flag(_kid(ser, 'trendline'), 'dispRSqr'),
          labels: _labelsOf(ser, ek),
          pointColors: _pointColors(ser),
        ),
      ));
      categories ??= ek == ChartKind.scatter
          ? ChartRef.parse(_path(ser, ['xVal', 'numRef', 'f'])?.innerText ?? _path(ser, ['xVal', 'strRef', 'f'])?.innerText ?? '')
          : ChartRef.parse(_path(ser, ['cat', 'strRef', 'f'])?.innerText ?? _path(ser, ['cat', 'numRef', 'f'])?.innerText ?? '');
    }
  }
  if (found.isEmpty) return _unsupported('chart without data');
  found.sort((a, b) => a.order.compareTo(b.order));
  final series = [for (final f in found) f.series];

  final titleEl = _kid(chart, 'title');
  final title = titleEl == null ? '' : titleEl.descendants.whereType<XmlElement>().where((e) => e.name.local == 't').map((e) => e.innerText).join();
  if (kind.isPie) {
    // Only the first series of a pie is shown.
    return SheetChart(kind: kind, title: title, categories: categories, series: [series.first], col: 0, row: 0);
  }
  return SheetChart(kind: kind, title: title, stacked: stacked, percent: percent, categories: categories, series: series, col: 0, row: 0);
}

// ---------------------------------------------------------------------- writing

String _esc(String s) => const HtmlEscape(HtmlEscapeMode.element).convert(s);

String _hex(int argb) => (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

String _numText(double v) => v == v.roundToDouble() && v.abs() < 1e15 ? v.toInt().toString() : v.toString();

String _strCache(List<String> items) =>
    '<c:strCache><c:ptCount val="${items.length}"/>${[for (var i = 0; i < items.length; i++) '<c:pt idx="$i"><c:v>${_esc(items[i])}</c:v></c:pt>'].join()}</c:strCache>';

String _numCache(List<double?> items) =>
    '<c:numCache><c:formatCode>General</c:formatCode><c:ptCount val="${items.length}"/>${[for (var i = 0; i < items.length; i++) if (items[i] != null) '<c:pt idx="$i"><c:v>${_numText(items[i]!)}</c:v></c:pt>'].join()}</c:numCache>';

String _fill(int argb) => '<c:spPr><a:solidFill><a:srgbClr val="${_hex(argb)}"/></a:solidFill></c:spPr>';

String _trendXml(TrendKind t, int color, {bool equation = false, bool rSquared = false}) {
  if (t == TrendKind.none) return '';
  final type = switch (t) {
    TrendKind.linear => '<c:trendlineType val="linear"/>',
    TrendKind.exponential => '<c:trendlineType val="exp"/>',
    TrendKind.polynomial => '<c:trendlineType val="poly"/><c:order val="2"/>',
    TrendKind.movingAverage => '<c:trendlineType val="movingAvg"/><c:period val="3"/>',
    TrendKind.none => '',
  };
  return '<c:trendline><c:spPr><a:ln w="19050" cap="rnd"><a:solidFill><a:srgbClr val="${_hex(color)}"/></a:solidFill><a:prstDash val="sysDot"/></a:ln></c:spPr>$type<c:dispRSqr val="${rSquared ? 1 : 0}"/><c:dispEq val="${equation ? 1 : 0}"/></c:trendline>';
}

String _seriesXml(SheetChart chart, ChartData data, int i) {
  final s = chart.series[i];
  final d = data.series[i];
  final kind = chart.kindOf(i);
  final color = s.color ?? chartPalette[i % chartPalette.length];
  final b = StringBuffer('<c:ser><c:idx val="$i"/><c:order val="$i"/>');
  if (s.nameRef != null) {
    b.write('<c:tx><c:strRef><c:f>${_esc(s.nameRef!.formula)}</c:f>${_strCache([d.name])}</c:strRef></c:tx>');
  } else {
    b.write('<c:tx><c:v>${_esc(d.name)}</c:v></c:tx>');
  }
  switch (kind) {
    case ChartKind.line:
      b.write('<c:spPr><a:ln w="28575" cap="rnd"><a:solidFill><a:srgbClr val="${_hex(color)}"/></a:solidFill><a:round/></a:ln></c:spPr>');
      b.write('<c:marker><c:symbol val="circle"/><c:size val="5"/>${_fill(color)}</c:marker>');
    case ChartKind.pie || ChartKind.doughnut:
      for (var p = 0; p < d.values.length; p++) {
        b.write('<c:dPt><c:idx val="$p"/><c:bubble3D val="0"/>${_fill(s.pointColor(p) ?? chartPalette[p % chartPalette.length])}</c:dPt>');
      }
    case ChartKind.column || ChartKind.bar:
      b.write('${_fill(color)}<c:invertIfNegative val="0"/>');
      for (var p = 0; p < s.pointColors.length; p++) {
        final c = s.pointColor(p);
        if (c != null) b.write('<c:dPt><c:idx val="$p"/><c:invertIfNegative val="0"/><c:bubble3D val="0"/>${_fill(c)}</c:dPt>');
      }
    case ChartKind.area:
      b.write(_fill(color));
    case ChartKind.scatter:
      b.write('<c:spPr><a:ln w="19050"><a:noFill/></a:ln></c:spPr><c:marker><c:symbol val="circle"/><c:size val="7"/>${_fill(color)}</c:marker>');
  }
  final labels = chart.labelsOf(i);
  if (labels != LabelKind.none || kind.isPie) {
    b.write(
      '<c:dLbls><c:showLegendKey val="0"/><c:showVal val="${labels == LabelKind.value ? 1 : 0}"/><c:showCatName val="0"/><c:showSerName val="0"/>'
      '<c:showPercent val="${labels == LabelKind.percent ? 1 : 0}"/><c:showBubbleSize val="0"/>${kind.isPie ? '<c:showLeaderLines val="1"/>' : ''}</c:dLbls>',
    );
  }
  if (!kind.isPie) b.write(_trendXml(s.trend, color, equation: s.showEquation, rSquared: s.showR2));
  if (kind == ChartKind.scatter) {
    final x = chart.categories;
    final xs = data.xs ?? [for (var p = 0; p < d.values.length; p++) p + 1.0];
    if (x != null) b.write('<c:xVal><c:numRef><c:f>${_esc(x.formula)}</c:f>${_numCache(xs)}</c:numRef></c:xVal>');
    b.write('<c:yVal><c:numRef><c:f>${_esc(s.values.formula)}</c:f>${_numCache(d.values)}</c:numRef></c:yVal><c:smooth val="0"/></c:ser>');
    return b.toString();
  }
  final cat = chart.categories;
  if (cat != null) b.write('<c:cat><c:strRef><c:f>${_esc(cat.formula)}</c:f>${_strCache(data.categories)}</c:strRef></c:cat>');
  b.write('<c:val><c:numRef><c:f>${_esc(s.values.formula)}</c:f>${_numCache(d.values)}</c:numRef></c:val>');
  if (kind == ChartKind.line) b.write('<c:smooth val="0"/>');
  b.write('</c:ser>');
  return b.toString();
}

const _gridXml = '<c:majorGridlines><c:spPr><a:ln w="9525"><a:solidFill><a:srgbClr val="D9D9D9"/></a:solidFill></a:ln></c:spPr></c:majorGridlines>';

/// The XML of a chart part for [chart], with the values it shows kept in it for programs that do not recalculate.
String chartXml(SheetChart chart, ChartData data) {
  final count = math.min(chart.series.length, data.series.length);
  const catId = '510001', valId = '510002', cat2 = '510003', val2 = '510004';
  final scatter = chart.kind == ChartKind.scatter;
  final horizontal = chart.kind == ChartKind.bar;

  // One chart element for every way the series are drawn: areas, then bars, then lines; the first scale, then the second.
  int rank(ChartKind k) => switch (k) {
    ChartKind.area => 0,
    ChartKind.column || ChartKind.bar => 1,
    ChartKind.line => 2,
    ChartKind.pie || ChartKind.doughnut => 3,
    ChartKind.scatter => 4,
  };
  final groups = <({ChartKind kind, bool second})>{
    for (var i = 0; i < count; i++) (kind: chart.kindOf(i), second: chart.secondaryOf(i)),
  }.toList()..sort((a, b) => a.second == b.second ? rank(a.kind).compareTo(rank(b.kind)) : (a.second ? 1 : -1));
  final hasSecond = groups.any((g) => g.second);

  final plot = StringBuffer();
  for (final g in groups) {
    final series = [for (var i = 0; i < count; i++) if (chart.kindOf(i) == g.kind && chart.secondaryOf(i) == g.second) _seriesXml(chart, data, i)].join();
    final ids = g.second ? '<c:axId val="$cat2"/><c:axId val="$val2"/>' : '<c:axId val="$catId"/><c:axId val="$valId"/>';
    final stacked = chart.stacked && !g.second;
    final grouping = chart.percent && stacked ? 'percentStacked' : (stacked ? 'stacked' : null);
    plot.write(switch (g.kind) {
      ChartKind.column || ChartKind.bar =>
        '<c:barChart><c:barDir val="${horizontal ? 'bar' : 'col'}"/><c:grouping val="${grouping ?? 'clustered'}"/><c:varyColors val="0"/>$series'
            '<c:gapWidth val="${stacked ? 80 : 150}"/>${stacked ? '<c:overlap val="100"/>' : ''}$ids</c:barChart>',
      ChartKind.line => '<c:lineChart><c:grouping val="standard"/><c:varyColors val="0"/>$series<c:marker val="1"/>$ids</c:lineChart>',
      ChartKind.area => '<c:areaChart><c:grouping val="${grouping ?? 'standard'}"/><c:varyColors val="0"/>$series$ids</c:areaChart>',
      ChartKind.scatter => '<c:scatterChart><c:scatterStyle val="lineMarker"/><c:varyColors val="0"/>$series$ids</c:scatterChart>',
      ChartKind.pie => '<c:pieChart><c:varyColors val="1"/>$series<c:firstSliceAng val="0"/></c:pieChart>',
      ChartKind.doughnut => '<c:doughnutChart><c:varyColors val="1"/>$series<c:firstSliceAng val="0"/><c:holeSize val="50"/></c:doughnutChart>',
    });
  }

  final percentFormat = chart.percent ? '<c:numFmt formatCode="0%" sourceLinked="0"/>' : '<c:numFmt formatCode="General" sourceLinked="1"/>';
  final axes = chart.kind.isPie
      ? ''
      : scatter
      ? '<c:valAx><c:axId val="$catId"/><c:scaling><c:orientation val="minMax"/></c:scaling><c:delete val="0"/><c:axPos val="b"/><c:numFmt formatCode="General" sourceLinked="1"/>'
            '<c:majorTickMark val="out"/><c:minorTickMark val="none"/><c:tickLblPos val="nextTo"/><c:crossAx val="$valId"/><c:crosses val="autoZero"/><c:crossBetween val="midCat"/></c:valAx>'
            '<c:valAx><c:axId val="$valId"/><c:scaling><c:orientation val="minMax"/></c:scaling><c:delete val="0"/><c:axPos val="l"/>$_gridXml'
            '<c:numFmt formatCode="General" sourceLinked="1"/><c:majorTickMark val="out"/><c:minorTickMark val="none"/><c:tickLblPos val="nextTo"/><c:crossAx val="$catId"/><c:crosses val="autoZero"/><c:crossBetween val="midCat"/></c:valAx>'
      : '<c:catAx><c:axId val="$catId"/><c:scaling><c:orientation val="minMax"/></c:scaling><c:delete val="0"/><c:axPos val="${horizontal ? 'l' : 'b'}"/>'
            '<c:numFmt formatCode="General" sourceLinked="1"/><c:majorTickMark val="none"/><c:minorTickMark val="none"/><c:tickLblPos val="nextTo"/><c:crossAx val="$valId"/>'
            '<c:crosses val="autoZero"/><c:auto val="1"/><c:lblAlgn val="ctr"/><c:lblOffset val="100"/><c:noMultiLvlLbl val="0"/></c:catAx>'
            '<c:valAx><c:axId val="$valId"/><c:scaling><c:orientation val="minMax"/></c:scaling><c:delete val="0"/><c:axPos val="${horizontal ? 'b' : 'l'}"/>$_gridXml'
            '$percentFormat<c:majorTickMark val="none"/><c:minorTickMark val="none"/><c:tickLblPos val="nextTo"/><c:crossAx val="$catId"/>'
            '<c:crosses val="autoZero"/><c:crossBetween val="${chart.kind == ChartKind.area ? 'midCat' : 'between'}"/></c:valAx>'
            '${hasSecond ? '<c:catAx><c:axId val="$cat2"/><c:scaling><c:orientation val="minMax"/></c:scaling><c:delete val="1"/><c:axPos val="b"/><c:majorTickMark val="none"/><c:minorTickMark val="none"/><c:tickLblPos val="nextTo"/><c:crossAx val="$val2"/><c:crosses val="autoZero"/><c:auto val="1"/><c:lblAlgn val="ctr"/><c:lblOffset val="100"/><c:noMultiLvlLbl val="0"/></c:catAx>'
                '<c:valAx><c:axId val="$val2"/><c:scaling><c:orientation val="minMax"/></c:scaling><c:delete val="0"/><c:axPos val="r"/><c:numFmt formatCode="General" sourceLinked="1"/><c:majorTickMark val="none"/><c:minorTickMark val="none"/><c:tickLblPos val="nextTo"/><c:crossAx val="$cat2"/><c:crosses val="max"/><c:crossBetween val="between"/></c:valAx>' : ''}';

  final title = chart.title.isEmpty
      ? ''
      : '<c:title><c:tx><c:rich><a:bodyPr/><a:lstStyle/><a:p><a:pPr><a:defRPr sz="1400" b="0"/></a:pPr><a:r><a:rPr lang="en-US" sz="1400" b="0"/><a:t>${_esc(chart.title)}</a:t></a:r></a:p></c:rich></c:tx><c:overlay val="0"/></c:title>';
  final legend = chart.series.length > 1 || chart.kind.isPie ? '<c:legend><c:legendPos val="${chart.kind.isPie ? 'r' : 'b'}"/><c:overlay val="0"/></c:legend>' : '';
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<c:chartSpace xmlns:c="$_chartNs" xmlns:a="$_drawNs" xmlns:r="$_relNs"><c:roundedCorners val="0"/><c:chart>$title<c:autoTitleDeleted val="${chart.title.isEmpty ? 1 : 0}"/>'
      '<c:plotArea><c:layout/>$plot$axes</c:plotArea>$legend<c:plotVisOnly val="1"/><c:dispBlanksAs val="gap"/></c:chart></c:chartSpace>';
}

/// A new, empty drawing part.
String emptyDrawingXml() => '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><xdr:wsDr xmlns:xdr="$_xdrNs" xmlns:a="$_drawNs"/>';

/// The anchor that places the chart with relationship [rid] on the sheet, numbered [shapeId] among the drawing's shapes.
XmlElement chartAnchor(SheetChart c, String rid, int shapeId) {
  final xml =
      '<xdr:wsDr xmlns:xdr="$_xdrNs" xmlns:a="$_drawNs"><xdr:twoCellAnchor><xdr:from><xdr:col>${c.col}</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>${c.row}</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:from>'
      '<xdr:to><xdr:col>${c.col + c.cols}</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>${c.row + c.rows}</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:to>'
      '<xdr:graphicFrame macro=""><xdr:nvGraphicFramePr><xdr:cNvPr id="$shapeId" name="Chart $shapeId"/><xdr:cNvGraphicFramePr/></xdr:nvGraphicFramePr>'
      '<xdr:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/></xdr:xfrm><a:graphic><a:graphicData uri="$_chartNs"><c:chart xmlns:c="$_chartNs" xmlns:r="$_relNs" r:id="$rid"/></a:graphicData></a:graphic>'
      '</xdr:graphicFrame><xdr:clientData/></xdr:twoCellAnchor></xdr:wsDr>';
  return XmlDocument.parse(xml).rootElement.childElements.first.copy();
}

/// The anchor in [drawing] that shows the chart with relationship [rid], or null.
XmlElement? findChartAnchor(XmlDocument drawing, String rid) {
  for (final anchor in drawing.rootElement.childElements) {
    final el = anchor.descendants.whereType<XmlElement>().where((e) => e.name.local == 'chart' && _attr(e, 'id') == rid).firstOrNull;
    if (el != null) return anchor;
  }
  return null;
}

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:xml/xml.dart';

/// PowerPoint measures in EMU: 12700 per point, 914400 per inch.
const emuPerPt = 12700.0;

/// Where a shape sits on its slide, in EMU.
class Frame {
  const Frame(this.x, this.y, this.w, this.h, {this.rot = 0, this.flipH = false, this.flipV = false});

  final double x;
  final double y;
  final double w;
  final double h;

  /// Degrees, clockwise.
  final double rot;
  final bool flipH;
  final bool flipV;

  double get cx => x + w / 2;
  double get cy => y + h / 2;

  Frame copyWith({double? x, double? y, double? w, double? h, double? rot}) =>
      Frame(x ?? this.x, y ?? this.y, w ?? this.w, h ?? this.h, rot: rot ?? this.rot, flipH: flipH, flipV: flipV);

  /// Whether a point on the slide falls inside the shape, allowing for its turn.
  bool contains(double px, double py) {
    var dx = px - cx, dy = py - cy;
    if (rot != 0) {
      final a = -rot * math.pi / 180;
      final c = math.cos(a), s = math.sin(a);
      final rx = dx * c - dy * s, ry = dx * s + dy * c;
      dx = rx;
      dy = ry;
    }
    return dx.abs() <= w / 2 && dy.abs() <= h / 2;
  }

  @override
  String toString() => 'Frame($x, $y, $w, $h, rot $rot)';
}

enum ShapeKind { text, picture, table, chart, diagram, line, other }

class RunView {
  const RunView({
    required this.text,
    required this.sizePt,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    required this.color,
    this.font,
  });

  final String text;
  final double sizePt;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strike;

  /// ARGB.
  final int color;
  final String? font;
}

class ParaView {
  const ParaView({
    required this.runs,
    this.align = 'l',
    this.level = 0,
    this.bullet,
    this.autoNumber = false,
    this.marL = 0,
    this.indent = 0,
    this.lineSpacing = 1.0,
    this.spaceBefore = 0,
    this.spaceAfter = 0,
    this.endSizePt = 18,
  });

  final List<RunView> runs;

  /// l, ctr, r or just.
  final String align;
  final int level;

  /// The bullet character, or null for no bullet.
  final String? bullet;
  final bool autoNumber;
  final double marL;
  final double indent;
  final double lineSpacing;
  final double spaceBefore;
  final double spaceAfter;

  /// Size of an empty paragraph, which still takes a line.
  final double endSizePt;

  String get text => runs.map((r) => r.text).join();
}

enum FillKind { none, solid, gradient, image }

class FillView {
  const FillView.none() : kind = FillKind.none, color = 0, stops = const [], angle = 0, media = null;
  const FillView.solid(this.color) : kind = FillKind.solid, stops = const [], angle = 0, media = null;
  const FillView.gradient(this.stops, this.angle) : kind = FillKind.gradient, color = 0, media = null;
  const FillView.image(this.media) : kind = FillKind.image, color = 0, stops = const [], angle = 0;

  final FillKind kind;
  final int color;
  final List<int> stops;
  final double angle;
  final String? media;
}

class LineView {
  const LineView({required this.widthPt, required this.color, this.dash, this.headArrow = false, this.tailArrow = false});
  final double widthPt;
  final int color;
  final String? dash;
  final bool headArrow;
  final bool tailArrow;
}

/// One outline command of a custom shape, with coordinates in the path's own units.
class PathCmd {
  const PathCmd(this.op, [this.pts = const []]);

  /// m, l, c (cubic) or z.
  final String op;
  final List<double> pts;
}

class CustomPath {
  const CustomPath(this.w, this.h, this.cmds);
  final double w;
  final double h;
  final List<PathCmd> cmds;
}

class TableCellView {
  const TableCellView({required this.paragraphs, this.fill, this.gridSpan = 1, this.rowSpan = 1, this.merged = false, this.anchor = 't'});
  final List<ParaView> paragraphs;
  final int? fill;
  final int gridSpan;
  final int rowSpan;

  /// Covered by a neighbouring merged cell.
  final bool merged;
  final String anchor;
}

class TableData {
  const TableData({required this.colWidths, required this.rowHeights, required this.rows});
  final List<double> colWidths;
  final List<double> rowHeights;
  final List<List<TableCellView>> rows;
}

class TextBox {
  const TextBox({this.left = 91440, this.top = 45720, this.right = 91440, this.bottom = 45720, this.anchor = 't', this.wrap = true, this.fontScale = 1.0});
  final double left;
  final double top;
  final double right;
  final double bottom;
  final String anchor;
  final bool wrap;
  final double fontScale;
}

/// A shape of a slide as it looks, with everything inherited from the layout and master worked out.
class ShapeView {
  const ShapeView({
    required this.id,
    required this.name,
    required this.kind,
    required this.frame,
    this.element,
    this.editable = true,
    this.placeholder = false,
    this.geometry = 'rect',
    this.custom,
    this.fill = const FillView.none(),
    this.line,
    this.paragraphs = const [],
    this.textBox = const TextBox(),
    this.media,
    this.crop,
    this.table,
    this.label,
    this.adjust,
  });

  final String id;
  final String name;
  final ShapeKind kind;
  final Frame frame;

  /// The XML the shape was read from, which edits change. Null for template shapes.
  final XmlElement? element;

  /// False for shapes inside groups and in the template, which can be seen but not moved.
  final bool editable;
  final bool placeholder;
  final String geometry;
  final CustomPath? custom;
  final FillView fill;
  final LineView? line;
  final List<ParaView> paragraphs;
  final TextBox textBox;

  /// Path of the picture inside the file.
  final String? media;

  /// Cropping of a picture as fractions: left, top, right, bottom.
  final List<double>? crop;
  final TableData? table;

  /// What to write on a shape that cannot be drawn, such as a chart.
  final String? label;

  /// First shape adjust value (corner radius and similar), 0 to 1.
  final double? adjust;

  /// The same shape somewhere else, used to show a shape while it is dragged.
  ShapeView withFrame(Frame f) => ShapeView(
    id: id,
    name: name,
    kind: kind,
    frame: f,
    element: element,
    editable: editable,
    placeholder: placeholder,
    geometry: geometry,
    custom: custom,
    fill: fill,
    line: line,
    paragraphs: paragraphs,
    textBox: textBox,
    media: media,
    crop: crop,
    table: table,
    label: label,
    adjust: adjust,
  );

  bool get hasText => paragraphs.any((p) => p.text.isNotEmpty);
  String get plainText => paragraphs.map((p) => p.text).join('\n');
  bool get canHaveText => kind == ShapeKind.text;
}

/// A slide ready to draw.
class SlideView {
  const SlideView({required this.background, required this.template, required this.shapes});

  final FillView background;

  /// Shapes of the master and layout that appear behind the slide's own.
  final List<ShapeView> template;
  final List<ShapeView> shapes;
}

/// Pictures of a presentation by their path inside the file.
typedef MediaFiles = Map<String, Uint8List>;

import 'sheet_model.dart';

/// What a highlighting rule looks for.
enum CondKind { greater, greaterOrEqual, less, lessOrEqual, equal, notEqual, between, textContains, duplicates, scale }

/// How a cell that matches a rule is shown: the parts of a cell look a rule can change.
class DxfStyle {
  const DxfStyle({this.fill, this.fontColor, this.bold = false});

  final int? fill;
  final int? fontColor;
  final bool bold;

  @override
  bool operator ==(Object other) => other is DxfStyle && other.fill == fill && other.fontColor == fontColor && other.bold == bold;

  @override
  int get hashCode => Object.hash(fill, fontColor, bold);
}

/// One highlighting rule of a sheet: cells of [range] that match are drawn with the rule's look.
/// A colour [scale] rule instead colours every number from the lowest to the highest value.
class CondRule {
  const CondRule({required this.range, required this.kind, this.a = '', this.b = '', this.look = const DxfStyle(), this.scale = const []});

  final MergeRange range;
  final CondKind kind;

  /// The value to compare with (and the upper limit in [b] for "between"), or the text to look for.
  final String a;
  final String b;
  final DxfStyle look;

  /// Two colours (low, high) or three (low, middle, high) as ARGB.
  final List<int> scale;

  CondRule withRange(MergeRange r) => CondRule(range: r, kind: kind, a: a, b: b, look: look, scale: scale);

  bool get needsValue => kind != CondKind.duplicates && kind != CondKind.scale;
}

/// The cell looks that rules give, worked out for one drawing of a sheet. Numbers that a scale needs are found once per rule.
class CondContext {
  CondContext(this.sheet);

  final Sheet sheet;
  final _stats = <CondRule, ({double min, double max, double mid})?>{};
  final _counts = <CondRule, Map<String, int>>{};

  bool get isEmpty => sheet.condRules.isEmpty;

  /// [base] with whatever the rules change at ([row], [col]). Earlier rules win where two change the same thing.
  CellStyle apply(CellStyle base, int row, int col) {
    if (sheet.condRules.isEmpty) return base;
    final value = sheet.cells[CellRef.key(row, col)]?.value ?? const EmptyValue();
    if (value is EmptyValue) return base;
    int? fill, font;
    var bold = false;
    for (final rule in sheet.condRules) {
      if (!rule.range.contains(row, col)) continue;
      if (rule.kind == CondKind.scale) {
        final c = _scaleColor(rule, value);
        if (c != null) fill ??= c;
        continue;
      }
      if (!_matches(rule, value)) continue;
      fill ??= rule.look.fill;
      font ??= rule.look.fontColor;
      bold = bold || rule.look.bold;
    }
    if (fill == null && font == null && !bold) return base;
    return base.copyWith(fill: fill ?? base.fill, fontColor: font ?? base.fontColor, bold: bold || base.bold);
  }

  static double? _number(String text) => double.tryParse(text.trim().replaceAll(',', ''));

  static String _text(CellValue v) => switch (v) {
    TextValue(:final text) => text,
    NumberValue(:final number) => number == number.roundToDouble() && number.abs() < 1e15 ? number.toInt().toString() : number.toString(),
    BoolValue(:final flag) => flag ? 'TRUE' : 'FALSE',
    ErrorValue(:final code) => code,
    EmptyValue() => '',
  };

  /// Negative, zero or positive as [v] sorts before, with or after [other], or null when they cannot be compared.
  static int? _compare(CellValue v, String other) {
    final n = _number(other);
    if (v is NumberValue) return n == null ? null : v.number.compareTo(n);
    if (v is TextValue) return n != null ? null : v.text.toLowerCase().compareTo(other.trim().toLowerCase());
    return null;
  }

  bool _matches(CondRule rule, CellValue v) {
    switch (rule.kind) {
      case CondKind.greater:
        return (_compare(v, rule.a) ?? -1) > 0;
      case CondKind.greaterOrEqual:
        return (_compare(v, rule.a) ?? -1) >= 0 && _compare(v, rule.a) != null;
      case CondKind.less:
        return (_compare(v, rule.a) ?? 1) < 0;
      case CondKind.lessOrEqual:
        return (_compare(v, rule.a) ?? 1) <= 0 && _compare(v, rule.a) != null;
      case CondKind.equal:
        return _compare(v, rule.a) == 0;
      case CondKind.notEqual:
        final c = _compare(v, rule.a);
        return c != null && c != 0;
      case CondKind.between:
        if (v is! NumberValue) return false;
        final lo = _number(rule.a), hi = _number(rule.b);
        if (lo == null || hi == null) return false;
        final a = lo < hi ? lo : hi, b = lo < hi ? hi : lo;
        return v.number >= a && v.number <= b;
      case CondKind.textContains:
        return rule.a.isNotEmpty && _text(v).toLowerCase().contains(rule.a.toLowerCase());
      case CondKind.duplicates:
        final counts = _counts[rule] ??= _countValues(rule);
        return (counts[_text(v).toLowerCase()] ?? 0) > 1;
      case CondKind.scale:
        return false;
    }
  }

  Map<String, int> _countValues(CondRule rule) {
    final out = <String, int>{};
    for (final e in sheet.cells.entries) {
      final r = CellRef.rowOf(e.key), c = CellRef.colOf(e.key);
      if (!rule.range.contains(r, c) || e.value.value is EmptyValue) continue;
      out.update(_text(e.value.value).toLowerCase(), (n) => n + 1, ifAbsent: () => 1);
    }
    return out;
  }

  int? _scaleColor(CondRule rule, CellValue v) {
    if (v is! NumberValue || rule.scale.length < 2) return null;
    final st = _stats.putIfAbsent(rule, () => _findStats(rule));
    if (st == null) return null;
    final x = v.number;
    if (st.max == st.min) return rule.scale.first;
    if (rule.scale.length == 2) return _lerp(rule.scale[0], rule.scale[1], ((x - st.min) / (st.max - st.min)).clamp(0.0, 1.0));
    if (x <= st.mid) {
      return st.mid == st.min ? rule.scale[1] : _lerp(rule.scale[0], rule.scale[1], ((x - st.min) / (st.mid - st.min)).clamp(0.0, 1.0));
    }
    return st.max == st.mid ? rule.scale[1] : _lerp(rule.scale[1], rule.scale[2], ((x - st.mid) / (st.max - st.mid)).clamp(0.0, 1.0));
  }

  ({double min, double max, double mid})? _findStats(CondRule rule) {
    final values = <double>[
      for (final e in sheet.cells.entries)
        if (e.value.value is NumberValue && rule.range.contains(CellRef.rowOf(e.key), CellRef.colOf(e.key))) (e.value.value as NumberValue).number,
    ]..sort();
    if (values.isEmpty) return null;
    final mid = values.length.isOdd ? values[values.length ~/ 2] : (values[values.length ~/ 2 - 1] + values[values.length ~/ 2]) / 2;
    return (min: values.first, max: values.last, mid: mid);
  }

  static int _lerp(int a, int b, double t) {
    int ch(int shift) => (((a >> shift) & 0xFF) + ((((b >> shift) & 0xFF) - ((a >> shift) & 0xFF)) * t)).round().clamp(0, 255);
    return 0xFF000000 | (ch(16) << 16) | (ch(8) << 8) | ch(0);
  }
}

/// Looks offered for highlighting, named as spreadsheet programs name them.
const condLooks = <(String, DxfStyle)>[
  ('Light red fill with dark red text', DxfStyle(fill: 0xFFFFC7CE, fontColor: 0xFF9C0006)),
  ('Yellow fill with dark yellow text', DxfStyle(fill: 0xFFFFEB9C, fontColor: 0xFF9C5700)),
  ('Green fill with dark green text', DxfStyle(fill: 0xFFC6EFCE, fontColor: 0xFF006100)),
  ('Light blue fill', DxfStyle(fill: 0xFFDDEBF7, fontColor: 0xFF1F4E79)),
  ('Red text', DxfStyle(fontColor: 0xFF9C0006)),
  ('Bold dark green text', DxfStyle(fontColor: 0xFF006100, bold: true)),
];

/// Colour scales offered, low to high.
const condScales = <(String, List<int>)>[
  ('Green, yellow, red', [0xFF63BE7B, 0xFFFFEB84, 0xFFF8696B]),
  ('Red, yellow, green', [0xFFF8696B, 0xFFFFEB84, 0xFF63BE7B]),
  ('White to blue', [0xFFFCFCFF, 0xFF5A8AC6]),
  ('White to green', [0xFFFCFCFF, 0xFF63BE7B]),
  ('White to red', [0xFFFCFCFF, 0xFFF8696B]),
];

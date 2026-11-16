import 'package:xml/xml.dart';

import '../domain/cond_format.dart';
import '../domain/sheet_model.dart';
import 'styles_xml.dart';

const _operators = {
  'greaterThan': CondKind.greater,
  'greaterThanOrEqual': CondKind.greaterOrEqual,
  'lessThan': CondKind.less,
  'lessThanOrEqual': CondKind.lessOrEqual,
  'equal': CondKind.equal,
  'notEqual': CondKind.notEqual,
  'between': CondKind.between,
};

Iterable<XmlElement> _kids(XmlElement e, String name) => e.childElements.where((c) => c.name.local == name);

/// The value of a formula that is only a number or a quoted text, or null when it is anything else.
String? _literal(String formula) {
  final f = formula.trim();
  if (double.tryParse(f) != null) return f;
  if (f.length >= 2 && f.startsWith('"') && f.endsWith('"')) return f.substring(1, f.length - 1).replaceAll('""', '"');
  return null;
}

List<MergeRange>? _ranges(XmlElement cf) {
  final tokens = (cf.getAttribute('sqref') ?? '').split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
  if (tokens.isEmpty) return null;
  final out = <MergeRange>[];
  for (final t in tokens) {
    final r = CellRef.parseRange(t);
    if (r == null) return null;
    out.add(r);
  }
  return out;
}

List<int>? _scaleColors(XmlElement rule, List<int> theme) {
  final scale = _kids(rule, 'colorScale').firstOrNull;
  if (scale == null) return null;
  final points = _kids(scale, 'cfvo').toList();
  final colors = [for (final c in _kids(scale, 'color')) parseColor(c, theme)];
  if (colors.any((c) => c == null)) return null;
  final types = [for (final p in points) p.getAttribute('type')];
  final ok = (types.length == 2 && types[0] == 'min' && types[1] == 'max') ||
      (types.length == 3 && types[0] == 'min' && types[1] == 'percentile' && points[1].getAttribute('val') == '50' && types[2] == 'max');
  if (!ok || colors.length != types.length) return null;
  return [for (final c in colors) c!];
}

CondRule? _readRule(XmlElement rule, MergeRange range, List<DxfStyle> dxfs, List<int> theme) {
  final dxfId = int.tryParse(rule.getAttribute('dxfId') ?? '');
  final look = dxfId != null && dxfId >= 0 && dxfId < dxfs.length ? dxfs[dxfId] : const DxfStyle();
  switch (rule.getAttribute('type')) {
    case 'cellIs':
      final kind = _operators[rule.getAttribute('operator')];
      if (kind == null) return null;
      final values = [for (final f in _kids(rule, 'formula')) _literal(f.innerText)];
      if (values.isEmpty || values.any((v) => v == null)) return null;
      if (kind == CondKind.between ? values.length != 2 : values.length != 1) return null;
      return CondRule(range: range, kind: kind, a: values[0]!, b: kind == CondKind.between ? values[1]! : '', look: look);
    case 'containsText':
      final text = rule.getAttribute('text');
      if (rule.getAttribute('operator') != 'containsText' || text == null || text.isEmpty) return null;
      return CondRule(range: range, kind: CondKind.textContains, a: text, look: look);
    case 'duplicateValues':
      return CondRule(range: range, kind: CondKind.duplicates, look: look);
    case 'colorScale':
      final colors = _scaleColors(rule, theme);
      return colors == null ? null : CondRule(range: range, kind: CondKind.scale, scale: colors);
  }
  return null;
}

/// True when the app can show and write back every rule in this <conditionalFormatting> element.
bool isSupportedCf(XmlElement cf, List<int> theme) {
  final ranges = _ranges(cf);
  final rules = _kids(cf, 'cfRule').toList();
  if (ranges == null || rules.isEmpty) return false;
  return rules.every((r) => _readRule(r, ranges.first, const [], theme) != null);
}

/// The rules of a worksheet that the app understands. Elements with other kinds of rules are left in the file as they are.
List<CondRule> readCondFormatting(XmlElement worksheet, List<DxfStyle> dxfs, List<int> theme) {
  final out = <CondRule>[];
  for (final cf in _kids(worksheet, 'conditionalFormatting')) {
    if (!isSupportedCf(cf, theme)) continue;
    final ranges = _ranges(cf)!;
    final rules = _kids(cf, 'cfRule').toList()
      ..sort((a, b) => (int.tryParse(a.getAttribute('priority') ?? '') ?? 0).compareTo(int.tryParse(b.getAttribute('priority') ?? '') ?? 0));
    for (final rule in rules) {
      for (final range in ranges) {
        final r = _readRule(rule, range, dxfs, theme);
        if (r != null) out.add(r);
      }
    }
  }
  return out;
}

String _sqref(MergeRange r) => r.isSingle ? CellRef.a1(r.firstRow, r.firstCol) : r.toString();

String _formulaText(String v) => double.tryParse(v.trim()) != null ? v.trim() : '"${v.replaceAll('"', '""')}"';

const _operatorNames = {
  CondKind.greater: 'greaterThan',
  CondKind.greaterOrEqual: 'greaterThanOrEqual',
  CondKind.less: 'lessThan',
  CondKind.lessOrEqual: 'lessThanOrEqual',
  CondKind.equal: 'equal',
  CondKind.notEqual: 'notEqual',
  CondKind.between: 'between',
};

String _argb(int c) => c.toRadixString(16).padLeft(8, '0').toUpperCase();

/// The <conditionalFormatting> elements for [rules], with their order kept as priority. [dxfId] gives the style entry of a look.
List<XmlElement> condElements(List<CondRule> rules, int Function(DxfStyle) dxfId) {
  XmlElement el(String name, [Map<String, String> attrs = const {}, List<XmlNode> children = const []]) =>
      XmlElement(XmlName(name), [for (final e in attrs.entries) XmlAttribute(XmlName(e.key), e.value)], children);

  final out = <XmlElement>[];
  for (var i = 0; i < rules.length; i++) {
    final r = rules[i];
    final priority = '${i + 1}';
    final XmlElement rule;
    switch (r.kind) {
      case CondKind.scale:
        rule = el('cfRule', {'type': 'colorScale', 'priority': priority}, [
          el('colorScale', const {}, [
            el('cfvo', {'type': 'min'}),
            if (r.scale.length == 3) el('cfvo', {'type': 'percentile', 'val': '50'}),
            el('cfvo', {'type': 'max'}),
            for (final c in r.scale) el('color', {'rgb': _argb(c)}),
          ]),
        ]);
      case CondKind.duplicates:
        rule = el('cfRule', {'type': 'duplicateValues', 'dxfId': '${dxfId(r.look)}', 'priority': priority});
      case CondKind.textContains:
        final first = CellRef.a1(r.range.firstRow, r.range.firstCol);
        rule = el(
          'cfRule',
          {'type': 'containsText', 'dxfId': '${dxfId(r.look)}', 'priority': priority, 'operator': 'containsText', 'text': r.a},
          [el('formula', const {}, [XmlText('NOT(ISERROR(SEARCH("${r.a.replaceAll('"', '""')}",$first)))')])],
        );
      default:
        rule = el(
          'cfRule',
          {'type': 'cellIs', 'dxfId': '${dxfId(r.look)}', 'priority': priority, 'operator': _operatorNames[r.kind]!},
          [
            el('formula', const {}, [XmlText(_formulaText(r.a))]),
            if (r.kind == CondKind.between) el('formula', const {}, [XmlText(_formulaText(r.b))]),
          ],
        );
    }
    out.add(el('conditionalFormatting', {'sqref': _sqref(r.range)}, [rule]));
  }
  return out;
}

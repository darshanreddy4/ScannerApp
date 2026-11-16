import 'package:xml/xml.dart';

import '../domain/sheet_model.dart';
import '../domain/validation.dart';

Iterable<XmlElement> _kids(XmlElement e, String name) => e.childElements.where((c) => c.name.local == name);

List<MergeRange>? _ranges(XmlElement dv) {
  final tokens = (dv.getAttribute('sqref') ?? '').split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
  if (tokens.isEmpty) return null;
  final out = <MergeRange>[];
  for (final t in tokens) {
    final r = CellRef.parseRange(t);
    if (r == null) return null;
    out.add(r);
  }
  return out;
}

ValidationRule? _readOne(XmlElement dv, MergeRange range) {
  final f1 = _kids(dv, 'formula1').firstOrNull?.innerText.trim();
  final f2 = _kids(dv, 'formula2').firstOrNull?.innerText.trim();
  switch (dv.getAttribute('type')) {
    case 'list':
      if (f1 == null || f1.length < 2 || !f1.startsWith('"') || !f1.endsWith('"')) return null;
      final items = [
        for (final i in f1.substring(1, f1.length - 1).replaceAll('""', '"').split(','))
          if (i.trim().isNotEmpty) i.trim(),
      ];
      return items.isEmpty ? null : ValidationRule(range: range, kind: ValidationKind.list, items: items);
    case 'whole' || 'decimal':
      final op = dv.getAttribute('operator') ?? 'between';
      if (op != 'between' || f1 == null || f2 == null || double.tryParse(f1) == null || double.tryParse(f2) == null) return null;
      return ValidationRule(range: range, kind: dv.getAttribute('type') == 'whole' ? ValidationKind.whole : ValidationKind.decimal, min: f1, max: f2);
  }
  return null;
}

/// True when the app can show and write back this <dataValidation> element.
bool isSupportedValidation(XmlElement dv) {
  final ranges = _ranges(dv);
  return ranges != null && _readOne(dv, ranges.first) != null;
}

/// The validation rules of a worksheet that the app understands. Others stay in the file as they are.
List<ValidationRule> readValidations(XmlElement worksheet) {
  final out = <ValidationRule>[];
  final holder = _kids(worksheet, 'dataValidations').firstOrNull;
  if (holder == null) return out;
  for (final dv in _kids(holder, 'dataValidation')) {
    final ranges = _ranges(dv);
    if (ranges == null) continue;
    for (final range in ranges) {
      final r = _readOne(dv, range);
      if (r != null) out.add(r);
    }
  }
  return out;
}

String _sqref(MergeRange r) => r.isSingle ? CellRef.a1(r.firstRow, r.firstCol) : r.toString();

/// The <dataValidation> elements for [rules].
List<XmlElement> validationElements(List<ValidationRule> rules) {
  XmlElement el(String name, Map<String, String> attrs, [List<XmlNode> children = const []]) =>
      XmlElement(XmlName(name), [for (final e in attrs.entries) XmlAttribute(XmlName(e.key), e.value)], children);
  return [
    for (final r in rules)
      el(
        'dataValidation',
        {
          'type': r.kind.name,
          if (r.kind != ValidationKind.list) 'operator': 'between',
          'allowBlank': '1',
          'showInputMessage': '1',
          'showErrorMessage': '1',
          'sqref': _sqref(r.range),
        },
        [
          el('formula1', const {}, [XmlText(r.kind == ValidationKind.list ? '"${r.items.join(',').replaceAll('"', '""')}"' : r.min.trim())]),
          if (r.kind != ValidationKind.list) el('formula2', const {}, [XmlText(r.max.trim())]),
        ],
      ),
  ];
}

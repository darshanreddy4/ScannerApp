import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../domain/formula_refs.dart';
import '../domain/sheet_model.dart';
import 'xlsx_reader.dart';
import 'xlsx_writer.dart';

/// One workbook to join: its file name (for messages) and its bytes.
class MergeInput {
  const MergeInput(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

/// What a merge made.
class MergeResult {
  const MergeResult(this.bytes, {required this.sheets, required this.skippedCharts});

  /// The merged .xlsx file.
  final Uint8List bytes;
  final int sheets;

  /// Charts of kinds the app cannot copy, which are left out.
  final int skippedCharts;
}

/// Joins every sheet of every workbook into one workbook, in the order given.
///
/// The first file is the base and is kept as it is; the sheets of the others are added after its sheets, with their
/// cell formats (borders included), merged cells, column widths, highlighting rules, input rules and charts. A sheet whose
/// name is already taken gets " (2)" and so on, and formulas of that file that point to it follow the new name.
/// Pure Dart so it can run in an isolate.
MergeResult mergeXlsx(List<MergeInput> inputs) {
  if (inputs.length < 2) throw const XlsxFormatException('Choose at least two Excel files to merge.');

  final others = <Workbook>[];
  for (final input in inputs.skip(1)) {
    try {
      others.add(readXlsx(input.bytes));
    } on XlsxFormatException catch (e) {
      throw XlsxFormatException('${input.name}: ${e.message}');
    }
  }

  // Bring the formats of the other files into the base file's styles, then read the base again so it knows them.
  final baseBytes = inputs.first.bytes;
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(baseBytes);
  } catch (_) {
    throw XlsxFormatException('${inputs.first.name}: This file is not a valid .xlsx workbook. Older .xls files are not supported.');
  }
  final stylesFile = archive.findFile('xl/styles.xml');
  if (stylesFile == null) throw XlsxFormatException('${inputs.first.name}: This workbook has no cell formats to merge into.');
  final baseStyles = XmlDocument.parse(utf8.decode(stylesFile.readBytes()!, allowMalformed: true));

  final maps = <Map<int, int>>[];
  for (var i = 0; i < others.length; i++) {
    final wb = others[i];
    final used = <int>{};
    for (final s in wb.sheets) {
      for (final c in s.cells.values) {
        used.add(c.style);
      }
      used
        ..addAll(s.rowStyles.values)
        ..addAll(s.colStyles.values);
    }
    used.remove(0);
    final theirs = _stylesOf(inputs[i + 1].bytes);
    maps.add(theirs == null ? {for (final u in used) u: 0} : _appendFormats(baseStyles, theirs, used));
  }

  final rebuilt = Archive();
  for (final f in archive.files) {
    if (f.name == 'xl/styles.xml') {
      rebuilt.addFile(ArchiveFile.bytes(f.name, utf8.encode(baseStyles.toXmlString())));
    } else {
      rebuilt.addFile(f);
    }
  }
  final merged = readXlsx(Uint8List.fromList(ZipEncoder().encode(rebuilt)));

  var skipped = 0;
  for (var i = 0; i < others.length; i++) {
    // Names first, so a formula can point to a sheet that comes later in its own file.
    final renames = <String, String>{};
    final planned = <Sheet, String>{};
    for (final s in others[i].sheets) {
      final name = _uniqueName(merged, planned.values, s.name);
      planned[s] = name;
      if (name != s.name) renames[s.name.toLowerCase()] = name;
    }
    for (final entry in planned.entries) {
      final made = _copySheet(entry.key, entry.value, maps[i], renames);
      skipped += made.skipped;
      merged.sheets.add(made.sheet);
    }
  }
  merged.structureChanged = true;
  return MergeResult(writeXlsx(merged), sheets: merged.sheets.length, skippedCharts: skipped);
}

XmlDocument? _stylesOf(Uint8List bytes) {
  final f = ZipDecoder().decodeBytes(bytes).findFile('xl/styles.xml');
  return f == null ? null : XmlDocument.parse(utf8.decode(f.readBytes()!, allowMalformed: true));
}

String _uniqueName(Workbook wb, Iterable<String> planned, String wanted) {
  var base = wanted.replaceAll(RegExp(r'[\\/?*\[\]:]'), '').trim();
  if (base.isEmpty) base = 'Sheet';
  if (base.length > 31) base = base.substring(0, 31);
  final taken = {...wb.sheets.map((s) => s.name.toLowerCase()), ...planned.map((n) => n.toLowerCase())};
  if (!taken.contains(base.toLowerCase())) return base;
  var i = 2;
  while (true) {
    final suffix = ' ($i)';
    final name = '${base.length + suffix.length > 31 ? base.substring(0, 31 - suffix.length) : base}$suffix';
    if (!taken.contains(name.toLowerCase())) return name;
    i++;
  }
}

({Sheet sheet, int skipped}) _copySheet(Sheet from, String name, Map<int, int> styleMap, Map<String, String> renames) {
  int style(int s) => styleMap[s] ?? s;
  final sheet = Sheet(
    name: name,
    cells: {for (final e in from.cells.entries) e.key: _copyCell(e.value, style, renames)},
    merges: List.of(from.merges),
    colWidths: Map.of(from.colWidths),
    rowHeights: Map.of(from.rowHeights),
    hiddenRows: Set.of(from.hiddenRows),
    hiddenCols: Set.of(from.hiddenCols),
    rowStyles: {for (final e in from.rowStyles.entries) e.key: style(e.value)},
    colStyles: {for (final e in from.colStyles.entries) e.key: style(e.value)},
    condRules: List.of(from.condRules),
    validations: List.of(from.validations),
    hidden: from.hidden,
    frozenRows: from.frozenRows,
    frozenCols: from.frozenCols,
  )..dirty = true;
  sheet
    ..colsDirty = true
    ..mergesDirty = true
    ..condDirty = sheet.condRules.isNotEmpty
    ..validDirty = sheet.validations.isNotEmpty;

  var skipped = 0;
  for (final c in from.charts) {
    if (!c.editable) {
      skipped++;
      continue;
    }
    final fresh = c.asNew();
    sheet.charts.add(fresh.remapped((r) => renames.containsKey(r.sheet.toLowerCase()) ? r.onSheet(renames[r.sheet.toLowerCase()]!) : r) ?? fresh);
  }
  sheet.chartsDirty = sheet.charts.isNotEmpty;
  return (sheet: sheet, skipped: skipped);
}

SheetCell _copyCell(SheetCell cell, int Function(int) style, Map<String, String> renames) {
  final f = cell.formula;
  return SheetCell(value: cell.value, formula: f == null || renames.isEmpty ? f : _followRenames(f, renames), style: style(cell.style));
}

final _sheetPrefix = RegExp(r"(?<![A-Za-z0-9_.$'])(?:'((?:[^']|'')+)'|([A-Za-z_][A-Za-z0-9_.]*))!");

String _followRenames(String formula, Map<String, String> renames) => mapFormulaOutsideText(formula, (part) {
  return part.replaceAllMapped(_sheetPrefix, (m) {
    final old = m.group(1)?.replaceAll("''", "'") ?? m.group(2)!;
    final now = renames[old.toLowerCase()];
    return now == null ? m.group(0)! : "'${now.replaceAll("'", "''")}'!";
  });
});

// ------------------------------------------------------------------ styles

Iterable<XmlElement> _kids(XmlElement e, String name) => e.childElements.where((c) => c.name.local == name);

/// Copies the cell formats [used] of [from] into [into] (with the fonts, fills, borders and number formats they need)
/// and returns where each one ended up. Format 0 stays the base file's own default.
Map<int, int> _appendFormats(XmlDocument into, XmlDocument from, Set<int> used) {
  final dst = into.rootElement, src = from.rootElement;
  final dstXfs = _kids(dst, 'cellXfs').firstOrNull, srcXfs = _kids(src, 'cellXfs').firstOrNull;
  final dstFonts = _kids(dst, 'fonts').firstOrNull, dstFills = _kids(dst, 'fills').firstOrNull;
  if (dstXfs == null || srcXfs == null || dstFonts == null || dstFills == null) return {for (final u in used) u: 0};

  var dstBorders = _kids(dst, 'borders').firstOrNull;
  if (dstBorders == null) {
    dstBorders = XmlElement(XmlName('borders'), const [], [XmlElement(XmlName('border'), const [], _emptyBorderSides())]);
    final at = dst.children.indexWhere((c) => c is XmlElement && const {'cellStyleXfs', 'cellXfs'}.contains(c.name.local));
    dst.children.insert(at < 0 ? dst.children.length : at, dstBorders);
  }

  final srcFonts = _kids(_kids(src, 'fonts').firstOrNull ?? XmlElement(XmlName('fonts')), 'font').toList();
  final srcFills = _kids(_kids(src, 'fills').firstOrNull ?? XmlElement(XmlName('fills')), 'fill').toList();
  final srcBorders = _kids(_kids(src, 'borders').firstOrNull ?? XmlElement(XmlName('borders')), 'border').toList();
  final srcXfList = _kids(srcXfs, 'xf').toList();
  final srcFormats = {
    for (final e in _kids(_kids(src, 'numFmts').firstOrNull ?? XmlElement(XmlName('numFmts')), 'numFmt'))
      int.tryParse(e.getAttribute('numFmtId') ?? '') ?? -1: e.getAttribute('formatCode') ?? 'General',
  };

  var dstFormatsEl = _kids(dst, 'numFmts').firstOrNull;
  final dstFormats = {
    if (dstFormatsEl != null)
      for (final e in _kids(dstFormatsEl, 'numFmt')) e.getAttribute('formatCode') ?? '': int.tryParse(e.getAttribute('numFmtId') ?? '') ?? 0,
  };

  int place(XmlElement holder, String tag, List<XmlElement> source, int id, Map<String, int> known) {
    if (id < 0 || id >= source.length) return 0;
    final key = source[id].toXmlString();
    final seen = known[key];
    if (seen != null) return seen;
    holder.children.add(source[id].copy());
    final at = _kids(holder, tag).length - 1;
    known[key] = at;
    return at;
  }

  Map<String, int> keysOf(XmlElement holder, String tag) {
    final out = <String, int>{};
    var i = 0;
    for (final e in _kids(holder, tag)) {
      out.putIfAbsent(e.toXmlString(), () => i);
      i++;
    }
    return out;
  }

  final fontKeys = keysOf(dstFonts, 'font'), fillKeys = keysOf(dstFills, 'fill'), borderKeys = keysOf(dstBorders, 'border');

  int numFmt(int id) {
    if (id < 164) return id;
    final code = srcFormats[id];
    if (code == null) return 0;
    final known = dstFormats[code];
    if (known != null) return known;
    if (dstFormatsEl == null) {
      dstFormatsEl = XmlElement(XmlName('numFmts'));
      dst.children.insert(0, dstFormatsEl!);
    }
    var next = 164;
    final ids = {...dstFormats.values};
    while (ids.contains(next)) {
      next++;
    }
    dstFormatsEl!.children.add(XmlElement(XmlName('numFmt'), [XmlAttribute(XmlName('numFmtId'), '$next'), XmlAttribute(XmlName('formatCode'), code)]));
    dstFormatsEl!.setAttribute('count', '${_kids(dstFormatsEl!, 'numFmt').length}');
    dstFormats[code] = next;
    return next;
  }

  final map = <int, int>{};
  for (final u in used.toList()..sort()) {
    if (u < 0 || u >= srcXfList.length) {
      map[u] = 0;
      continue;
    }
    final xf = srcXfList[u].copy();
    int number(String attr) => int.tryParse(xf.getAttribute(attr) ?? '') ?? 0;
    xf
      ..setAttribute('fontId', '${place(dstFonts, 'font', srcFonts, number('fontId'), fontKeys)}')
      ..setAttribute('fillId', '${place(dstFills, 'fill', srcFills, number('fillId'), fillKeys)}')
      ..setAttribute('borderId', '${place(dstBorders, 'border', srcBorders, number('borderId'), borderKeys)}')
      ..setAttribute('numFmtId', '${numFmt(number('numFmtId'))}')
      ..setAttribute('xfId', '0')
      ..setAttribute('applyFont', '1')
      ..setAttribute('applyFill', '1')
      ..setAttribute('applyBorder', '1')
      ..setAttribute('applyNumberFormat', '1');
    dstXfs.children.add(xf);
    map[u] = _kids(dstXfs, 'xf').length - 1;
  }
  dstFonts.setAttribute('count', '${_kids(dstFonts, 'font').length}');
  dstFills.setAttribute('count', '${_kids(dstFills, 'fill').length}');
  dstBorders.setAttribute('count', '${_kids(dstBorders, 'border').length}');
  dstXfs.setAttribute('count', '${_kids(dstXfs, 'xf').length}');
  return map;
}

List<XmlElement> _emptyBorderSides() => [
  for (final n in const ['left', 'right', 'top', 'bottom', 'diagonal']) XmlElement(XmlName(n)),
];

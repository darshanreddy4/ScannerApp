import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../domain/formula_refs.dart';
import '../domain/sheet_model.dart';
import 'styles_xml.dart';

class XlsxFormatException implements Exception {
  const XlsxFormatException(this.message);
  final String message;
}

XmlDocument _xml(Archive a, String path) {
  final f = a.findFile(path);
  if (f == null) throw XlsxFormatException('Missing $path');
  return XmlDocument.parse(utf8.decode(f.readBytes()!, allowMalformed: true));
}

XmlDocument? _xmlOrNull(Archive a, String path) {
  final f = a.findFile(path);
  return f == null ? null : XmlDocument.parse(utf8.decode(f.readBytes()!, allowMalformed: true));
}

Iterable<XmlElement> _kids(XmlElement e, String name) => e.childElements.where((c) => c.name.local == name);

/// Resolves a relationship target against the part that owns the relationships.
String resolveTarget(String base, String target) {
  if (target.startsWith('/')) return target.substring(1);
  final parts = base.split('/')..removeLast();
  for (final seg in target.split('/')) {
    if (seg == '..') {
      if (parts.isNotEmpty) parts.removeLast();
    } else if (seg != '.' && seg.isNotEmpty) {
      parts.add(seg);
    }
  }
  return parts.join('/');
}

/// Reads an .xlsx file into a [Workbook]. Pure Dart so it can run in an isolate.
Workbook readXlsx(Uint8List bytes) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw const XlsxFormatException('This file is not a valid .xlsx workbook. Older .xls files are not supported.');
  }
  if (archive.findFile('xl/workbook.xml') == null) throw const XlsxFormatException('This file is not a valid .xlsx workbook.');

  final workbookDoc = _xml(archive, 'xl/workbook.xml');
  final wb = workbookDoc.rootElement;
  final rels = <String, String>{};
  final relsDoc = _xmlOrNull(archive, 'xl/_rels/workbook.xml.rels');
  if (relsDoc != null) {
    for (final r in relsDoc.rootElement.childElements) {
      final id = r.getAttribute('Id'), target = r.getAttribute('Target');
      if (id != null && target != null) rels[id] = resolveTarget('xl/workbook.xml', target);
    }
  }

  final shared = _readSharedStrings(_xmlOrNull(archive, 'xl/sharedStrings.xml'));
  final theme = parseThemeColors(_xmlOrNull(archive, 'xl/theme/theme1.xml'));
  final stylesDoc = _xmlOrNull(archive, 'xl/styles.xml');
  final stylesXml = stylesDoc == null ? null : StylesXml(stylesDoc, theme);
  final styles = StyleTable(stylesXml?.readStyles());
  styles.originalCount = styles.styles.length;

  final sheets = <Sheet>[];
  final sheetsEl = _kids(wb, 'sheets').firstOrNull;
  if (sheetsEl != null) {
    for (final s in _kids(sheetsEl, 'sheet')) {
      final name = s.getAttribute('name') ?? 'Sheet${sheets.length + 1}';
      final rid = s.attributes.where((a) => a.name.local == 'id').map((a) => a.value).firstOrNull;
      final path = rid == null ? null : rels[rid];
      if (path == null) continue;
      final doc = _xmlOrNull(archive, path);
      if (doc == null) continue;
      final sheet = _readSheet(doc, name, path, shared);
      sheet.hidden = s.getAttribute('state') == 'hidden' || s.getAttribute('state') == 'veryHidden';
      sheets.add(sheet);
    }
  }
  if (sheets.isEmpty) throw const XlsxFormatException('This workbook has no sheets.');

  final props = _kids(wb, 'workbookPr').firstOrNull;
  final date1904 = props?.getAttribute('date1904') == '1' || props?.getAttribute('date1904') == 'true';
  return Workbook(sheets: sheets, styles: styles, source: bytes, date1904: date1904);
}

List<String> _readSharedStrings(XmlDocument? doc) {
  if (doc == null) return const [];
  final out = <String>[];
  for (final si in _kids(doc.rootElement, 'si')) {
    final text = StringBuffer();
    void walk(XmlElement e) {
      for (final c in e.childElements) {
        if (c.name.local == 't') {
          text.write(c.innerText);
        } else if (c.name.local == 'r') {
          walk(c);
        }
        // Phonetic hints (rPh) are not shown.
      }
    }

    walk(si);
    out.add(text.toString());
  }
  return out;
}

Sheet _readSheet(XmlDocument doc, String name, String path, List<String> shared) {
  final root = doc.rootElement;
  final sheet = Sheet(name: name, partPath: path);

  final format = _kids(root, 'sheetFormatPr').firstOrNull;
  final defaultWidth = double.tryParse(format?.getAttribute('defaultColWidth') ?? '');

  final cols = _kids(root, 'cols').firstOrNull;
  if (cols != null) {
    for (final c in _kids(cols, 'col')) {
      final min = int.tryParse(c.getAttribute('min') ?? '') ?? 1, max = int.tryParse(c.getAttribute('max') ?? '') ?? min;
      final width = double.tryParse(c.getAttribute('width') ?? '');
      final hidden = c.getAttribute('hidden') == '1' || c.getAttribute('hidden') == 'true';
      final style = int.tryParse(c.getAttribute('style') ?? '');
      // Whole-sheet column ranges (max 16384) are not expanded one by one.
      for (var i = min; i <= max && i - min < 2000 && i <= CellRef.maxCols; i++) {
        if (width != null && (width != defaultWidth)) sheet.colWidths[i - 1] = width;
        if (hidden) sheet.hiddenCols.add(i - 1);
        if (style != null && style != 0) sheet.colStyles[i - 1] = style;
      }
    }
  }

  final data = _kids(root, 'sheetData').firstOrNull;
  final sharedFormulas = <String, ({String formula, int row, int col})>{};
  if (data != null) {
    var rowIndex = -1;
    for (final row in _kids(data, 'row')) {
      rowIndex = int.tryParse(row.getAttribute('r') ?? '') != null ? int.parse(row.getAttribute('r')!) - 1 : rowIndex + 1;
      final ht = double.tryParse(row.getAttribute('ht') ?? '');
      if (ht != null && (row.getAttribute('customHeight') == '1' || row.getAttribute('customHeight') == 'true')) sheet.rowHeights[rowIndex] = ht;
      if (row.getAttribute('hidden') == '1' || row.getAttribute('hidden') == 'true') sheet.hiddenRows.add(rowIndex);
      final rowStyle = int.tryParse(row.getAttribute('s') ?? '');
      if (rowStyle != null && rowStyle != 0 && (row.getAttribute('customFormat') == '1' || row.getAttribute('customFormat') == 'true'))
        sheet.rowStyles[rowIndex] = rowStyle;

      var colIndex = -1;
      for (final c in _kids(row, 'c')) {
        final ref = c.getAttribute('r');
        final parsed = ref == null ? null : CellRef.parse(ref);
        if (parsed != null) {
          colIndex = parsed.col;
        } else {
          colIndex++;
        }
        final cell = _readCell(c, shared, sharedFormulas, rowIndex, colIndex);
        if (cell != null && !cell.isEmpty) sheet.cells[CellRef.key(rowIndex, colIndex)] = cell;
      }
    }
  }

  final merges = _kids(root, 'mergeCells').firstOrNull;
  if (merges != null) {
    for (final m in _kids(merges, 'mergeCell')) {
      final r = CellRef.parseRange(m.getAttribute('ref') ?? '');
      if (r != null && !r.isSingle) sheet.merges.add(r);
    }
  }

  final views = _kids(root, 'sheetViews').firstOrNull;
  final pane = views == null ? null : _kids(views, 'sheetView').expand((v) => _kids(v, 'pane')).firstOrNull;
  if (pane != null && pane.getAttribute('state') != 'split') {
    sheet.frozenCols = int.tryParse(pane.getAttribute('xSplit') ?? '')?.clamp(0, 100) ?? 0;
    sheet.frozenRows = int.tryParse(pane.getAttribute('ySplit') ?? '')?.clamp(0, 1000) ?? 0;
  }
  return sheet;
}

SheetCell? _readCell(XmlElement c, List<String> shared, Map<String, ({String formula, int row, int col})> sharedFormulas, int row, int col) {
  final style = int.tryParse(c.getAttribute('s') ?? '') ?? 0;
  final type = c.getAttribute('t') ?? 'n';
  final v = _kids(c, 'v').firstOrNull?.innerText;
  final f = _kids(c, 'f').firstOrNull;

  String? formula;
  if (f != null) {
    final kind = f.getAttribute('t');
    final text = f.innerText;
    if (kind == 'shared') {
      final si = f.getAttribute('si') ?? '';
      if (text.isNotEmpty) {
        sharedFormulas[si] = (formula: text, row: row, col: col);
        formula = text;
      } else {
        final master = sharedFormulas[si];
        if (master != null) formula = shiftFormula(master.formula, row - master.row, col - master.col);
      }
    } else if (text.isNotEmpty) {
      formula = text;
    }
  }

  CellValue value;
  switch (type) {
    case 's':
      final i = int.tryParse(v ?? '');
      value = i != null && i >= 0 && i < shared.length ? TextValue(shared[i]) : const EmptyValue();
    case 'inlineStr':
      final is_ = _kids(c, 'is').firstOrNull;
      value = is_ == null
          ? const EmptyValue()
          : TextValue(
              is_.descendants
                  .whereType<XmlElement>()
                  .where((e) => e.name.local == 't' && e.parent is XmlElement && (e.parent as XmlElement).name.local != 'rPh')
                  .map((e) => e.innerText)
                  .join(),
            );
    case 'str':
      value = v == null ? const EmptyValue() : TextValue(v);
    case 'b':
      value = v == null ? const EmptyValue() : BoolValue(v == '1' || v.toLowerCase() == 'true');
    case 'e':
      value = v == null ? const EmptyValue() : ErrorValue(v);
    case 'd':
      final d = v == null ? null : DateTime.tryParse(v);
      value = d == null ? (v == null ? const EmptyValue() : TextValue(v)) : NumberValue(_isoToSerial(d));
    default:
      final n = v == null || v.isEmpty ? null : double.tryParse(v);
      value = n == null ? (v == null || v.isEmpty ? const EmptyValue() : TextValue(v)) : NumberValue(n);
  }
  return SheetCell(value: value, formula: formula, style: style);
}

double _isoToSerial(DateTime d) {
  final base = DateTime.utc(1899, 12, 30);
  final days = DateTime.utc(d.year, d.month, d.day, d.hour, d.minute, d.second).difference(base).inSeconds / 86400;
  return days < 60 ? days - 1 : days;
}

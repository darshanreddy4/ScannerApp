import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../domain/sheet_model.dart';
import 'styles_xml.dart';
import 'xlsx_reader.dart';

const _mainNs = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const _relNs = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _worksheetType = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet';
const _worksheetContentType = 'application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml';

const _childOrder = [
  'sheetPr', 'dimension', 'sheetViews', 'sheetFormatPr', 'cols', 'sheetData', 'sheetCalcPr', 'sheetProtection', 'protectedRanges', 'scenarios', 'autoFilter', //
  'sortState', 'dataConsolidate', 'customSheetViews', 'mergeCells', 'phoneticPr', 'conditionalFormatting', 'dataValidations', 'hyperlinks', 'printOptions',
  'pageMargins', 'pageSetup', 'headerFooter', 'rowBreaks', 'colBreaks', 'customProperties', 'cellWatches', 'ignoredErrors', 'smartTags', 'drawing',
  'legacyDrawing', 'legacyDrawingHF', 'drawingHF', 'picture', 'oleObjects', 'controls', 'webPublishItems', 'tableParts', 'extLst',
];

/// A new, empty workbook with one sheet.
Workbook newWorkbook({String sheetName = 'Sheet1'}) {
  final a = Archive();
  void add(String name, String content) => a.addFile(ArchiveFile.bytes(name, utf8.encode(content)));
  add(
    '[Content_Types].xml',
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="$_worksheetContentType"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>',
  );
  add(
    '_rels/.rels',
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>',
  );
  add(
    'xl/workbook.xml',
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="$_mainNs" xmlns:r="$_relNs"><bookViews><workbookView/></bookViews>'
        '<sheets><sheet name="${const HtmlEscape(HtmlEscapeMode.attribute).convert(sheetName)}" sheetId="1" r:id="rId1"/></sheets></workbook>',
  );
  add(
    'xl/_rels/workbook.xml.rels',
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="$_worksheetType" Target="worksheets/sheet1.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>',
  );
  add(
    'xl/styles.xml',
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><styleSheet xmlns="$_mainNs"><fonts count="1"><font><sz val="11"/><color theme="1"/><name val="Calibri"/><family val="2"/></font></fonts>'
        '<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>'
        '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
        '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
        '<cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs>'
        '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>',
  );
  add('xl/worksheets/sheet1.xml', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="$_mainNs"><sheetData/></worksheet>');
  return readXlsx(Uint8List.fromList(ZipEncoder().encode(a)));
}

String _num(double v) => v == v.roundToDouble() && v.abs() < 1e15 ? v.toInt().toString() : v.toString();

/// Writes the workbook as .xlsx. Parts the app did not change are copied from the original file unchanged.
Uint8List writeXlsx(Workbook wb) {
  final source = wb.source;
  if (source == null) throw StateError('The workbook has no file to build on');
  final archive = ZipDecoder().decodeBytes(source);
  final files = <String, Uint8List>{
    for (final f in archive.files)
      if (f.isFile) f.name: f.readBytes()!,
  };
  XmlDocument parse(String name) => XmlDocument.parse(utf8.decode(files[name]!, allowMalformed: true));
  void put(String name, XmlDocument d) => files[name] = Uint8List.fromList(utf8.encode(d.toXmlString()));

  final anyDirty = wb.structureChanged || wb.sheets.any((s) => s.dirty || s.partPath == null) || wb.styles.hasNew;

  // Styles added in the app.
  if (wb.styles.hasNew && files.containsKey('xl/styles.xml')) {
    final doc = parse('xl/styles.xml');
    StylesXml(doc, parseThemeColors(files.containsKey('xl/theme/theme1.xml') ? parse('xl/theme/theme1.xml') : null)).addStyles(wb.styles);
    put('xl/styles.xml', doc);
  }

  // Sheet parts.
  final used = {for (final n in files.keys) n};
  var nextSheetNumber = 1;
  String freshPart() {
    while (used.contains('xl/worksheets/sheet$nextSheetNumber.xml')) {
      nextSheetNumber++;
    }
    final name = 'xl/worksheets/sheet$nextSheetNumber.xml';
    used.add(name);
    return name;
  }

  final newParts = <Sheet, String>{};
  for (final sheet in wb.sheets) {
    var path = sheet.partPath;
    if (path == null || !files.containsKey(path)) {
      path = freshPart();
      newParts[sheet] = path;
      sheet.partPath = path;
    } else if (!sheet.dirty) {
      continue;
    }
    final doc = newParts.containsKey(sheet)
        ? XmlDocument.parse('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="$_mainNs"><sheetData/></worksheet>')
        : parse(path);
    _writeSheet(doc, sheet);
    put(path, doc);
  }

  if (wb.structureChanged || newParts.isNotEmpty) _writeStructure(wb, files, newParts, parse, put);

  if (anyDirty) {
    // Excel rebuilds this list itself; a stale one makes it report a damaged file.
    files.remove('xl/calcChain.xml');
    if (files.containsKey('[Content_Types].xml')) {
      final ct = parse('[Content_Types].xml');
      ct.rootElement.children.removeWhere((c) => c is XmlElement && c.getAttribute('PartName') == '/xl/calcChain.xml');
      put('[Content_Types].xml', ct);
    }
    if (files.containsKey('xl/_rels/workbook.xml.rels')) {
      final rels = parse('xl/_rels/workbook.xml.rels');
      rels.rootElement.children.removeWhere((c) => c is XmlElement && (c.getAttribute('Type') ?? '').endsWith('/calcChain'));
      put('xl/_rels/workbook.xml.rels', rels);
    }
    final book = parse('xl/workbook.xml');
    _setFullCalc(book.rootElement);
    put('xl/workbook.xml', book);
  }

  final out = Archive();
  // The content types part goes first, as the format asks.
  final names = files.keys.toList()..sort((a, b) => a == '[Content_Types].xml' ? -1 : (b == '[Content_Types].xml' ? 1 : 0));
  for (final n in names) {
    out.addFile(ArchiveFile.bytes(n, files[n]!));
  }
  return Uint8List.fromList(ZipEncoder().encode(out));
}

void _setFullCalc(XmlElement root) {
  var calc = root.childElements.where((e) => e.name.local == 'calcPr').firstOrNull;
  if (calc == null) {
    calc = XmlElement(XmlName('calcPr'));
    const before = [
      'calcPr',
      'oleSize',
      'customWorkbookViews',
      'pivotCaches',
      'smartTagPr',
      'smartTagTypes',
      'webPublishing',
      'fileRecoveryPr',
      'webPublishObjects',
      'extLst',
    ];
    final at = root.children.indexWhere((c) => c is XmlElement && before.contains(c.name.local));
    if (at < 0) {
      root.children.add(calc);
    } else {
      root.children.insert(at, calc);
    }
  }
  calc.setAttribute('fullCalcOnLoad', '1');
}

void _setChild(XmlElement root, String name, XmlElement? replacement) {
  final existing = root.childElements.where((e) => e.name.local == name).firstOrNull;
  if (existing != null) {
    if (replacement == null) {
      existing.remove();
    } else {
      existing.replace(replacement);
    }
    return;
  }
  if (replacement == null) return;
  final rank = _childOrder.indexOf(name);
  final at = root.children.indexWhere((c) => c is XmlElement && _childOrder.indexOf(c.name.local) > rank);
  if (at < 0) {
    root.children.add(replacement);
  } else {
    root.children.insert(at, replacement);
  }
}

void _writeSheet(XmlDocument doc, Sheet sheet) {
  final root = doc.rootElement;

  final rowSet = <int>{...sheet.rowHeights.keys, ...sheet.hiddenRows, ...sheet.rowStyles.keys};
  final byRow = <int, List<int>>{};
  for (final k in sheet.cells.keys) {
    final r = CellRef.rowOf(k);
    rowSet.add(r);
    (byRow[r] ??= []).add(k);
  }
  final rows = rowSet.toList()..sort();

  final b = XmlBuilder();
  b.element(
    'sheetData',
    nest: () {
      for (final r in rows) {
        final attrs = <String, String>{'r': '${r + 1}'};
        if (sheet.rowHeights.containsKey(r)) {
          attrs['ht'] = _num(sheet.rowHeights[r]!);
          attrs['customHeight'] = '1';
        }
        if (sheet.hiddenRows.contains(r)) attrs['hidden'] = '1';
        if (sheet.rowStyles.containsKey(r)) {
          attrs['s'] = '${sheet.rowStyles[r]}';
          attrs['customFormat'] = '1';
        }
        b.element(
          'row',
          attributes: attrs,
          nest: () {
            final keys = (byRow[r] ?? const <int>[])..sort();
            for (final k in keys) {
              _writeCell(b, r, CellRef.colOf(k), sheet.cells[k]!);
            }
          },
        );
      }
    },
  );
  _setChild(root, 'sheetData', b.buildFragment().children.whereType<XmlElement>().first.copy());

  final lastRow = sheet.lastRow, lastCol = sheet.lastCol;
  final dim = lastRow < 0 ? 'A1' : (lastRow == 0 && lastCol == 0 ? 'A1' : 'A1:${CellRef.a1(lastRow, lastCol)}');
  _setChild(root, 'dimension', XmlElement(XmlName('dimension'), [XmlAttribute(XmlName('ref'), dim)]));

  if (sheet.colsDirty) _setChild(root, 'cols', _colsElement(sheet));
  if (sheet.mergesDirty) {
    _setChild(
      root,
      'mergeCells',
      sheet.merges.isEmpty
          ? null
          : XmlElement(
              XmlName('mergeCells'),
              [XmlAttribute(XmlName('count'), '${sheet.merges.length}')],
              [
                for (final m in sheet.merges) XmlElement(XmlName('mergeCell'), [XmlAttribute(XmlName('ref'), m.toString())]),
              ],
            ),
    );
  }
}

XmlElement? _colsElement(Sheet sheet) {
  final cols = <int>{...sheet.colWidths.keys, ...sheet.hiddenCols, ...sheet.colStyles.keys}.toList()..sort();
  if (cols.isEmpty) return null;
  final out = <XmlElement>[];
  int? start, prev;
  String? sig;
  Map<String, String>? attrs;
  void flush() {
    if (start == null) return;
    out.add(
      XmlElement(XmlName('col'), [
        XmlAttribute(XmlName('min'), '${start + 1}'),
        XmlAttribute(XmlName('max'), '${prev! + 1}'),
        for (final e in attrs!.entries) XmlAttribute(XmlName(e.key), e.value),
      ]),
    );
  }

  for (final c in cols) {
    final a = <String, String>{'width': _num(sheet.colWidths[c] ?? Sheet.defaultColWidth)};
    if (sheet.colWidths.containsKey(c)) a['customWidth'] = '1';
    if (sheet.hiddenCols.contains(c)) a['hidden'] = '1';
    if (sheet.colStyles.containsKey(c)) a['style'] = '${sheet.colStyles[c]}';
    final s = a.toString();
    if (start != null && prev == c - 1 && s == sig) {
      prev = c;
    } else {
      flush();
      start = prev = c;
      sig = s;
      attrs = a;
    }
  }
  flush();
  return XmlElement(XmlName('cols'), const [], out);
}

void _writeCell(XmlBuilder b, int row, int col, SheetCell cell) {
  final attrs = <String, String>{'r': CellRef.a1(row, col)};
  if (cell.style != 0) attrs['s'] = '${cell.style}';
  final v = cell.value;
  final hasFormula = cell.formula != null;
  String? inline;
  String? valueText;
  switch (v) {
    case EmptyValue():
      break;
    case TextValue(:final text):
      if (hasFormula) {
        attrs['t'] = 'str';
        valueText = text;
      } else {
        attrs['t'] = 'inlineStr';
        inline = text;
      }
    case NumberValue(:final number):
      valueText = _num(number);
    case BoolValue(:final flag):
      attrs['t'] = 'b';
      valueText = flag ? '1' : '0';
    case ErrorValue(:final code):
      attrs['t'] = 'e';
      valueText = code;
  }
  b.element(
    'c',
    attributes: attrs,
    nest: () {
      if (hasFormula) b.element('f', nest: cell.formula!);
      if (inline != null) {
        b.element(
          'is',
          nest: () => b.element('t', attributes: {'xml:space': 'preserve'}, nest: inline!),
        );
      } else if (valueText != null) {
        b.element('v', nest: valueText);
      }
    },
  );
}

/// Updates the workbook's sheet list, the relationships and the content types after sheets were added, removed, renamed or reordered.
void _writeStructure(
  Workbook wb,
  Map<String, Uint8List> files,
  Map<Sheet, String> newParts,
  XmlDocument Function(String) parse,
  void Function(String, XmlDocument) put,
) {
  final book = parse('xl/workbook.xml');
  final root = book.rootElement;
  if (root.getAttribute('xmlns:r') == null) root.setAttribute('xmlns:r', _relNs);
  final relsDoc = parse('xl/_rels/workbook.xml.rels');
  final relsRoot = relsDoc.rootElement;
  final ct = parse('[Content_Types].xml');

  final sheetsEl = root.childElements.firstWhere((e) => e.name.local == 'sheets');
  final byPath = <String, XmlElement>{};
  final ridToPath = <String, String>{};
  for (final r in relsRoot.childElements) {
    final id = r.getAttribute('Id'), target = r.getAttribute('Target');
    if (id != null && target != null) ridToPath[id] = resolveTarget('xl/workbook.xml', target);
  }
  var maxId = 0;
  for (final s in sheetsEl.childElements) {
    final rid = s.attributes.where((a) => a.name.local == 'id').map((a) => a.value).firstOrNull;
    if (rid != null && ridToPath[rid] != null) byPath[ridToPath[rid]!] = s;
    maxId = [maxId, int.tryParse(s.getAttribute('sheetId') ?? '') ?? 0].reduce((a, b) => a > b ? a : b);
  }

  final keep = {
    for (final s in wb.sheets)
      if (s.partPath != null) s.partPath!,
  };
  // Removed sheets lose their part, relationship and content type.
  for (final entry in byPath.entries) {
    if (keep.contains(entry.key)) continue;
    files.remove(entry.key);
    final relName = entry.key.replaceFirst(RegExp(r'([^/]+)$'), r'_rels/$1.rels');
    files.remove(relName);
    relsRoot.children.removeWhere((c) => c is XmlElement && ridToPath[c.getAttribute('Id')] == entry.key);
    ct.rootElement.children.removeWhere((c) => c is XmlElement && c.getAttribute('PartName') == '/${entry.key}');
  }

  var nextRid = 1;
  String freshRid() {
    while (relsRoot.childElements.any((e) => e.getAttribute('Id') == 'rId$nextRid')) {
      nextRid++;
    }
    return 'rId${nextRid++}';
  }

  final built = <XmlElement>[];
  for (final sheet in wb.sheets) {
    final path = sheet.partPath!;
    XmlElement el;
    final existing = byPath[path];
    if (existing != null) {
      el = existing.copy();
    } else {
      final rid = freshRid();
      relsRoot.children.add(
        XmlElement(XmlName('Relationship'), [
          XmlAttribute(XmlName('Id'), rid),
          XmlAttribute(XmlName('Type'), _worksheetType),
          XmlAttribute(XmlName('Target'), path.replaceFirst('xl/', '')),
        ]),
      );
      ct.rootElement.children.add(
        XmlElement(XmlName('Override'), [XmlAttribute(XmlName('PartName'), '/$path'), XmlAttribute(XmlName('ContentType'), _worksheetContentType)]),
      );
      el = XmlElement(XmlName('sheet'), [
        XmlAttribute(XmlName('name'), sheet.name),
        XmlAttribute(XmlName('sheetId'), '${++maxId}'),
        XmlAttribute(XmlName('r:id'), rid),
      ]);
    }
    el.setAttribute('name', sheet.name);
    if (sheet.hidden) {
      el.setAttribute('state', 'hidden');
    } else {
      el.removeAttribute('state');
    }
    built.add(el);
  }
  sheetsEl.children
    ..clear()
    ..addAll(built);

  // Names tied to a sheet position or to a removed sheet would point to the wrong place.
  final names = root.childElements.where((e) => e.name.local == 'definedNames').firstOrNull;
  if (names != null) {
    final sheetNames = {for (final s in wb.sheets) s.name};
    names.children.removeWhere((c) {
      if (c is! XmlElement) return false;
      if (c.getAttribute('localSheetId') != null) return true;
      final text = c.innerText;
      final m = RegExp(r"^'?([^'!]+)'?!").firstMatch(text);
      return m != null && !sheetNames.contains(m.group(1));
    });
    if (names.childElements.isEmpty) names.remove();
  }
  final views = root.childElements.where((e) => e.name.local == 'bookViews').firstOrNull;
  for (final v in views?.childElements ?? const <XmlElement>[]) {
    v.removeAttribute('activeTab');
    v.removeAttribute('firstSheet');
  }

  put('xl/workbook.xml', book);
  put('xl/_rels/workbook.xml.rels', relsDoc);
  put('[Content_Types].xml', ct);
}

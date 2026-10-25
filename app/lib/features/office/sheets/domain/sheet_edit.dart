import 'dart:math' as math;

import 'formula.dart';
import 'formula_refs.dart';
import 'number_format.dart';
import 'sheet_model.dart';

/// Cells copied from a sheet, ready to be pasted elsewhere.
class ClipBlock {
  const ClipBlock({
    required this.rows,
    required this.cols,
    required this.cells,
    required this.originRow,
    required this.originCol,
    this.cut = false,
    this.sourceSheet,
  });

  final int rows;
  final int cols;

  /// Row by row; null for a cell that was empty.
  final List<List<SheetCell?>> cells;
  final int originRow;
  final int originCol;
  final bool cut;
  final Sheet? sourceSheet;

  /// Tab-separated text of the values, for other apps.
  String toText(StyleLookup styles, {bool date1904 = false}) {
    final b = StringBuffer();
    for (var r = 0; r < rows; r++) {
      b.writeAll([for (var c = 0; c < cols; c++) displayText(cells[r][c], styles, date1904: date1904)], '\t');
      if (r < rows - 1) b.write('\n');
    }
    return b.toString();
  }
}

typedef StyleLookup = CellStyle Function(int index);

/// What a cell shows, as text.
String displayText(SheetCell? cell, StyleLookup styles, {bool date1904 = false}) {
  if (cell == null) return '';
  return switch (cell.value) {
    EmptyValue() => '',
    TextValue(:final text) => text,
    NumberValue(:final number) => NumberFormatter.format(number, styles(cell.style).numFmt, date1904: date1904),
    BoolValue(:final flag) => flag ? 'TRUE' : 'FALSE',
    ErrorValue(:final code) => code,
  };
}

/// The cell a typed text turns into.
class ParsedInput {
  const ParsedInput(this.value, {this.formula, this.numFmt});
  final CellValue value;
  final String? formula;

  /// A format to apply when the cell has none yet, such as a percent or a date.
  final String? numFmt;
}

final _plainNumber = RegExp(r'^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$');
final _groupedNumber = RegExp(r'^[+-]?\d{1,3}(,\d{3})+(\.\d+)?$');
final _isoDate = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$');

ParsedInput parseInput(String text) {
  if (text.isEmpty) return const ParsedInput(EmptyValue());
  if (text.startsWith("'")) return ParsedInput(TextValue(text.substring(1)));
  if (text.startsWith('=') && text.length > 1) return ParsedInput(const EmptyValue(), formula: text.substring(1).trim());
  final t = text.trim();
  if (_plainNumber.hasMatch(t)) return ParsedInput(NumberValue(double.parse(t)));
  if (_groupedNumber.hasMatch(t)) return ParsedInput(NumberValue(double.parse(t.replaceAll(',', ''))));
  if (t.endsWith('%')) {
    final body = t.substring(0, t.length - 1).trim();
    if (_plainNumber.hasMatch(body)) return ParsedInput(NumberValue(double.parse(body) / 100), numFmt: body.contains('.') ? '0.00%' : '0%');
  }
  final up = t.toUpperCase();
  if (up == 'TRUE' || up == 'FALSE') return ParsedInput(BoolValue(up == 'TRUE'));
  final d = _isoDate.firstMatch(t);
  if (d != null) {
    final y = int.parse(d.group(1)!), m = int.parse(d.group(2)!), day = int.parse(d.group(3)!);
    final date = DateTime.utc(y, m, day);
    if (date.month == m && date.day == day && y >= 1900) return ParsedInput(NumberValue(NumberFormatter.dateToSerial(date)), numFmt: 'yyyy-mm-dd');
  }
  return ParsedInput(TextValue(text));
}

class _State {
  _State(this.order, this.names, this.hidden, this.contents);
  final List<Sheet> order;
  final List<String> names;
  final List<bool> hidden;
  final Map<Sheet, Sheet> contents;
}

/// Edits a [Workbook] and remembers each change so it can be undone.
class SheetEditor {
  SheetEditor(this.workbook);

  final Workbook workbook;
  final List<_State> _undo = [];
  final List<_State> _redo = [];
  static const _maxHistory = 40;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// Set when something changed since the last save.
  bool modified = false;

  _State _capture(Iterable<Sheet> sheets) => _State(
    List.of(workbook.sheets),
    [for (final s in workbook.sheets) s.name],
    [for (final s in workbook.sheets) s.hidden],
    {for (final s in sheets) s: s.copy()},
  );

  void _restore(_State st) {
    workbook.sheets
      ..clear()
      ..addAll(st.order);
    for (var i = 0; i < st.order.length; i++) {
      st.order[i].name = st.names[i];
      st.order[i].hidden = st.hidden[i];
    }
    st.contents.forEach((sheet, copy) => sheet.assignFrom(copy));
  }

  void _checkpoint(Iterable<Sheet> sheets) {
    _undo.add(_capture(sheets));
    if (_undo.length > _maxHistory) _undo.removeAt(0);
    _redo.clear();
    modified = true;
  }

  void undo() {
    if (_undo.isEmpty) return;
    final st = _undo.removeLast();
    _redo.add(_capture(st.contents.keys));
    _restore(st);
    _recalc();
    modified = true;
  }

  void redo() {
    if (_redo.isEmpty) return;
    final st = _redo.removeLast();
    _undo.add(_capture(st.contents.keys));
    _restore(st);
    _recalc();
    modified = true;
  }

  void _recalc() => FormulaEngine(workbook).recalculateAll();

  int _style(Sheet sheet, SheetCell? cell, CellStyle Function(CellStyle) change) {
    final from = cell?.style ?? 0;
    return workbook.styles.indexOf(change(workbook.styles.at(from)), from: from);
  }

  // ------------------------------------------------------------------ cells

  /// Puts what the user typed into a cell.
  void setInput(Sheet sheet, int row, int col, String text) {
    final old = sheet.cells[CellRef.key(row, col)];
    final parsed = parseInput(text);
    _checkpoint([sheet]);
    var style = old?.style ?? 0;
    if (parsed.numFmt != null && workbook.styles.at(style).numFmt == 'General') {
      style = _style(sheet, old, (s) => s.copyWith(numFmt: parsed.numFmt));
    }
    final cell = SheetCell(value: parsed.value, formula: parsed.formula, style: style);
    sheet.setCell(row, col, cell);
    _recalc();
  }

  /// Changes how every cell of [region] looks. Cells that are empty get the look too.
  void setStyle(Sheet sheet, MergeRange region, CellStyle Function(CellStyle) change) {
    _checkpoint([sheet]);
    final r2 = math.min(region.lastRow, math.max(sheet.lastRow, region.firstRow) + 200);
    final c2 = math.min(region.lastCol, math.max(sheet.lastCol, region.firstCol) + 30);
    final done = <int, int>{};
    for (var r = region.firstRow; r <= r2; r++) {
      for (var c = region.firstCol; c <= c2; c++) {
        final cell = sheet.cells[CellRef.key(r, c)];
        final style = done[cell?.style ?? 0] ??= _style(sheet, cell, change);
        sheet.setCell(r, c, (cell ?? const SheetCell()).copyWith(style: style));
      }
    }
    sheet.dirty = true;
  }

  void clear(Sheet sheet, MergeRange region) {
    _checkpoint([sheet]);
    for (final k in sheet.cells.keys.toList()) {
      final r = CellRef.rowOf(k), c = CellRef.colOf(k);
      if (!region.contains(r, c)) continue;
      sheet.setCell(r, c, SheetCell(style: sheet.cells[k]!.style));
    }
    sheet.dirty = true;
    _recalc();
  }

  ClipBlock copy(Sheet sheet, MergeRange region, {bool cut = false}) {
    final rows = region.lastRow - region.firstRow + 1, cols = region.lastCol - region.firstCol + 1;
    return ClipBlock(
      rows: rows,
      cols: cols,
      cells: [
        for (var r = 0; r < rows; r++) [for (var c = 0; c < cols; c++) sheet.cells[CellRef.key(region.firstRow + r, region.firstCol + c)]],
      ],
      originRow: region.firstRow,
      originCol: region.firstCol,
      cut: cut,
      sourceSheet: sheet,
    );
  }

  /// Pastes [block] with its top-left corner at ([row], [col]). Formulas move with the block.
  void paste(Sheet sheet, int row, int col, ClipBlock block) {
    final touched = [sheet, if (block.cut && block.sourceSheet != null && block.sourceSheet != sheet) block.sourceSheet!];
    _checkpoint(touched);
    final dr = row - block.originRow, dc = col - block.originCol;
    if (block.cut && block.sourceSheet != null) {
      for (var r = 0; r < block.rows; r++) {
        for (var c = 0; c < block.cols; c++) {
          block.sourceSheet!.setCell(block.originRow + r, block.originCol + c, const SheetCell());
        }
      }
    }
    for (var r = 0; r < block.rows; r++) {
      for (var c = 0; c < block.cols; c++) {
        final tr = row + r, tc = col + c;
        if (tr >= CellRef.maxRows || tc >= CellRef.maxCols) continue;
        final src = block.cells[r][c];
        if (src == null) {
          sheet.setCell(tr, tc, const SheetCell());
        } else {
          // Cut cells keep their formulas as they are; copies behave like copied formulas in Excel.
          final f = src.formula == null || block.cut ? src.formula : shiftFormula(src.formula!, dr, dc);
          sheet.setCell(tr, tc, src.copyWith(formula: f));
        }
      }
    }
    _recalc();
  }

  /// Fills the cells below or to the right of [region] by repeating its first row or column.
  void fill(Sheet sheet, MergeRange region, {required bool down}) {
    _checkpoint([sheet]);
    if (down) {
      for (var c = region.firstCol; c <= region.lastCol; c++) {
        final src = sheet.cells[CellRef.key(region.firstRow, c)];
        for (var r = region.firstRow + 1; r <= region.lastRow; r++) {
          final f = src?.formula == null ? null : shiftFormula(src!.formula!, r - region.firstRow, 0);
          sheet.setCell(r, c, src == null ? const SheetCell() : src.copyWith(formula: f));
        }
      }
    } else {
      for (var r = region.firstRow; r <= region.lastRow; r++) {
        final src = sheet.cells[CellRef.key(r, region.firstCol)];
        for (var c = region.firstCol + 1; c <= region.lastCol; c++) {
          final f = src?.formula == null ? null : shiftFormula(src!.formula!, 0, c - region.firstCol);
          sheet.setCell(r, c, src == null ? const SheetCell() : src.copyWith(formula: f));
        }
      }
    }
    _recalc();
  }

  void merge(Sheet sheet, MergeRange region) {
    if (region.isSingle) return;
    _checkpoint([sheet]);
    sheet.merges.removeWhere(region.overlaps);
    sheet.merges.add(region);
    // Only the top-left cell keeps its content, as in Excel.
    for (final k in sheet.cells.keys.toList()) {
      final r = CellRef.rowOf(k), c = CellRef.colOf(k);
      if (region.contains(r, c) && !(r == region.firstRow && c == region.firstCol)) sheet.cells[k] = SheetCell(style: sheet.cells[k]!.style);
    }
    sheet.mergesDirty = true;
    sheet.dirty = true;
    _recalc();
  }

  void unmerge(Sheet sheet, MergeRange region) {
    final hit = sheet.merges.where(region.overlaps).toList();
    if (hit.isEmpty) return;
    _checkpoint([sheet]);
    sheet.merges.removeWhere(hit.contains);
    sheet.mergesDirty = true;
    sheet.dirty = true;
  }

  void setColumnWidth(Sheet sheet, int col, double width) {
    _checkpoint([sheet]);
    sheet.colWidths[col] = width.clamp(1.0, 255.0);
    sheet.colsDirty = true;
    sheet.dirty = true;
  }

  void setRowHeight(Sheet sheet, int row, double height) {
    _checkpoint([sheet]);
    sheet.rowHeights[row] = height.clamp(4.0, 409.0);
    sheet.dirty = true;
  }

  void setHiddenRows(Sheet sheet, Iterable<int> rows, bool hide) {
    _checkpoint([sheet]);
    hide ? sheet.hiddenRows.addAll(rows) : sheet.hiddenRows.removeAll(rows);
    sheet.dirty = true;
  }

  void setHiddenCols(Sheet sheet, Iterable<int> cols, bool hide) {
    _checkpoint([sheet]);
    hide ? sheet.hiddenCols.addAll(cols) : sheet.hiddenCols.removeAll(cols);
    sheet.colsDirty = true;
    sheet.dirty = true;
  }

  void setFreeze(Sheet sheet, int rows, int cols) {
    _checkpoint([sheet]);
    sheet.frozenRows = rows;
    sheet.frozenCols = cols;
    sheet.dirty = true;
  }

  /// Sorts the rows of [region] by one of its columns. Text sorts ignoring case, numbers before text, empty cells last.
  void sort(Sheet sheet, MergeRange region, {required int byCol, required bool ascending, required bool hasHeader}) {
    final first = region.firstRow + (hasHeader ? 1 : 0);
    if (first >= region.lastRow) return;
    _checkpoint([sheet]);
    final rows = [
      for (var r = first; r <= region.lastRow; r++) (row: r, cells: [for (var c = region.firstCol; c <= region.lastCol; c++) sheet.cells[CellRef.key(r, c)]]),
    ];
    Object? keyOf(SheetCell? c) => switch (c?.value) {
      NumberValue(:final number) => number,
      TextValue(:final text) => text.toLowerCase(),
      BoolValue(:final flag) => flag ? 1.0 : 0.0,
      _ => null,
    };
    int cmp(Object? a, Object? b) {
      if (a == null && b == null) return 0;
      if (a == null) return 1; // empty last in both directions
      if (b == null) return -1;
      if (a is double && b is double) return a.compareTo(b);
      if (a is String && b is String) return a.compareTo(b);
      return a is double ? -1 : 1;
    }

    final idx = byCol - region.firstCol;
    final sorted = List.of(rows);
    sorted.sort((a, b) {
      final ka = keyOf(a.cells[idx]), kb = keyOf(b.cells[idx]);
      if (ka == null || kb == null) return cmp(ka, kb);
      final c = cmp(ka, kb);
      return ascending ? c : -c;
    });
    for (var i = 0; i < sorted.length; i++) {
      final target = first + i;
      for (var c = 0; c < sorted[i].cells.length; c++) {
        final src = sorted[i].cells[c];
        final f = src?.formula == null ? null : shiftFormula(src!.formula!, target - sorted[i].row, 0);
        sheet.setCell(target, region.firstCol + c, src == null ? const SheetCell() : src.copyWith(formula: f));
      }
    }
    _recalc();
  }

  // ------------------------------------------------------- rows and columns

  void insertRows(Sheet sheet, int at, [int count = 1]) => _shift(sheet, rows: true, at: at, delta: count);
  void deleteRows(Sheet sheet, int at, [int count = 1]) => _shift(sheet, rows: true, at: at, delta: -count);
  void insertCols(Sheet sheet, int at, [int count = 1]) => _shift(sheet, rows: false, at: at, delta: count);
  void deleteCols(Sheet sheet, int at, [int count = 1]) => _shift(sheet, rows: false, at: at, delta: -count);

  void _shift(Sheet sheet, {required bool rows, required int at, required int delta}) {
    _checkpoint(workbook.sheets);
    final n = delta.abs();
    final limit = rows ? CellRef.maxRows : CellRef.maxCols;
    int? move(int i) {
      if (delta > 0) return i >= at ? i + n : i;
      if (i < at) return i;
      if (i < at + n) return null;
      return i - n;
    }

    final moved = <int, SheetCell>{};
    for (final e in sheet.cells.entries) {
      final r = CellRef.rowOf(e.key), c = CellRef.colOf(e.key);
      final to = move(rows ? r : c);
      if (to == null || to >= limit) continue;
      moved[rows ? CellRef.key(to, c) : CellRef.key(r, to)] = e.value;
    }
    sheet.cells
      ..clear()
      ..addAll(moved);

    Map<int, T> shiftMap<T>(Map<int, T> m) => {
      for (final e in m.entries)
        if (move(e.key) case final to?) to: e.value,
    };
    Set<int> shiftSet(Set<int> s) => {
      for (final i in s)
        if (move(i) case final to?) to,
    };
    void replaceMap<T>(Map<int, T> target, Map<int, T> value) {
      target
        ..clear()
        ..addAll(value);
    }

    if (rows) {
      replaceMap(sheet.rowHeights, shiftMap(sheet.rowHeights));
      replaceMap(sheet.rowStyles, shiftMap(sheet.rowStyles));
      final h = shiftSet(sheet.hiddenRows);
      sheet.hiddenRows
        ..clear()
        ..addAll(h);
      if (delta < 0 && sheet.frozenRows > at) sheet.frozenRows = math.max(at, sheet.frozenRows - n);
    } else {
      replaceMap(sheet.colWidths, shiftMap(sheet.colWidths));
      replaceMap(sheet.colStyles, shiftMap(sheet.colStyles));
      final h = shiftSet(sheet.hiddenCols);
      sheet.hiddenCols
        ..clear()
        ..addAll(h);
      sheet.colsDirty = true;
      if (delta < 0 && sheet.frozenCols > at) sheet.frozenCols = math.max(at, sheet.frozenCols - n);
    }

    final merges = <MergeRange>[];
    for (final m in sheet.merges) {
      final a = rows ? m.firstRow : m.firstCol, b = rows ? m.lastRow : m.lastCol;
      final (na, nb) = _mapSpan(a, b, at, delta);
      if (na == null) continue;
      final out = rows ? MergeRange(na, m.firstCol, nb!, m.lastCol) : MergeRange(m.firstRow, na, m.lastRow, nb!);
      if (!out.isSingle) merges.add(out);
    }
    sheet.merges
      ..clear()
      ..addAll(merges);
    sheet.mergesDirty = true;
    sheet.dirty = true;

    // Every formula that points into this sheet follows the move.
    for (final s in workbook.sheets) {
      for (final e in s.cells.entries.toList()) {
        final f = e.value.formula;
        if (f == null) continue;
        final adjusted = _adjustRefs(f, s, sheet, rows: rows, at: at, delta: delta);
        if (adjusted != f) {
          s.cells[e.key] = e.value.copyWith(formula: adjusted);
          s.dirty = true;
        }
      }
    }
    _recalc();
  }

  /// Where the span [a]..[b] ends up when rows or columns are inserted or deleted at [at]; null when it is gone.
  static (int?, int?) _mapSpan(int a, int b, int at, int delta) {
    if (delta > 0) return (a >= at ? a + delta : a, b >= at ? b + delta : b);
    final n = -delta;
    final na = a < at ? a : (a >= at + n ? a - n : at);
    final nb = b < at ? b : (b >= at + n ? b - n : at - 1);
    if (na > nb) return (null, null);
    return (na, nb);
  }

  static final _refWithSheet = RegExp(
    r"(?<![A-Za-z0-9_.$])((?:'(?:[^']|'')+'|[A-Za-z_][A-Za-z0-9_.]*)!)?(\$?)([A-Za-z]{1,3})(\$?)(\d{1,7})(?::(\$?)([A-Za-z]{1,3})(\$?)(\d{1,7}))?(?![A-Za-z0-9_(.])",
  );

  static String _sheetOfPrefix(String prefix) {
    var name = prefix.substring(0, prefix.length - 1);
    if (name.startsWith("'")) name = name.substring(1, name.length - 1).replaceAll("''", "'");
    return name;
  }

  String _adjustRefs(String formula, Sheet owner, Sheet target, {required bool rows, required int at, required int delta}) {
    return mapFormulaOutsideText(formula, (part) {
      return part.replaceAllMapped(_refWithSheet, (m) {
        final prefix = m.group(1);
        final refSheet = prefix == null ? owner.name : _sheetOfPrefix(prefix);
        if (refSheet.toLowerCase() != target.name.toLowerCase()) return m.group(0)!;
        final col1 = CellRef.columnIndex(m.group(3)!), row1 = int.parse(m.group(5)!) - 1;
        if (col1 < 0) return m.group(0)!;
        final hasEnd = m.group(7) != null;
        final col2 = hasEnd ? CellRef.columnIndex(m.group(7)!) : col1, row2 = hasEnd ? int.parse(m.group(9)!) - 1 : row1;
        final a = rows ? row1 : col1, b = rows ? row2 : col2;
        final (na, nb) = _mapSpan(math.min(a, b), math.max(a, b), at, delta);
        if (na == null) return '#REF!';
        String one(String colAbs, int col, String rowAbs, int row) => '$colAbs${CellRef.columnName(col)}$rowAbs${row + 1}';
        final c1 = rows ? col1 : na, r1 = rows ? na : row1;
        final c2 = rows ? col2 : nb!, r2 = rows ? nb! : row2;
        final start = one(m.group(2)!, c1, m.group(4)!, r1);
        if (!hasEnd) return '${prefix ?? ''}$start';
        return '${prefix ?? ''}$start:${one(m.group(6)!, c2, m.group(8)!, r2)}';
      });
    });
  }

  // ------------------------------------------------------------------ sheets

  String uniqueName(String wanted) {
    var base = _cleanName(wanted);
    if (base.isEmpty) base = 'Sheet';
    if (workbook.sheetNamed(base) == null) return base;
    var i = 2;
    while (workbook.sheetNamed('$base ($i)') != null) {
      i++;
    }
    return '$base ($i)';
  }

  static String _cleanName(String n) {
    var s = n.replaceAll(RegExp(r'[\\/?*\[\]:]'), '').trim();
    if (s.startsWith("'")) s = s.substring(1);
    if (s.endsWith("'")) s = s.substring(0, s.length - 1);
    return s.length > 31 ? s.substring(0, 31) : s;
  }

  Sheet addSheet([String? name]) {
    _checkpoint(const []);
    final sheet = Sheet(name: uniqueName(name ?? 'Sheet${workbook.sheets.length + 1}'))..dirty = true;
    workbook.sheets.add(sheet);
    workbook.structureChanged = true;
    return sheet;
  }

  Sheet duplicateSheet(Sheet sheet) {
    _checkpoint(const []);
    final copy = sheet.copy(name: uniqueName('${sheet.name} copy'))
      ..partPath = null
      ..dirty = true
      ..colsDirty = true
      ..mergesDirty = true;
    workbook.sheets.insert(workbook.sheets.indexOf(sheet) + 1, copy);
    workbook.structureChanged = true;
    return copy;
  }

  /// Returns false when the name is empty or taken by another sheet.
  bool renameSheet(Sheet sheet, String name) {
    final clean = _cleanName(name);
    if (clean.isEmpty) return false;
    final other = workbook.sheetNamed(clean);
    if (other != null && other != sheet) return false;
    if (clean == sheet.name) return true;
    _checkpoint(workbook.sheets);
    final old = sheet.name;
    sheet.name = clean;
    final quoted = RegExp(r'^[A-Za-z_][A-Za-z0-9_.]*$').hasMatch(clean) && CellRef.parse(clean) == null ? clean : "'${clean.replaceAll("'", "''")}'";
    final re = RegExp(r"(?<![A-Za-z0-9_.$'])(?:'((?:[^']|'')+)'|([A-Za-z_][A-Za-z0-9_.]*))!");
    for (final s in workbook.sheets) {
      for (final e in s.cells.entries.toList()) {
        final f = e.value.formula;
        if (f == null) continue;
        final updated = mapFormulaOutsideText(f, (part) {
          return part.replaceAllMapped(re, (m) {
            final ref = (m.group(1)?.replaceAll("''", "'") ?? m.group(2)!);
            return ref.toLowerCase() == old.toLowerCase() ? '$quoted!' : m.group(0)!;
          });
        });
        if (updated != f) {
          s.cells[e.key] = e.value.copyWith(formula: updated);
          s.dirty = true;
        }
      }
    }
    workbook.structureChanged = true;
    return true;
  }

  /// Returns false when it is the only visible sheet.
  bool deleteSheet(Sheet sheet) {
    if (workbook.visibleSheets.length <= 1 && !sheet.hidden) return false;
    _checkpoint(workbook.sheets);
    final re = RegExp(r"(?<![A-Za-z0-9_.$'])(?:'(?:[^']|'')+'|[A-Za-z_][A-Za-z0-9_.]*)!\$?[A-Za-z]{1,3}\$?\d{1,7}(?::\$?[A-Za-z]{1,3}\$?\d{1,7})?");
    workbook.sheets.remove(sheet);
    for (final s in workbook.sheets) {
      for (final e in s.cells.entries.toList()) {
        final f = e.value.formula;
        if (f == null) continue;
        final updated = mapFormulaOutsideText(f, (part) {
          return part.replaceAllMapped(re, (m) {
            final text = m.group(0)!;
            final name = _sheetOfPrefix(text.substring(0, text.indexOf('!') + 1));
            return name.toLowerCase() == sheet.name.toLowerCase() ? '#REF!' : text;
          });
        });
        if (updated != f) {
          s.cells[e.key] = e.value.copyWith(formula: updated);
          s.dirty = true;
        }
      }
    }
    workbook.structureChanged = true;
    _recalc();
    return true;
  }

  void moveSheet(int from, int to) {
    if (from == to || from < 0 || to < 0 || from >= workbook.sheets.length || to >= workbook.sheets.length) return;
    _checkpoint(const []);
    workbook.sheets.insert(to, workbook.sheets.removeAt(from));
    workbook.structureChanged = true;
  }

  // ------------------------------------------------------------------ search

  /// Cells whose shown text contains [query], in reading order.
  List<({int row, int col})> find(Sheet sheet, String query, {bool matchCase = false}) {
    if (query.isEmpty) return const [];
    final q = matchCase ? query : query.toLowerCase();
    final keys = sheet.cells.keys.toList()..sort();
    final out = <({int row, int col})>[];
    for (final k in keys) {
      var text = displayText(sheet.cells[k], workbook.styles.at, date1904: workbook.date1904);
      final f = sheet.cells[k]?.formula;
      if (f != null) text = '$text\n$f';
      if (!matchCase) text = text.toLowerCase();
      if (text.contains(q)) out.add((row: CellRef.rowOf(k), col: CellRef.colOf(k)));
    }
    return out;
  }
}

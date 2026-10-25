import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

import '../../../../core/error/failures.dart';
import '../data/csv.dart';
import '../data/sheet_renderer.dart';
import '../data/xlsx_reader.dart';
import '../data/xlsx_writer.dart';
import '../domain/formula.dart';
import '../domain/sheet_edit.dart';
import '../domain/sheet_model.dart';

enum SelectionKind { cells, rows, cols }

enum SheetExportFormat {
  xlsx('Excel workbook (.xlsx)', 'xlsx', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'),
  csv('This sheet as CSV (.csv)', 'csv', 'text/csv'),
  pdf('PDF (all sheets)', 'pdf', 'application/pdf');

  const SheetExportFormat(this.label, this.extension, this.mimeType);
  final String label;
  final String extension;
  final String mimeType;
}

class SheetState extends Equatable {
  const SheetState({
    this.loading = true,
    this.version = 0,
    this.sheetIndex = 0,
    this.row = 0,
    this.col = 0,
    this.anchorRow,
    this.anchorCol,
    this.kind = SelectionKind.cells,
    this.rangeMode = false,
    this.zoom = 1.0,
    this.busy,
    this.failure,
    this.notice,
    this.matches = const [],
    this.matchIndex = -1,
    this.query = '',
    this.canUndo = false,
    this.canRedo = false,
    this.modified = false,
    this.hasClip = false,
  });

  final bool loading;

  /// Counts every change of the workbook, which is edited in place.
  final int version;
  final int sheetIndex;
  final int row;
  final int col;
  final int? anchorRow;
  final int? anchorCol;
  final SelectionKind kind;
  final bool rangeMode;
  final double zoom;

  /// What a long operation is doing, or null.
  final String? busy;
  final Failure? failure;
  final String? notice;
  final List<({int row, int col})> matches;
  final int matchIndex;
  final String query;
  final bool canUndo;
  final bool canRedo;
  final bool modified;
  final bool hasClip;

  MergeRange get selection {
    final ar = anchorRow ?? row, ac = anchorCol ?? col;
    return MergeRange(math.min(ar, row), math.min(ac, col), math.max(ar, row), math.max(ac, col));
  }

  SheetState copyWith({
    bool? loading,
    int? version,
    int? sheetIndex,
    int? row,
    int? col,
    Object? anchorRow = _keep,
    Object? anchorCol = _keep,
    SelectionKind? kind,
    bool? rangeMode,
    double? zoom,
    Object? busy = _keep,
    Object? failure = _keep,
    Object? notice = _keep,
    List<({int row, int col})>? matches,
    int? matchIndex,
    String? query,
    bool? canUndo,
    bool? canRedo,
    bool? modified,
    bool? hasClip,
  }) => SheetState(
    loading: loading ?? this.loading,
    version: version ?? this.version,
    sheetIndex: sheetIndex ?? this.sheetIndex,
    row: row ?? this.row,
    col: col ?? this.col,
    anchorRow: identical(anchorRow, _keep) ? this.anchorRow : anchorRow as int?,
    anchorCol: identical(anchorCol, _keep) ? this.anchorCol : anchorCol as int?,
    kind: kind ?? this.kind,
    rangeMode: rangeMode ?? this.rangeMode,
    zoom: zoom ?? this.zoom,
    busy: identical(busy, _keep) ? this.busy : busy as String?,
    failure: identical(failure, _keep) ? this.failure : failure as Failure?,
    notice: identical(notice, _keep) ? this.notice : notice as String?,
    matches: matches ?? this.matches,
    matchIndex: matchIndex ?? this.matchIndex,
    query: query ?? this.query,
    canUndo: canUndo ?? this.canUndo,
    canRedo: canRedo ?? this.canRedo,
    modified: modified ?? this.modified,
    hasClip: hasClip ?? this.hasClip,
  );

  static const _keep = Object();

  @override
  List<Object?> get props => [
    loading,
    version,
    sheetIndex,
    row,
    col,
    anchorRow,
    anchorCol,
    kind,
    rangeMode,
    zoom,
    busy,
    failure,
    notice,
    matches.length,
    matchIndex,
    query,
    canUndo,
    canRedo,
    modified,
    hasClip,
  ];
}

/// The work behind the spreadsheet screen: opening, selecting, editing and saving a workbook.
class SheetCubit extends Cubit<SheetState> {
  SheetCubit({required Future<Directory> Function() workDir}) : _workDir = workDir, super(const SheetState());

  final Future<Directory> Function() _workDir;
  late Workbook workbook;
  bool hasWorkbook = false;
  late SheetEditor editor;
  String name = 'Spreadsheet';
  ClipBlock? _clip;

  static const maxFileBytes = 30 * 1024 * 1024;

  Sheet get sheet => workbook.sheets[state.sheetIndex.clamp(0, workbook.sheets.length - 1)];

  // ---------------------------------------------------------------- opening

  void startBlank() {
    workbook = newWorkbook();
    hasWorkbook = true;
    editor = SheetEditor(workbook);
    name = 'New spreadsheet';
    emit(state.copyWith(loading: false));
  }

  /// Opens an .xlsx or .csv file.
  Future<void> open(String path) async {
    emit(const SheetState());
    try {
      final file = File(path);
      if (!await file.exists()) throw const ImportFailure('The file could not be found.');
      if (await file.length() > maxFileBytes) throw const ImportFailure('This file is too large to open here (over 30 MB).');
      final bytes = await file.readAsBytes();
      final isCsv = RegExp(r'\.(csv|tsv|txt)$', caseSensitive: false).hasMatch(path);
      final Workbook wb;
      if (isCsv) {
        wb = await Isolate.run(() => workbookFromCsv(parseCsv(decodeCsvBytes(bytes))));
      } else {
        wb = await Isolate.run(() => readXlsx(bytes));
      }
      workbook = wb;
      hasWorkbook = true;
      editor = SheetEditor(wb);
      name = p.basenameWithoutExtension(path);
      calculateMissingResults(wb);
      final first = wb.sheets.indexWhere((s) => !s.hidden);
      emit(SheetState(loading: false, sheetIndex: first < 0 ? 0 : first));
    } on XlsxFormatException catch (e) {
      emit(SheetState(loading: false, failure: ImportFailure(e.message)));
    } on Failure catch (e) {
      emit(SheetState(loading: false, failure: e));
    } catch (e) {
      emit(SheetState(loading: false, failure: ImportFailure('This spreadsheet could not be opened.', cause: e)));
    }
  }

  // ------------------------------------------------------------- bookkeeping

  void _changed({int? row, int? col, bool resetSelection = false, String? notice}) {
    final base = resetSelection ? state.copyWith(anchorRow: null, anchorCol: null, kind: SelectionKind.cells) : state;
    emit(
      base.copyWith(
        version: state.version + 1,
        row: row,
        col: col,
        canUndo: editor.canUndo,
        canRedo: editor.canRedo,
        modified: editor.modified,
        hasClip: _clip != null,
        notice: notice,
        failure: null,
      ),
    );
  }

  void clearMessages() {
    if (state.failure != null || state.notice != null) emit(state.copyWith(failure: null, notice: null));
  }

  void _run(void Function() action, {int? row, int? col, bool resetSelection = false, String? notice}) {
    try {
      action();
      _changed(row: row, col: col, resetSelection: resetSelection, notice: notice);
    } on FormulaError catch (e) {
      emit(state.copyWith(failure: ExportFailure('That could not be calculated (${e.code}).')));
    } catch (e) {
      emit(state.copyWith(failure: UnexpectedFailure('That change could not be made.', cause: e)));
    }
  }

  // --------------------------------------------------------------- selection

  void selectSheet(int index) {
    if (index < 0 || index >= workbook.sheets.length) return;
    emit(state.copyWith(sheetIndex: index, row: 0, col: 0, anchorRow: null, anchorCol: null, kind: SelectionKind.cells, matches: const [], matchIndex: -1));
  }

  void selectCell(int row, int col) {
    if (state.rangeMode && state.kind == SelectionKind.cells) {
      emit(state.copyWith(anchorRow: state.anchorRow ?? state.row, anchorCol: state.anchorCol ?? state.col, row: row, col: col));
    } else {
      emit(state.copyWith(row: row, col: col, anchorRow: null, anchorCol: null, kind: SelectionKind.cells));
    }
  }

  void selectRange(int r1, int c1, int r2, int c2) => emit(state.copyWith(anchorRow: r1, anchorCol: c1, row: r2, col: c2, kind: SelectionKind.cells));

  void selectRow(int row) {
    final last = math.max(sheet.lastCol, 0);
    emit(state.copyWith(anchorRow: row, anchorCol: 0, row: row, col: last, kind: SelectionKind.rows));
  }

  void selectCol(int col) {
    final last = math.max(sheet.lastRow, 0);
    emit(state.copyWith(anchorRow: 0, anchorCol: col, row: last, col: col, kind: SelectionKind.cols));
  }

  void selectAll() {
    emit(state.copyWith(anchorRow: 0, anchorCol: 0, row: math.max(sheet.lastRow, 0), col: math.max(sheet.lastCol, 0), kind: SelectionKind.cells));
  }

  void toggleRangeMode() =>
      emit(state.copyWith(rangeMode: !state.rangeMode, anchorRow: state.rangeMode ? null : state.row, anchorCol: state.rangeMode ? null : state.col));

  void moveSelection(int dRow, int dCol) {
    final r = (state.row + dRow).clamp(0, CellRef.maxRows - 1), c = (state.col + dCol).clamp(0, CellRef.maxCols - 1);
    emit(state.copyWith(row: r, col: c, anchorRow: null, anchorCol: null, kind: SelectionKind.cells));
  }

  void setZoom(double z) => emit(state.copyWith(zoom: z.clamp(0.5, 2.0)));

  // ----------------------------------------------------------------- reading

  SheetCell get activeCell => sheet.cellAt(state.row, state.col);

  /// What the formula bar shows for the active cell.
  String inputTextOf(int row, int col) {
    final cell = sheet.cellAt(row, col);
    if (cell.formula != null) return '=${cell.formula}';
    return switch (cell.value) {
      EmptyValue() => '',
      TextValue(:final text) => _needsQuote(text) ? "'$text" : text,
      NumberValue(:final number) => _rawNumber(number, row, col),
      BoolValue(:final flag) => flag ? 'TRUE' : 'FALSE',
      ErrorValue(:final code) => code,
    };
  }

  static bool _needsQuote(String text) {
    if (text.startsWith("'")) return true;
    final parsed = parseInput(text);
    return parsed.value is! TextValue || parsed.formula != null;
  }

  String _rawNumber(double n, int row, int col) {
    final fmt = workbook.styles.at(sheet.cellAt(row, col).style).numFmt;
    if (fmt.contains('%') && !fmt.contains('"')) {
      final v = n * 100;
      return '${v == v.roundToDouble() ? v.toInt() : double.parse(v.toStringAsPrecision(12))}%';
    }
    if (n == n.roundToDouble() && n.abs() < 1e15) return n.toInt().toString();
    return double.parse(n.toStringAsPrecision(15)).toString();
  }

  CellStyle get activeStyle => workbook.styles.at(activeCell.style);

  // ----------------------------------------------------------------- editing

  /// Puts [text] in the active cell and moves down, as spreadsheets do.
  void commitInput(String text, {bool moveDown = true}) {
    if (text == inputTextOf(state.row, state.col)) {
      if (moveDown) moveSelection(1, 0);
      return;
    }
    final r = state.row, c = state.col;
    _run(() => editor.setInput(sheet, r, c, text), row: moveDown ? r + 1 : r, col: c, resetSelection: true);
  }

  void _style(CellStyle Function(CellStyle) change) {
    final sel = state.selection;
    _run(() => editor.setStyle(sheet, sel, change));
  }

  void toggleBold() {
    final on = !activeStyle.bold;
    _style((s) => s.copyWith(bold: on));
  }

  void toggleItalic() {
    final on = !activeStyle.italic;
    _style((s) => s.copyWith(italic: on));
  }

  void toggleUnderline() {
    final on = !activeStyle.underline;
    _style((s) => s.copyWith(underline: on));
  }

  void toggleWrap() {
    final on = !activeStyle.wrap;
    _style((s) => s.copyWith(wrap: on));
  }

  void setAlign(HAlign a) {
    final same = activeStyle.align == a;
    _style((s) => s.copyWith(align: same ? HAlign.general : a));
  }

  void setFill(int? argb) => _style((s) => s.copyWith(fill: argb));
  void setFontColor(int? argb) => _style((s) => s.copyWith(fontColor: argb));
  void setFontSize(double size) => _style((s) => s.copyWith(fontSize: size));
  void setNumberFormat(String code) => _style((s) => s.copyWith(numFmt: code));

  void clearContents() {
    final sel = state.selection;
    _run(() => editor.clear(sheet, sel));
  }

  void clearFormatting() => _style((s) => CellStyle.plain.copyWith(numFmt: 'General'));

  bool get selectionIsMerged => sheet.mergeAt(state.selection.firstRow, state.selection.firstCol) != null;

  void toggleMerge() {
    final sel = state.selection;
    if (sel.isSingle && !selectionIsMerged) return;
    _run(() => selectionIsMerged ? editor.unmerge(sheet, sel) : editor.merge(sheet, sel), resetSelection: false);
  }

  void insertRows() {
    final sel = state.selection;
    final count = state.kind == SelectionKind.cols ? 1 : sel.lastRow - sel.firstRow + 1;
    _run(() => editor.insertRows(sheet, state.kind == SelectionKind.cols ? state.row : sel.firstRow, math.min(count, 1000)), resetSelection: true);
  }

  void deleteRows() {
    final sel = state.selection;
    final count = state.kind == SelectionKind.cols ? 1 : sel.lastRow - sel.firstRow + 1;
    _run(() => editor.deleteRows(sheet, state.kind == SelectionKind.cols ? state.row : sel.firstRow, math.min(count, 1000)), resetSelection: true);
  }

  void insertCols() {
    final sel = state.selection;
    final count = state.kind == SelectionKind.rows ? 1 : sel.lastCol - sel.firstCol + 1;
    _run(() => editor.insertCols(sheet, state.kind == SelectionKind.rows ? state.col : sel.firstCol, math.min(count, 200)), resetSelection: true);
  }

  void deleteCols() {
    final sel = state.selection;
    final count = state.kind == SelectionKind.rows ? 1 : sel.lastCol - sel.firstCol + 1;
    _run(() => editor.deleteCols(sheet, state.kind == SelectionKind.rows ? state.col : sel.firstCol, math.min(count, 200)), resetSelection: true);
  }

  void setColumnWidth(double chars) {
    final sel = state.selection;
    _run(() {
      for (var c = sel.firstCol; c <= math.min(sel.lastCol, sel.firstCol + 200); c++) {
        editor.setColumnWidth(sheet, c, chars);
      }
    });
  }

  void setRowHeight(double points) {
    final sel = state.selection;
    _run(() {
      for (var r = sel.firstRow; r <= math.min(sel.lastRow, sel.firstRow + 2000); r++) {
        editor.setRowHeight(sheet, r, points);
      }
    });
  }

  void setHidden({required bool rows, required bool hide}) {
    final sel = state.selection;
    final range = rows
        ? [for (var r = sel.firstRow; r <= math.min(sel.lastRow, sel.firstRow + 5000); r++) r]
        : [for (var c = sel.firstCol; c <= sel.lastCol; c++) c];
    _run(() => rows ? editor.setHiddenRows(sheet, range, hide) : editor.setHiddenCols(sheet, range, hide));
  }

  /// Shows every hidden row and column of the sheet again.
  void showAllHidden() {
    _run(() {
      editor.setHiddenRows(sheet, sheet.hiddenRows.toList(), false);
      editor.setHiddenCols(sheet, sheet.hiddenCols.toList(), false);
    });
  }

  bool get hasHidden => sheet.hiddenRows.isNotEmpty || sheet.hiddenCols.isNotEmpty;

  void toggleFreeze() {
    final frozen = sheet.frozenRows > 0 || sheet.frozenCols > 0;
    _run(() => editor.setFreeze(sheet, frozen ? 0 : state.row, frozen ? 0 : state.col));
  }

  bool get isFrozen => sheet.frozenRows > 0 || sheet.frozenCols > 0;

  void sortSelection({required bool ascending, required bool hasHeader}) {
    var sel = state.selection;
    if (sel.isSingle || (sel.firstRow == sel.lastRow)) {
      sel = MergeRange(0, 0, math.max(sheet.lastRow, 0), math.max(sheet.lastCol, 0));
    }
    final byCol = state.col.clamp(sel.firstCol, sel.lastCol);
    _run(() => editor.sort(sheet, sel, byCol: byCol, ascending: ascending, hasHeader: hasHeader));
  }

  void autoSum() {
    final sel = state.selection;
    void put(int r, int c, String f) => editor.setInput(sheet, r, c, f);
    _run(() {
      bool isNum(int r, int c) => r >= 0 && c >= 0 && sheet.cellAt(r, c).value is NumberValue;
      if (!sel.isSingle) {
        // A sum under every selected column, or to the right of a single selected row.
        if (sel.lastRow > sel.firstRow) {
          for (var c = sel.firstCol; c <= sel.lastCol; c++) {
            put(sel.lastRow + 1, c, '=SUM(${CellRef.a1(sel.firstRow, c)}:${CellRef.a1(sel.lastRow, c)})');
          }
        } else {
          put(sel.firstRow, sel.lastCol + 1, '=SUM(${CellRef.a1(sel.firstRow, sel.firstCol)}:${CellRef.a1(sel.firstRow, sel.lastCol)})');
        }
        return;
      }
      final r = sel.firstRow, c = sel.firstCol;
      var top = r - 1;
      while (isNum(top, c)) {
        top--;
      }
      if (top < r - 1) {
        put(r, c, '=SUM(${CellRef.a1(top + 1, c)}:${CellRef.a1(r - 1, c)})');
        return;
      }
      var left = c - 1;
      while (isNum(r, left)) {
        left--;
      }
      if (left < c - 1) {
        put(r, c, '=SUM(${CellRef.a1(r, left + 1)}:${CellRef.a1(r, c - 1)})');
        return;
      }
      put(r, c, '=SUM()');
    });
  }

  // --------------------------------------------------------------- clipboard

  void copySelection({bool cut = false}) {
    _clip = editor.copy(sheet, state.selection, cut: cut);
    emit(state.copyWith(hasClip: true, notice: cut ? 'Cut. Pick a cell and paste.' : 'Copied. Pick a cell and paste.'));
  }

  /// The copied cells as tab-separated text, for sharing with other apps.
  String? get clipText => _clip?.toText(workbook.styles.at, date1904: workbook.date1904);

  void paste() {
    final clip = _clip;
    if (clip == null) return;
    _run(() {
      editor.paste(sheet, state.row, state.col, clip);
      if (clip.cut) _clip = null;
    });
  }

  void fillDown() {
    final sel = state.selection;
    if (sel.lastRow == sel.firstRow) return;
    _run(() => editor.fill(sheet, sel, down: true));
  }

  void fillRight() {
    final sel = state.selection;
    if (sel.lastCol == sel.firstCol) return;
    _run(() => editor.fill(sheet, sel, down: false));
  }

  // ---------------------------------------------------------- undo and redo

  void undo() => _run(editor.undo);
  void redo() => _run(editor.redo);

  // ------------------------------------------------------------------ sheets

  void addSheet() {
    _run(() {
      final s = editor.addSheet();
      emit(state.copyWith(sheetIndex: workbook.sheets.indexOf(s), row: 0, col: 0, anchorRow: null, anchorCol: null));
    });
  }

  void duplicateSheet(int index) {
    _run(() {
      final s = editor.duplicateSheet(workbook.sheets[index]);
      emit(state.copyWith(sheetIndex: workbook.sheets.indexOf(s)));
    });
  }

  bool renameSheet(int index, String newName) {
    var ok = false;
    _run(() => ok = editor.renameSheet(workbook.sheets[index], newName));
    if (!ok) emit(state.copyWith(failure: const ExportFailure('That name is empty or already used by another sheet.')));
    return ok;
  }

  void deleteSheet(int index) {
    final target = workbook.sheets[index];
    var ok = false;
    _run(() => ok = editor.deleteSheet(target));
    if (!ok) {
      emit(state.copyWith(failure: const ExportFailure('A workbook needs at least one visible sheet.')));
      return;
    }
    final next = state.sheetIndex.clamp(0, workbook.sheets.length - 1);
    emit(state.copyWith(sheetIndex: next, row: 0, col: 0, anchorRow: null, anchorCol: null));
    if (workbook.sheets[next].hidden) selectSheet(workbook.sheets.indexWhere((s) => !s.hidden));
  }

  void moveSheet(int index, int delta) {
    final to = index + delta;
    if (to < 0 || to >= workbook.sheets.length) return;
    final active = sheet;
    _run(() => editor.moveSheet(index, to));
    emit(state.copyWith(sheetIndex: workbook.sheets.indexOf(active)));
  }

  void setSheetHidden(int index, bool hide) {
    final target = workbook.sheets[index];
    if (hide && workbook.visibleSheets.length <= 1) {
      emit(state.copyWith(failure: const ExportFailure('A workbook needs at least one visible sheet.')));
      return;
    }
    _run(() {
      target.hidden = hide;
      workbook.structureChanged = true;
      editor.modified = true;
    });
    if (hide && workbook.sheets[state.sheetIndex] == target) selectSheet(workbook.sheets.indexWhere((s) => !s.hidden));
  }

  // ------------------------------------------------------------------ search

  void find(String query) {
    if (query.isEmpty) {
      emit(state.copyWith(query: '', matches: const [], matchIndex: -1));
      return;
    }
    final found = editor.find(sheet, query);
    emit(state.copyWith(query: query, matches: found, matchIndex: found.isEmpty ? -1 : 0, notice: found.isEmpty ? 'Nothing found' : null));
    if (found.isNotEmpty) selectCell(found.first.row, found.first.col);
  }

  void findNext({bool back = false}) {
    if (state.matches.isEmpty) return;
    final n = state.matches.length;
    final i = (state.matchIndex + (back ? -1 : 1) + n) % n;
    emit(state.copyWith(matchIndex: i));
    selectCell(state.matches[i].row, state.matches[i].col);
  }

  void endFind() => emit(state.copyWith(query: '', matches: const [], matchIndex: -1));

  // ------------------------------------------------------------------ saving

  String exportName(SheetExportFormat f) =>
      '${name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}${f == SheetExportFormat.csv && workbook.sheets.length > 1 ? '_${sheet.name}' : ''}.${f.extension}';

  /// Writes the workbook in [format] to a temporary file and returns its path.
  Future<String?> export(SheetExportFormat format) async {
    if (state.busy != null) return null;
    emit(state.copyWith(busy: 'Preparing the file', failure: null));
    try {
      final dir = await Directory(p.join((await _workDir()).path, 'office_out')).create(recursive: true);
      final out = p.join(dir.path, exportName(format));
      switch (format) {
        case SheetExportFormat.xlsx:
          final wb = workbook;
          final bytes = await Isolate.run(() => writeXlsx(wb));
          await File(out).writeAsBytes(bytes, flush: true);
        case SheetExportFormat.csv:
          final text = sheetToCsv(sheet, workbook.styles, date1904: workbook.date1904);
          await File(out).writeAsBytes(Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(text)]), flush: true);
        case SheetExportFormat.pdf:
          final renderer = SheetRenderer(workbook: workbook);
          await renderer.exportPdf(
            workbook.visibleSheets,
            workDir: Directory(p.join(dir.path, 'pages')),
            outputPath: out,
            onProgress: (done, total) {
              if (!isClosed) emit(state.copyWith(busy: 'Drawing page $done of $total'));
            },
          );
      }
      if (!isClosed) emit(state.copyWith(busy: null));
      return out;
    } on SheetTooLargeException catch (e) {
      if (!isClosed)
        emit(
          state.copyWith(
            busy: null,
            failure: ExportFailure('This workbook would make ${e.pages} pages, which is too many for a PDF. Export one sheet or use CSV instead.'),
          ),
        );
      return null;
    } catch (e) {
      if (!isClosed) emit(state.copyWith(busy: null, failure: ExportFailure('The file could not be created.', cause: e)));
      return null;
    }
  }

  /// Marks the work as saved once the user has shared or saved the file.
  void markSaved() {
    editor.modified = false;
    emit(state.copyWith(modified: false));
  }
}

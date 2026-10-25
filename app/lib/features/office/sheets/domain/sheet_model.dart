import 'dart:typed_data';

/// What a cell holds.
sealed class CellValue {
  const CellValue();
}

class EmptyValue extends CellValue {
  const EmptyValue();
}

class TextValue extends CellValue {
  const TextValue(this.text);
  final String text;
}

class NumberValue extends CellValue {
  const NumberValue(this.number);
  final double number;
}

class BoolValue extends CellValue {
  const BoolValue(this.flag);
  final bool flag;
}

/// An error such as #DIV/0!, kept as the code Excel shows.
class ErrorValue extends CellValue {
  const ErrorValue(this.code);
  final String code;

  static const divZero = ErrorValue('#DIV/0!');
  static const value = ErrorValue('#VALUE!');
  static const ref = ErrorValue('#REF!');
  static const name = ErrorValue('#NAME?');
  static const na = ErrorValue('#N/A');
  static const num = ErrorValue('#NUM!');
}

enum HAlign { general, left, center, right }

/// How a cell looks. Only what the app shows and edits; other formatting of the file is kept as it is.
class CellStyle {
  const CellStyle({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.fontColor,
    this.fill,
    this.align = HAlign.general,
    this.wrap = false,
    this.numFmt = 'General',
    this.fontSize,
  });

  final bool bold;
  final bool italic;
  final bool underline;

  /// ARGB, or null for the default colour.
  final int? fontColor;
  final int? fill;
  final HAlign align;
  final bool wrap;
  final String numFmt;
  final double? fontSize;

  static const plain = CellStyle();

  CellStyle copyWith({
    bool? bold,
    bool? italic,
    bool? underline,
    Object? fontColor = _keep,
    Object? fill = _keep,
    HAlign? align,
    bool? wrap,
    String? numFmt,
    Object? fontSize = _keep,
  }) => CellStyle(
    bold: bold ?? this.bold,
    italic: italic ?? this.italic,
    underline: underline ?? this.underline,
    fontColor: identical(fontColor, _keep) ? this.fontColor : fontColor as int?,
    fill: identical(fill, _keep) ? this.fill : fill as int?,
    align: align ?? this.align,
    wrap: wrap ?? this.wrap,
    numFmt: numFmt ?? this.numFmt,
    fontSize: identical(fontSize, _keep) ? this.fontSize : fontSize as double?,
  );

  static const _keep = Object();

  @override
  bool operator ==(Object other) =>
      other is CellStyle &&
      other.bold == bold &&
      other.italic == italic &&
      other.underline == underline &&
      other.fontColor == fontColor &&
      other.fill == fill &&
      other.align == align &&
      other.wrap == wrap &&
      other.numFmt == numFmt &&
      other.fontSize == fontSize;

  @override
  int get hashCode => Object.hash(bold, italic, underline, fontColor, fill, align, wrap, numFmt, fontSize);
}

class SheetCell {
  const SheetCell({this.value = const EmptyValue(), this.formula, this.style = 0});

  final CellValue value;

  /// The formula without the leading "=", or null for a plain value.
  final String? formula;

  /// Index into the workbook's cell styles.
  final int style;

  bool get isEmpty => value is EmptyValue && formula == null && style == 0;

  SheetCell copyWith({CellValue? value, Object? formula = _keep, int? style}) =>
      SheetCell(value: value ?? this.value, formula: identical(formula, _keep) ? this.formula : formula as String?, style: style ?? this.style);

  static const _keep = Object();
}

/// A block of cells shown as one, zero-based and inclusive.
class MergeRange {
  const MergeRange(this.firstRow, this.firstCol, this.lastRow, this.lastCol);
  final int firstRow;
  final int firstCol;
  final int lastRow;
  final int lastCol;

  bool contains(int row, int col) => row >= firstRow && row <= lastRow && col >= firstCol && col <= lastCol;
  bool get isSingle => firstRow == lastRow && firstCol == lastCol;
  bool overlaps(MergeRange o) => !(o.lastRow < firstRow || o.firstRow > lastRow || o.lastCol < firstCol || o.firstCol > lastCol);

  @override
  bool operator ==(Object other) =>
      other is MergeRange && other.firstRow == firstRow && other.firstCol == firstCol && other.lastRow == lastRow && other.lastCol == lastCol;

  @override
  int get hashCode => Object.hash(firstRow, firstCol, lastRow, lastCol);

  @override
  String toString() => '${CellRef.a1(firstRow, firstCol)}:${CellRef.a1(lastRow, lastCol)}';
}

/// Cell addresses such as B12.
abstract final class CellRef {
  static const maxCols = 16384;
  static const maxRows = 1048576;

  static String columnName(int col) {
    var n = col + 1;
    final out = <int>[];
    while (n > 0) {
      final r = (n - 1) % 26;
      out.add(65 + r);
      n = (n - 1) ~/ 26;
    }
    return String.fromCharCodes(out.reversed);
  }

  /// "AB" -> 27, or -1 when it is not a column name.
  static int columnIndex(String name) {
    if (name.isEmpty || name.length > 3) return -1;
    var n = 0;
    for (final c in name.toUpperCase().codeUnits) {
      if (c < 65 || c > 90) return -1;
      n = n * 26 + (c - 64);
    }
    return n > maxCols ? -1 : n - 1;
  }

  static String a1(int row, int col) => '${columnName(col)}${row + 1}';

  /// "B12" -> (row 11, col 1), or null.
  static ({int row, int col})? parse(String ref) {
    final m = RegExp(r'^\$?([A-Za-z]{1,3})\$?(\d{1,7})$').firstMatch(ref.trim());
    if (m == null) return null;
    final col = columnIndex(m.group(1)!);
    final row = int.parse(m.group(2)!) - 1;
    if (col < 0 || row < 0 || row >= maxRows) return null;
    return (row: row, col: col);
  }

  /// "A1:C3" or "A1" -> a range.
  static MergeRange? parseRange(String text) {
    final parts = text.split(':');
    if (parts.length > 2) return null;
    final a = parse(parts.first);
    final b = parts.length == 2 ? parse(parts.last) : a;
    if (a == null || b == null) return null;
    return MergeRange(a.row < b.row ? a.row : b.row, a.col < b.col ? a.col : b.col, a.row > b.row ? a.row : b.row, a.col > b.col ? a.col : b.col);
  }

  static int key(int row, int col) => row * maxCols + col;
  static int rowOf(int key) => key ~/ maxCols;
  static int colOf(int key) => key % maxCols;
}

/// One worksheet. Cells are kept sparsely by [CellRef.key].
class Sheet {
  Sheet({
    required this.name,
    Map<int, SheetCell>? cells,
    List<MergeRange>? merges,
    Map<int, double>? colWidths,
    Map<int, double>? rowHeights,
    Set<int>? hiddenRows,
    Set<int>? hiddenCols,
    Map<int, int>? rowStyles,
    Map<int, int>? colStyles,
    this.partPath,
    this.hidden = false,
    this.frozenRows = 0,
    this.frozenCols = 0,
  }) : cells = cells ?? {},
       merges = merges ?? [],
       colWidths = colWidths ?? {},
       rowHeights = rowHeights ?? {},
       hiddenRows = hiddenRows ?? {},
       hiddenCols = hiddenCols ?? {},
       rowStyles = rowStyles ?? {},
       colStyles = colStyles ?? {};

  String name;
  final Map<int, SheetCell> cells;
  final List<MergeRange> merges;

  /// Widths in Excel character units, by zero-based column.
  final Map<int, double> colWidths;

  /// Heights in points, by zero-based row.
  final Map<int, double> rowHeights;
  final Set<int> hiddenRows;
  final Set<int> hiddenCols;

  /// Style of a whole row or column, shown on cells that have no style of their own.
  final Map<int, int> rowStyles;
  final Map<int, int> colStyles;
  bool hidden;
  int frozenRows;
  int frozenCols;

  /// Where the sheet lives in the file, null for sheets made in the app.
  String? partPath;

  /// Changed since it was opened, so it has to be written again.
  bool dirty = false;

  /// Column settings or merged cells changed; otherwise the file's own ones are kept as they are.
  bool colsDirty = false;
  bool mergesDirty = false;

  static const defaultColWidth = 8.43;
  static const defaultRowHeight = 15.0;

  SheetCell cellAt(int row, int col) => cells[CellRef.key(row, col)] ?? const SheetCell();

  void setCell(int row, int col, SheetCell cell) {
    if (cell.isEmpty) {
      cells.remove(CellRef.key(row, col));
    } else {
      cells[CellRef.key(row, col)] = cell;
    }
    dirty = true;
  }

  int get lastRow {
    var m = -1;
    for (final k in cells.keys) {
      final r = CellRef.rowOf(k);
      if (r > m) m = r;
    }
    return m;
  }

  int get lastCol {
    var m = -1;
    for (final k in cells.keys) {
      final c = CellRef.colOf(k);
      if (c > m) m = c;
    }
    return m;
  }

  MergeRange? mergeAt(int row, int col) {
    for (final m in merges) {
      if (m.contains(row, col)) return m;
    }
    return null;
  }

  double widthOf(int col) => colWidths[col] ?? defaultColWidth;
  double heightOf(int row) => rowHeights[row] ?? defaultRowHeight;

  /// Puts the contents of [o] into this sheet, keeping this object (and so every reference to it) in place.
  void assignFrom(Sheet o) {
    cells
      ..clear()
      ..addAll(o.cells);
    merges
      ..clear()
      ..addAll(o.merges);
    colWidths
      ..clear()
      ..addAll(o.colWidths);
    rowHeights
      ..clear()
      ..addAll(o.rowHeights);
    hiddenRows
      ..clear()
      ..addAll(o.hiddenRows);
    hiddenCols
      ..clear()
      ..addAll(o.hiddenCols);
    rowStyles
      ..clear()
      ..addAll(o.rowStyles);
    colStyles
      ..clear()
      ..addAll(o.colStyles);
    name = o.name;
    hidden = o.hidden;
    frozenRows = o.frozenRows;
    frozenCols = o.frozenCols;
    dirty = o.dirty;
    colsDirty = o.colsDirty;
    mergesDirty = o.mergesDirty;
  }

  Sheet copy({String? name}) =>
      Sheet(
          name: name ?? this.name,
          cells: Map.of(cells),
          merges: List.of(merges),
          colWidths: Map.of(colWidths),
          rowHeights: Map.of(rowHeights),
          hiddenRows: Set.of(hiddenRows),
          hiddenCols: Set.of(hiddenCols),
          rowStyles: Map.of(rowStyles),
          colStyles: Map.of(colStyles),
          partPath: partPath,
          hidden: hidden,
          frozenRows: frozenRows,
          frozenCols: frozenCols,
        )
        ..dirty = dirty
        ..colsDirty = colsDirty
        ..mergesDirty = mergesDirty;
}

/// All sheets of a file, with the cell styles they share.
class Workbook {
  Workbook({required this.sheets, required this.styles, this.source, this.date1904 = false});

  final List<Sheet> sheets;
  final StyleTable styles;

  /// The original file, kept so that parts the app does not edit are written back unchanged.
  final Uint8List? source;
  final bool date1904;

  /// Sheets were added, removed, renamed or reordered.
  bool structureChanged = false;

  Sheet? sheetNamed(String name) {
    for (final s in sheets) {
      if (s.name.toLowerCase() == name.toLowerCase()) return s;
    }
    return null;
  }

  List<Sheet> get visibleSheets => [
    for (final s in sheets)
      if (!s.hidden) s,
  ];
}

/// The distinct cell looks of a workbook; a cell's [SheetCell.style] points into it.
class StyleTable {
  StyleTable([List<CellStyle>? styles]) : styles = styles ?? [CellStyle.plain];

  final List<CellStyle> styles;

  /// How many entries were there when the file was opened; the rest are new and must be written.
  int originalCount = 1;

  CellStyle at(int index) => index >= 0 && index < styles.length ? styles[index] : CellStyle.plain;

  /// For each added style, the original style it was made from, so its borders and other details are kept.
  final Map<int, int> basedOn = {};

  /// The index of [style], adding it when it is new. [from] is the style index of the cell being changed.
  int indexOf(CellStyle style, {int from = 0}) {
    final i = styles.indexOf(style);
    if (i >= 0) return i;
    styles.add(style);
    final index = styles.length - 1;
    basedOn[index] = from < originalCount ? from : (basedOn[from] ?? 0);
    return index;
  }

  bool get hasNew => styles.length > originalCount;
}

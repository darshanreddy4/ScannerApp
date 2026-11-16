import 'dart:math' as math;

import 'package:flutter/material.dart' hide Text;
import 'package:two_dimensional_scrollables/two_dimensional_scrollables.dart';

import '../../../../core/theme/app_colors.dart';
import '../domain/cell_display.dart';
import '../domain/chart.dart';
import '../domain/cond_format.dart';
import '../domain/sheet_model.dart';
import 'chart_painter.dart';
import 'sheet_cubit.dart';
import '../../../../core/widgets/text.dart';

const _headerFill = Color(0xFFF1F4F9);
const _gridLine = Color(0xFFDDE3EC);

/// The scrolling grid of cells with column letters and row numbers.
class SheetGrid extends StatefulWidget {
  const SheetGrid({
    super.key,
    required this.workbook,
    required this.sheet,
    required this.state,
    required this.onTapCell,
    required this.onTapRow,
    required this.onTapCol,
    required this.onTapCorner,
    this.onMoveChart,
    this.onEditChart,
    this.onDeleteChart,
  });

  /// A chart was dragged or resized to this place, in cells.
  final void Function(SheetChart chart, {int? col, int? row, int? cols, int? rows})? onMoveChart;
  final ValueChanged<SheetChart>? onEditChart;
  final ValueChanged<SheetChart>? onDeleteChart;

  final Workbook workbook;
  final Sheet sheet;
  final SheetState state;
  final void Function(int row, int col) onTapCell;
  final ValueChanged<int> onTapRow;
  final ValueChanged<int> onTapCol;
  final VoidCallback onTapCorner;

  @override
  State<SheetGrid> createState() => _SheetGridState();
}

class _SheetGridState extends State<SheetGrid> {
  final _vertical = ScrollController();
  final _horizontal = ScrollController();

  /// The chart being moved or resized, as its place in the sheet's list of charts.
  int? _chart;
  Offset _moveBy = Offset.zero;
  Offset _resizeBy = Offset.zero;

  static const _rowHeaderWidth = 46.0;
  static const _colHeaderHeight = 26.0;

  double get _zoom => widget.state.zoom;
  Sheet get _sheet => widget.sheet;

  double _colWidth(int c) => _sheet.hiddenCols.contains(c) ? 0 : (_sheet.widthOf(c) * 7 + 5) * _zoom;
  double _rowHeight(int r) => _sheet.hiddenRows.contains(r) ? 0 : _sheet.heightOf(r) * 4 / 3 * _zoom;

  int get _rowCount {
    var last = _sheet.lastRow;
    for (final m in _sheet.merges) {
      last = math.max(last, m.lastRow);
    }
    return math.min(math.max(last + 40, 100), CellRef.maxRows);
  }

  int get _colCount {
    var last = _sheet.lastCol;
    for (final m in _sheet.merges) {
      last = math.max(last, m.lastCol);
    }
    return math.min(math.max(last + 10, 26), CellRef.maxCols);
  }

  @override
  void dispose() {
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(SheetGrid old) {
    super.didUpdateWidget(old);
    final s = widget.state, o = old.state;
    if (s.sheetIndex != o.sheetIndex) _chart = null;
    if (s.row != o.row || s.col != o.col || s.sheetIndex != o.sheetIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(s.row, s.col));
    }
  }

  void _reveal(int row, int col) {
    if (!mounted || !_vertical.hasClients || !_horizontal.hasClients) return;
    if (row >= _sheet.frozenRows) {
      var top = 0.0;
      for (var r = _sheet.frozenRows; r < row; r++) {
        top += _rowHeight(r);
      }
      final h = _rowHeight(row);
      final pos = _vertical.position;
      if (top < pos.pixels) {
        pos.jumpTo(top.clamp(0, pos.maxScrollExtent));
      } else if (top + h > pos.pixels + pos.viewportDimension - _frozenHeight() - _colHeaderHeight) {
        pos.jumpTo((top + h - pos.viewportDimension + _frozenHeight() + _colHeaderHeight + 4).clamp(0, pos.maxScrollExtent));
      }
    }
    if (col >= _sheet.frozenCols) {
      var left = 0.0;
      for (var c = _sheet.frozenCols; c < col; c++) {
        left += _colWidth(c);
      }
      final w = _colWidth(col);
      final pos = _horizontal.position;
      if (left < pos.pixels) {
        pos.jumpTo(left.clamp(0, pos.maxScrollExtent));
      } else if (left + w > pos.pixels + pos.viewportDimension - _frozenWidth() - _rowHeaderWidth * _zoom) {
        pos.jumpTo((left + w - pos.viewportDimension + _frozenWidth() + _rowHeaderWidth * _zoom + 4).clamp(0, pos.maxScrollExtent));
      }
    }
  }

  double _frozenHeight() => [for (var r = 0; r < _sheet.frozenRows; r++) _rowHeight(r)].fold(0.0, (a, b) => a + b);
  double _frozenWidth() => [for (var c = 0; c < _sheet.frozenCols; c++) _colWidth(c)].fold(0.0, (a, b) => a + b);

  double _colLeft(int c) {
    var x = 0.0;
    for (var i = 0; i < c; i++) {
      x += _colWidth(i);
    }
    return x;
  }

  double _rowTop(int r) {
    var y = 0.0;
    for (var i = 0; i < r; i++) {
      y += _rowHeight(i);
    }
    return y;
  }

  int _colAt(double x) {
    var acc = 0.0;
    for (var c = 0; c < _colCount; c++) {
      acc += _colWidth(c);
      if (x < acc) return c;
    }
    return _colCount - 1;
  }

  int _rowAt(double y) {
    var acc = 0.0;
    for (var r = 0; r < _rowCount; r++) {
      acc += _rowHeight(r);
      if (y < acc) return r;
    }
    return _rowCount - 1;
  }

  void _finishMove(SheetChart chart) {
    final by = _moveBy;
    setState(() => _moveBy = Offset.zero);
    if (by.distance < 4) return;
    widget.onMoveChart?.call(chart, col: _colAt(math.max(0, _colLeft(chart.col) + by.dx) + 1), row: _rowAt(math.max(0, _rowTop(chart.row) + by.dy) + 1));
  }

  void _finishResize(SheetChart chart) {
    final by = _resizeBy;
    setState(() => _resizeBy = Offset.zero);
    if (by.distance < 4) return;
    final endCol = _colAt(math.max(0, _colLeft(chart.col + chart.cols) + by.dx) - 1);
    final endRow = _rowAt(math.max(0, _rowTop(chart.row + chart.rows) + by.dy) - 1);
    widget.onMoveChart?.call(chart, cols: math.max(2, endCol - chart.col + 1), rows: math.max(3, endRow - chart.row + 1));
  }

  /// The charts of the sheet, drawn over the cells. A tap selects one; a selected chart can be dragged, resized, changed or removed.
  Widget _chartLayer(List<ChartData?> data, double rowHeader, double colHeader) {
    return Positioned(
      left: rowHeader,
      top: colHeader,
      right: 0,
      bottom: 0,
      child: ClipRect(
        child: AnimatedBuilder(
          animation: Listenable.merge([_vertical, _horizontal]),
          builder: (context, _) {
            final h = _horizontal.hasClients ? _horizontal.positions.first.pixels : 0.0, v = _vertical.hasClients ? _vertical.positions.first.pixels : 0.0;
            return Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                for (var i = 0; i < _sheet.charts.length; i++) _chartBox(i, _sheet.charts[i], data[i], h, v),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _chartBox(int i, SheetChart chart, ChartData? data, double h, double v) {
    final selected = _chart == i;
    final left = _colLeft(chart.col) - h, top = _rowTop(chart.row) - v;
    var w = _colLeft(chart.col + chart.cols) - _colLeft(chart.col), ht = _rowTop(chart.row + chart.rows) - _rowTop(chart.row);
    if (selected) {
      w = math.max(80, w + _resizeBy.dx);
      ht = math.max(60, ht + _resizeBy.dy);
    }
    final moveBy = selected ? _moveBy : Offset.zero;
    return Positioned(
      left: left + moveBy.dx,
      top: top + moveBy.dy,
      width: w,
      height: ht,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: GestureDetector(
              key: ValueKey('grid_chart_$i'),
              behavior: selected ? HitTestBehavior.opaque : HitTestBehavior.translucent,
              onTap: () => setState(() => _chart = selected ? null : i),
              onPanUpdate: selected ? (d) => setState(() => _moveBy += d.delta) : null,
              onPanEnd: selected ? (_) => _finishMove(chart) : null,
              onPanCancel: selected ? () => setState(() => _moveBy = Offset.zero) : null,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: selected ? AppColors.primary : const Color(0xFFB8C2D1), width: selected ? 2 : 1),
                  boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 4, offset: Offset(0, 1))],
                ),
                child: chart.editable && data != null
                    ? CustomPaint(painter: ChartPainter(chart, data), child: const SizedBox.expand())
                    : Center(
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(chart.label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
                        ),
                      ),
              ),
            ),
          ),
          if (selected) ...[
            Positioned(
              top: 4,
              right: 4,
              child: Material(
                color: Colors.white.withValues(alpha: 0.92),
                elevation: 2,
                borderRadius: BorderRadius.circular(18),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (chart.editable)
                      IconButton(
                        key: const ValueKey('grid_chart_edit'),
                        visualDensity: VisualDensity.compact,
                        iconSize: 18,
                        onPressed: () => widget.onEditChart?.call(chart),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                    IconButton(
                      key: const ValueKey('grid_chart_delete'),
                      visualDensity: VisualDensity.compact,
                      iconSize: 18,
                      color: AppColors.danger,
                      onPressed: () {
                        setState(() => _chart = null);
                        widget.onDeleteChart?.call(chart);
                      },
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              right: -14,
              bottom: -14,
              width: 40,
              height: 40,
              child: GestureDetector(
                key: const ValueKey('grid_chart_resize'),
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (d) => setState(() => _resizeBy += d.delta),
                onPanEnd: (_) => _finishResize(chart),
                onPanCancel: () => setState(() => _resizeBy = Offset.zero),
                child: Center(
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final sel = s.selection;
    final matchKeys = {for (final m in s.matches) CellRef.key(m.row, m.col)};
    final cond = CondContext(_sheet);
    final mergeOf = <int, MergeRange>{};
    var budget = 150000;
    for (final m in _sheet.merges) {
      final size = (m.lastRow - m.firstRow + 1) * (m.lastCol - m.firstCol + 1);
      if (size > budget) continue;
      budget -= size;
      for (var r = m.firstRow; r <= m.lastRow; r++) {
        for (var c = m.firstCol; c <= m.lastCol; c++) {
          mergeOf[CellRef.key(r, c)] = m;
        }
      }
    }
    return LayoutBuilder(
      builder: (context, box) {
        // Frozen panes that would fill most of a small screen are not frozen here, or nothing could scroll.
        var frozenRows = _sheet.frozenRows, frozenCols = _sheet.frozenCols;
        if (_frozenHeight() + _colHeaderHeight > box.maxHeight * 0.5) frozenRows = 0;
        if (_frozenWidth() + _rowHeaderWidth * _zoom > box.maxWidth * 0.6) frozenCols = 0;
        final rows = _rowCount, cols = _colCount;
        final rowHeader = _rowHeaderWidth * _zoom, colHeader = _colHeaderHeight * _zoom;
        final activeMerge = mergeOf[CellRef.key(s.row, s.col)];
        final chartData = [for (final c in _sheet.charts) c.editable ? resolveChart(widget.workbook, c) : null];

        final table = TableView.builder(
          verticalDetails: ScrollableDetails.vertical(controller: _vertical),
          horizontalDetails: ScrollableDetails.horizontal(controller: _horizontal),
          diagonalDragBehavior: DiagonalDragBehavior.free,
          pinnedRowCount: 1 + frozenRows,
          pinnedColumnCount: 1 + frozenCols,
          rowCount: rows + 1,
          columnCount: cols + 1,
          rowBuilder: (i) => TableSpan(extent: FixedTableSpanExtent(i == 0 ? colHeader : _rowHeight(i - 1))),
          columnBuilder: (i) => TableSpan(extent: FixedTableSpanExtent(i == 0 ? rowHeader : _colWidth(i - 1))),
          cellBuilder: (context, v) {
            final r = v.row - 1, c = v.column - 1;
            if (r < 0 && c < 0) {
              return TableViewCell(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onTapCorner,
                  child: Container(
                    decoration: _headerDecoration(false),
                    child: Center(
                      child: Icon(Icons.select_all, size: 14 * _zoom, color: AppColors.inkMuted),
                    ),
                  ),
                ),
              );
            }
            if (r < 0) {
              return TableViewCell(
                child: GestureDetector(
                  key: ValueKey('col_$c'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => widget.onTapCol(c),
                  child: Container(
                    decoration: _headerDecoration(c >= sel.firstCol && c <= sel.lastCol),
                    alignment: Alignment.center,
                    child: Text(
                      CellRef.columnName(c),
                      style: TextStyle(fontSize: 11.5 * _zoom, fontWeight: FontWeight.w600, color: AppColors.inkMuted),
                    ),
                  ),
                ),
              );
            }
            if (c < 0) {
              return TableViewCell(
                child: GestureDetector(
                  key: ValueKey('row_$r'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => widget.onTapRow(r),
                  child: Container(
                    decoration: _headerDecoration(r >= sel.firstRow && r <= sel.lastRow),
                    alignment: Alignment.center,
                    child: Text(
                      '${r + 1}',
                      style: TextStyle(fontSize: 11 * _zoom, fontWeight: FontWeight.w600, color: AppColors.inkMuted),
                    ),
                  ),
                ),
              );
            }

            final merge = mergeOf[CellRef.key(r, c)];
            // A merged block cannot cross the frozen edge; it is drawn as separate cells there.
            final crossesFrozen =
                merge != null && ((merge.firstRow < frozenRows && merge.lastRow >= frozenRows) || (merge.firstCol < frozenCols && merge.lastCol >= frozenCols));
            final use = crossesFrozen ? null : merge;
            final anchor = use == null ? (r: r, c: c) : (r: use.firstRow, c: use.firstCol);
            final cell = _sheet.cells[CellRef.key(anchor.r, anchor.c)] ?? SheetCell(style: _sheet.rowStyles[r] ?? _sheet.colStyles[c] ?? 0);
            final style = cond.apply(widget.workbook.styles.at(cell.style), anchor.r, anchor.c);
            final desc = describeCell(cell, style, date1904: widget.workbook.date1904);
            final inSelection = r >= sel.firstRow && r <= sel.lastRow && c >= sel.firstCol && c <= sel.lastCol;
            final active = (r == s.row && c == s.col) || (use != null && activeMerge == use);
            final isMatch = matchKeys.contains(CellRef.key(anchor.r, anchor.c));
            final multi = !sel.isSingle;

            final child = GestureDetector(
              key: ValueKey('cell_${r}_$c'),
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (_chart != null) setState(() => _chart = null);
                widget.onTapCell(anchor.r, anchor.c);
              },
              child: Container(
                decoration: BoxDecoration(
                  color: style.fill != null ? Color(style.fill!) : Colors.white,
                  border: const Border(
                    right: BorderSide(color: _gridLine, width: 0.7),
                    bottom: BorderSide(color: _gridLine, width: 0.7),
                  ),
                ),
                foregroundDecoration: BoxDecoration(
                  color: isMatch ? const Color(0x66FFC107) : (inSelection && multi ? AppColors.primary.withValues(alpha: 0.14) : null),
                  border: active ? Border.all(color: AppColors.primary, width: 2) : null,
                ),
                padding: EdgeInsets.symmetric(horizontal: 3 * _zoom),
                alignment: switch (desc.align) {
                  HAlign.right => style.wrap ? AlignmentDirectional.topEnd : AlignmentDirectional.bottomEnd,
                  HAlign.center => style.wrap ? Alignment.topCenter : Alignment.bottomCenter,
                  _ => style.wrap ? AlignmentDirectional.topStart : AlignmentDirectional.bottomStart,
                },
                child: desc.text.isEmpty
                    ? null
                    : Text(
                        desc.text,
                        maxLines: style.wrap ? null : 1,
                        softWrap: style.wrap,
                        overflow: style.wrap ? TextOverflow.clip : TextOverflow.ellipsis,
                        textAlign: switch (desc.align) {
                          HAlign.right => TextAlign.end,
                          HAlign.center => TextAlign.center,
                          _ => TextAlign.start,
                        },
                        style: TextStyle(
                          fontSize: (style.fontSize ?? 11) * 1.2 * _zoom,
                          height: 1.15,
                          color: Color(style.fontColor ?? 0xFF000000),
                          fontWeight: style.bold ? FontWeight.w700 : FontWeight.w400,
                          fontStyle: style.italic ? FontStyle.italic : FontStyle.normal,
                          decoration: style.underline ? TextDecoration.underline : TextDecoration.none,
                        ),
                      ),
              ),
            );
            if (use == null) return TableViewCell(child: child);
            return TableViewCell(
              rowMergeStart: use.firstRow + 1,
              rowMergeSpan: use.lastRow - use.firstRow + 1,
              columnMergeStart: use.firstCol + 1,
              columnMergeSpan: use.lastCol - use.firstCol + 1,
              child: child,
            );
          },
        );
        if (_sheet.charts.isEmpty) return table;
        return Stack(children: [Positioned.fill(child: table), _chartLayer(chartData, rowHeader, colHeader)]);
      },
    );
  }

  BoxDecoration _headerDecoration(bool selected) => BoxDecoration(
    color: selected ? AppColors.primarySoft : _headerFill,
    border: const Border(
      right: BorderSide(color: _gridLine, width: 0.7),
      bottom: BorderSide(color: _gridLine, width: 0.7),
    ),
  );
}

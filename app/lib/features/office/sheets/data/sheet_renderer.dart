import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show TextAlign, TextDirection, TextPainter, TextSpan, TextStyle, FontStyle, FontWeight, TextDecoration;
import 'package:path/path.dart' as p;

import '../../../export/data/document_builders.dart';
import '../../../export/domain/entities/export_options.dart';
import '../domain/cell_display.dart';
import '../domain/sheet_model.dart';

class SheetTooLargeException implements Exception {
  const SheetTooLargeException(this.pages);
  final int pages;
}

const _dpi = 150.0;
const _pxPerPt = _dpi / 72;

double _colPx(Sheet s, int c) => s.hiddenCols.contains(c) ? 0 : (s.widthOf(c) * 7 + 5) * _dpi / 96;
double _rowPx(Sheet s, int r) => s.hiddenRows.contains(r) ? 0 : s.heightOf(r) * _pxPerPt;

/// Draws sheets onto A4 pages (as pictures) so they can be turned into a PDF or images. Text of any language is drawn with the device's fonts.
class SheetRenderer {
  SheetRenderer({required this.workbook});

  final Workbook workbook;

  static const maxPages = 120;

  /// The pages of every sheet in [sheets], written as PNG files into [dir].
  Future<List<PageSource>> renderPages(List<Sheet> sheets, Directory dir, {void Function(int done, int total)? onProgress}) async {
    final plans = [for (final s in sheets) _plan(s)];
    final total = plans.fold<int>(0, (a, b) => a + b.pages);
    if (total > maxPages) throw SheetTooLargeException(total);
    final out = <PageSource>[];
    var done = 0;
    final stamp = DateTime.now().microsecondsSinceEpoch;
    for (var i = 0; i < sheets.length; i++) {
      final plan = plans[i];
      var pageNo = 0;
      for (final rows in plan.rowGroups) {
        for (final cols in plan.colGroups) {
          pageNo++;
          final bytes = await _drawPage(sheets[i], plan, rows, cols, '${sheets[i].name}  -  page $pageNo of ${plan.pages}');
          final path = p.join(dir.path, 'sheet_${stamp}_${out.length}.png');
          await File(path).writeAsBytes(bytes.data, flush: true);
          out.add(PageSource(path: path, width: bytes.width, height: bytes.height));
          onProgress?.call(++done, total);
        }
      }
    }
    return out;
  }

  _Plan _plan(Sheet s) {
    var lastRow = s.lastRow, lastCol = s.lastCol;
    for (final m in s.merges) {
      lastRow = math.max(lastRow, m.lastRow);
      lastCol = math.max(lastCol, m.lastCol);
    }
    if (lastRow < 0) {
      lastRow = 0;
      lastCol = 0;
    }
    const margin = 70.0;
    final totalWidth = [for (var c = 0; c <= lastCol; c++) _colPx(s, c)].fold<double>(0, (a, b) => a + b);
    final portrait = totalWidth <= 1240 - 2 * margin;
    final pageW = portrait ? 1240.0 : 1754.0, pageH = portrait ? 1754.0 : 1240.0;
    final areaW = pageW - 2 * margin, areaH = pageH - 2 * margin - 30;

    List<(int, int)> group(int count, double Function(int) size, double limit) {
      final groups = <(int, int)>[];
      var start = 0;
      var used = 0.0;
      for (var i = 0; i < count; i++) {
        final sz = size(i);
        if (i > start && used + sz > limit) {
          groups.add((start, i - 1));
          start = i;
          used = 0;
        }
        used += sz;
      }
      groups.add((start, count - 1));
      return groups;
    }

    return _Plan(
      lastRow: lastRow,
      lastCol: lastCol,
      pageW: pageW,
      pageH: pageH,
      margin: margin,
      rowGroups: group(lastRow + 1, (r) => _rowPx(s, r), areaH),
      colGroups: group(lastCol + 1, (c) => math.min(_colPx(s, c), areaW), areaW),
    );
  }

  Future<({List<int> data, int width, int height})> _drawPage(Sheet s, _Plan plan, (int, int) rows, (int, int) cols, String footer) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder, ui.Rect.fromLTWH(0, 0, plan.pageW, plan.pageH));
    canvas.drawRect(ui.Rect.fromLTWH(0, 0, plan.pageW, plan.pageH), ui.Paint()..color = const ui.Color(0xFFFFFFFF));

    final areaW = plan.pageW - 2 * plan.margin;
    // x and y offsets of each visible row and column within this page.
    final xs = <int, double>{}, ys = <int, double>{};
    var x = plan.margin, y = plan.margin;
    for (var c = cols.$1; c <= cols.$2; c++) {
      xs[c] = x;
      x += math.min(_colPx(s, c), areaW);
    }
    for (var r = rows.$1; r <= rows.$2; r++) {
      ys[r] = y;
      y += _rowPx(s, r);
    }
    final right = x, bottom = y;
    double colW(int c) => math.min(_colPx(s, c), areaW);

    final grid = ui.Paint()
      ..color = const ui.Color(0xFFD0D0D0)
      ..strokeWidth = 1;
    final merged = <int>{};
    final drawn = <(int, int, int, int)>[];

    for (final m in s.merges) {
      if (m.firstRow < rows.$1 || m.firstRow > rows.$2 || m.firstCol < cols.$1 || m.firstCol > cols.$2) continue;
      drawn.add((m.firstRow, m.firstCol, math.min(m.lastRow, rows.$2), math.min(m.lastCol, cols.$2)));
    }
    for (final m in drawn) {
      for (var r = m.$1; r <= m.$3; r++) {
        for (var c = m.$2; c <= m.$4; c++) {
          merged.add(CellRef.key(r, c));
        }
      }
    }

    void paintCell(int r, int c, double left, double top, double w, double h) {
      if (w <= 0 || h <= 0) return;
      final cell = s.cells[CellRef.key(r, c)] ?? SheetCell(style: s.rowStyles[r] ?? s.colStyles[c] ?? 0);
      final style = workbook.styles.at(cell.style);
      final rect = ui.Rect.fromLTWH(left, top, w, h);
      if (style.fill != null) canvas.drawRect(rect, ui.Paint()..color = ui.Color(style.fill!));
      final desc = describeCell(cell, style, date1904: workbook.date1904);
      if (desc.text.isEmpty) return;
      final tp = TextPainter(
        text: TextSpan(
          text: desc.text,
          style: TextStyle(
            color: ui.Color(style.fontColor ?? 0xFF000000),
            fontSize: (style.fontSize ?? 11) * _pxPerPt,
            fontWeight: style.bold ? FontWeight.w700 : FontWeight.w400,
            fontStyle: style.italic ? FontStyle.italic : FontStyle.normal,
            decoration: style.underline ? TextDecoration.underline : TextDecoration.none,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: switch (desc.align) {
          HAlign.right => TextAlign.right,
          HAlign.center => TextAlign.center,
          _ => TextAlign.left,
        },
        maxLines: style.wrap ? null : 1,
        ellipsis: style.wrap ? null : '\u2026',
      )..layout(minWidth: w - 8, maxWidth: math.max(1, w - 8));
      canvas.save();
      canvas.clipRect(rect);
      final dy = style.wrap ? top + 2 : math.max(top, top + h - tp.height - 3);
      tp.paint(canvas, ui.Offset(left + 4, dy));
      canvas.restore();
      tp.dispose();
    }

    for (var r = rows.$1; r <= rows.$2; r++) {
      for (var c = cols.$1; c <= cols.$2; c++) {
        if (merged.contains(CellRef.key(r, c))) continue;
        paintCell(r, c, xs[c]!, ys[r]!, colW(c), _rowPx(s, r));
      }
    }
    // Grid lines first, so merged blocks are drawn over them.
    for (var r = rows.$1; r <= rows.$2 + 1; r++) {
      final yy = r <= rows.$2 ? ys[r]! : bottom;
      canvas.drawLine(ui.Offset(plan.margin, yy), ui.Offset(right, yy), grid);
    }
    for (var c = cols.$1; c <= cols.$2 + 1; c++) {
      final xx = c <= cols.$2 ? xs[c]! : right;
      canvas.drawLine(ui.Offset(xx, plan.margin), ui.Offset(xx, bottom), grid);
    }
    for (final m in drawn) {
      final left = xs[m.$2]!, top = ys[m.$1]!;
      var w = 0.0, h = 0.0;
      for (var c = m.$2; c <= m.$4; c++) {
        w += colW(c);
      }
      for (var r = m.$1; r <= m.$3; r++) {
        h += _rowPx(s, r);
      }
      canvas.drawRect(ui.Rect.fromLTWH(left, top, w, h), ui.Paint()..color = const ui.Color(0xFFFFFFFF));
      paintCell(m.$1, m.$2, left, top, w, h);
      canvas.drawRect(
        ui.Rect.fromLTWH(left, top, w, h),
        ui.Paint()
          ..color = const ui.Color(0xFFD0D0D0)
          ..style = ui.PaintingStyle.stroke,
      );
    }

    final foot = TextPainter(
      text: TextSpan(
        text: footer,
        style: const TextStyle(color: ui.Color(0xFF888888), fontSize: 22),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    foot.paint(canvas, ui.Offset(plan.margin, plan.pageH - plan.margin + 4));
    foot.dispose();

    final picture = recorder.endRecording();
    final image = await picture.toImage(plan.pageW.round(), plan.pageH.round());
    picture.dispose();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final w = image.width, h = image.height;
    image.dispose();
    if (data == null) throw StateError('The page could not be drawn');
    return (data: data.buffer.asUint8List(), width: w, height: h);
  }

  /// Renders [sheets] and writes them as one PDF.
  Future<void> exportPdf(List<Sheet> sheets, {required Directory workDir, required String outputPath, void Function(int done, int total)? onProgress}) async {
    await workDir.create(recursive: true);
    final pages = await renderPages(sheets, workDir, onProgress: onProgress);
    try {
      await buildPdf(pages, ExportQuality.high, outputPath);
    } finally {
      for (final page in pages) {
        try {
          File(page.path).deleteSync();
        } catch (_) {}
      }
    }
  }
}

class _Plan {
  _Plan({
    required this.lastRow,
    required this.lastCol,
    required this.pageW,
    required this.pageH,
    required this.margin,
    required this.rowGroups,
    required this.colGroups,
  });
  final int lastRow, lastCol;
  final double pageW, pageH, margin;
  final List<(int, int)> rowGroups, colGroups;
  int get pages => rowGroups.length * colGroups.length;
}

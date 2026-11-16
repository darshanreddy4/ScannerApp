import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:doculoom/features/office/sheets/data/sheet_renderer.dart';
import 'package:doculoom/features/office/sheets/data/xlsx_reader.dart';
import 'package:doculoom/features/office/sheets/data/xlsx_writer.dart';
import 'package:doculoom/features/office/sheets/domain/chart.dart';
import 'package:doculoom/features/office/sheets/domain/formula.dart';
import 'package:doculoom/features/office/sheets/domain/sheet_edit.dart';
import 'package:doculoom/features/office/sheets/domain/sheet_model.dart';

void main() {
  testWidgets('a workbook renders to pages and a PDF', (tester) async {
    final wb = readXlsx(File('test/fixtures/office/basic.xlsx').readAsBytesSync());
    FormulaEngine(wb, now: DateTime(2024, 5, 17)).recalculateAll();
    final dir = Directory.systemTemp.createTempSync('sheet_render');
    await tester.runAsync(() async {
      final renderer = SheetRenderer(workbook: wb);
      final pages = await renderer.renderPages([wb.sheets.first], dir);
      expect(pages, hasLength(1));
      File(pages.first.path).copySync('/tmp/sheet_page1.png');
      final out = '${dir.path}/out.pdf';
      await renderer.exportPdf(wb.visibleSheets, workDir: dir, outputPath: out);
      final bytes = File(out).readAsBytesSync();
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(RegExp(r'/Type\s*/Page(?![a-z])').allMatches(String.fromCharCodes(bytes)).length, 2, reason: 'one page for each visible sheet');
    });
    dir.deleteSync(recursive: true);
  });

  testWidgets('charts are drawn on pages after the cells, as many to a page as fit', (tester) async {
    final wb = newWorkbook();
    final e = SheetEditor(wb);
    final s = wb.sheets.first;
    const rows = [
      ['Month', 'North', 'South'],
      ['Jan', '10', '7'],
      ['Feb', '12', '9'],
      ['Mar', '9', '14'],
    ];
    for (var r = 0; r < rows.length; r++) {
      for (var c = 0; c < 3; c++) {
        e.setInput(s, r, c, rows[r][c]);
      }
    }
    for (final k in [ChartKind.column, ChartKind.line, ChartKind.pie]) {
      e.addChart(s, const MergeRange(0, 0, 3, 2), k, title: k.name);
    }
    final dir = Directory.systemTemp.createTempSync('sheet_render_charts');
    await tester.runAsync(() async {
      final renderer = SheetRenderer(workbook: wb);
      final pages = await renderer.renderPages([s], dir);
      expect(pages.length, greaterThanOrEqualTo(2), reason: 'the cells, then the charts');
      expect(pages.length, lessThanOrEqualTo(3));
      File(pages.last.path).copySync('/tmp/sheet_chart_page.png');
      final out = '${dir.path}/out.pdf';
      await renderer.exportPdf([s], workDir: dir, outputPath: out);
      expect(String.fromCharCodes(File(out).readAsBytesSync().take(5)), '%PDF-');
    });
    dir.deleteSync(recursive: true);
  });
}

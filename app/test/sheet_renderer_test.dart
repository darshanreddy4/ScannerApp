import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:doculoom/features/office/sheets/data/sheet_renderer.dart';
import 'package:doculoom/features/office/sheets/data/xlsx_reader.dart';
import 'package:doculoom/features/office/sheets/domain/formula.dart';

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
}

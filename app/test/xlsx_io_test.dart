import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:scanvault/features/office/sheets/data/xlsx_reader.dart';
import 'package:scanvault/features/office/sheets/data/xlsx_writer.dart';
import 'package:scanvault/features/office/sheets/domain/number_format.dart';
import 'package:scanvault/features/office/sheets/domain/sheet_model.dart';

Uint8List fixture(String name) => File('test/fixtures/office/$name').readAsBytesSync();

void main() {
  group('readXlsx', () {
    test('reads values, formulas, styles, merges, sizes and panes', () {
      final wb = readXlsx(fixture('basic.xlsx'));
      expect(wb.sheets.map((s) => s.name), ['Sales', 'Hidden', 'Notes']);
      expect(wb.sheets[1].hidden, isTrue);
      final s = wb.sheets.first;
      expect((s.cellAt(0, 0).value as TextValue).text, 'Item');
      expect((s.cellAt(1, 1).value as NumberValue).number, 3);
      expect(s.cellAt(1, 3).formula, 'B2*C2');
      expect(s.cellAt(5, 3).formula, 'SUM(D2:D4)');
      expect(s.cellAt(0, 5).value, isA<BoolValue>());
      expect(s.merges.single.toString(), 'A8:C8');
      expect(s.colWidths[0], 20);
      expect(s.rowHeights[2], 30);
      expect(s.frozenRows, 1);
      expect(s.frozenCols, 1);
      final head = wb.styles.at(s.cellAt(0, 0).style);
      expect(head.bold, isTrue);
      expect(head.fontColor, 0xFFFF0000);
      expect(wb.styles.at(s.cellAt(0, 1).style).fill, 0xFFFFFF00);
      expect(wb.styles.at(s.cellAt(1, 2).style).numFmt, '0.00');
      expect(NumberFormatter.isDate(wb.styles.at(s.cellAt(1, 4).style).numFmt), isTrue);
      expect(wb.styles.at(s.cellAt(7, 0).style).align, HAlign.center);
      expect((wb.sheets[2].cellAt(0, 0).value as TextValue).text, 'line1\nline2 & <tag>');
    });

    test('reads shared strings, rich text, dates and cached formula values', () {
      final wb = readXlsx(fixture('strings.xlsx'));
      final s = wb.sheets.first;
      expect((s.cellAt(1, 0).value as TextValue).text, 'Hello');
      expect((s.cellAt(3, 0).value as TextValue).text, 'plain bold end');
      expect(s.cellAt(1, 1).formula, 'B1*2');
      expect((s.cellAt(1, 1).value as NumberValue).number, 2469);
      final st = wb.styles.at(s.cellAt(0, 1).style);
      expect(st.bold, isTrue);
      expect(st.numFmt, '#,##0.00');
      expect(s.rowHeights[5], closeTo(40, 0.5));
      expect(s.colWidths[2], closeTo(15, 0.8));
    });

    test('expands shared formulas', () {
      final s = readXlsx(fixture('shared_formula.xlsx')).sheets.first;
      expect(s.cellAt(1, 3).formula, 'B2*C2');
      expect(s.cellAt(2, 3).formula, 'B3*C3');
      expect(s.cellAt(3, 3).formula, 'B4*C4');
    });

    test('rejects files that are not workbooks', () {
      expect(() => readXlsx(Uint8List.fromList([1, 2, 3, 4])), throwsA(isA<XlsxFormatException>()));
    });
  });

  group('writeXlsx', () {
    test('an untouched workbook is rewritten with the same sheets', () {
      final wb = readXlsx(fixture('basic.xlsx'));
      final again = readXlsx(writeXlsx(wb));
      expect(again.sheets.map((s) => s.name), ['Sales', 'Hidden', 'Notes']);
      expect(again.sheets.first.cellAt(1, 3).formula, 'B2*C2');
    });

    test('edits, styles, merges, columns and new sheets survive', () {
      final wb = readXlsx(fixture('basic.xlsx'));
      final s = wb.sheets.first;
      s.setCell(0, 0, const SheetCell(value: TextValue('Name & <more>'), style: 0));
      final bold = wb.styles.indexOf(const CellStyle(bold: true, fill: 0xFF00FF00, numFmt: '0.0%'), from: s.cellAt(1, 2).style);
      s.setCell(1, 2, SheetCell(value: const NumberValue(0.5), style: bold));
      s.setCell(9, 0, const SheetCell(value: TextValue(' padded '), formula: null));
      s.setCell(9, 1, const SheetCell(value: NumberValue(7), formula: 'B2+4'));
      s.colWidths[4] = 33;
      s.colsDirty = true;
      s.merges.add(const MergeRange(9, 2, 9, 3));
      s.mergesDirty = true;
      wb.sheets.add(Sheet(name: 'New <1>')..setCell(0, 0, const SheetCell(value: BoolValue(true))));
      wb.sheets.removeAt(1);
      wb.structureChanged = true;
      final bytes = writeXlsx(wb);
      File('/tmp/roundtrip.xlsx').writeAsBytesSync(bytes);

      final back = readXlsx(bytes);
      expect(back.sheets.map((x) => x.name), ['Sales', 'Notes', 'New <1>']);
      final b = back.sheets.first;
      expect((b.cellAt(0, 0).value as TextValue).text, 'Name & <more>');
      expect((b.cellAt(9, 0).value as TextValue).text, ' padded ');
      expect(b.cellAt(9, 1).formula, 'B2+4');
      final st = back.styles.at(b.cellAt(1, 2).style);
      expect(st.bold, isTrue);
      expect(st.fill, 0xFF00FF00);
      expect(st.numFmt, '0.0%');
      expect(back.styles.at(b.cellAt(0, 1).style).fill, 0xFFFFFF00, reason: 'untouched styles stay');
      expect(b.colWidths[4], 33);
      expect(b.colWidths[0], 20);
      expect(b.merges.map((m) => m.toString()), containsAll(['A8:C8', 'C10:D10']));
      expect(b.frozenRows, 1);
      expect(back.sheets[2].cellAt(0, 0).value, isA<BoolValue>());
    });

    test('a new workbook can be written and read back', () {
      final wb = newWorkbook(sheetName: 'Mine');
      wb.sheets.first.setCell(0, 0, const SheetCell(value: TextValue('hi')));
      wb.sheets.first.setCell(1, 0, const SheetCell(value: NumberValue(2.5)));
      final back = readXlsx(writeXlsx(wb));
      expect(back.sheets.single.name, 'Mine');
      expect((back.sheets.single.cellAt(1, 0).value as NumberValue).number, 2.5);
    });
  });
}

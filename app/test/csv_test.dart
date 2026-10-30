import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:doculoom/features/office/sheets/data/csv.dart';
import 'package:doculoom/features/office/sheets/data/xlsx_reader.dart';
import 'package:doculoom/features/office/sheets/data/xlsx_writer.dart';
import 'package:doculoom/features/office/sheets/domain/sheet_model.dart';

void main() {
  test('parses quotes, embedded separators, line breaks and both newline styles', () {
    final rows = parseCsv('a,"b,1","say ""hi"""\r\n1,"two\nlines",\n\nlast,x,y');
    expect(rows, [
      ['a', 'b,1', 'say "hi"'],
      ['1', 'two\nlines', ''],
      ['last', 'x', 'y'],
    ]);
  });

  test('detects semicolon and tab separators', () {
    expect(detectDelimiter('a;b;c\n1;2;3'), ';');
    expect(detectDelimiter('a\tb\n1\t2'), '\t');
    expect(detectDelimiter('a,b\n1,2'), ',');
    expect(parseCsv('x;y\n1,5;2').last, ['1,5', '2']);
  });

  test('decodes UTF-8 with a mark and falls back to Latin-1', () {
    expect(decodeCsvBytes(Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode('é,ü')])), 'é,ü');
    expect(decodeCsvBytes(Uint8List.fromList([0x63, 0x61, 0x66, 0xE9])), 'café');
  });

  test('CSV to workbook infers types and keeps codes as text; workbook to CSV quotes properly', () {
    final wb = workbookFromCsv(parseCsv('name,qty,price,when,zip\n"Smith, J",3,1.5,2024-03-05,00123\nx,TRUE,12%,,"a ""q"""'));
    final s = wb.sheets.first;
    expect((s.cellAt(1, 1).value as NumberValue).number, 3);
    expect((s.cellAt(1, 4).value as TextValue).text, '00123');
    expect((s.cellAt(2, 1).value as BoolValue).flag, isTrue);
    expect((s.cellAt(2, 2).value as NumberValue).number, 0.12);
    expect(wb.styles.at(s.cellAt(1, 3).style).numFmt, 'yyyy-mm-dd');
    final csv = sheetToCsv(s, wb.styles);
    expect(csv, 'name,qty,price,when,zip\r\n"Smith, J",3,1.5,2024-03-05,00123\r\nx,TRUE,12%,,"a ""q"""\r\n');
    // The whole path to an .xlsx file and back.
    final back = readXlsx(writeXlsx(wb));
    expect(sheetToCsv(back.sheets.first, back.styles), csv);
  });
}

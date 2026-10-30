import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:doculoom/features/office/sheets/data/csv.dart';
import 'package:doculoom/features/office/sheets/data/xlsx_reader.dart';
import 'package:doculoom/features/office/sheets/domain/sheet_edit.dart';
import 'package:doculoom/features/office/sheets/domain/sheet_model.dart';
import 'package:doculoom/features/tables/data/table_export.dart';

void main() {
  const rows = [
    ['Item', 'Qty', 'Price', 'Code'],
    ['Apples', '12', '3.50', '007'],
    ['Green tea, loose', '4', '12.00', '1234567890123456789'],
    ['Rice "basmati"', '2', '40.25', ''],
  ];

  CellValue valueAt(Workbook wb, int r, int c) => wb.sheets.first.cells[CellRef.key(r, c)]?.value ?? const EmptyValue();

  group('Excel file', () {
    final wb = readXlsx(tableToXlsx(rows));

    test('opens as a workbook with one sheet called Table and every cell in place', () {
      expect(wb.sheets, hasLength(1));
      expect(wb.sheets.first.name, 'Table');
      expect((valueAt(wb, 0, 0) as TextValue).text, 'Item');
      expect((valueAt(wb, 2, 0) as TextValue).text, 'Green tea, loose');
      expect((valueAt(wb, 3, 0) as TextValue).text, 'Rice "basmati"');
      expect(valueAt(wb, 3, 3), isA<EmptyValue>());
    });

    test('numbers are numbers, but codes with leading zeros and very long numbers stay text', () {
      expect((valueAt(wb, 1, 1) as NumberValue).number, 12);
      expect((valueAt(wb, 1, 2) as NumberValue).number, 3.5);
      expect((valueAt(wb, 1, 3) as TextValue).text, '007');
      expect((valueAt(wb, 2, 3) as TextValue).text, '1234567890123456789');
    });

    test('the heading row is bold and the rows under it are not', () {
      final header = wb.styles.at(wb.sheets.first.cells[CellRef.key(0, 1)]!.style);
      final body = wb.styles.at(wb.sheets.first.cells[CellRef.key(1, 1)]!.style);
      expect(header.bold, isTrue);
      expect(body.bold, isFalse);
    });

    test('columns are as wide as their longest text, within limits', () {
      final w = wb.sheets.first.colWidths;
      expect(w[0]!, greaterThan(w[1]!));
      expect(w[1]!, 8, reason: 'never narrower than 8');
      final wide = readXlsx(
        tableToXlsx([
          ['x' * 200, 'y'],
        ]),
      );
      expect(wide.sheets.first.colWidths[0], 60);
    });

    test('a table with numbers in its first row gets no bold heading', () {
      final plain = readXlsx(
        tableToXlsx(const [
          ['1', '2'],
          ['3', '4'],
        ]),
      );
      expect(plain.styles.at(plain.sheets.first.cells[CellRef.key(0, 0)]!.style).bold, isFalse);
    });

    test('a table with a single row, or an empty one, is still a valid file', () {
      final one = readXlsx(
        tableToXlsx(const [
          ['a', 'b'],
        ]),
      );
      expect((valueAt(one, 0, 1) as TextValue).text, 'b');
      expect(() => readXlsx(tableToXlsx(const [])), returnsNormally);
    });

    test('text in other scripts survives', () {
      final hindi = readXlsx(
        tableToXlsx(const [
          ['नाम', 'शहर'],
          ['आशा', 'पुणे'],
        ]),
      );
      expect((valueAt(hindi, 1, 1) as TextValue).text, 'पुणे');
    });

    test('shown values are what the sheet screen would show', () {
      expect(displayText(wb.sheets.first.cells[CellRef.key(1, 2)], wb.styles.at), '3.5');
    });
  });

  group('CSV file', () {
    final bytes = tableToCsv(rows);

    test('starts with a byte order mark so Excel reads accents, and ends rows with CRLF', () {
      expect(bytes.take(3), [0xEF, 0xBB, 0xBF]);
      final text = utf8.decode(bytes.skip(3).toList());
      expect(text.endsWith('\r\n'), isTrue);
      expect(text.split('\r\n').where((l) => l.isNotEmpty), hasLength(4));
    });

    test('commas and quotes are quoted so the cells stay whole, and it reads back as the same table', () {
      final text = utf8.decode(bytes.skip(3).toList());
      expect(text, contains('"Green tea, loose"'));
      expect(text, contains('"Rice ""basmati"""'));
      final back = parseCsv(text);
      expect(back, rows);
    });

    test('other scripts and an empty table', () {
      expect(
        utf8.decode(
          tableToCsv(const [
            ['नाम'],
          ]).skip(3).toList(),
        ),
        'नाम\r\n',
      );
      expect(tableToCsv(const []), [0xEF, 0xBB, 0xBF]);
    });
  });
}

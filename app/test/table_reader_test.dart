import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:doculoom/features/ocr/domain/ocr_models.dart';
import 'package:doculoom/features/tables/domain/table_reader.dart';

import 'support/table_pages.dart';

void main() {
  const data = [
    ['Item', 'Qty', 'Price'],
    ['Apples', '12', '3.50'],
    ['Green tea', '4', '12.00'],
    ['Rice bag', '2', '40.25'],
  ];

  group('rows and columns', () {
    test('a table comes out cell by cell', () {
      final t = readTable(page(grid(data, [100, 400, 700])));
      expect(t.rows, data);
      expect(t.columnCount, 3);
    });

    test('the same table when every row is one line with the words of all its cells', () {
      final t = readTable(page(grid(data, [100, 400, 700]), oneLinePerRow: true));
      expect(t.rows, data);
    });

    test('words of one cell stay together, even several of them', () {
      final t = readTable(
        page(
          grid(
            [
              ['City', 'Population'],
              ['New York', '8300000'],
              ['San Francisco Bay Area', '7700000'],
            ],
            [100, 600],
          ),
        ),
      );
      expect(t.rows[1], ['New York', '8300000']);
      expect(t.rows[2], ['San Francisco Bay Area', '7700000']);
    });

    test('a missing value keeps the others in their columns', () {
      final t = readTable(
        page(
          grid(
            [
              ['Name', 'Phone', 'City'],
              ['Asha', '', 'Pune'],
              ['Ravi', '98765', ''],
              ['Meera', '55555', 'Goa'],
            ],
            [100, 400, 700],
          ),
        ),
      );
      expect(t.rows[1], ['Asha', '', 'Pune']);
      expect(t.rows[2], ['Ravi', '98765', '']);
    });

    test('numbers lined up on their right edge are one column even though they start at different places', () {
      final cells = <(String, double, int)>[('Item', 100, 0), ('Amount', 520, 0)];
      final amounts = ['5', '1250', '75', '42000'];
      for (var i = 0; i < amounts.length; i++) {
        cells
          ..add(('Row${i + 1}', 100, i + 1))
          ..add((amounts[i], 640.0 - amounts[i].length * 14.0, i + 1));
      }
      final t = readTable(page(cells));
      expect(t.columnCount, 2);
      expect([for (final r in t.rows.skip(1)) r[1]], amounts);
    });

    test('rows that are a little higher or lower than their neighbours are still one row', () {
      final t = readTable(page(grid(data, [100, 400, 700]), jitter: 6));
      expect(t.rows, data);
    });

    test('a title above the table goes in the first column and does not add columns', () {
      final cells = [
        ('Monthly sales', 100.0, 0),
        ...[
          for (final c in grid(data, [100, 400, 700])) (c.$1, c.$2, c.$3 + 1),
        ],
      ];
      final t = readTable(page(cells));
      expect(t.columnCount, 3);
      expect(t.rows.first, ['Monthly sales', '', '']);
      expect(t.rows[1], data.first);
    });

    test('text that is not a table is one column, a line to a row', () {
      final t = readTable(page([('Dear customer,', 100, 0), ('thank you for your order', 100, 1), ('which will arrive soon', 100, 2)]));
      expect(t.columnCount, 1);
      expect(t.rows.map((r) => r.first), ['Dear customer,', 'thank you for your order', 'which will arrive soon']);
    });

    test('a page with no text, or only empty words, gives an empty table', () {
      expect(readTable(const OcrPageResult(width: 100, height: 100, blocks: [])).isEmpty, isTrue);
      final blank = OcrPageResult(
        width: 100,
        height: 100,
        blocks: [
          OcrBlock(
            lines: [
              const OcrLine(text: '  ', left: 0, top: 0, right: 10, bottom: 10),
              const OcrLine(text: 'x', left: 5, top: 5, right: 5, bottom: 5),
            ],
          ),
        ],
      );
      expect(readTable(blank).isEmpty, isTrue);
    });

    test('lines without words are used as they are, one cell each', () {
      final t = readTable(page(grid(data, [100, 400, 700]), withWords: false));
      expect(t.rows, data);
    });
  });

  group('column spacing', () {
    final close = [
      ['Name', 'Dept'],
      ['Asha', 'Sales'],
      ['Ravi', 'Ops'],
    ];

    test('with the columns close together, Tight splits them and Normal and Loose keep each row as one cell', () {
      // 26 px between the end of the first and the start of the second: 0.87 of a line height.
      final cells = [
        for (var r = 0; r < close.length; r++) ...[(close[r][0], 100.0, r), (close[r][1], 100.0 + close[r][0].length * 14.0 + 26 + (r == 0 ? 0 : 0), r)],
      ];
      final tight = readTable(page(cells), spacing: TableSpacing.tight);
      final normal = readTable(page(cells), spacing: TableSpacing.normal);
      expect(tight.columnCount, 2);
      expect(normal.columnCount, 1);
      expect(normal.rows.first.single, 'Name Dept');
    });

    test('far apart columns are columns at every setting except Loose when they are only a little apart', () {
      final cells = grid(data, [100, 400, 700]);
      for (final s in TableSpacing.values) {
        expect(readTable(page(cells), spacing: s).columnCount, 3, reason: s.name);
      }
    });
  });

  group('a tilted photo', () {
    test('the table is found when every line is turned about 4 degrees', () {
      final t = readTable(page(grid(data, [100, 400, 700]), tilt: 4 * math.pi / 180));
      expect(t.rows, data);
    });

    test('the same turn the other way', () {
      final t = readTable(page(grid(data, [100, 400, 700]), tilt: -3 * math.pi / 180));
      expect(t.rows, data);
    });
  });

  group('numbers', () {
    test('thousands commas are taken out, in the Western and the Indian way, and decimals stay', () {
      final t = readTable(
        page(
          grid(
            [
              ['Item', 'Amount'],
              ['A', '1,234.50'],
              ['B', '1,23,456'],
              ['C', '-9,000'],
              ['D', '12,34'],
            ],
            [100, 500],
          ),
        ),
      );
      expect([for (final r in t.rows.skip(1)) r[1]], ['1234.50', '123456', '-9000', '12,34']);
    });

    test('in a column of numbers a letter O or l that stands for a digit is read as a digit; text columns are left alone', () {
      final t = readTable(
        page(
          grid(
            [
              ['Code', 'Qty'],
              ['LOL', '10'],
              ['OIL', '2O'],
              ['ROLL', '30'],
              ['LIL', '4l'],
            ],
            [100, 500],
          ),
        ),
      );
      expect([for (final r in t.rows.skip(1)) r[1]], ['10', '20', '30', '41']);
      expect([for (final r in t.rows.skip(1)) r[0]], ['LOL', 'OIL', 'ROLL', 'LIL']);
    });

    test('a mixed column is not changed', () {
      final t = readTable(
        page(
          grid(
            [
              ['Ref', 'Note'],
              ['1', 'Open'],
              ['2', 'Lost'],
              ['3', 'OIO'],
            ],
            [100, 500],
          ),
        ),
      );
      expect([for (final r in t.rows.skip(1)) r[1]], ['Open', 'Lost', 'OIO']);
    });
  });

  group('tables of several pages', () {
    test('rows follow one another, and a repeated heading row is left out', () {
      final a = RecognizedTable(data);
      final b = RecognizedTable([
        data.first,
        ['Soap', '9', '1.00'],
      ]);
      final joined = joinTables([a, b]);
      expect(joined.rows, [
        ...data,
        ['Soap', '9', '1.00'],
      ]);
    });

    test('a different first row is kept, narrower tables are padded, and empty pages are skipped', () {
      final a = RecognizedTable(data);
      final b = const RecognizedTable([
        ['Soap', '9'],
      ]);
      final joined = joinTables([const RecognizedTable([]), a, b]);
      expect(joined.rows.last, ['Soap', '9', '']);
      expect(joined.rows, hasLength(5));
      expect(joinTables(const [RecognizedTable([])]).isEmpty, isTrue);
      expect(joinTables(const []).isEmpty, isTrue);
    });

    test('a page that has only a heading row is not dropped', () {
      final joined = joinTables([
        RecognizedTable(data),
        RecognizedTable([data.first]),
      ]);
      expect(joined.rows, hasLength(5));
    });
  });
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:doculoom/features/expenses/data/expense_export.dart';
import 'package:doculoom/features/expenses/domain/receipt_record.dart';
import 'package:doculoom/features/office/sheets/data/xlsx_reader.dart';
import 'package:doculoom/features/office/sheets/data/xlsx_writer.dart';
import 'package:doculoom/features/office/sheets/domain/sheet_model.dart';

ReceiptRecord bill(
  String id,
  String vendor,
  DateTime? day,
  double? total, {
  String currency = 'INR',
  double? tax,
  ExpenseCategory c = ExpenseCategory.other,
  List<ReceiptItem> items = const [],
}) => ReceiptRecord(
  id: id,
  source: '$id.jpg',
  vendor: vendor,
  date: day,
  currency: currency,
  total: total,
  tax: tax,
  subtotal: total == null || tax == null ? null : total - tax,
  category: c,
  items: items,
);

double? number(Sheet s, int row, int col) {
  final v = s.cellAt(row, col).value;
  return v is NumberValue ? v.number : null;
}

String? text(Sheet s, int row, int col) {
  final v = s.cellAt(row, col).value;
  return v is TextValue ? v.text : null;
}

void main() {
  final bills = [
    bill('c', 'Shop C', DateTime(2026, 2, 2), 200.25, tax: 20, c: ExpenseCategory.groceries),
    bill(
      'a',
      'Shop A',
      DateTime(2026, 1, 5),
      100.0,
      tax: 10,
      c: ExpenseCategory.groceries,
      items: const [ReceiptItem(description: 'Rice', amount: 90)],
    ),
    bill('b', 'Shop B', DateTime(2026, 1, 20), 50.5, c: ExpenseCategory.dining),
    bill('d', 'Shop D', DateTime(2026, 2, 3), 30.0, currency: 'USD'),
    bill('e', 'Shop E', null, 5.0),
  ];

  group('the workbook', () {
    final wb = buildExpenseWorkbook(bills);

    test('has a sheet for bills, months, kinds of spending and lines', () {
      expect(wb.sheets.map((s) => s.name), ['Receipts', 'Monthly', 'Categories', 'Items']);
    });

    test('lists the bills by date, those without a date last', () {
      final s = wb.sheets.first;
      expect([for (var r = 1; r <= 5; r++) text(s, r, 2)], ['Shop A', 'Shop B', 'Shop C', 'Shop D', 'Shop E']);
      expect(text(s, 0, 8), 'Total');
      expect(number(s, 1, 8), 100.0);
      expect(text(s, 1, 1), '2026-01');
      expect(s.cellAt(5, 0).value, isA<EmptyValue>());
    });

    test('adds up each currency under the bills with real formulas', () {
      final s = wb.sheets.first;
      expect(text(s, 7, 2), 'Total');
      expect(text(s, 7, 4), 'INR');
      expect(number(s, 7, 8), 355.75);
      expect(number(s, 7, 6), 30.0);
      expect(s.cellAt(7, 8).formula, isNotNull);
      expect(text(s, 8, 4), 'USD');
      expect(number(s, 8, 8), 30.0);
    });

    test('sums by month for each currency, bills without a date apart', () {
      final s = wb.sheets[1];
      final rows = [
        for (var r = 1; r <= 4; r++) [text(s, r, 0), text(s, r, 1), number(s, r, 2), number(s, r, 5)],
      ];
      expect(rows, [
        ['2026-01', 'INR', 2.0, 150.5],
        ['2026-02', 'INR', 1.0, 200.25],
        ['(no date)', 'INR', 1.0, 5.0],
        ['2026-02', 'USD', 1.0, 30.0],
      ]);
      expect(text(s, 6, 0), 'All months');
      expect(number(s, 6, 5), 355.75);
      expect(number(s, 6, 2), 4.0);
      expect(number(s, 7, 5), 30.0);
    });

    test('sums by kind of spending', () {
      final s = wb.sheets[2];
      final rows = [
        for (var r = 1; r <= 4; r++) [text(s, r, 0), text(s, r, 1), number(s, r, 2), number(s, r, 3)],
      ];
      expect(rows.first, ['Groceries', 'INR', 2.0, 300.25]);
      expect(rows.any((r) => r[0] == 'Food and dining' && r[3] == 50.5), isTrue);
    });

    test('keeps the lines of the bills', () {
      final s = wb.sheets[3];
      expect([text(s, 1, 1), text(s, 1, 2), number(s, 1, 3)], ['Shop A', 'Rice', 90.0]);
    });

    test('survives being saved and opened again, with its formulas', () {
      final again = readXlsx(writeXlsx(wb));
      expect(again.sheets.map((s) => s.name), ['Receipts', 'Monthly', 'Categories', 'Items']);
      final s = again.sheets.first;
      expect(s.cellAt(7, 8).formula, contains('SUMIFS'));
      expect(number(s, 7, 8), 355.75);
      expect(number(again.sheets[1], 6, 5), 355.75);
    });
  });

  test('a bill with no currency printed is summed on its own', () {
    final wb = buildExpenseWorkbook([bill('a', 'A', DateTime(2026, 1, 1), 10.0, currency: ''), bill('b', 'B', DateTime(2026, 1, 2), 5.0, currency: '')]);
    final s = wb.sheets.first;
    expect(text(s, 4, 4), '(none)');
    expect(number(s, 4, 8), 15.0);
  });

  test('without items there is no Items sheet', () {
    final wb = buildExpenseWorkbook([bill('a', 'A', DateTime(2026, 1, 1), 10.0)]);
    expect(wb.sheets.map((s) => s.name), ['Receipts', 'Monthly', 'Categories']);
  });

  group('csv', () {
    final csv = utf8.decode(expensesToCsv(bills).sublist(3));
    final lines = const LineSplitter().convert(csv);

    test('starts with a byte order mark and a heading', () {
      expect(expensesToCsv(bills).take(3), [0xEF, 0xBB, 0xBF]);
      expect(lines.first, 'Date,Vendor,Category,Currency,Subtotal,Tax,Tip and charges,Total,Check,Source');
    });

    test('has one row for each bill with plain numbers', () {
      expect(lines.length, 6);
      expect(lines[1], startsWith('2026-01-05,Shop A,Groceries,INR,90.00,10.00,,100.00,'));
      expect(lines.last, contains('Shop E'));
    });

    test('quotes commas and says what to check', () {
      final c = utf8.decode(expensesToCsv([bill('a', 'Smith, Jones & Co', DateTime(2026, 1, 1), null)]).sublist(3));
      expect(c, contains('"Smith, Jones & Co"'));
      expect(c, contains('No total was found'));
    });
  });
}

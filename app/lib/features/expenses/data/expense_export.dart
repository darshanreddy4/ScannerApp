import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../office/sheets/data/xlsx_writer.dart';
import '../../office/sheets/domain/formula.dart';
import '../../office/sheets/domain/number_format.dart';
import '../../office/sheets/domain/sheet_model.dart';
import '../domain/expense_summary.dart';
import '../domain/receipt_record.dart';

const _none = '(none)';
String _code(ReceiptRecord r) => r.currency.isEmpty ? _none : r.currency;

List<ReceiptRecord> _byDate(List<ReceiptRecord> records) {
  final indexed = [for (var i = 0; i < records.length; i++) (i: i, r: records[i])];
  indexed.sort((a, b) {
    final da = a.r.date, db = b.r.date;
    if (da == null || db == null) {
      if (da == null && db == null) return a.i.compareTo(b.i);
      return da == null ? 1 : -1;
    }
    final c = da.compareTo(db);
    return c != 0 ? c : a.i.compareTo(b.i);
  });
  return [for (final e in indexed) e.r];
}

String _two(int n) => n.toString().padLeft(2, '0');
String _isoDay(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

String _checkText(ReceiptRecord r, bool duplicate) {
  final parts = [for (final n in r.notes) n.message, if (duplicate) ReceiptNote.duplicate.message];
  return parts.isEmpty ? 'OK' : parts.join(' ');
}

/// An Excel workbook of the bills: a sheet of bills with totals, one by month, one by kind of spending and one with the lines.
/// Sums are real formulas, so they follow when the sheet is edited; they are worked out here too, so the numbers show in any viewer.
Workbook buildExpenseWorkbook(List<ReceiptRecord> records) {
  final bills = _byDate(records);
  final dupes = duplicateIds(bills);
  final wb = newWorkbook(sheetName: 'Receipts');
  final st = wb.styles;
  final head = st.indexOf(const CellStyle(bold: true, fill: 0xFFE2E8F0));
  final money = st.indexOf(const CellStyle(numFmt: '#,##0.00'));
  final moneyBold = st.indexOf(const CellStyle(numFmt: '#,##0.00', bold: true));
  final bold = st.indexOf(const CellStyle(bold: true));
  final day = st.indexOf(const CellStyle(numFmt: 'yyyy-mm-dd'));

  void text(Sheet s, int r, int c, String v, {int style = 0}) => s.cells[CellRef.key(r, c)] = SheetCell(value: TextValue(v), style: style);
  void number(Sheet s, int r, int c, double v, {int style = 0}) => s.cells[CellRef.key(r, c)] = SheetCell(value: NumberValue(v), style: style);
  void formula(Sheet s, int r, int c, String f, {int style = 0}) =>
      s.cells[CellRef.key(r, c)] = SheetCell(value: const NumberValue(0), formula: f, style: style);
  void widths(Sheet s, List<double> w) {
    for (var i = 0; i < w.length; i++) {
      s.colWidths[i] = w[i];
    }
    s.colsDirty = true;
    s.frozenRows = 1;
    s.dirty = true;
  }

  // Bills
  final receipts = wb.sheets.first;
  const headers = ['Date', 'Month', 'Vendor', 'Category', 'Currency', 'Subtotal', 'Tax', 'Tip and charges', 'Total', 'Check', 'Source'];
  for (var c = 0; c < headers.length; c++) {
    text(receipts, 0, c, headers[c], style: head);
  }
  for (var i = 0; i < bills.length; i++) {
    final r = bills[i], row = i + 1;
    if (r.date != null) number(receipts, row, 0, NumberFormatter.dateToSerial(DateTime.utc(r.date!.year, r.date!.month, r.date!.day)), style: day);
    if (r.month.isNotEmpty) text(receipts, row, 1, r.month);
    text(receipts, row, 2, r.vendor);
    text(receipts, row, 3, r.category.label);
    text(receipts, row, 4, _code(r));
    if (r.subtotal != null) number(receipts, row, 5, r.subtotal!, style: money);
    if (r.tax != null) number(receipts, row, 6, r.tax!, style: money);
    if (r.tip != null) number(receipts, row, 7, r.tip!, style: money);
    if (r.total != null) number(receipts, row, 8, r.total!, style: money);
    text(receipts, row, 9, _checkText(r, dupes.contains(r.id)));
    text(receipts, row, 10, r.source);
  }
  final last = bills.length + 1; // the last data row in Excel numbering
  String col(String letter) => 'Receipts!\$$letter\$2:\$$letter\$${math.max(last, 2)}';

  // Totals by currency, under the bills.
  final codes = <String>[];
  for (final r in bills) {
    if (!codes.contains(_code(r))) codes.add(_code(r));
  }
  var row = bills.length + 2;
  for (final code in codes) {
    text(receipts, row, 2, 'Total', style: bold);
    text(receipts, row, 4, code, style: bold);
    for (final (c, letter) in [(5, 'F'), (6, 'G'), (7, 'H'), (8, 'I')]) {
      formula(receipts, row, c, 'SUMIFS(${letter}2:$letter$last,E2:E$last,E${row + 1})', style: moneyBold);
    }
    row++;
  }
  widths(receipts, [12, 9, 26, 18, 9, 12, 10, 14, 12, 40, 28]);

  // By month
  final months = Sheet(name: 'Monthly');
  const monthHeaders = ['Month', 'Currency', 'Bills', 'Subtotal', 'Tax', 'Total'];
  for (var c = 0; c < monthHeaders.length; c++) {
    text(months, 0, c, monthHeaders[c], style: head);
  }
  final pairs = <(String, String)>[];
  for (final r in bills) {
    final p = (r.month.isEmpty ? '(no date)' : r.month, _code(r));
    if (!pairs.contains(p)) pairs.add(p);
  }
  pairs.sort(
    (a, b) =>
        a.$2 != b.$2 ? a.$2.compareTo(b.$2) : (a.$1.startsWith('(') ? (b.$1.startsWith('(') ? 0 : 1) : (b.$1.startsWith('(') ? -1 : a.$1.compareTo(b.$1))),
  );
  for (var i = 0; i < pairs.length; i++) {
    final r = i + 1, x = r + 1;
    text(months, r, 0, pairs[i].$1);
    text(months, r, 1, pairs[i].$2);
    // A bill without a date has an empty month cell on the bills sheet.
    final monthMatch = pairs[i].$1.startsWith('(') ? '""' : 'A$x';
    formula(months, r, 2, 'COUNTIFS(${col('B')},$monthMatch,${col('E')},B$x,${col('I')},">=-1E+99")');
    for (final (c, letter) in [(3, 'F'), (4, 'G'), (5, 'I')]) {
      formula(months, r, c, 'SUMIFS(${col(letter)},${col('B')},$monthMatch,${col('E')},B$x)', style: money);
    }
  }
  var mrow = pairs.length + 2;
  final monthLast = pairs.length + 1;
  for (final code in codes) {
    text(months, mrow, 0, 'All months', style: bold);
    text(months, mrow, 1, code, style: bold);
    formula(months, mrow, 2, 'SUMIFS(C2:C${math.max(monthLast, 2)},B2:B${math.max(monthLast, 2)},B${mrow + 1})', style: bold);
    for (final (c, letter) in [(3, 'D'), (4, 'E'), (5, 'F')]) {
      formula(months, mrow, c, 'SUMIFS(${letter}2:$letter${math.max(monthLast, 2)},B2:B${math.max(monthLast, 2)},B${mrow + 1})', style: moneyBold);
    }
    mrow++;
  }
  widths(months, [12, 10, 8, 13, 12, 13]);

  // By kind of spending
  final kinds = Sheet(name: 'Categories');
  const kindHeaders = ['Category', 'Currency', 'Bills', 'Total'];
  for (var c = 0; c < kindHeaders.length; c++) {
    text(kinds, 0, c, kindHeaders[c], style: head);
  }
  final summary = summarize(bills);
  var krow = 1;
  for (final cs in summary.currencies) {
    for (final k in cs.categories) {
      final x = krow + 1;
      final code = cs.currency.isEmpty ? _none : cs.currency;
      text(kinds, krow, 0, k.category.label);
      text(kinds, krow, 1, code);
      formula(kinds, krow, 2, 'COUNTIFS(${col('D')},A$x,${col('E')},B$x,${col('I')},">=-1E+99")');
      formula(kinds, krow, 3, 'SUMIFS(${col('I')},${col('D')},A$x,${col('E')},B$x)', style: money);
      krow++;
    }
  }
  widths(kinds, [22, 10, 8, 13]);

  wb.sheets.addAll([months, kinds]);

  // Lines of the bills, when any were read.
  final lines = [
    for (final r in bills)
      for (final it in r.items) (r, it),
  ];
  if (lines.isNotEmpty) {
    final items = Sheet(name: 'Items');
    const itemHeaders = ['Date', 'Vendor', 'Item', 'Amount', 'Currency'];
    for (var c = 0; c < itemHeaders.length; c++) {
      text(items, 0, c, itemHeaders[c], style: head);
    }
    for (var i = 0; i < lines.length; i++) {
      final (r, it) = lines[i];
      if (r.date != null) text(items, i + 1, 0, _isoDay(r.date!));
      text(items, i + 1, 1, r.vendor);
      text(items, i + 1, 2, it.description);
      number(items, i + 1, 3, it.amount, style: money);
      text(items, i + 1, 4, _code(r));
    }
    widths(items, [12, 26, 34, 12, 10]);
    wb.sheets.add(items);
  }

  for (final s in wb.sheets) {
    s.dirty = true;
  }
  wb.structureChanged = true;
  FormulaEngine(wb).recalculateAll();
  return wb;
}

Uint8List expensesToXlsx(List<ReceiptRecord> records) => writeXlsx(buildExpenseWorkbook(records));

String _quote(String f) => f.contains(',') || f.contains('"') || f.contains('\n') || f.contains('\r') ? '"${f.replaceAll('"', '""')}"' : f;

/// The bills as CSV that Excel opens with accents intact: one row for each bill, amounts as plain numbers.
Uint8List expensesToCsv(List<ReceiptRecord> records) {
  String n(double? v) => v == null ? '' : v.toStringAsFixed(2);
  final bills = _byDate(records);
  final dupes = duplicateIds(bills);
  final b = StringBuffer()..write('Date,Vendor,Category,Currency,Subtotal,Tax,Tip and charges,Total,Check,Source\r\n');
  for (final r in bills) {
    final fields = [
      r.date == null ? '' : _isoDay(r.date!),
      r.vendor,
      r.category.label,
      r.currency,
      n(r.subtotal),
      n(r.tax),
      n(r.tip),
      n(r.total),
      _checkText(r, dupes.contains(r.id)),
      r.source,
    ];
    b.write('${fields.map(_quote).join(',')}\r\n');
  }
  return Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(b.toString())]);
}

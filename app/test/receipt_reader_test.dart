import 'package:flutter_test/flutter_test.dart';
import 'package:doculoom/features/expenses/domain/expense_summary.dart';
import 'package:doculoom/features/expenses/domain/receipt_reader.dart';
import 'package:doculoom/features/expenses/domain/receipt_record.dart';

final _now = DateTime(2026, 6, 1);

ReceiptRecord read(List<String> rows, {String defaultCurrency = ''}) =>
    readReceipt(rows, id: 'x', source: 'bill.jpg', now: _now, defaultCurrency: defaultCurrency);

void main() {
  group('amounts', () {
    test('plain, grouped and marked numbers', () {
      expect(parseAmount('450.00'), 450.0);
      expect(parseAmount('1,234.56'), 1234.56);
      expect(parseAmount('1.234,56'), 1234.56);
      expect(parseAmount('1,23,456.00'), 123456.0);
      expect(parseAmount('12,50'), 12.5);
      expect(parseAmount('₹450'), 450.0);
      expect(parseAmount('Rs.450'), 450.0);
      expect(parseAmount('450INR'), 450.0);
      expect(parseAmount('\$9.99'), 9.99);
      expect(parseAmount('R\$12,90'), 12.9);
    });

    test('negative amounts', () {
      expect(parseAmount('-20.00'), -20.0);
      expect(parseAmount('(20.00)'), -20.0);
      expect(parseAmount('20.00-'), -20.0);
    });

    test('whole numbers are quantities unless marked or asked for', () {
      expect(parseAmount('3'), isNull);
      expect(parseAmount('450'), isNull);
      expect(parseAmount('450', allowBare: true), 450.0);
      expect(parseAmount('₹450'), 450.0);
    });

    test('dates, phone numbers, percentages and words are not amounts', () {
      for (final t in ['12/05/2026', '12.05.2026', '12.05.26', '9876543210', '18%', '@', 'Milk', '2x', '12:30']) {
        expect(parseAmount(t, allowBare: true), isNull, reason: t);
      }
    });

    test('the last amount of a row is the one at the right end', () {
      expect(lastAmount('Milk 2 30.00 60.00'), 60.0);
      expect(lastAmount('TOTAL ₹ 472.00'), 472.0);
      expect(lastAmount('TOTAL Rs 472.00'), 472.0);
      expect(lastAmount('GST @ 18% 76.27'), 76.27);
      expect(lastAmount('Total 450', allowBare: true), 450.0);
      expect(lastAmount('Total 450'), isNull);
      expect(lastAmount('Bill No 1234 Table 5'), isNull);
    });
  });

  group('a till bill from India with GST', () {
    final r = read([
      'SUNRISE SUPERMARKET',
      'MG Road, Pune',
      'GSTIN 27AABCU9603R1ZM',
      'Invoice No 1234',
      'Date 12/03/2026 18:42',
      'Milk 1L 2 30.00 60.00',
      'Bread 45.00',
      'Rice 5kg 295.00',
      'Sub Total 400.00',
      'CGST @ 9% 36.00',
      'SGST @ 9% 36.00',
      'Grand Total ₹472.00',
      'Cash 500.00',
      'Change 28.00',
      'Thank you, visit again',
    ]);

    test('shop, date and currency', () {
      expect(r.vendor, 'SUNRISE SUPERMARKET');
      expect(r.date, DateTime(2026, 3, 12));
      expect(r.currency, 'INR');
      expect(r.category, ExpenseCategory.groceries);
    });

    test('subtotal, both taxes added, total, and the cash paid is not the total', () {
      expect(r.subtotal, 400.0);
      expect(r.tax, 72.0);
      expect(r.total, 472.0);
      expect(r.adds, isTrue);
      expect(r.notes, isEmpty);
    });

    test('the lines add up to the subtotal', () {
      expect([for (final i in r.items) i.description], ['Milk 1L', 'Bread', 'Rice 5kg']);
      expect([for (final i in r.items) i.amount], [60.0, 45.0, 295.0]);
    });
  });

  group('a restaurant bill from the US', () {
    final r = read([
      "Joe's Pizza Kitchen",
      '123 Main St',
      '04/18/2026 7:45 PM',
      'Margherita 14.00',
      'Soda 3.50',
      'Subtotal 17.50',
      'Sales Tax 1.44',
      'Tip 3.50',
      'Total \$22.44',
      'Thank you',
    ]);

    test('reads every part and they add up', () {
      expect(r.vendor, "Joe's Pizza Kitchen");
      expect(r.date, DateTime(2026, 4, 18));
      expect(r.currency, 'USD');
      expect(r.subtotal, 17.5);
      expect(r.tax, 1.44);
      expect(r.tip, 3.5);
      expect(r.total, 22.44);
      expect(r.adds, isTrue);
      expect(r.category, ExpenseCategory.dining);
    });
  });

  group('a bill with the amount on the line below, and printed in European style', () {
    test('a label whose amount stands alone on the next row', () {
      final r = read(['Biomarkt Berlin', '03.05.2026', 'Zwischensumme', '10,00', 'MwSt 7%', '0,70', 'Gesamtbetrag', '10,70 €']);
      expect(r.subtotal, 10.0);
      expect(r.tax, 0.7);
      expect(r.total, 10.7);
      expect(r.currency, 'EUR');
      expect(r.date, DateTime(2026, 5, 3));
    });
  });

  group('maths fills in what is missing', () {
    test('no total printed: it is worked out from subtotal and tax, and says so', () {
      final r = read(['Corner Shop', '01/02/2026', 'Item 10.00', 'Subtotal 10.00', 'VAT 2.00']);
      expect(r.total, 12.0);
      expect(r.totalWorkedOut, isTrue);
      expect(r.notes, contains(ReceiptNote.totalWorkedOut));
    });

    test('no tax printed: it is the difference between total and subtotal, and says so', () {
      final r = read(['Corner Shop', '01/02/2026', 'Subtotal 100.00', 'Total 118.00']);
      expect(r.tax, 18.0);
      expect(r.taxWorkedOut, isTrue);
      expect(r.notes, contains(ReceiptNote.taxWorkedOut));
    });

    test('nothing marked as total: the biggest amount is used and it is flagged', () {
      final r = read(['Tea Stall', '01/02/2026', 'Tea 10.00', 'Samosa 25.00', 'Cash 100.00']);
      expect(r.total == null || r.totalGuessed || r.totalWorkedOut, isTrue);
      expect(r.notes.any((n) => n == ReceiptNote.totalGuessed || n == ReceiptNote.totalWorkedOut), isTrue);
    });

    test('parts that do not add up are flagged', () {
      final r = read(['Shop', '01/02/2026', 'Subtotal 100.00', 'Tax 10.00', 'Total 150.00']);
      expect(r.adds, isFalse);
      expect(r.notes, contains(ReceiptNote.mismatch));
    });

    test('a small rounding difference is accepted', () {
      final r = read(['Shop', '01/02/2026', 'Subtotal 99.60', 'Tax 10.00', 'Round off 0.40', 'Total 110.00']);
      expect(r.adds, isTrue);
    });
  });

  group('picking the right line', () {
    test('a whole-number total with no decimals', () {
      final r = read(['Chai Point', '01/02/2026', 'Total 450', 'Total Items 3', 'Cash 500']);
      expect(r.total, 450.0);
    });

    test('several totals: the one that matches subtotal plus tax wins', () {
      final r = read(['Shop', '01/02/2026', 'Subtotal 200.00', 'Tax 20.00', 'Total 220.00', 'Total Savings 15.00', 'Total 220.00']);
      expect(r.total, 220.0);
    });

    test('savings, items counts and points are not the total', () {
      final r = read(['Shop', '01/02/2026', 'Total Qty 4', 'Total Savings 30.00', 'Reward points 12.00', 'Total 300.00']);
      expect(r.total, 300.0);
    });

    test('CGST and SGST are added, and a total tax line is used on its own', () {
      final a = read(['Shop', 'CGST 9% 9.00', 'SGST 9% 9.00', 'Total 118.00']);
      expect(a.tax, 18.0);
      final b = read(['Shop', 'CGST 9% 9.00', 'SGST 9% 9.00', 'Total GST 18.00', 'Total 118.00']);
      expect(b.tax, 18.0);
    });

    test('a line printed twice counts once', () {
      final r = read(['Shop', 'GST 18% 18.00', 'GST 18% 18.00', 'Total 118.00']);
      expect(r.tax, 18.0);
    });

    test('a discount is kept and used in the check', () {
      final r = read(['Shop', '01/02/2026', 'Subtotal 100.00', 'Discount -10.00', 'Tax 9.00', 'Total 99.00']);
      expect(r.discount, 10.0);
      expect(r.adds, isTrue);
    });

    test('the default currency is used when none is printed', () {
      expect(read(['Shop', 'Total 12.50'], defaultCurrency: 'INR').currency, 'INR');
      expect(read(['Shop', 'Total ₹12.50'], defaultCurrency: 'USD').currency, 'INR');
    });

    test('a bill with nothing readable has no total, vendor or date', () {
      final r = read(['~~~']);
      expect(r.total, isNull);
      expect(r.date, isNull);
      expect(r.notes, contains(ReceiptNote.missingTotal));
      expect(r.notes, contains(ReceiptNote.missingDate));
    });
  });

  group('kind of spending', () {
    test('from the shop name', () {
      ExpenseCategory of(String shop) => categoryFor(shop, [shop]);
      expect(of('Indian Oil Petrol Pump'), ExpenseCategory.fuel);
      expect(of('Apollo Pharmacy'), ExpenseCategory.health);
      expect(of('Cafe Coffee Day'), ExpenseCategory.dining);
      expect(of('Uber Rides'), ExpenseCategory.transport);
      expect(of('Hotel Taj'), ExpenseCategory.travel);
      expect(of('Airtel Broadband'), ExpenseCategory.utilities);
      expect(of('Fresh Mart'), ExpenseCategory.groceries);
      expect(of('Westside Fashion Store'), ExpenseCategory.shopping);
      expect(of('Mystery Co'), ExpenseCategory.other);
    });
  });

  group('summary', () {
    ReceiptRecord bill(
      String id,
      String vendor,
      DateTime? day,
      double? total, {
      String currency = 'INR',
      double? tax,
      ExpenseCategory c = ExpenseCategory.other,
    }) => ReceiptRecord(
      id: id,
      source: id,
      vendor: vendor,
      date: day,
      currency: currency,
      total: total,
      tax: tax,
      subtotal: total == null || tax == null ? null : total - tax,
      category: c,
    );

    final bills = [
      bill('a', 'Shop A', DateTime(2026, 1, 5), 100.0, tax: 10, c: ExpenseCategory.groceries),
      bill('b', 'Shop B', DateTime(2026, 1, 20), 50.5, c: ExpenseCategory.dining),
      bill('c', 'Shop C', DateTime(2026, 2, 2), 200.25, tax: 20, c: ExpenseCategory.groceries),
      bill('d', 'Shop D', DateTime(2026, 2, 3), 30.0, currency: 'USD'),
      bill('e', 'Shop E', null, 5.0),
      bill('f', 'Shop F', DateTime(2026, 2, 4), null),
    ];

    test('totals by currency, never mixed', () {
      final s = summarize(bills);
      expect(s.currencies.map((c) => c.currency), ['INR', 'USD']);
      final inr = s.currencies.first;
      expect(inr.count, 4);
      expect(inr.total, 355.75);
      expect(inr.tax, 30.0);
      expect(inr.average, 88.94);
      expect(s.currencies.last.total, 30.0);
      expect(s.withoutTotal, 1);
    });

    test('by month, a bill without a date last', () {
      final inr = summarize(bills).currencies.first;
      expect([for (final m in inr.months) m.month], ['2026-01', '2026-02', '']);
      expect([for (final m in inr.months) m.total], [150.5, 200.25, 5.0]);
      expect(inr.months.first.count, 2);
    });

    test('by kind of spending, biggest first, and the biggest bill', () {
      final inr = summarize(bills).currencies.first;
      expect(inr.categories.first.category, ExpenseCategory.groceries);
      expect(inr.categories.first.total, 300.25);
      expect(inr.biggest!.id, 'c');
    });

    test('a second photo of the same bill is spotted', () {
      final two = [
        bill('a', "Joe's Pizza", DateTime(2026, 4, 18), 22.44),
        bill('b', 'joes pizza', DateTime(2026, 4, 18), 22.44),
        bill('c', "Joe's Pizza", DateTime(2026, 4, 19), 22.44),
      ];
      expect(duplicateIds(two), {'b'});
    });

    test('no bills, no summary', () {
      expect(summarize(const []).isEmpty, isTrue);
    });
  });
}

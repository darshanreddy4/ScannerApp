import 'receipt_record.dart';

class MonthTotal {
  const MonthTotal({required this.month, required this.count, required this.subtotal, required this.tax, required this.total});

  /// "2026-01", or empty for bills without a date.
  final String month;
  final int count;
  final double subtotal;
  final double tax;
  final double total;
}

class CategoryTotal {
  const CategoryTotal({required this.category, required this.count, required this.total});
  final ExpenseCategory category;
  final int count;
  final double total;
}

/// What was spent in one currency. Amounts of different currencies are never added together.
class CurrencySummary {
  const CurrencySummary({
    required this.currency,
    required this.count,
    required this.subtotal,
    required this.tax,
    required this.tip,
    required this.total,
    required this.months,
    required this.categories,
    required this.biggest,
  });

  final String currency;

  /// Bills that have a total.
  final int count;
  final double subtotal;
  final double tax;
  final double tip;
  final double total;
  final List<MonthTotal> months;
  final List<CategoryTotal> categories;
  final ReceiptRecord? biggest;

  double get average => count == 0 ? 0 : roundCents(total / count);
}

class ExpenseSummary {
  const ExpenseSummary({required this.currencies, required this.withoutTotal});
  final List<CurrencySummary> currencies;

  /// Bills left out of the sums because no total is known.
  final int withoutTotal;

  bool get isEmpty => currencies.isEmpty;
}

/// Adds up the bills by currency, by month and by kind of spending.
ExpenseSummary summarize(List<ReceiptRecord> records) {
  final byCurrency = <String, List<ReceiptRecord>>{};
  var without = 0;
  for (final r in records) {
    if (r.total == null) {
      without++;
      continue;
    }
    byCurrency.putIfAbsent(r.currency, () => []).add(r);
  }
  final codes = byCurrency.keys.toList()
    ..sort((a, b) {
      // The currency with the most spending first.
      double sum(String c) => byCurrency[c]!.fold<double>(0, (s, r) => s + r.total!);
      return sum(b).compareTo(sum(a));
    });
  double add(Iterable<ReceiptRecord> rs, double? Function(ReceiptRecord) pick) => roundCents(rs.fold<double>(0, (s, r) => s + (pick(r) ?? 0)));

  final out = <CurrencySummary>[];
  for (final code in codes) {
    final rs = byCurrency[code]!;
    final months = <String, List<ReceiptRecord>>{};
    final kinds = <ExpenseCategory, List<ReceiptRecord>>{};
    for (final r in rs) {
      months.putIfAbsent(r.month, () => []).add(r);
      kinds.putIfAbsent(r.category, () => []).add(r);
    }
    final monthKeys = months.keys.toList()
      ..sort((a, b) {
        if (a.isEmpty) return b.isEmpty ? 0 : 1;
        if (b.isEmpty) return -1;
        return a.compareTo(b);
      });
    final categories = [for (final e in kinds.entries) CategoryTotal(category: e.key, count: e.value.length, total: add(e.value, (r) => r.total))]
      ..sort((a, b) => b.total.compareTo(a.total));
    ReceiptRecord? biggest;
    for (final r in rs) {
      if (biggest == null || r.total! > biggest.total!) biggest = r;
    }
    out.add(
      CurrencySummary(
        currency: code,
        count: rs.length,
        subtotal: add(rs, (r) => r.subtotal),
        tax: add(rs, (r) => r.tax),
        tip: add(rs, (r) => r.tip),
        total: add(rs, (r) => r.total),
        months: [
          for (final m in monthKeys)
            MonthTotal(
              month: m,
              count: months[m]!.length,
              subtotal: add(months[m]!, (r) => r.subtotal),
              tax: add(months[m]!, (r) => r.tax),
              total: add(months[m]!, (r) => r.total),
            ),
        ],
        categories: categories,
        biggest: biggest,
      ),
    );
  }
  return ExpenseSummary(currencies: out, withoutTotal: without);
}

/// The ids of bills that look like a second photo of one already in the list: the same shop, day, total and currency.
Set<String> duplicateIds(List<ReceiptRecord> records) {
  final seen = <String>{};
  final dupes = <String>{};
  for (final r in records) {
    if (r.total == null || r.date == null) continue;
    final key = '${r.vendor.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')}|${r.month}|${r.date!.day}|${r.total}|${r.currency}';
    if (!seen.add(key)) dupes.add(r.id);
  }
  return dupes;
}

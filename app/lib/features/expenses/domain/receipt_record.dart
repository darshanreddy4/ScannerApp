import 'package:equatable/equatable.dart';

/// What a bill was for, guessed from the shop and the words on it; the person can change it.
enum ExpenseCategory {
  groceries('Groceries'),
  dining('Food and dining'),
  fuel('Fuel'),
  transport('Transport'),
  travel('Hotels and travel'),
  health('Health'),
  utilities('Bills and utilities'),
  shopping('Shopping'),
  other('Other');

  const ExpenseCategory(this.label);
  final String label;
}

/// Things worth a second look on a bill.
enum ReceiptNote {
  missingTotal('No total was found. Type it in.'),
  missingDate('No date was found.'),
  mismatch('The parts do not add up to the total. Check the amounts.'),
  totalWorkedOut('The total was worked out from the other amounts; it was not printed.'),
  totalGuessed('No total was marked on the bill; the biggest amount is used.'),
  taxWorkedOut('The tax was worked out as the total minus the subtotal.'),
  duplicate('Looks like the same bill as another one.');

  const ReceiptNote(this.message);
  final String message;
}

/// One line of a bill.
class ReceiptItem extends Equatable {
  const ReceiptItem({required this.description, required this.amount});
  final String description;
  final double amount;

  @override
  List<Object?> get props => [description, amount];
}

/// What was read from one bill. Amounts are in [currency] (a code such as INR, or empty when none was printed).
class ReceiptRecord extends Equatable {
  const ReceiptRecord({
    required this.id,
    required this.source,
    this.vendor = '',
    this.date,
    this.currency = '',
    this.subtotal,
    this.discount,
    this.tax,
    this.tip,
    this.total,
    this.category = ExpenseCategory.other,
    this.items = const [],
    this.taxWorkedOut = false,
    this.totalWorkedOut = false,
    this.totalGuessed = false,
  });

  final String id;

  /// The file or page the bill was read from.
  final String source;
  final String vendor;
  final DateTime? date;
  final String currency;
  final double? subtotal;
  final double? discount;
  final double? tax;

  /// Tips and charges added to the bill, such as service charge or delivery.
  final double? tip;
  final double? total;
  final ExpenseCategory category;
  final List<ReceiptItem> items;
  final bool taxWorkedOut;
  final bool totalWorkedOut;
  final bool totalGuessed;

  /// "2026-01" for the month of the date, or empty when there is no date.
  String get month => date == null ? '' : '${date!.year}-${date!.month.toString().padLeft(2, '0')}';

  /// The total less the parts it is made of; near zero when the bill adds up. Null when it cannot be checked.
  double? get difference {
    final t = total, s = subtotal;
    if (t == null || s == null) return null;
    return _cents(t - (s - (discount ?? 0) + (tax ?? 0) + (tip ?? 0)));
  }

  bool get adds {
    final d = difference;
    if (d == null) return true;
    final t = total!;
    return d.abs() <= (t.abs() * 0.005 > 1 ? t.abs() * 0.005 : 1) + 0.01;
  }

  List<ReceiptNote> get notes => [
    if (total == null) ReceiptNote.missingTotal,
    if (date == null) ReceiptNote.missingDate,
    if (total != null && !adds) ReceiptNote.mismatch,
    if (totalWorkedOut) ReceiptNote.totalWorkedOut,
    if (totalGuessed) ReceiptNote.totalGuessed,
    if (taxWorkedOut) ReceiptNote.taxWorkedOut,
  ];

  ReceiptRecord copyWith({
    String? vendor,
    Object? date = _keep,
    String? currency,
    Object? subtotal = _keep,
    Object? discount = _keep,
    Object? tax = _keep,
    Object? tip = _keep,
    Object? total = _keep,
    ExpenseCategory? category,
    bool? taxWorkedOut,
    bool? totalWorkedOut,
    bool? totalGuessed,
  }) => ReceiptRecord(
    id: id,
    source: source,
    vendor: vendor ?? this.vendor,
    date: identical(date, _keep) ? this.date : date as DateTime?,
    currency: currency ?? this.currency,
    subtotal: identical(subtotal, _keep) ? this.subtotal : subtotal as double?,
    discount: identical(discount, _keep) ? this.discount : discount as double?,
    tax: identical(tax, _keep) ? this.tax : tax as double?,
    tip: identical(tip, _keep) ? this.tip : tip as double?,
    total: identical(total, _keep) ? this.total : total as double?,
    category: category ?? this.category,
    items: items,
    taxWorkedOut: taxWorkedOut ?? this.taxWorkedOut,
    totalWorkedOut: totalWorkedOut ?? this.totalWorkedOut,
    totalGuessed: totalGuessed ?? this.totalGuessed,
  );

  static const _keep = Object();

  @override
  List<Object?> get props => [
    id,
    source,
    vendor,
    date,
    currency,
    subtotal,
    discount,
    tax,
    tip,
    total,
    category,
    items,
    taxWorkedOut,
    totalWorkedOut,
    totalGuessed,
  ];
}

double _cents(double v) => (v * 100).round() / 100;

/// Rounds an amount to two decimals.
double roundCents(double v) => _cents(v);

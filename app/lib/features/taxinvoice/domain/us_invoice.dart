import 'tax_common.dart';

/// One US state (or the District of Columbia) with its state-level sales tax rate as it stood in January 2026, in millionths
/// (6.875% is 68750). Local taxes come on top and differ by city, county and district, so the rate is only a starting point.
class UsState {
  const UsState(this.code, this.name, this.baseRate);
  final String code;
  final String name;
  final int baseRate;
}

const usRatesAsOf = 'January 2026';

const usStates = <UsState>[
  UsState('AL', 'Alabama', 40000),
  UsState('AK', 'Alaska', 0),
  UsState('AZ', 'Arizona', 56000),
  UsState('AR', 'Arkansas', 65000),
  UsState('CA', 'California', 72500),
  UsState('CO', 'Colorado', 29000),
  UsState('CT', 'Connecticut', 63500),
  UsState('DE', 'Delaware', 0),
  UsState('DC', 'District of Columbia', 60000),
  UsState('FL', 'Florida', 60000),
  UsState('GA', 'Georgia', 40000),
  UsState('HI', 'Hawaii', 40000),
  UsState('ID', 'Idaho', 60000),
  UsState('IL', 'Illinois', 62500),
  UsState('IN', 'Indiana', 70000),
  UsState('IA', 'Iowa', 60000),
  UsState('KS', 'Kansas', 65000),
  UsState('KY', 'Kentucky', 60000),
  UsState('LA', 'Louisiana', 50000),
  UsState('ME', 'Maine', 55000),
  UsState('MD', 'Maryland', 60000),
  UsState('MA', 'Massachusetts', 62500),
  UsState('MI', 'Michigan', 60000),
  UsState('MN', 'Minnesota', 68750),
  UsState('MS', 'Mississippi', 70000),
  UsState('MO', 'Missouri', 42250),
  UsState('MT', 'Montana', 0),
  UsState('NE', 'Nebraska', 55000),
  UsState('NV', 'Nevada', 68500),
  UsState('NH', 'New Hampshire', 0),
  UsState('NJ', 'New Jersey', 66250),
  UsState('NM', 'New Mexico', 48750),
  UsState('NY', 'New York', 40000),
  UsState('NC', 'North Carolina', 47500),
  UsState('ND', 'North Dakota', 50000),
  UsState('OH', 'Ohio', 57500),
  UsState('OK', 'Oklahoma', 45000),
  UsState('OR', 'Oregon', 0),
  UsState('PA', 'Pennsylvania', 60000),
  UsState('RI', 'Rhode Island', 70000),
  UsState('SC', 'South Carolina', 60000),
  UsState('SD', 'South Dakota', 42000),
  UsState('TN', 'Tennessee', 70000),
  UsState('TX', 'Texas', 62500),
  UsState('UT', 'Utah', 61000),
  UsState('VT', 'Vermont', 60000),
  UsState('VA', 'Virginia', 53000),
  UsState('WA', 'Washington', 65000),
  UsState('WV', 'West Virginia', 60000),
  UsState('WI', 'Wisconsin', 50000),
  UsState('WY', 'Wyoming', 40000),
];

UsState? usStateOf(String code) {
  for (final s in usStates) {
    if (s.code == code) return s;
  }
  return null;
}

/// A rate of up to four decimals, from 0 to 20 percent, in millionths; null when the text is not one.
int? parseUsRate(String input) {
  final v = parseDecimal(input, decimals: 4, digits: 2);
  if (v == null) return null;
  final m = (v * 10000).round();
  return m > 200000 ? null : m;
}

/// A rate as text without trailing zeros: 68750 is `6.875`, 80000 is `8`.
String usRateText(int millionths) {
  final whole = millionths ~/ 10000;
  final fraction = (millionths % 10000).toString().padLeft(4, '0').replaceFirst(RegExp(r'0+$'), '');
  return fraction.isEmpty ? '$whole' : '$whole.$fraction';
}

/// [cents] times a rate in millionths, rounded half up.
int usTaxOf(int cents, int millionths) => (cents * millionths + 500000) ~/ 1000000;

bool isValidZip(String zip) => RegExp(r'^\d{5}(-\d{4})?$').hasMatch(zip.trim());

/// An Employer Identification Number: nine digits, written 12-3456789 or without the dash.
bool isValidEin(String ein) => RegExp(r'^\d{2}-?\d{7}$').hasMatch(ein.trim());

/// What the sheet may say about when payment is due.
const usTermsDays = [0, 15, 30, 45, 60];

String usTermsText(int days) => days == 0 ? 'Due on receipt' : 'Net $days';

class UsParty {
  const UsParty({this.name = '', this.address = '', this.city = '', this.state = '', this.zip = '', this.phone = '', this.email = '', this.taxId = ''});
  final String name;
  final String address;
  final String city;
  final String state;
  final String zip;
  final String phone;
  final String email;

  /// The seller's EIN or sales tax permit number; for the buyer, the exemption or resale certificate number.
  final String taxId;

  String get cityLine {
    final tail = [state.trim(), zip.trim()].where((s) => s.isNotEmpty).join(' ');
    return [city.trim(), tail].where((s) => s.isNotEmpty).join(', ');
  }
}

class UsLine {
  const UsLine({required this.description, required this.quantity, required this.unitPriceCents, this.taxable = true});
  final String description;
  final double quantity;
  final int unitPriceCents;
  final bool taxable;

  int get amountCents => (quantity * unitPriceCents).round();
}

class UsDraft {
  const UsDraft({
    this.seller = const UsParty(),
    this.buyer = const UsParty(),
    this.number = '',
    required this.date,
    this.termsDays = 30,
    this.items = const [],
    this.discountIsPercent = true,
    this.discountValue = 0,
    this.shippingCents = 0,
    this.shippingTaxable = false,
    this.taxRate = 0,
    this.taxName = 'Sales tax',
    this.exempt = false,
    this.paidCents = 0,
    this.payment = '',
    this.notes = '',
  });
  final UsParty seller;
  final UsParty buyer;
  final String number;
  final DateTime date;
  final int termsDays;
  final List<UsLine> items;

  /// A percent in hundredths when [discountIsPercent], otherwise an amount in cents.
  final bool discountIsPercent;
  final int discountValue;
  final int shippingCents;
  final bool shippingTaxable;

  /// The combined state and local rate, in millionths.
  final int taxRate;
  final String taxName;
  final bool exempt;
  final int paidCents;
  final String payment;
  final String notes;

  DateTime get dueDate => DateTime(date.year, date.month, date.day + termsDays);
}

class UsTotals {
  const UsTotals({
    required this.subtotal,
    required this.discount,
    required this.shipping,
    required this.taxableBase,
    required this.tax,
    required this.total,
    required this.paid,
    required this.balance,
  });
  final int subtotal;
  final int discount;
  final int shipping;
  final int taxableBase;
  final int tax;
  final int total;
  final int paid;
  final int balance;
}

/// The discount comes off every line in proportion, so the tax is charged on what the customer really pays.
UsTotals computeUs(UsDraft d) {
  var subtotal = 0;
  var taxableSub = 0;
  for (final l in d.items) {
    subtotal += l.amountCents;
    if (l.taxable) taxableSub += l.amountCents;
  }
  final wanted = d.discountIsPercent ? percentOf(subtotal, d.discountValue) : d.discountValue;
  final discount = wanted > subtotal ? subtotal : (wanted < 0 ? 0 : wanted);
  final taxableDiscount = subtotal == 0 ? 0 : (discount * taxableSub + subtotal ~/ 2) ~/ subtotal;
  final base = (taxableSub - taxableDiscount) + (d.shippingTaxable ? d.shippingCents : 0);
  final tax = d.exempt ? 0 : usTaxOf(base, d.taxRate);
  final total = subtotal - discount + d.shippingCents + tax;
  final paid = d.paidCents;
  return UsTotals(
    subtotal: subtotal,
    discount: discount,
    shipping: d.shippingCents,
    taxableBase: d.exempt ? 0 : base,
    tax: tax,
    total: total,
    paid: paid,
    balance: total - paid,
  );
}

const maxUsItems = 60;

bool isValidUsInvoiceNumber(String s) => RegExp(r'^[A-Za-z0-9][A-Za-z0-9\-_/#.]{0,19}$').hasMatch(s.trim());

/// The next number after [last]: the digits at the end count up, so `INV-0042` gives `INV-0043`; with nothing before it starts at 1001.
String nextUsInvoiceNumber(String last) {
  final m = RegExp(r'^(.*?)(\d+)$').firstMatch(last.trim());
  if (m == null) return last.trim().isEmpty ? '1001' : '${last.trim()}-1';
  final digits = m[2]!;
  return '${m[1]}${(int.parse(digits) + 1).toString().padLeft(digits.length, '0')}';
}

List<TaxIssue> usIssues(UsDraft d) {
  final out = <TaxIssue>[];
  void add(String field, String template, [Map<String, Object> values = const {}]) => out.add(TaxIssue(field, template, values));

  if (d.seller.name.trim().isEmpty) add('seller.name', 'Enter your business name.');
  if (d.seller.address.trim().isEmpty) add('seller.address', 'Enter your street address.');
  if (d.seller.city.trim().isEmpty) add('seller.city', 'Enter your city.');
  if (usStateOf(d.seller.state) == null) add('seller.state', 'Choose your state.');
  if (d.seller.zip.trim().isEmpty) {
    add('seller.zip', 'Enter your ZIP code.');
  } else if (!isValidZip(d.seller.zip)) {
    add('seller.zip', 'A ZIP code has 5 digits, or 5 and 4 as in 94105-1234.');
  }
  if (d.seller.taxId.trim().isNotEmpty && !isValidEin(d.seller.taxId) && !RegExp(r'^[A-Za-z0-9\-]{5,20}$').hasMatch(d.seller.taxId.trim())) {
    add('seller.taxId', 'This number does not look right. An EIN is 9 digits, like 12-3456789.');
  }
  if (d.seller.email.trim().isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(d.seller.email.trim()))
    add('seller.email', 'This email address does not look right.');

  if (d.buyer.name.trim().isEmpty) add('buyer.name', 'Enter the customer\'s name.');
  if (d.buyer.zip.trim().isNotEmpty && !isValidZip(d.buyer.zip)) add('buyer.zip', 'A ZIP code has 5 digits, or 5 and 4 as in 94105-1234.');

  if (d.number.trim().isEmpty) {
    add('number', 'Enter an invoice number.');
  } else if (!isValidUsInvoiceNumber(d.number)) {
    add('number', 'Use up to 20 letters, digits, dashes or slashes.');
  }
  if (d.items.isEmpty) add('items', 'Add at least one item.');
  for (final (n, l) in d.items.indexed) {
    if (l.description.trim().isEmpty) add('item.$n.description', 'Item {n}: describe what was sold.', {'n': n + 1});
  }
  if (d.discountIsPercent && d.discountValue > 10000) add('discount', 'A discount cannot be more than 100%.');
  if (!d.discountIsPercent && d.discountValue > computeUs(UsDraft(date: d.date, items: d.items)).subtotal)
    add('discount', 'The discount is more than the items cost.');
  final t = computeUs(d);
  if (d.paidCents > t.total) add('paid', 'The amount paid is more than the invoice total.');
  return out;
}

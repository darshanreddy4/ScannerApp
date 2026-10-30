import '../../einvoice/domain/einvoice.dart' show InvoiceParty;
import '../../qr/domain/payments.dart' show isValidIban;

class InvoiceItem {
  const InvoiceItem({required this.description, required this.quantity, this.unit = '', required this.unitPriceCents, required this.vatRate});
  final String description;
  final double quantity;
  final String unit;
  final int unitPriceCents;

  /// VAT in percent, such as 19 or 5.5.
  final double vatRate;

  /// Price of the line before VAT, in cents, rounded half up.
  int get netCents => ((quantity * 1000).round() * unitPriceCents + 500) ~/ 1000;
}

class InvoiceDraft {
  const InvoiceDraft({
    required this.seller,
    this.sellerIban = '',
    this.sellerBic = '',
    this.buyer = const InvoiceParty(),
    this.number = '',
    required this.issueDate,
    required this.dueDate,
    this.currency = 'EUR',
    this.items = const [],
    this.notes = '',
    this.reverseCharge = false,
    this.language = 'en',
  });

  final InvoiceParty seller;
  final String sellerIban;
  final String sellerBic;
  final InvoiceParty buyer;
  final String number;
  final DateTime issueDate;
  final DateTime dueDate;
  final String currency;
  final List<InvoiceItem> items;
  final String notes;

  /// The buyer pays the VAT in their own country; the invoice shows no VAT and says why.
  final bool reverseCharge;

  /// The language the invoice is written in, as a two-letter code.
  final String language;
}

class VatGroup {
  const VatGroup({required this.rate, required this.netCents, required this.vatCents});
  final double rate;
  final int netCents;
  final int vatCents;
}

class InvoiceTotals {
  const InvoiceTotals({required this.groups, required this.netCents, required this.vatCents});
  final List<VatGroup> groups;
  final int netCents;
  final int vatCents;
  int get grossCents => netCents + vatCents;
}

/// Adds the lines up. VAT is worked out once per rate on the sum of the lines, as invoices must show it.
InvoiceTotals computeTotals(List<InvoiceItem> items, {bool reverseCharge = false}) {
  final byRate = <double, int>{};
  for (final i in items) {
    final rate = reverseCharge ? 0.0 : i.vatRate;
    byRate[rate] = (byRate[rate] ?? 0) + i.netCents;
  }
  final rates = byRate.keys.toList()..sort((a, b) => b.compareTo(a));
  final groups = [for (final r in rates) VatGroup(rate: r, netCents: byRate[r]!, vatCents: (byRate[r]! * (r * 100).round() + 5000) ~/ 10000)];
  return InvoiceTotals(groups: groups, netCents: groups.fold(0, (a, g) => a + g.netCents), vatCents: groups.fold(0, (a, g) => a + g.vatCents));
}

/// Cents from text such as `12`, `12,5` or `1234.56`; null when it is not an amount of money.
int? parseCents(String input) {
  final m = RegExp(r'^(\d{1,9})(?:[.,](\d{1,2}))?$').firstMatch(input.trim());
  if (m == null) return null;
  return int.parse(m[1]!) * 100 + int.parse((m[2] ?? '').padRight(2, '0'));
}

/// A quantity such as `3` or `1,5`; null when it is not above zero.
double? parseQuantity(String input) {
  final m = RegExp(r'^(\d{1,6})(?:[.,](\d{1,3}))?$').firstMatch(input.trim());
  if (m == null) return null;
  final v = double.parse('${m[1]}.${m[2] ?? '0'}');
  return v > 0 ? v : null;
}

/// A VAT rate such as `19`, `5,5` or `0`; null when it is not between 0 and 100.
double? parseVatRate(String input) {
  final m = RegExp(r'^(\d{1,2}|100)(?:[.,](\d{1,2}))?$').firstMatch(input.trim());
  if (m == null) return null;
  final v = double.parse('${m[1]}.${m[2] ?? '0'}');
  return v <= 100 ? v : null;
}

const _symbols = {
  'EUR': '\u20AC',
  'GBP': '\u00A3',
  'CHF': 'CHF',
  'PLN': 'z\u0142',
  'SEK': 'kr',
  'DKK': 'kr.',
  'NOK': 'kr',
  'CZK': 'K\u010D',
  'HUF': 'Ft',
  'RON': 'lei',
};
const _pointCountries = {'GB', 'IE', 'MT', 'CY', 'US'};
const _spaceCountries = {'FR', 'PL', 'CZ', 'SK', 'SE', 'FI', 'NO', 'HU', 'BG', 'LT', 'LV', 'EE', 'RU', 'UA'};

/// The way an amount is written in a country: `1.234,56 €`, `1 234,56 €` or `£1,234.56`.
String formatMoney(int cents, String currency, {String? country}) {
  final c = (country ?? '').toUpperCase();
  final negative = cents < 0;
  final abs = cents.abs();
  final whole = (abs ~/ 100).toString();
  final fraction = (abs % 100).toString().padLeft(2, '0');
  final String group, decimal;
  if (_pointCountries.contains(c)) {
    group = ',';
    decimal = '.';
  } else if (c == 'CH' || c == 'LI') {
    group = '\u2019';
    decimal = '.';
  } else if (_spaceCountries.contains(c)) {
    group = '\u00A0';
    decimal = ',';
  } else {
    group = '.';
    decimal = ',';
  }
  final buffer = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buffer.write(group);
    buffer.write(whole[i]);
  }
  final number = '${negative ? '-' : ''}$buffer$decimal$fraction';
  final symbol = _symbols[currency] ?? currency;
  return decimal == '.' && (c == 'GB' || c == 'IE' || c == 'MT' || c == 'CY' || c == 'US') ? '$symbol$number' : '$number\u00A0$symbol';
}

/// The next number after [last]: `2025-007` gives `2025-008`, a new year starts again, anything else counts up its last digits.
String nextInvoiceNumber(String last, DateTime now) {
  final t = last.trim();
  final yearly = RegExp(r'^(\d{4})([-/])(\d+)$').firstMatch(t);
  if (yearly != null) {
    final width = yearly[3]!.length;
    if (int.parse(yearly[1]!) != now.year) return '${now.year}${yearly[2]}${'1'.padLeft(width, '0')}';
    return '${yearly[1]}${yearly[2]}${(int.parse(yearly[3]!) + 1).toString().padLeft(width, '0')}';
  }
  final tail = RegExp(r'^(.*?)(\d+)$').firstMatch(t);
  if (tail != null) return '${tail[1]}${(int.parse(tail[2]!) + 1).toString().padLeft(tail[2]!.length, '0')}';
  return '${now.year}-001';
}

/// The invoice language that suits a country.
String invoiceLanguageFor(String? country) => switch ((country ?? '').toUpperCase()) {
  'DE' || 'AT' || 'CH' || 'LI' => 'de',
  'FR' || 'MC' || 'LU' => 'fr',
  'ES' => 'es',
  'IT' || 'SM' || 'VA' => 'it',
  'NL' => 'nl',
  'PL' => 'pl',
  _ => 'en',
};

/// Usual VAT rates of a country, for quick choosing. Rates change, so the person can always type another.
List<double> commonVatRates(String? country) => switch ((country ?? '').toUpperCase()) {
  'DE' => [19, 7, 0],
  'AT' => [20, 10, 13, 0],
  'FR' => [20, 10, 5.5, 2.1, 0],
  'ES' => [21, 10, 4, 0],
  'IT' => [22, 10, 5, 4, 0],
  'NL' => [21, 9, 0],
  'BE' => [21, 12, 6, 0],
  'PL' => [23, 8, 5, 0],
  'PT' => [23, 13, 6, 0],
  'IE' => [23, 13.5, 9, 0],
  'SE' => [25, 12, 6, 0],
  'DK' => [25, 0],
  'FI' => [25.5, 14, 10, 0],
  'CZ' => [21, 12, 0],
  'GR' => [24, 13, 6, 0],
  'HU' => [27, 18, 5, 0],
  'GB' => [20, 5, 0],
  'CH' => [8.1, 2.6, 3.8, 0],
  _ => [20, 10, 0],
};

/// What is missing or wrong before the invoice can be made; null when it is complete.
String? invoiceProblem(InvoiceDraft d) {
  if (d.seller.name.trim().isEmpty) return 'Enter your name or company name.';
  if (d.seller.street.trim().isEmpty || d.seller.city.trim().isEmpty) return 'Enter your street and town.';
  if (d.buyer.name.trim().isEmpty) return 'Enter the customer\'s name.';
  if (d.number.trim().isEmpty) return 'Enter an invoice number.';
  if (d.items.isEmpty) return 'Add at least one item.';
  if (d.items.any((i) => i.description.trim().isEmpty)) return 'Every item needs a description.';
  if (d.sellerIban.trim().isNotEmpty && !isValidIban(d.sellerIban)) return 'Your IBAN is not valid. Check the numbers.';
  if (d.dueDate.isBefore(DateTime(d.issueDate.year, d.issueDate.month, d.issueDate.day))) return 'The due date is before the invoice date.';
  return null;
}

import 'dart:convert';
import 'dart:typed_data';

import 'tax_common.dart';

/// A tax invoice is made out to a business that is registered for VAT; a simplified tax invoice is for a consumer and carries the QR code.
enum ZatcaDocument { simplified, standard }

/// The VAT of an item: 15 percent, nothing (zero-rated), or outside VAT (exempt).
enum VatCategory { standard, zero, exempt }

const zatcaVatRate = 1500;

/// A VAT registration number: 15 digits that start and end with 3.
bool isValidSaudiVat(String v) => RegExp(r'^3\d{13}3$').hasMatch(v.trim());

bool isValidSaudiPostcode(String v) => RegExp(r'^\d{5}$').hasMatch(v.trim());

class ZatcaParty {
  const ZatcaParty({this.name = '', this.vat = '', this.address = '', this.district = '', this.city = '', this.postcode = '', this.cr = ''});
  final String name;
  final String vat;

  /// Building number and street.
  final String address;
  final String district;
  final String city;
  final String postcode;

  /// The commercial registration number.
  final String cr;

  String get addressLine => [
    address.trim(),
    district.trim(),
    [city.trim(), postcode.trim()].where((s) => s.isNotEmpty).join(' '),
  ].where((s) => s.isNotEmpty).join(', ');
}

class ZatcaLine {
  const ZatcaLine({
    required this.description,
    required this.quantity,
    required this.unitPriceCents,
    this.discountCents = 0,
    this.category = VatCategory.standard,
  });
  final String description;
  final double quantity;
  final int unitPriceCents;

  /// Taken off the line, in the same terms as the price: with VAT when prices include VAT.
  final int discountCents;
  final VatCategory category;

  int get amountCents => (quantity * unitPriceCents).round();
}

class ZatcaDraft {
  const ZatcaDraft({
    this.document = ZatcaDocument.simplified,
    this.seller = const ZatcaParty(),
    this.buyer = const ZatcaParty(),
    this.number = '',
    required this.issuedAt,
    this.items = const [],
    this.pricesIncludeVat = false,
    this.notes = '',
  });
  final ZatcaDocument document;
  final ZatcaParty seller;
  final ZatcaParty buyer;
  final String number;
  final DateTime issuedAt;
  final List<ZatcaLine> items;
  final bool pricesIncludeVat;
  final String notes;
}

class ZatcaLineTotals {
  const ZatcaLineTotals(this.discount, this.net, this.vat);
  final int discount;
  final int net;
  final int vat;
  int get total => net + vat;
}

class ZatcaTotals {
  const ZatcaTotals({required this.lines, required this.discount, required this.taxable, required this.vat, required this.total});
  final List<ZatcaLineTotals> lines;
  final int discount;

  /// The amount VAT is charged on: all lines, before VAT, after discounts.
  final int taxable;
  final int vat;
  final int total;
}

ZatcaTotals computeZatca(ZatcaDraft d) {
  final lines = <ZatcaLineTotals>[];
  var discount = 0;
  var taxable = 0;
  var vat = 0;
  for (final l in d.items) {
    final disc = l.discountCents > l.amountCents ? l.amountCents : (l.discountCents < 0 ? 0 : l.discountCents);
    final amount = l.amountCents - disc;
    int net;
    int tax;
    if (l.category != VatCategory.standard) {
      net = amount;
      tax = 0;
    } else if (d.pricesIncludeVat) {
      net = (amount * 10000 + (10000 + zatcaVatRate) ~/ 2) ~/ (10000 + zatcaVatRate);
      tax = amount - net;
    } else {
      net = amount;
      tax = percentOf(net, zatcaVatRate);
    }
    // With prices that include VAT the discount is shown without VAT too, so the lines add up.
    final shownDisc = d.pricesIncludeVat && l.category == VatCategory.standard ? (disc * 10000 + (10000 + zatcaVatRate) ~/ 2) ~/ (10000 + zatcaVatRate) : disc;
    lines.add(ZatcaLineTotals(shownDisc, net, tax));
    discount += shownDisc;
    taxable += net;
    vat += tax;
  }
  return ZatcaTotals(lines: lines, discount: discount, taxable: taxable, vat: vat, total: taxable + vat);
}

/// The time as the QR code writes it: 2026-06-01T10:30:00Z, with the time as it was written on the invoice.
String zatcaTimestamp(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year.toString().padLeft(4, '0')}-${two(t.month)}-${two(t.day)}T${two(t.hour)}:${two(t.minute)}:${two(t.second)}Z';
}

String zatcaAmount(int cents) => '${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';

/// The first-phase QR code as the bytes of tag, length and value for five facts, in order: the seller's name, the VAT number, the time,
/// the total with VAT, and the VAT.
Uint8List zatcaTlv({required String sellerName, required String vatNumber, required DateTime issuedAt, required int totalCents, required int vatCents}) {
  final out = BytesBuilder();
  final values = [sellerName.trim(), vatNumber.trim(), zatcaTimestamp(issuedAt), zatcaAmount(totalCents), zatcaAmount(vatCents)];
  for (final (i, v) in values.indexed) {
    final bytes = utf8.encode(v);
    if (bytes.length > 255) throw ArgumentError('The value of tag ${i + 1} is longer than 255 bytes.');
    out
      ..addByte(i + 1)
      ..addByte(bytes.length)
      ..add(bytes);
  }
  return out.toBytes();
}

/// The text that goes in the QR code: the bytes above in Base64.
String zatcaQrPayload(ZatcaDraft d) {
  final t = computeZatca(d);
  return base64Encode(zatcaTlv(sellerName: d.seller.name, vatNumber: d.seller.vat, issuedAt: d.issuedAt, totalCents: t.total, vatCents: t.vat));
}

/// The facts in a first-phase QR payload by tag, or null when it is not one.
Map<int, String>? decodeZatcaQr(String payload) {
  try {
    final bytes = base64Decode(payload.trim());
    final out = <int, String>{};
    var i = 0;
    while (i < bytes.length) {
      if (i + 2 > bytes.length) return null;
      final tag = bytes[i];
      final len = bytes[i + 1];
      if (i + 2 + len > bytes.length) return null;
      out[tag] = utf8.decode(bytes.sublist(i + 2, i + 2 + len));
      i += 2 + len;
    }
    return out.isEmpty ? null : out;
  } on Object {
    return null;
  }
}

const maxZatcaItems = 60;

bool isValidZatcaInvoiceNumber(String s) => RegExp(r'^[A-Za-z0-9][A-Za-z0-9\-_/#.]{0,19}$').hasMatch(s.trim());

List<TaxIssue> zatcaIssues(ZatcaDraft d) {
  final out = <TaxIssue>[];
  void add(String field, String template, [Map<String, Object> values = const {}]) => out.add(TaxIssue(field, template, values));
  final standard = d.document == ZatcaDocument.standard;

  if (d.seller.name.trim().isEmpty) {
    add('seller.name', 'Enter your business name.');
  } else if (utf8.encode(d.seller.name.trim()).length > 255) {
    add('seller.name', 'The business name is too long.');
  }
  if (d.seller.vat.trim().isEmpty) {
    add('seller.vat', 'Enter your VAT registration number.');
  } else if (!isValidSaudiVat(d.seller.vat)) {
    add('seller.vat', 'A VAT registration number has 15 digits and starts and ends with 3.');
  }
  if (d.seller.address.trim().isEmpty) add('seller.address', 'Enter your building number and street.');
  if (d.seller.city.trim().isEmpty) add('seller.city', 'Enter your city.');
  if (d.seller.postcode.trim().isNotEmpty && !isValidSaudiPostcode(d.seller.postcode)) add('seller.postcode', 'A postal code has 5 digits.');

  if (standard) {
    if (d.buyer.name.trim().isEmpty) add('buyer.name', 'Enter the customer\'s name.');
    if (d.buyer.vat.trim().isEmpty) {
      add('buyer.vat', 'A tax invoice needs the customer\'s VAT registration number.');
    } else if (!isValidSaudiVat(d.buyer.vat)) {
      add('buyer.vat', 'A VAT registration number has 15 digits and starts and ends with 3.');
    }
    if (d.buyer.address.trim().isEmpty) add('buyer.address', 'A tax invoice needs the customer\'s address.');
  } else if (d.buyer.vat.trim().isNotEmpty && !isValidSaudiVat(d.buyer.vat)) {
    add('buyer.vat', 'A VAT registration number has 15 digits and starts and ends with 3.');
  }
  if (d.buyer.postcode.trim().isNotEmpty && !isValidSaudiPostcode(d.buyer.postcode)) add('buyer.postcode', 'A postal code has 5 digits.');

  if (d.number.trim().isEmpty) {
    add('number', 'Enter an invoice number.');
  } else if (!isValidZatcaInvoiceNumber(d.number)) {
    add('number', 'Use up to 20 letters, digits, dashes or slashes.');
  }
  if (d.items.isEmpty) add('items', 'Add at least one item.');
  for (final (n, l) in d.items.indexed) {
    if (l.description.trim().isEmpty) add('item.$n.description', 'Item {n}: describe what was sold.', {'n': n + 1});
    if (l.discountCents > l.amountCents) add('item.$n.discount', 'Item {n}: the discount is more than the item costs.', {'n': n + 1});
  }
  return out;
}

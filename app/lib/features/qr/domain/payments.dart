import 'dart:convert';

import '../../../core/i18n/tr.dart' show tr, trf;

/// A request for a bank transfer, read from a payment QR code or made for one.
class PaymentRequest {
  const PaymentRequest({
    required this.scheme,
    required this.name,
    required this.iban,
    this.bic = '',
    this.currency = '',
    this.amount = '',
    this.reference = '',
    this.message = '',
    this.address = '',
    this.vpa = '',
  });

  /// `SEPA` for the European Girocode, `Swiss QR-bill` for the Swiss and Liechtenstein bill, `UPI` for an Indian UPI code.
  final String scheme;

  /// Who is paid.
  final String name;
  final String iban;
  final String bic;
  final String currency;

  /// Digits with a point, such as `123.45`; empty when the payer fills it in.
  final String amount;
  final String reference;
  final String message;
  final String address;

  /// The UPI ID of a UPI payment code (India); empty for the others.
  final String vpa;

  bool get isUpi => scheme == 'UPI';
  bool get ibanValid => isValidIban(iban);
  String get ibanText => formatIban(iban);
  String get amountText => amount.isEmpty ? '' : '$currency $amount'.trim();
}

/// Length and name of the IBAN of each country that has one the app knows. Other countries are checked by their check digits alone.
const _ibanCountries = <String, (int, String)>{
  'AD': (24, 'Andorra'),
  'AE': (23, 'United Arab Emirates'),
  'AL': (28, 'Albania'),
  'AT': (20, 'Austria'),
  'AZ': (28, 'Azerbaijan'),
  'BA': (20, 'Bosnia and Herzegovina'),
  'BE': (16, 'Belgium'),
  'BG': (22, 'Bulgaria'),
  'BH': (22, 'Bahrain'),
  'BR': (29, 'Brazil'),
  'BY': (28, 'Belarus'),
  'CH': (21, 'Switzerland'),
  'CR': (22, 'Costa Rica'),
  'CY': (28, 'Cyprus'),
  'CZ': (24, 'Czechia'),
  'DE': (22, 'Germany'),
  'DK': (18, 'Denmark'),
  'DO': (28, 'Dominican Republic'),
  'EE': (20, 'Estonia'),
  'EG': (29, 'Egypt'),
  'ES': (24, 'Spain'),
  'FI': (18, 'Finland'),
  'FO': (18, 'Faroe Islands'),
  'FR': (27, 'France'),
  'GB': (22, 'United Kingdom'),
  'GE': (22, 'Georgia'),
  'GI': (23, 'Gibraltar'),
  'GL': (18, 'Greenland'),
  'GR': (27, 'Greece'),
  'GT': (28, 'Guatemala'),
  'HR': (21, 'Croatia'),
  'HU': (28, 'Hungary'),
  'IE': (22, 'Ireland'),
  'IL': (23, 'Israel'),
  'IQ': (23, 'Iraq'),
  'IS': (26, 'Iceland'),
  'IT': (27, 'Italy'),
  'JO': (30, 'Jordan'),
  'KW': (30, 'Kuwait'),
  'KZ': (20, 'Kazakhstan'),
  'LB': (28, 'Lebanon'),
  'LC': (32, 'Saint Lucia'),
  'LI': (21, 'Liechtenstein'),
  'LT': (20, 'Lithuania'),
  'LU': (20, 'Luxembourg'),
  'LV': (21, 'Latvia'),
  'MC': (27, 'Monaco'),
  'MD': (24, 'Moldova'),
  'ME': (22, 'Montenegro'),
  'MK': (19, 'North Macedonia'),
  'MR': (27, 'Mauritania'),
  'MT': (31, 'Malta'),
  'MU': (30, 'Mauritius'),
  'NL': (18, 'Netherlands'),
  'NO': (15, 'Norway'),
  'PK': (24, 'Pakistan'),
  'PL': (28, 'Poland'),
  'PS': (29, 'Palestine'),
  'PT': (25, 'Portugal'),
  'QA': (29, 'Qatar'),
  'RO': (24, 'Romania'),
  'RS': (22, 'Serbia'),
  'SA': (24, 'Saudi Arabia'),
  'SC': (31, 'Seychelles'),
  'SE': (24, 'Sweden'),
  'SI': (19, 'Slovenia'),
  'SK': (24, 'Slovakia'),
  'SM': (27, 'San Marino'),
  'SV': (28, 'El Salvador'),
  'TL': (23, 'Timor-Leste'),
  'TN': (24, 'Tunisia'),
  'TR': (26, 'Turkey'),
  'UA': (29, 'Ukraine'),
  'VA': (22, 'Vatican City'),
  'VG': (24, 'British Virgin Islands'),
  'XK': (20, 'Kosovo'),
};

/// The countries of the Single Euro Payments Area, whose banks take a euro transfer made from a Girocode.
const _sepaCountries = {
  'AD', 'AL', 'AT', 'BE', 'BG', 'CH', 'CY', 'CZ', 'DE', 'DK', 'EE', 'ES', 'FI', 'FR', 'GB', 'GI', 'GR', 'HR', 'HU', 'IE', 'IS', 'IT', 'LI', 'LT', //
  'LU', 'LV', 'MC', 'MD', 'ME', 'MK', 'MT', 'NL', 'NO', 'PL', 'PT', 'RO', 'RS', 'SE', 'SI', 'SK', 'SM', 'VA',
};

String _compactIban(String iban) => iban.replaceAll(RegExp(r'[\s\-.]+'), '').toUpperCase();

/// The IBAN in groups of four, as it is written on paper.
String formatIban(String iban) {
  final c = _compactIban(iban);
  return [for (var i = 0; i < c.length; i += 4) c.substring(i, i + 4 > c.length ? c.length : i + 4)].join(' ');
}

enum IbanStatus {
  empty,

  /// Not an IBAN so far: the country letters or the check digits are wrong.
  badStart,
  tooShort,
  tooLong,

  /// The length is right but the check digits do not add up: a character is wrong.
  badCheck,
  valid,
}

/// What is known about an IBAN typed so far.
class IbanCheck {
  const IbanCheck(this.status, {this.length = 0, this.countryCode = '', this.countryName = '', this.expectedLength});
  final IbanStatus status;
  final int length;
  final String countryCode;

  /// Empty when the country is not one the app knows.
  final String countryName;

  /// The length an IBAN of the country has, when known.
  final int? expectedLength;

  bool get valid => status == IbanStatus.valid;
  bool get sepa => _sepaCountries.contains(countryCode);
}

bool _ibanChecksum(String c) {
  final moved = c.substring(4) + c.substring(0, 4);
  var rest = 0;
  for (final unit in moved.codeUnits) {
    final digits = unit >= 0x41 ? (unit - 0x41 + 10).toString() : String.fromCharCode(unit);
    for (final d in digits.codeUnits) {
      rest = (rest * 10 + (d - 0x30)) % 97;
    }
  }
  return rest == 1;
}

/// Looks at an IBAN as it is typed: spaces and dashes are ignored, letters may be lower case.
IbanCheck checkIban(String iban) {
  final c = _compactIban(iban);
  if (c.isEmpty) return const IbanCheck(IbanStatus.empty);
  final code = c.length >= 2 && RegExp(r'^[A-Z]{2}').hasMatch(c) ? c.substring(0, 2) : '';
  final known = _ibanCountries[code];
  IbanCheck result(IbanStatus s) => IbanCheck(s, length: c.length, countryCode: code, countryName: known?.$2 ?? '', expectedLength: known?.$1);
  if (!RegExp(r'^[A-Z0-9]+$').hasMatch(c)) return result(IbanStatus.badStart);
  if (!RegExp(r'^[A-Z]').hasMatch(c) || (c.length >= 2 && code.isEmpty)) return result(IbanStatus.badStart);
  if (c.length >= 4 && !RegExp(r'^[A-Z]{2}\d{2}').hasMatch(c)) return result(IbanStatus.badStart);
  final expected = known?.$1;
  final shortest = expected ?? 15;
  final longest = expected ?? 34;
  if (c.length < shortest) return result(IbanStatus.tooShort);
  if (c.length > longest) return result(IbanStatus.tooLong);
  return result(_ibanChecksum(c) ? IbanStatus.valid : IbanStatus.badCheck);
}

/// True when the IBAN has the right length for its country and its check digits add up.
bool isValidIban(String iban) => checkIban(iban).valid;

/// The name of the country of an IBAN, or an empty string when it is not known.
String ibanCountryName(String iban) => checkIban(iban).countryName;

/// What to tell the person about the IBAN, or null when it is fine.
/// The length and the country are named, so a missing digit is easy to find.
String? ibanProblem(String iban) {
  final c = checkIban(iban);
  switch (c.status) {
    case IbanStatus.valid:
      return null;
    case IbanStatus.empty:
      return 'Enter the IBAN.';
    case IbanStatus.badStart:
      return 'An IBAN starts with two letters for the country and two check digits, such as DE89.';
    case IbanStatus.tooShort:
    case IbanStatus.tooLong:
      if (c.expectedLength == null) return 'An IBAN has 15 to 34 characters; you typed {m}.';
      return 'An IBAN from {country} has {n} characters; you typed {m}.';
    case IbanStatus.badCheck:
      return 'The check digits do not match, so a character is wrong. Compare the IBAN with the invoice or ask the payee.';
  }
}

/// The values for the {country}, {n} and {m} of [ibanProblem].
Map<String, Object> ibanProblemValues(String iban) {
  final c = checkIban(iban);
  return {'country': c.countryName.isEmpty ? '' : tr(c.countryName), 'n': c.expectedLength ?? 0, 'm': c.length};
}

String _plainAmount(String input) => input.trim().replaceAll(RegExp(r'[\s\u00A0\u202F]'), '');

/// An amount typed by a person as `12.00`, `12.50`, `1234.56`; null when it is not a usable amount (0.01 up to 999,999,999.99).
/// Accepts `12`, `12,5`, `1234.56`, and thousands separators when the cents are written too (`1.234,56`, `1,234.56`).
/// A lone `1.234` is refused, because it could mean a thousand or a euro and a bit.
String? normalizeAmount(String input) {
  final t = _plainAmount(input);
  if (t.isEmpty) return null;
  String whole;
  String cents = '';
  final plain = RegExp(r'^(\d{1,9})(?:[.,](\d{1,2}))?$').firstMatch(t);
  if (plain != null) {
    whole = plain[1]!;
    cents = plain[2] ?? '';
  } else {
    final at = t.lastIndexOf(RegExp(r'[.,]'));
    if (at < 0) return null;
    final decimal = t[at];
    final tail = t.substring(at + 1);
    final head = t.substring(0, at);
    final other = decimal == '.' ? ',' : '.';
    if (RegExp(r'^\d{1,2}$').hasMatch(tail) && RegExp('^\\d{1,3}(\\${other}\\d{3})+\$').hasMatch(head)) {
      whole = head.replaceAll(other, '');
      cents = tail;
    } else if (tail.length == 3 && RegExp('^\\d{1,3}(\\$decimal\\d{3})+\$').hasMatch(t) && head.contains(decimal)) {
      whole = t.replaceAll(decimal, '');
    } else {
      return null;
    }
  }
  if (whole.length > 9) return null;
  final c2 = cents.padRight(2, '0');
  final value = int.parse(whole);
  if (value == 0 && c2 == '00') return null;
  return '$value.$c2';
}

/// What is wrong with an amount typed for a payment, or null when it is empty or fine.
String? amountProblem(String input) {
  if (input.trim().isEmpty || normalizeAmount(input) != null) return null;
  return 'The amount is not valid. Use numbers such as 12.50 or 1,234.56, from 0.01 up to 999,999,999.99.';
}

final _bicRe = RegExp(r'^[A-Za-z]{6}[A-Za-z0-9]{2}([A-Za-z0-9]{3})?$');

/// What is wrong with a BIC (8 or 11 characters: bank, country, place and optionally branch), or null when it is empty or fine.
String? bicProblem(String bic) {
  final t = bic.trim();
  if (t.isEmpty || _bicRe.hasMatch(t)) return null;
  return 'The BIC is not valid. It has 8 or 11 letters and numbers.';
}

/// A creditor reference of ISO 11649: `RF`, two check digits and up to 21 letters or digits, with spaces allowed.
bool isCreditorReference(String text) {
  final c = text.replaceAll(RegExp(r'\s+'), '').toUpperCase();
  if (!RegExp(r'^RF\d{2}[A-Z0-9]{1,21}$').hasMatch(c)) return false;
  final moved = c.substring(4) + c.substring(0, 4);
  var rest = 0;
  for (final unit in moved.codeUnits) {
    final digits = unit >= 0x41 ? (unit - 0x41 + 10).toString() : String.fromCharCode(unit);
    for (final d in digits.codeUnits) {
      rest = (rest * 10 + (d - 0x30)) % 97;
    }
  }
  return rest == 1;
}

String _oneLine(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

/// One text for the payer: a valid creditor reference goes in the reference line of the code, anything else in the message line.
({String reference, String message}) splitRemittance(String text) {
  final t = _oneLine(text);
  if (isCreditorReference(t)) return (reference: t.replaceAll(' ', '').toUpperCase(), message: '');
  return (reference: '', message: t);
}

/// The most bytes an EPC payment QR code may carry.
const sepaMaxBytes = 331;

/// What is wrong with the details for a SEPA (Girocode) payment, or null when the code can be made.
String? sepaProblem({required String name, required String iban, String bic = '', String amount = '', String reference = '', String message = ''}) {
  if (_oneLine(name).isEmpty) return 'Enter who is paid.';
  if (_oneLine(name).length > 70) return 'The name is too long (70 letters at most).';
  final ib = ibanProblem(iban);
  if (ib != null) return trf(ib, ibanProblemValues(iban));
  final b = bicProblem(bic);
  if (b != null) return b;
  final a = amountProblem(amount);
  if (a != null) return a;
  if (reference.trim().isNotEmpty && message.trim().isNotEmpty) return 'Use either a payment reference or a message, not both.';
  if (_oneLine(reference).length > 35) return 'The reference is too long (35 characters at most).';
  if (_oneLine(message).length > 140) return 'The message is too long (140 characters at most).';
  if (utf8.encode(sepaPayload(name: name, iban: iban, bic: bic, amount: amount, reference: reference, message: message)).length > sepaMaxBytes) {
    return 'Too much text for one payment QR code. Shorten the name or the message.';
  }
  return null;
}

/// The text inside a European payment QR code (EPC "Girocode", version 002, UTF-8). Call [sepaProblem] first.
String sepaPayload({required String name, required String iban, String bic = '', String amount = '', String reference = '', String message = ''}) {
  final lines = [
    'BCD',
    '002',
    '1',
    'SCT',
    bic.trim().toUpperCase(),
    _oneLine(name),
    _compactIban(iban),
    amount.trim().isEmpty ? '' : 'EUR${normalizeAmount(amount)}',
    '',
    _oneLine(reference),
    _oneLine(message),
  ];
  return lines.join('\n');
}

/// Reads a Girocode; null when the text is not one.
PaymentRequest? parseEpc(String raw) {
  final lines = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  if (lines.length < 7 || lines[0].trim() != 'BCD' || lines[3].trim() != 'SCT') return null;
  String at(int i) => i < lines.length ? lines[i].trim() : '';
  final iban = at(6);
  if (at(5).isEmpty || iban.isEmpty) return null;
  final amountLine = at(7);
  final money = RegExp(r'^([A-Za-z]{3})(\d+(?:\.\d{1,2})?)$').firstMatch(amountLine);
  return PaymentRequest(
    scheme: 'SEPA',
    name: at(5),
    iban: _compactIban(iban),
    bic: at(4),
    currency: money?[1]?.toUpperCase() ?? '',
    amount: money?[2] ?? '',
    reference: at(9),
    message: at(10),
  );
}

/// Reads a Swiss QR-bill (also used in Liechtenstein); null when the text is not one.
PaymentRequest? parseSwissQrBill(String raw) {
  final lines = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  if (lines.length < 30 || lines[0].trim() != 'SPC') return null;
  String at(int i) => i < lines.length ? lines[i].trim() : '';
  final iban = at(3);
  final name = at(5);
  if (iban.isEmpty || name.isEmpty) return null;
  final address = [
    at(6),
    at(7),
    [at(8), at(9)].where((s) => s.isNotEmpty).join(' '),
    at(10),
  ].where((s) => s.isNotEmpty).join(', ');
  final amount = at(18);
  return PaymentRequest(
    scheme: 'Swiss QR-bill',
    name: name,
    iban: _compactIban(iban),
    currency: at(19),
    amount: RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(amount) ? amount : '',
    reference: at(28),
    message: at(29),
    address: address,
  );
}

/// Details to fill in on the payment QR screen, such as the ones of an invoice.
class SepaPrefill {
  const SepaPrefill({required this.name, required this.iban, this.bic = '', this.amount = '', this.reference = ''});
  final String name;
  final String iban;
  final String bic;
  final String amount;

  /// A creditor reference (`RF...`) goes in the reference field, any other text in the message.
  final String reference;

  bool get isCreditorReference => RegExp(r'^RF\d{2}[A-Za-z0-9]{1,21}$').hasMatch(reference.trim());
}

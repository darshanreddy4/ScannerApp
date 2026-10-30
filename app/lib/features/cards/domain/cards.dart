import 'package:barcode/barcode.dart';

import '../../../core/i18n/tr.dart';

/// How the number of a card is drawn so a shop scanner can read it.
enum CardCodeType {
  code128('Code 128'),
  ean13('EAN-13'),
  ean8('EAN-8'),
  upca('UPC-A'),
  upce('UPC-E'),
  code39('Code 39'),
  code93('Code 93'),
  itf('ITF'),
  codabar('Codabar'),
  qr('QR code'),
  pdf417('PDF417'),
  aztec('Aztec'),
  dataMatrix('Data Matrix'),
  none('Number only (no code)');

  const CardCodeType(this.label);
  final String label;

  bool get isDrawn => this != none;

  bool get isSquare => this == qr || this == aztec || this == dataMatrix;

  Barcode? get barcode => switch (this) {
    code128 => Barcode.code128(),
    ean13 => Barcode.ean13(drawEndChar: false),
    ean8 => Barcode.ean8(drawSpacers: false),
    upca => Barcode.upcA(),
    upce => Barcode.upcE(),
    code39 => Barcode.code39(),
    code93 => Barcode.code93(),
    itf => Barcode.itf(),
    codabar => Barcode.codabar(),
    qr => Barcode.qrCode(),
    pdf417 => Barcode.pdf417(),
    aztec => Barcode.aztec(),
    dataMatrix => Barcode.dataMatrix(),
    none => null,
  };

  /// The type for the name the camera gives a scanned code, or null when it is not one a card can show.
  static CardCodeType? fromScan(String format) => switch (format.toLowerCase()) {
    'code128' => code128,
    'ean13' => ean13,
    'ean8' => ean8,
    'upca' => upca,
    'upce' => upce,
    'code39' => code39,
    'code93' => code93,
    'itf' || 'itf14' || 'itf2of5' || 'itf2of5withchecksum' => itf,
    'codabar' => codabar,
    'qrcode' => qr,
    'pdf417' => pdf417,
    'aztec' => aztec,
    'datamatrix' => dataMatrix,
    _ => null,
  };
}

enum CardCategory {
  shop('Shop'),
  supermarket('Supermarket'),
  pharmacy('Pharmacy'),
  fuel('Fuel'),
  food('Food and cafe'),
  travel('Travel'),
  fitness('Gym and sport'),
  library('Library'),
  gift('Gift card'),
  membership('Membership'),
  other('Other');

  const CardCategory(this.label);
  final String label;
}

/// The colours a card can have, as ARGB.
const cardColors = [0xFF1565C0, 0xFF2E7D32, 0xFFC62828, 0xFFEF6C00, 0xFF6A1B9A, 0xFF00838F, 0xFF4E342E, 0xFF37474F];

const maxCards = 100;
const maxCardName = 40;
const maxCardNote = 200;
const maxCardNumber = 120;

class LoyaltyCard {
  const LoyaltyCard({
    required this.id,
    required this.name,
    required this.number,
    this.type = CardCodeType.code128,
    this.category = CardCategory.shop,
    this.color = 0xFF1565C0,
    this.note = '',
    this.expiry,
    this.pinned = false,
    this.usedAt = 0,
  });

  final String id;
  final String name;
  final String number;
  final CardCodeType type;
  final CardCategory category;

  /// ARGB.
  final int color;
  final String note;

  /// The last day the card is valid, if it has one.
  final DateTime? expiry;
  final bool pinned;

  /// When it was last shown at a till, in milliseconds since 1970; 0 when never.
  final int usedAt;

  LoyaltyCard copyWith({
    String? id,
    String? name,
    String? number,
    CardCodeType? type,
    CardCategory? category,
    int? color,
    String? note,
    Object? expiry = _keep,
    bool? pinned,
    int? usedAt,
  }) => LoyaltyCard(
    id: id ?? this.id,
    name: name ?? this.name,
    number: number ?? this.number,
    type: type ?? this.type,
    category: category ?? this.category,
    color: color ?? this.color,
    note: note ?? this.note,
    expiry: identical(expiry, _keep) ? this.expiry : expiry as DateTime?,
    pinned: pinned ?? this.pinned,
    usedAt: usedAt ?? this.usedAt,
  );

  static const _keep = Object();

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'number': number,
    'type': type.name,
    'category': category.name,
    'color': color,
    'note': note,
    'expiry': expiry == null ? null : _day(expiry!),
    'pinned': pinned,
    'usedAt': usedAt,
  };

  static LoyaltyCard? fromJson(Object? o) {
    if (o is! Map) return null;
    final id = o['id'], name = o['name'], number = o['number'];
    if (id is! String || name is! String || number is! String || name.trim().isEmpty || number.trim().isEmpty) return null;
    final color = o['color'];
    final expiry = o['expiry'];
    return LoyaltyCard(
      id: id,
      name: name,
      number: number,
      type: CardCodeType.values.asNameMap()[o['type']] ?? CardCodeType.code128,
      category: CardCategory.values.asNameMap()[o['category']] ?? CardCategory.other,
      color: color is int ? color : cardColors.first,
      note: o['note'] is String ? o['note'] as String : '',
      expiry: expiry is String ? DateTime.tryParse(expiry) : null,
      pinned: o['pinned'] == true,
      usedAt: o['usedAt'] is int ? o['usedAt'] as int : 0,
    );
  }

  static String _day(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

enum CardValidity { none, valid, soon, expired }

/// Whether a card with a last day is still good, about to run out (within 30 days) or over.
CardValidity validityOf(LoyaltyCard card, DateTime now) {
  final e = card.expiry;
  if (e == null) return CardValidity.none;
  final today = DateTime(now.year, now.month, now.day);
  final last = DateTime(e.year, e.month, e.day);
  if (last.isBefore(today)) return CardValidity.expired;
  return last.difference(today).inDays <= 30 ? CardValidity.soon : CardValidity.valid;
}

/// The last four characters only, so a card in a list cannot be read over a shoulder.
String maskedNumber(String number) => number.length <= 4 ? number : '\u2022\u2022\u2022\u2022 ${number.substring(number.length - 4)}';

/// Pinned cards first, then the one used most recently, then by name. [query] narrows by name, kind or note.
List<LoyaltyCard> sortedCards(List<LoyaltyCard> cards, {String query = ''}) {
  final q = query.trim().toLowerCase();
  final shown = q.isEmpty
      ? [...cards]
      : cards.where((c) => c.name.toLowerCase().contains(q) || c.category.label.toLowerCase().contains(q) || c.note.toLowerCase().contains(q)).toList();
  shown.sort((a, b) {
    if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
    if (a.usedAt != b.usedAt) return b.usedAt.compareTo(a.usedAt);
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return shown;
}

/// The check digit that follows [body] in EAN and UPC codes.
int eanCheckDigit(String body) {
  var sum = 0;
  for (var i = 0; i < body.length; i++) {
    final digit = body.codeUnitAt(body.length - 1 - i) - 48;
    sum += i.isEven ? digit * 3 : digit;
  }
  return (10 - sum % 10) % 10;
}

/// A message with {names} in it, so it can be translated before the values go in.
class CardProblem {
  const CardProblem(this.template, [this.values = const {}]);
  final String template;
  final Map<String, Object> values;

  String get text => trf(template, values);

  @override
  String toString() => text;
}

final _digits = RegExp(r'^\d+$');

/// Digits printed in groups, such as 4006 3813 3393 1, which a scanner reads as one number.
final _groupedDigits = RegExp(r'^\d[\d\s-]*$');
final _code39 = RegExp(r'^[A-Z0-9\-. $/+%]+$');

/// What is wrong with [number] for [type], or null when the code can be drawn.
CardProblem? numberProblem(CardCodeType type, String number) {
  if (number.trim().isEmpty) return const CardProblem('Enter the card number.');
  if (number.length > maxCardNumber) return const CardProblem('The number is too long (120 characters at most).');
  switch (type) {
    case CardCodeType.none:
      return null;
    case CardCodeType.ean13 || CardCodeType.ean8 || CardCodeType.upca:
      final length = switch (type) {
        CardCodeType.ean13 => 13,
        CardCodeType.ean8 => 8,
        _ => 12,
      };
      if (!_digits.hasMatch(number) || number.length != length)
        return CardProblem('The {type} code must be exactly {n} digits, with no spaces or letters.', {'type': type.label, 'n': length});
      final expected = eanCheckDigit(number.substring(0, length - 1));
      if (number.codeUnitAt(length - 1) - 48 != expected)
        return CardProblem('The last digit of a {type} code is a check digit and should be {digit} here. Check the number on the card.', {
          'type': type.label,
          'digit': expected,
        });
      return null;
    case CardCodeType.upce:
      if (!_digits.hasMatch(number) || number.length != 8) return const CardProblem('A UPC-E code is exactly 8 digits.');
    case CardCodeType.itf:
      if (!_digits.hasMatch(number)) return const CardProblem('An ITF code has digits only.');
      if (number.length.isOdd) return const CardProblem('An ITF code needs an even number of digits. Add a 0 at the front if the card has an odd number.');
    case CardCodeType.code39:
      if (!_code39.hasMatch(number)) return const CardProblem('A Code 39 code has capital letters, digits and the signs - . \$ / + % and space only.');
    case CardCodeType.code128:
      if (number.runes.any((r) => r < 32 || r > 126))
        return const CardProblem('A Code 128 code has plain letters, digits and signs only. Choose QR code for other characters.');
    case CardCodeType.code93 || CardCodeType.codabar || CardCodeType.pdf417 || CardCodeType.aztec || CardCodeType.qr || CardCodeType.dataMatrix:
      break;
  }
  final barcode = type.barcode;
  if (barcode != null && !barcode.isValid(number))
    return CardProblem('This number cannot be drawn as {type}. Choose another type, or QR code.', {'type': type.label});
  return null;
}

/// The code type that fits a number typed by hand: the product types for digits that pass their check, else Code 128.
CardCodeType suggestCodeType(String number) {
  final n = _groupedDigits.hasMatch(number.trim()) ? number.replaceAll(RegExp(r'[\s-]'), '') : number.trim();
  if (_digits.hasMatch(n)) {
    if (n.length == 13 && numberProblem(CardCodeType.ean13, n) == null) return CardCodeType.ean13;
    if (n.length == 12 && numberProblem(CardCodeType.upca, n) == null) return CardCodeType.upca;
    if (n.length == 8 && numberProblem(CardCodeType.ean8, n) == null) return CardCodeType.ean8;
  }
  return CardCodeType.code128;
}

/// What is wrong with the whole card, field by field. [others] are the cards already saved.
Map<String, CardProblem> cardProblems(LoyaltyCard card, List<LoyaltyCard> others) {
  final problems = <String, CardProblem>{};
  final name = card.name.trim();
  if (name.isEmpty) {
    problems['name'] = const CardProblem('Enter the name of the shop or club.');
  } else if (name.length > maxCardName) {
    problems['name'] = const CardProblem('The name is too long (40 characters at most).');
  }
  final number = numberProblem(card.type, card.number);
  if (number != null) problems['number'] = number;
  if (card.note.length > maxCardNote) problems['note'] = const CardProblem('The note is too long (200 characters at most).');
  if (problems.isEmpty && others.any((c) => c.id != card.id && c.name.trim().toLowerCase() == name.toLowerCase() && c.number == card.number)) {
    problems['number'] = const CardProblem('This card is already saved.');
  }
  return problems;
}

/// The card tidied before it is saved: spaces trimmed, and capitals for the types that have only capitals.
LoyaltyCard tidyCard(LoyaltyCard card) {
  var number = card.number.trim();
  if (card.type == CardCodeType.code39) number = number.toUpperCase();
  if (card.type != CardCodeType.none && _groupedDigits.hasMatch(number)) number = number.replaceAll(RegExp(r'[\s-]'), '');
  return card.copyWith(name: card.name.trim().replaceAll(RegExp(r'\s+'), ' '), number: number, note: card.note.trim());
}

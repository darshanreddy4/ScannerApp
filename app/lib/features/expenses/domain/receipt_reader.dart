import '../../scanner/domain/receipt_parser.dart';
import 'receipt_record.dart';

// ---------------------------------------------------------------- amounts

const _symbols = '₹\$€£¥₩₺₽฿₫₱₦';
const _symbolRe = '[$_symbols]|R\\\$';
final _symbolPattern = RegExp(_symbolRe);
const _words = r'rs\.?|inr|usd|eur|gbp|aed|sar|cad|aud|nzd|chf|jpy|cny|sgd|myr|thb|zar|brl|mxn|sek|nok|dkk|pln|try|pkr|bdt|lkr|npr';
final _wordFront = RegExp('^(?:$_words)(?=[\\d(-])', caseSensitive: false);
final _wordBack = RegExp('(?<=\\d)(?:$_words)\$', caseSensitive: false);

/// Reads one piece of a bill as an amount: "450.00", "₹1,23,456.50", "12,50", "Rs.450" or "(20.00)". A whole number counts as an amount
/// only with a currency sign or when [allowBare] is set, because on its own it is more likely a quantity or a code. Null when it is no amount.
double? parseAmount(String raw, {bool allowBare = false}) {
  var s = raw.trim();
  if (s.isEmpty) return null;
  var negative = false;
  if (s.startsWith('(') && s.endsWith(')')) {
    negative = true;
    s = s.substring(1, s.length - 1);
  }
  s = s.replaceAll(RegExp(r'^[*:=|]+|[*:=|;]+$'), '');
  var marked = false;
  final noSymbol = s.replaceAll(_symbolPattern, '');
  if (noSymbol != s) {
    marked = true;
    s = noSymbol;
  }
  if (s.startsWith('-')) {
    negative = true;
    s = s.substring(1);
  }
  final front = _wordFront.firstMatch(s);
  if (front != null) {
    marked = true;
    s = s.substring(front.end);
  }
  final back = _wordBack.firstMatch(s);
  if (back != null) {
    marked = true;
    s = s.substring(0, back.start);
  }
  if (s.endsWith('-')) {
    negative = true;
    s = s.substring(0, s.length - 1);
  }
  s = s.replaceAll(RegExp(r'[*:=]+$'), '').replaceAll(RegExp(r'^[.,]+|[.,]+$'), '');
  if (!RegExp(r'^\d[\d.,]*$').hasMatch(s)) return null;

  final dot = s.lastIndexOf('.');
  final comma = s.lastIndexOf(',');
  final dots = '.'.allMatches(s).length, commas = ','.allMatches(s).length;
  var whole = s;
  var cents = '';
  final sep = dot > comma ? dot : comma;
  if (sep >= 0) {
    final tail = s.substring(sep + 1);
    final head = s.substring(0, sep);
    final single = (dot >= 0 ? dots : commas) == 1;
    final both = dots > 0 && commas > 0;
    final decimal = tail.isNotEmpty && (both ? tail.length <= 3 : single && (tail.length <= 2 || head == '0'));
    if (decimal) {
      whole = head;
      cents = tail;
    } else if (tail.length != 3) {
      return null;
    }
  }
  whole = whole.replaceAll(RegExp(r'[.,]'), '');
  if (whole.isEmpty || whole.length > 9) return null;
  if (cents.isEmpty && !marked && !allowBare) return null;
  final v = double.parse(cents.isEmpty ? whole : '$whole.$cents');
  return negative ? -v : v;
}

/// The last amount of a row of text: amounts stand at the right end of a line, after the words and any quantity and price per unit.
double? lastAmount(String row, {bool allowBare = false}) {
  final tokens = row.replaceAll(RegExp(r'[:=]'), ' ').trim().split(RegExp(r'\s+'));
  double? found;
  for (var i = 0; i < tokens.length; i++) {
    var t = tokens[i];
    // A sign or a currency word standing alone belongs to the number after it.
    if (RegExp('^(?:$_symbolRe|$_words)\$', caseSensitive: false).hasMatch(t) && i + 1 < tokens.length) {
      t = '$t${tokens[++i]}';
    }
    final v = parseAmount(t, allowBare: allowBare);
    if (v != null) found = v;
  }
  return found;
}

bool _hasLetters(String s) => RegExp(r'\p{L}', unicode: true).hasMatch(s.replaceAll(RegExp('^(?:$_words)\$|\\b(?:$_words)\\b', caseSensitive: false), ''));

// ---------------------------------------------------------------- currency

const _codeOfSymbol = {
  '₹': 'INR',
  '\$': 'USD',
  '€': 'EUR',
  '£': 'GBP',
  '¥': 'JPY',
  '₩': 'KRW',
  '₺': 'TRY',
  '₽': 'RUB',
  '฿': 'THB',
  '₫': 'VND',
  '₱': 'PHP',
  '₦': 'NGN',
  'R\$': 'BRL',
};

/// A currency code for what a bill prints ("₹" is INR); a printed code stays as it is, and a dollar sign is taken as USD.
String currencyCodeFor(String? marker) {
  if (marker == null || marker.isEmpty) return '';
  final m = marker.trim();
  return _codeOfSymbol[m] ?? (RegExp(r'^[A-Za-z]{3}$').hasMatch(m) ? m.toUpperCase() : '');
}

/// The sign of a currency code for showing amounts; the code itself when there is no sign.
String currencySign(String code) {
  for (final e in _codeOfSymbol.entries) {
    if (e.value == code) return e.key;
  }
  return code;
}

// ---------------------------------------------------------------- reading

String _flat(String s) => s.toLowerCase();

final _subtotalRe = RegExp(r'sub\s*-?\s*total|sous[\s-]*total|zwischensumme|subtotale');
final _taxableRe = RegExp(r'taxable\s*(?:value|amount|amt)?|net\s*value');
final _taxRe = RegExp(r'(?<![\p{L}])(?:cgst|sgst|utgst|igst|gst|vat|tax|iva|mwst|tva|ust|cess)(?![\p{L}])', unicode: true);
final _taxSkipRe = RegExp(r'invoice|gstin|\bno\b|number|tax\s*id|\btin\b|taxable|incl|inclusive|included|exempt|\bpan\b|regist|total\s*items');
final _taxTotalRe = RegExp(r'total\s*(?:tax|gst|vat|iva|mwst)|(?:tax|gst|vat)\s*total');
final _taxPartRe = RegExp(r'(?<![\p{L}])(?:cgst|sgst|utgst|igst|cess)(?![\p{L}])', unicode: true);
final _discountRe = RegExp(r'discount|coupon|promo|rebate|voucher');
final _tipRe = RegExp(
  r'(?<![\p{L}])(?:tip|gratuity)(?![\p{L}])|service\s*(?:charge|fee)|delivery|packing|handling|convenience|surcharge|platform\s*fee',
  unicode: true,
);
final _roundRe = RegExp(r'round(?:ing)?\s*-?\s*off|rounding|round\s*up|round\s*down');
final _paymentRe = RegExp(
  r'(?<![\p{L}])(?:cash|card|visa|master|upi|paytm|gpay|phonepe|tender|tendered|change|paid|credit|debit|wallet|cheque|received|refund)(?![\p{L}])|balance(?!\s*due)|net\s*banking',
  unicode: true,
);
final _infoRe = RegExp(
  r'(?<![\p{L}])(?:qty|quantity|saving|savings|saved|points?|loyalty|mrp|invoice|bill\s*no|order|table|tel|ph|phone|mob|gstin|fssai|date|time|cashier|server|token|www|http)(?![\p{L}])|total\s*items?|items?\s*:|@',
  unicode: true,
);
final _strongRe = RegExp(
  r'grand\s*total|amount\s*(?:due|payable)|balance\s*due|net\s*(?:amount|payable|total|amt)|to\s*pay|total\s*(?:due|payable|amount|amt|invoice|a\s*pagar|à\s*payer)|bill\s*(?:amount|total)|invoice\s*(?:amount|total)|a\s*pagar|à\s*payer|gesamtbetrag|gesamtsumme|importe\s*total|totale\s*complessivo|कुल\s*(?:देय|राशि)',
);
final _plainRe = RegExp(r'(?<![\p{L}])(?:total(?:e|i)?|totaal|toplam|summe|gesamt|betrag|montant|importe|importo|कुल|योग)(?![\p{L}])', unicode: true);

enum _Kind { subtotal, taxable, tax, taxTotal, discount, tip, round, payment, info, strong, plain, other }

_Kind _kindOf(String row) {
  final s = _flat(row);
  if (_roundRe.hasMatch(s)) return _Kind.round;
  if (_subtotalRe.hasMatch(s)) return _Kind.subtotal;
  if (_taxTotalRe.hasMatch(s)) return _Kind.taxTotal;
  if (_taxRe.hasMatch(s) && !_taxSkipRe.hasMatch(s)) return _Kind.tax;
  if (_taxableRe.hasMatch(s) && !_strongRe.hasMatch(s)) return _Kind.taxable;
  if (_discountRe.hasMatch(s)) return _Kind.discount;
  if (_tipRe.hasMatch(s)) return _Kind.tip;
  if (_strongRe.hasMatch(s)) return _Kind.strong;
  if (_paymentRe.hasMatch(s)) return _Kind.payment;
  if (_infoRe.hasMatch(s)) return _Kind.info;
  if (_plainRe.hasMatch(s)) return _Kind.plain;
  return _Kind.other;
}

/// Reads one bill from the rows of text of its photo: shop, date, currency, the lines, subtotal, tax, tip, discount and total. The parts are
/// checked against each other, and what is missing is worked out where the maths allows it; [ReceiptRecord.notes] says what was worked out.
ReceiptRecord readReceipt(List<String> rowsIn, {required String id, required String source, DateTime? now, String defaultCurrency = ''}) {
  final rows = [
    for (final r in rowsIn)
      if (r.trim().isNotEmpty) r.trim().replaceAll(RegExp(r'\s+'), ' '),
  ];
  final today = now ?? DateTime.now();
  final kinds = [for (final r in rows) _kindOf(r)];

  // A label with its amount on the row below (columns that were read as separate lines).
  double? amountAt(int i, {bool bare = false}) {
    final own = lastAmount(rows[i], allowBare: bare);
    if (own != null) return own;
    if (i + 1 < rows.length && !_hasLetters(rows[i + 1])) return lastAmount(rows[i + 1], allowBare: bare);
    return null;
  }

  double? sumOf(_Kind kind, {bool bare = false, bool absolute = false}) {
    double? sum;
    final seen = <String>{};
    for (var i = 0; i < rows.length; i++) {
      if (kinds[i] != kind) continue;
      final a = amountAt(i, bare: bare);
      if (a == null) continue;
      // The same line read twice (two photos of one page, or a repeated footer) is counted once.
      if (!seen.add('${_flat(rows[i])}|$a')) continue;
      sum = (sum ?? 0) + (absolute ? a.abs() : a);
    }
    return sum == null ? null : roundCents(sum);
  }

  double? lastOf(_Kind kind, {bool bare = false}) {
    for (var i = rows.length - 1; i >= 0; i--) {
      if (kinds[i] != kind) continue;
      final a = amountAt(i, bare: bare);
      if (a != null) return roundCents(a);
    }
    return null;
  }

  var subtotal = lastOf(_Kind.subtotal, bare: true) ?? lastOf(_Kind.taxable, bare: true);
  final discount = sumOf(_Kind.discount, absolute: true);
  final tip = sumOf(_Kind.tip, absolute: true);

  // Tax: a printed total of tax, else the parts (CGST + SGST), else the lines called tax or VAT.
  double? tax = lastOf(_Kind.taxTotal, bare: false);
  if (tax == null) {
    double? parts, generic;
    final seen = <String>{};
    for (var i = 0; i < rows.length; i++) {
      if (kinds[i] != _Kind.tax) continue;
      final a = amountAt(i);
      if (a == null || !seen.add('${_flat(rows[i])}|$a')) continue;
      if (_taxPartRe.hasMatch(_flat(rows[i]))) {
        parts = (parts ?? 0) + a;
      } else {
        generic = (generic ?? 0) + a;
      }
    }
    tax = parts ?? generic;
    if (tax != null) tax = roundCents(tax);
  }

  // The lines of the bill, above the first summary line.
  var firstSummary = rows.length;
  for (var i = 0; i < rows.length; i++) {
    if (const {_Kind.subtotal, _Kind.taxable, _Kind.tax, _Kind.taxTotal, _Kind.strong, _Kind.plain, _Kind.payment}.contains(kinds[i])) {
      firstSummary = i;
      break;
    }
  }
  final vendor = receiptVendor(rows) ?? '';
  final items = <ReceiptItem>[];
  for (var i = 0; i < firstSummary; i++) {
    if (kinds[i] != _Kind.other) continue;
    final a = lastAmount(rows[i]);
    if (a == null) continue;
    final description = _describe(rows[i]);
    if (description.length < 3 || description == vendor) continue;
    items.add(ReceiptItem(description: description, amount: roundCents(a)));
  }
  final itemsSum = items.isEmpty ? null : roundCents(items.fold<double>(0, (s, e) => s + e.amount));

  // The total: a marked one, and when there are several, the one that fits the parts.
  final strong = <double>[], plain = <double>[];
  for (var i = 0; i < rows.length; i++) {
    final k = kinds[i];
    if (k != _Kind.strong && k != _Kind.plain) continue;
    final a = amountAt(i, bare: true);
    if (a == null || a <= 0) continue;
    (k == _Kind.strong ? strong : plain).add(roundCents(a));
  }
  double? total;
  var guessed = false;
  var worked = false;
  final candidates = strong.isNotEmpty ? strong : plain;
  if (candidates.isNotEmpty) {
    total = candidates.last;
    if (subtotal != null && candidates.length > 1) {
      final expected = roundCents(subtotal - (discount ?? 0) + (tax ?? 0) + (tip ?? 0));
      for (final c in candidates.reversed) {
        if ((c - expected).abs() <= 0.02) {
          total = c;
          break;
        }
      }
    }
  }
  if (total == null) {
    if (subtotal != null) {
      total = roundCents(subtotal - (discount ?? 0) + (tax ?? 0) + (tip ?? 0));
      worked = true;
    } else if (itemsSum != null) {
      total = roundCents(itemsSum - (discount ?? 0) + (tax ?? 0) + (tip ?? 0));
      worked = true;
    } else {
      double? biggest;
      for (var i = 0; i < rows.length; i++) {
        if (kinds[i] == _Kind.payment || kinds[i] == _Kind.info || kinds[i] == _Kind.round) continue;
        final a = lastAmount(rows[i]);
        if (a != null && (biggest == null || a > biggest)) biggest = a;
      }
      if (biggest != null && biggest > 0) {
        total = roundCents(biggest);
        guessed = true;
      }
    }
  }

  // Maths that fills a gap: the lines add up to the subtotal when no tax is added to them, and the tax is what lies between the two.
  var taxWorked = false;
  if (total != null && subtotal == null && itemsSum != null) {
    final expected = roundCents(total - (tax ?? 0) - (tip ?? 0) + (discount ?? 0));
    if ((itemsSum - expected).abs() <= (expected.abs() * 0.01 > 0.05 ? expected.abs() * 0.01 : 0.05)) subtotal = itemsSum;
  }
  if (total != null && subtotal != null && tax == null && !worked) {
    final between = roundCents(total - subtotal + (discount ?? 0) - (tip ?? 0));
    if (between > 0.009 && between <= subtotal * 0.5) {
      tax = between;
      taxWorked = true;
    }
  }

  final text = rows.join('\n');
  final marker = (total == null ? null : _markerOfRowWith(rows, kinds)) ?? firstCurrencyMarker(text);
  final currency = currencyCodeFor(marker).isEmpty ? defaultCurrency : currencyCodeFor(marker);

  return ReceiptRecord(
    id: id,
    source: source,
    vendor: vendor,
    date: receiptDate(text, today),
    currency: currency,
    subtotal: subtotal,
    discount: discount,
    tax: tax,
    tip: tip,
    total: total,
    category: categoryFor(vendor, rows),
    items: items,
    taxWorkedOut: taxWorked,
    totalWorkedOut: worked,
    totalGuessed: guessed,
  );
}

String? _markerOfRowWith(List<String> rows, List<_Kind> kinds) {
  for (var i = rows.length - 1; i >= 0; i--) {
    if (kinds[i] != _Kind.strong && kinds[i] != _Kind.plain) continue;
    final m = firstCurrencyMarker(rows[i]) ?? (i + 1 < rows.length ? firstCurrencyMarker(rows[i + 1]) : null);
    if (m != null) return m;
  }
  return null;
}

/// The words of an item line: its amounts, a leading quantity or code, and stray one-letter marks are taken away.
String _describe(String row) {
  final words = <String>[];
  for (final t in row.split(' ')) {
    if (parseAmount(t, allowBare: false) != null) continue;
    if (RegExp('^(?:$_symbolRe|$_words)\$', caseSensitive: false).hasMatch(t)) continue;
    words.add(t);
  }
  while (words.isNotEmpty && RegExp(r'^[\dxX*.,@]+$').hasMatch(words.first)) {
    words.removeAt(0);
  }
  while (words.isNotEmpty && RegExp(r'^[\dxX*.,@%A-Z]$|^[\d.,%]+$').hasMatch(words.last)) {
    words.removeLast();
  }
  return words.join(' ').trim();
}

// ---------------------------------------------------------------- category

final _categoryWords = <ExpenseCategory, RegExp>{
  ExpenseCategory.fuel: RegExp(
    r'petrol|diesel|\bfuel\b|filling\s*station|bharat\s*petroleum|\bbpcl\b|\bhpcl\b|\biocl\b|indian\s*oil|\bshell\b|nayara|essar|\bcng\b',
  ),
  ExpenseCategory.health: RegExp(r'pharma|chemist|medical|medico|hospital|clinic|diagnostic|apollo|medplus|netmeds|dental|\blab\b|\blabs\b|optical|doctor'),
  ExpenseCategory.dining: RegExp(
    r'restaurant|\bcafe\b|café|coffee|pizza|burger|kitchen|dhaba|biryani|bakery|sweets|\bbar\b|\bpub\b|diner|bistro|eatery|domino|mcdonald|\bkfc\b|starbucks|subway|swiggy|zomato|tandoor|food\s*court|\bdine|tea\s*house|juice',
  ),
  ExpenseCategory.transport: RegExp(
    r'\buber\b|\bola\b|rapido|\btaxi\b|\bcab\b|\bmetro\b|railway|irctc|\bbus\b|parking|\btoll\b|fastag|airlines?|airways|indigo|air\s*india|vistara|flight|transport',
  ),
  ExpenseCategory.travel: RegExp(r'hotel|resort|\binn\b|lodge|hostel|\bstay\b|\boyo\b|airbnb|booking|motel|guest\s*house'),
  ExpenseCategory.utilities: RegExp(
    r'electricity|power\s*(?:bill|corp)|water\s*bill|broadband|internet|airtel|\bjio\b|vodafone|\bbsnl\b|recharge|gas\s*(?:bill|agency|cylinder)|telecom|\bdth\b|tata\s*(?:play|sky)|postpaid|prepaid|mobile\s*bill',
  ),
  ExpenseCategory.groceries: RegExp(
    r'supermarket|grocer|\bmart\b|bazaar|bazar|kirana|provision|fresh|dmart|d-mart|big\s*bazaar|\bmore\b|\bspar\b|hypermarket|vegetable|fruits|dairy|general\s*store|walmart|tesco|aldi|lidl|carrefour|costco|mandi',
  ),
  ExpenseCategory.shopping: RegExp(
    r'\bstore\b|\bmall\b|fashion|apparel|clothing|garment|electronics|mobile|reliance|croma|amazon|flipkart|myntra|lifestyle|shoppers|westside|pantaloons|decathlon|ikea|books?\b|stationery|hardware|jewel|footwear|shoes|boutique|textile',
  ),
};

/// A guess at what a bill was for from the shop's name and the first lines, then the whole text.
ExpenseCategory categoryFor(String vendor, List<String> rows) {
  final header = _flat('$vendor ${rows.take(10).join(' ')}');
  for (final e in _categoryWords.entries) {
    if (e.value.hasMatch(header)) return e.key;
  }
  final all = _flat(rows.join(' '));
  for (final e in _categoryWords.entries) {
    if (e.value.hasMatch(all)) return e.key;
  }
  return ExpenseCategory.other;
}

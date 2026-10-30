/// What could be read from the text of a till receipt.
class ReceiptInfo {
  const ReceiptInfo({this.vendor, this.total, this.date});

  final String? vendor;

  /// Amount with its currency sign or code when one was printed, e.g. "$4.94", "₹450.00" or "12.50 EUR".
  final String? total;
  final DateTime? date;

  bool get isEmpty => vendor == null && total == null && date == null;

  /// "Receipt - Shop - $24.50 - 2026-01-31", or null when nothing was found.
  String? get title {
    if (isEmpty) return null;
    final d = date;
    final day = d == null ? null : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return ['Receipt', ?vendor, ?total, ?day].join(' - ');
  }
}

ReceiptInfo parseReceipt(String text, {DateTime? now}) {
  final lines = [
    for (final l in text.split('\n'))
      if (l.trim().isNotEmpty) l.trim(),
  ];
  return ReceiptInfo(vendor: _vendor(lines), total: _total(lines), date: _date(text, now ?? DateTime.now()));
}

// Money

const _symbols = r'₹|\$|€|£|¥|₩|₺|₽|฿|₫|₱|₦|R\$';
const _codes = r'INR|USD|EUR|GBP|AED|SAR|CAD|AUD|NZD|CHF|JPY|CNY|SGD|MYR|THB|ZAR|BRL|MXN|SEK|NOK|DKK|PLN|TRY|PKR|BDT|LKR|NPR|Rs\.?';

/// A currency marker in front, a number, and optionally a marker behind: "₹ 1,23,456.00", "12,50 €", "Rs. 450", "450 INR".
final _money = RegExp('($_symbols|\\b(?:$_codes))?\\s*(\\d[\\d., ]*\\d|\\d)\\s*($_symbols|\\b(?:$_codes)\\b)?', caseSensitive: false);

final _marker = RegExp('$_symbols|\\b(?:$_codes)\\b', caseSensitive: false);

const _strong =
    r'grand\s*total|amount\s*(?:due|payable)|balance\s*due|net\s*(?:amount|payable|total)|to\s*pay|total\s*(?:due|payable|a\s*pagar)|a\s*pagar|à\s*payer|gesamtbetrag|कुल\s*देय';
const _plain = r'total(?:e|i)?|totaal|toplam|summe|gesamt|betrag|montant|importe|importo|कुल|योग';

final _strongWord = RegExp('(?<![\\p{L}])(?:$_strong)(?![\\p{L}])', caseSensitive: false, unicode: true);
final _plainWord = RegExp('(?<![\\p{L}])(?:$_plain)(?![\\p{L}])', caseSensitive: false, unicode: true);
final _notTotal = RegExp(
  r'sub\s*-?\s*total|tax|gst|vat|cgst|sgst|igst|iva|mwst|tva|change|saving|discount|tender|cash|round|qty|quantity|items?\b|tip',
  caseSensitive: false,
);

/// Turns "1,234.56", "1.234,56", "12,50", "1,23,456.00" or "1 234,56" into 1234.56 style, or null when it is not an amount.
String? _normalise(String raw, {required bool marked}) {
  final s = raw.trim();
  final lastDot = s.lastIndexOf('.');
  final lastComma = s.lastIndexOf(',');
  final sep = lastDot > lastComma ? lastDot : lastComma;
  var whole = s;
  String? cents;
  if (sep >= 0) {
    final tail = s.substring(sep + 1);
    if (tail.length <= 2 && tail.isNotEmpty) {
      whole = s.substring(0, sep);
      cents = tail.padRight(2, '0');
    }
  }
  whole = whole.replaceAll(RegExp(r'[., ]'), '');
  if (whole.isEmpty || whole.length > 9) return null;
  // A bare whole number is more likely a quantity or a code than money, unless a currency sign stands next to it.
  if (cents == null && !marked) return null;
  return cents == null ? '$whole.00' : '$whole.$cents';
}

/// The printed marker as it should read in the name: "₹", "$", or "EUR".
String _display(String marker) {
  final m = marker.trim();
  if (RegExp(r'^rs\.?$', caseSensitive: false).hasMatch(m)) return '₹';
  return m.length == 1 ? m : m.toUpperCase();
}

typedef _Found = ({String amount, String? marker});

_Found? _amountIn(String line) {
  _Found? found;
  for (final m in _money.allMatches(line)) {
    final front = m.group(1);
    final back = m.group(3);
    final amount = _normalise(m.group(2)!, marked: front != null || back != null);
    if (amount != null) found = (amount: amount, marker: front ?? back);
  }
  return found;
}

String? _total(List<String> lines) {
  _Found? best;
  var bestScore = 0;
  String? anyMarker;
  for (final l in lines) {
    anyMarker ??= _marker.firstMatch(l)?.group(0);
  }
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final score = _strongWord.hasMatch(line) ? 2 : (_plainWord.hasMatch(line) ? 1 : 0);
    if (score == 0 || _notTotal.hasMatch(line)) continue;
    var amount = _amountIn(line);
    if (amount == null && i + 1 < lines.length) amount = _amountIn(lines[i + 1]);
    if (amount == null) continue;
    // A stronger wording wins; among equals the later line, as the total comes near the end.
    if (score >= bestScore) {
      best = amount;
      bestScore = score;
    }
  }
  if (best == null) return null;
  final marker = best.marker ?? anyMarker;
  if (marker == null) return best.amount;
  final shown = _display(marker);
  final isCode = RegExp(r'^[A-Z]{3}$').hasMatch(shown);
  return isCode ? '${best.amount} $shown' : '$shown${best.amount}';
}

// Shop

final _skipVendor = RegExp(
  r'^(?:tax\s*)?(?:invoice|retail|receipt|bill|cash\s*memo|gstin|gst|vat|tin|cin|tel|ph|phone|mob|www|http|date|time|no\b|#|welcome|thank|customer|copy|order|table|address|store\s*#|duplicate)|@|\d{1,2}[:/.\-]\d{1,2}[:/.\-]\d{2,4}',
  caseSensitive: false,
);

String? _vendor(List<String> lines) {
  for (final line in lines.take(8)) {
    final letters = RegExp(r'\p{L}', unicode: true).allMatches(line).length;
    final digits = RegExp(r'\d').allMatches(line).length;
    if (letters < 3 || digits > letters || line.length > 40) continue;
    if (_skipVendor.hasMatch(line) || _strongWord.hasMatch(line) || _plainWord.hasMatch(line) || _amountIn(line) != null) continue;
    return line.replaceAll(RegExp(r'\s+'), ' ');
  }
  return null;
}

// Date

final _isoDate = RegExp(r'\b(20\d{2})[-/.](\d{1,2})[-/.](\d{1,2})\b');
final _cjkDate = RegExp(r'(20\d{2})\s*年\s*(\d{1,2})\s*月\s*(\d{1,2})\s*日');
final _numericDate = RegExp(r'\b(\d{1,2})[-/.](\d{1,2})[-/.](20\d{2}|\d{2})\b');
const _monthNames = '(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\\.?';
final _dayFirstWord = RegExp('\\b(\\d{1,2})(?:st|nd|rd|th)?[\\s\\-/]+$_monthNames[\\s,\\-/]+(20\\d{2}|\\d{2})\\b', caseSensitive: false);
final _monthFirstWord = RegExp('\\b$_monthNames\\s+(\\d{1,2})(?:st|nd|rd|th)?,?\\s+(20\\d{2})\\b', caseSensitive: false);
const _months = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];

DateTime? _date(String text, DateTime now) {
  DateTime? build(int y, int m, int d) {
    final year = y < 100 ? 2000 + y : y;
    if (m < 1 || m > 12 || d < 1 || d > 31 || year < 2000 || year > now.year + 1) return null;
    final date = DateTime(year, m, d);
    return date.month == m ? date : null;
  }

  final iso = _isoDate.firstMatch(text);
  if (iso != null) {
    final d = build(int.parse(iso[1]!), int.parse(iso[2]!), int.parse(iso[3]!));
    if (d != null) return d;
  }
  final cjk = _cjkDate.firstMatch(text);
  if (cjk != null) {
    final d = build(int.parse(cjk[1]!), int.parse(cjk[2]!), int.parse(cjk[3]!));
    if (d != null) return d;
  }
  for (final m in _dayFirstWord.allMatches(text)) {
    final d = build(int.parse(m[3]!), _months.indexOf(m[2]!.toLowerCase()) + 1, int.parse(m[1]!));
    if (d != null) return d;
  }
  for (final m in _monthFirstWord.allMatches(text)) {
    final d = build(int.parse(m[3]!), _months.indexOf(m[1]!.toLowerCase()) + 1, int.parse(m[2]!));
    if (d != null) return d;
  }
  for (final m in _numericDate.allMatches(text)) {
    final a = int.parse(m[1]!);
    final b = int.parse(m[2]!);
    final y = int.parse(m[3]!);
    // Day first unless only month first makes sense.
    final d = (b > 12 && a <= 12) ? build(y, a, b) : build(y, b, a);
    if (d != null) return d;
  }
  return null;
}

/// The shop name from the rows of a receipt, or null.
String? receiptVendor(List<String> rows) => _vendor(rows);

/// The date printed on a receipt, or null.
DateTime? receiptDate(String text, DateTime now) => _date(text, now);

/// The first currency sign or code printed in [text], as it should read ("₹", "$", "EUR"), or null.
String? firstCurrencyMarker(String text) {
  final m = _marker.firstMatch(text)?.group(0);
  return m == null ? null : _display(m);
}

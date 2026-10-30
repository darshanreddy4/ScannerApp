import '../../ocr/domain/ocr_models.dart';

/// The kind of card or paper being copied. It decides which numbers are covered without being asked.
enum IdKind {
  aadhaar('Aadhaar', 'The first 8 digits are covered. The last 4 stay, as on a masked Aadhaar. The QR code holds the full number: cover it by hand.'),
  pan('PAN card', 'Nothing is covered by itself, because most KYC needs the PAN. Tap the number to cover it.'),
  passport('Passport', 'The two lines of code at the foot of the page are covered. Tap any other part to cover it.'),
  drivingLicence('Driving licence', 'Nothing is covered by itself. Tap the number or anything else to cover it.'),
  voter('Voter ID', 'Nothing is covered by itself. Tap the number or anything else to cover it.'),
  emiratesId('Emirates ID', 'Nothing is covered by itself. Tap the number or anything else to cover it.'),
  saudiId('Saudi ID or Iqama', 'Nothing is covered by itself. Tap the number or anything else to cover it.'),
  usSsn('US Social Security card', 'The first 5 digits of the number are covered. The last 4 stay.'),
  bankCard('Bank card', 'All but the last 4 digits of the card number are covered. The security code on the back is not read: cover it by hand.'),
  other('Another ID', 'Long numbers are covered except their last 4 digits. Tap anything else to cover it.');

  const IdKind(this.label, this.hint);
  final String label;
  final String hint;
}

/// A part of the picture to hide, as shares of the width and height (0 to 1) from the top left.
class CoverBox {
  const CoverBox(this.left, this.top, this.right, this.bottom);
  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => bottom - top;

  bool contains(double x, double y) => x >= left && x <= right && y >= top && y <= bottom;

  /// A box from two corners in any order, kept inside the picture.
  factory CoverBox.fromCorners(double x1, double y1, double x2, double y2) {
    double c(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);
    final a = c(x1 < x2 ? x1 : x2), b = c(y1 < y2 ? y1 : y2), r = c(x1 < x2 ? x2 : x1), d = c(y1 < y2 ? y2 : y1);
    return CoverBox(a, b, r, d);
  }

  @override
  bool operator ==(Object other) => other is CoverBox && other.left == left && other.top == top && other.right == right && other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);
}

/// A number or line found on the picture, with where it is in pixels.
class SafeFinding {
  const SafeFinding({required this.label, required this.left, required this.top, required this.right, required this.bottom, required this.covered});
  final String label;
  final double left;
  final double top;
  final double right;
  final double bottom;

  /// Whether it is covered unless the person says otherwise.
  final bool covered;
}

typedef _Span = (int start, int end);

class _Rule {
  const _Rule(this.label, this.find, {this.covered = true});
  final String label;
  final List<_Span> Function(String line) find;
  final bool covered;
}

/// The end of the [n]-th digit counting from [from], or the end of the text.
int _afterDigits(String s, int from, int n) {
  var seen = 0;
  for (var i = from; i < s.length; i++) {
    if (RegExp(r'\d').hasMatch(s[i]) && ++seen == n) return i + 1;
  }
  return s.length;
}

int _digitCount(String s) => RegExp(r'\d').allMatches(s).length;

List<_Span> _matches(RegExp re, String line, {_Span Function(Match m, String line)? cover}) => [
  for (final m in re.allMatches(line))
    if (cover == null) (m.start, m.end) else cover(m, line),
];

/// Covers the first [n] digits of the match and leaves the rest.
_Span Function(Match, String) _firstDigits(int n) =>
    (m, line) => (m.start, _afterDigits(line, m.start, n));

/// Covers every digit of the match but the last four.
_Span _allButLastFour(Match m, String line) {
  final digits = _digitCount(m[0]!);
  return (m.start, _afterDigits(line, m.start, digits - 4));
}

bool _luhn(String digits) {
  var sum = 0;
  var alt = false;
  for (var i = digits.length - 1; i >= 0; i--) {
    var d = digits.codeUnitAt(i) - 48;
    if (alt) {
      d *= 2;
      if (d > 9) d -= 9;
    }
    sum += d;
    alt = !alt;
  }
  return sum % 10 == 0;
}

final _aadhaarVid = RegExp(r'(?<!\d)\d{4}\s?\d{4}\s?\d{4}\s?\d{4}(?!\d)');

/// Spaced in groups of four, any digits (a misread first digit must not leave the number showing); in one piece, as a real number starts 2 to 9.
final _aadhaar = RegExp(r'(?<!\d)(?:\d{4}\s\d{4}\s\d{4}|[2-9]\d{11})(?!\d)');

List<_Span> _aadhaarSpans(String line) {
  final vids = _matches(_aadhaarVid, line, cover: _firstDigits(12));
  final numbers = <_Span>[];
  for (final m in _aadhaar.allMatches(line)) {
    final overlaps = _aadhaarVid.allMatches(line).any((v) => m.start < v.end && m.end > v.start);
    if (!overlaps) numbers.add(_firstDigits(8)(m, line));
  }
  return [...vids, ...numbers];
}

List<_Span> _mrz(String line) {
  final t = line.replaceAll(RegExp(r'\s'), '');
  final fillers = '<'.allMatches(t).length;
  if (t.length >= 28 && fillers >= 3 && RegExp(r'^[A-Z0-9<]+$').hasMatch(t)) return [(0, line.length)];
  return const [];
}

List<_Span> _cards(String line) {
  final out = <_Span>[];
  for (final m in RegExp(r'(?<!\d)(?:\d[ -]?){12,18}\d(?!\d)').allMatches(line)) {
    final digits = m[0]!.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 13 && digits.length <= 19 && _luhn(digits)) out.add(_allButLastFour(m, line));
  }
  return out;
}

final _rules = <IdKind, List<_Rule>>{
  IdKind.aadhaar: [_Rule('Aadhaar number', _aadhaarSpans)],
  IdKind.pan: [_Rule('PAN', (l) => _matches(RegExp(r'(?<![A-Z0-9])[A-Z]{5}\d{4}[A-Z](?![A-Z0-9])'), l), covered: false)],
  IdKind.passport: [
    _Rule('Machine-readable lines', _mrz),
    _Rule('Passport number', (l) => _matches(RegExp(r'(?<![A-Z0-9])[A-Z]{1,2}\d{6,8}(?![A-Z0-9])'), l), covered: false),
  ],
  IdKind.drivingLicence: [
    _Rule('Licence number', (l) => _matches(RegExp(r'(?<![A-Z0-9])[A-Z]{2}[-\s]?\d{2}[-\s]?(?:19|20)\d{2}[-\s]?\d{7}(?!\d)'), l), covered: false),
  ],
  IdKind.voter: [_Rule('EPIC number', (l) => _matches(RegExp(r'(?<![A-Z0-9])[A-Z]{3}\d{7}(?!\d)'), l), covered: false)],
  IdKind.emiratesId: [_Rule('Emirates ID number', (l) => _matches(RegExp(r'(?<!\d)784[-\s]?\d{4}[-\s]?\d{7}[-\s]?\d(?!\d)'), l), covered: false)],
  IdKind.saudiId: [_Rule('ID number', (l) => _matches(RegExp(r'(?<!\d)[12]\d{9}(?!\d)'), l), covered: false)],
  IdKind.usSsn: [_Rule('Social Security number', (l) => _matches(RegExp(r'(?<!\d)\d{3}[-\s]\d{2}[-\s]\d{4}(?!\d)'), l, cover: _firstDigits(5)))],
  IdKind.bankCard: [_Rule('Card number', _cards)],
  IdKind.other: [_Rule('Number', (l) => _matches(RegExp(r'(?<!\d)\d(?:[ -]?\d){8,}(?!\d)'), l, cover: _allButLastFour))],
};

/// The part of a line between two character positions, as a box in pixels. A word is taken to have even letters, so a cut inside a
/// word falls in proportion.
({double left, double top, double right, double bottom})? _boxOf(OcrLine line, int start, int end) {
  final words = line.words.isEmpty ? [OcrWord(text: line.text, left: line.left, top: line.top, right: line.right, bottom: line.bottom)] : line.words;
  double? l, t, r, b;
  var pos = 0;
  for (final w in words) {
    final ws = pos, we = pos + w.text.length;
    pos = we + 1;
    final a = start > ws ? start : ws, z = end < we ? end : we;
    if (z <= a || w.text.isEmpty) continue;
    final len = w.text.length;
    final x0 = w.left + (w.right - w.left) * (a - ws) / len;
    final x1 = w.left + (w.right - w.left) * (z - ws) / len;
    l = l == null || x0 < l ? x0 : l;
    r = r == null || x1 > r ? x1 : r;
    t = t == null || w.top < t ? w.top : t;
    b = b == null || w.bottom > b ? w.bottom : b;
  }
  return l == null ? null : (left: l, top: t!, right: r!, bottom: b!);
}

String _lineText(OcrLine line) => line.words.isEmpty ? line.text : line.words.map((w) => w.text).join(' ');

/// The numbers and lines of this kind of ID that are worth covering, in picture pixels. A few pixels are added all round so the edges
/// of the digits are hidden.
List<SafeFinding> findSensitive(OcrPageResult page, IdKind kind) {
  final out = <SafeFinding>[];
  final pad = (page.height < page.width ? page.height : page.width) * 0.008;
  for (final block in page.blocks) {
    for (final line in block.lines) {
      final text = _lineText(line);
      for (final rule in _rules[kind] ?? const <_Rule>[]) {
        for (final (start, end) in rule.find(text)) {
          final box = _boxOf(line, start, end);
          if (box == null) continue;
          out.add(
            SafeFinding(label: rule.label, left: box.left - pad, top: box.top - pad, right: box.right + pad, bottom: box.bottom + pad, covered: rule.covered),
          );
        }
      }
    }
  }
  return out;
}

/// Wording the mark can carry. The person may type their own.
const safeIdPurposes = ['KYC verification', 'Bank account opening', 'SIM card', 'Visa application', 'Hotel check-in', 'Job application', 'Rental agreement'];

/// What the repeated mark says: the purpose and the date it was made, so the copy cannot be used for anything else. `{date}` is filled in
/// when the mark is drawn.
String safeIdMarkText(String purpose) {
  final p = purpose.replaceAll(RegExp(r'[{}]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
  final cut = p.length > 60 ? p.substring(0, 60).trim() : p;
  return cut.isEmpty ? 'Copy made on {date}' : 'Only for $cut - {date}';
}

const maxSafeIdSide = 2400;

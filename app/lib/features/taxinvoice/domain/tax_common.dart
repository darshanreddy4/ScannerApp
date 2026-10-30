import '../../../core/i18n/tr.dart';

/// A problem found while checking an invoice, tied to the field it belongs to. The text has {names}, so it can be translated first.
class TaxIssue {
  const TaxIssue(this.field, this.template, [this.values = const {}]);
  final String field;
  final String template;
  final Map<String, Object> values;

  String get text => trf(template, values);

  @override
  String toString() => '$field: $text';
}

/// A number of up to [decimals] places from text such as `12`, `12,5` or `1234.56`; null when it is not one.
double? parseDecimal(String input, {int decimals = 2, int digits = 9}) {
  final m = RegExp('^(\\d{1,$digits})(?:[.,](\\d{1,$decimals}))?\$').firstMatch(input.trim());
  if (m == null) return null;
  return double.parse('${m[1]}.${m[2] ?? '0'}');
}

/// A rate in hundredths of a percent, so 7.25 is 725. Null when it is not a number with up to two places.
int? rateHundredths(String input) {
  final v = parseDecimal(input, decimals: 2, digits: 3);
  return v == null ? null : (v * 100).round();
}

/// [cents] times [hundredths] of a percent, rounded half up, in cents.
int percentOf(int cents, int hundredths) => (cents * hundredths + 5000) ~/ 10000;

/// An amount with Indian grouping: 1,23,456.78.
String groupIndian(int cents) {
  final negative = cents < 0;
  final abs = cents.abs();
  final whole = (abs ~/ 100).toString();
  final fraction = (abs % 100).toString().padLeft(2, '0');
  String grouped;
  if (whole.length <= 3) {
    grouped = whole;
  } else {
    final tail = whole.substring(whole.length - 3);
    var head = whole.substring(0, whole.length - 3);
    final parts = <String>[];
    while (head.length > 2) {
      parts.insert(0, head.substring(head.length - 2));
      head = head.substring(0, head.length - 2);
    }
    if (head.isNotEmpty) parts.insert(0, head);
    grouped = '${parts.join(',')},$tail';
  }
  return '${negative ? '-' : ''}$grouped.$fraction';
}

/// An amount with Western grouping: 1,234,567.89.
String groupWestern(int cents) {
  final negative = cents < 0;
  final abs = cents.abs();
  final whole = (abs ~/ 100).toString();
  final fraction = (abs % 100).toString().padLeft(2, '0');
  final b = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) b.write(',');
    b.write(whole[i]);
  }
  return '${negative ? '-' : ''}$b.$fraction';
}

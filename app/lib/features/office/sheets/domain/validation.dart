import 'sheet_model.dart';

enum ValidationKind { list, whole, decimal }

/// What may be typed into the cells of [range]: one of a list of choices, or a whole or decimal number between two limits.
class ValidationRule {
  const ValidationRule({required this.range, required this.kind, this.items = const [], this.min = '', this.max = ''});

  final MergeRange range;
  final ValidationKind kind;

  /// The choices of a list.
  final List<String> items;

  /// The limits of a number rule.
  final String min;
  final String max;

  ValidationRule withRange(MergeRange r) => ValidationRule(range: r, kind: kind, items: items, min: min, max: max);

  double? get _min => double.tryParse(min.trim());
  double? get _max => double.tryParse(max.trim());

  /// True when [text], as typed, is allowed. Empty text and formulas are always allowed.
  bool allows(String text) {
    final t = text.trim();
    if (t.isEmpty || t.startsWith('=')) return true;
    switch (kind) {
      case ValidationKind.list:
        return items.any((i) => i.toLowerCase() == t.toLowerCase());
      case ValidationKind.whole:
      case ValidationKind.decimal:
        final n = double.tryParse(t.replaceAll(',', ''));
        final lo = _min, hi = _max;
        if (n == null || lo == null || hi == null) return false;
        if (kind == ValidationKind.whole && n != n.roundToDouble()) return false;
        return n >= (lo < hi ? lo : hi) && n <= (lo < hi ? hi : lo);
    }
  }

  /// The item as written in the list, for text that matches it ignoring case; otherwise the text itself.
  String canonical(String text) {
    if (kind != ValidationKind.list) return text;
    final t = text.trim().toLowerCase();
    for (final i in items) {
      if (i.toLowerCase() == t) return i;
    }
    return text;
  }
}

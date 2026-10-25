/// Finds formulas in recognised text and writes them as LaTeX for flutter_math_fork.
///
/// Text recognition reads printed formulas as ordinary characters (`x²`, `√(a+b)`, `∑`, `a = b`), so this works
/// from those characters. It does not understand stacked layouts such as matrices or multi-line fractions.
abstract final class MathConverter {
  static const _greek = {
    'α': r'\alpha',
    'β': r'\beta',
    'γ': r'\gamma',
    'δ': r'\delta',
    'ε': r'\varepsilon',
    'ζ': r'\zeta',
    'η': r'\eta',
    'θ': r'\theta',
    'ι': r'\iota',
    'κ': r'\kappa',
    'λ': r'\lambda',
    'μ': r'\mu',
    'ν': r'\nu',
    'ξ': r'\xi',
    'π': r'\pi',
    'ρ': r'\rho',
    'σ': r'\sigma',
    'τ': r'\tau',
    'υ': r'\upsilon',
    'φ': r'\phi',
    'χ': r'\chi',
    'ψ': r'\psi',
    'ω': r'\omega',
    'Γ': r'\Gamma',
    'Δ': r'\Delta',
    'Θ': r'\Theta',
    'Λ': r'\Lambda',
    'Ξ': r'\Xi',
    'Π': r'\Pi',
    'Σ': r'\Sigma',
    'Φ': r'\Phi',
    'Ψ': r'\Psi',
    'Ω': r'\Omega',
  };

  static const _symbols = {
    '×': r'\times',
    '÷': r'\div',
    '±': r'\pm',
    '∓': r'\mp',
    '≤': r'\leq',
    '≥': r'\geq',
    '≠': r'\neq',
    '≈': r'\approx',
    '≡': r'\equiv',
    '∞': r'\infty',
    '∑': r'\sum',
    '∏': r'\prod',
    '∫': r'\int',
    '∮': r'\oint',
    '∂': r'\partial',
    '∆': r'\Delta',
    '∇': r'\nabla',
    '∈': r'\in',
    '∉': r'\notin',
    '⊂': r'\subset',
    '⊆': r'\subseteq',
    '⊃': r'\supset',
    '⊇': r'\supseteq',
    '∪': r'\cup',
    '∩': r'\cap',
    '∅': r'\emptyset',
    '∀': r'\forall',
    '∃': r'\exists',
    '¬': r'\neg',
    '∧': r'\wedge',
    '∨': r'\vee',
    '→': r'\to',
    '←': r'\leftarrow',
    '⇒': r'\Rightarrow',
    '⇐': r'\Leftarrow',
    '⇔': r'\Leftrightarrow',
    '↔': r'\leftrightarrow',
    '·': r'\cdot',
    '⋅': r'\cdot',
    '∙': r'\cdot',
    '∝': r'\propto',
    '∴': r'\therefore',
    '∵': r'\because',
    '≪': r'\ll',
    '≫': r'\gg',
    '∼': r'\sim',
    '≅': r'\cong',
    '⊥': r'\perp',
    '∥': r'\parallel',
    '∠': r'\angle',
    '°': r'^{\circ}',
    '′': "'",
    '″': "''",
    '−': '-',
    '–': '-',
    '—': '-',
    '…': r'\ldots',
    '½': r'\frac{1}{2}',
    '¼': r'\frac{1}{4}',
    '¾': r'\frac{3}{4}',
    '⅓': r'\frac{1}{3}',
    '⅔': r'\frac{2}{3}',
  };

  static const _superscripts = {
    '⁰': '0',
    '¹': '1',
    '²': '2',
    '³': '3',
    '⁴': '4',
    '⁵': '5',
    '⁶': '6',
    '⁷': '7',
    '⁸': '8',
    '⁹': '9',
    '⁺': '+',
    '⁻': '-',
    'ⁿ': 'n',
  };
  static const _subscripts = {'₀': '0', '₁': '1', '₂': '2', '₃': '3', '₄': '4', '₅': '5', '₆': '6', '₇': '7', '₈': '8', '₉': '9', '₊': '+', '₋': '-'};

  static const _functions = {
    'sin',
    'cos',
    'tan',
    'cot',
    'sec',
    'csc',
    'log',
    'ln',
    'lim',
    'exp',
    'max',
    'min',
    'det',
    'sup',
    'inf',
    'arcsin',
    'arccos',
    'arctan',
    'sinh',
    'cosh',
    'tanh',
    'mod',
    'gcd',
  };

  static final _superRun = RegExp('[${_superscripts.keys.join()}]+');
  static final _subRun = RegExp('[${_subscripts.keys.join()}]+');
  static final _wordy = RegExp(r'[\p{L}]{3,}', unicode: true);

  /// Characters that only appear in mathematics. One of these in a short line is a strong hint.
  static final _strong = RegExp('[∑∏∫∮∂∇√∞≤≥≠≈≡±∓∈∉⊂⊆⊃⊇∪∩∅∀∃∧∨⇒⇔∝∴∵≪≫∼≅⊥∥∠${_superscripts.keys.join()}${_subscripts.keys.join()}]');
  static final _relation = RegExp(r'[=<>]');
  static final _exponent = RegExp(r'[A-Za-z0-9\)\]]\^[\{\(]?[A-Za-z0-9\-+]');
  static final _arithmetic = RegExp(r'[A-Za-z0-9\)]\s*[+\-*/×÷]\s*[A-Za-z0-9\(]');

  /// Number of real words in [text], not counting function names such as `sin` and `log`.
  static int _wordCount(String text) => _wordy.allMatches(text).where((m) => !_functions.contains(m[0]!.toLowerCase())).length;

  /// True when the whole line reads as a formula rather than a sentence.
  static bool isFormulaLine(String line) {
    final text = line.trim();
    if (text.length < 3 || text.length > 140) return false;
    if (_wordCount(text) > 0) return false;
    final hasStrong = _strong.hasMatch(text);
    final hasRelation = _relation.hasMatch(text);
    if (!(hasStrong || hasRelation || _exponent.hasMatch(text))) return false;
    // A bare number list or a date such as 12/05/2024 must not become a formula.
    if (!hasStrong && !_arithmetic.hasMatch(text) && !_relation.hasMatch(text) && !_exponent.hasMatch(text)) return false;
    // Needs something to calculate with: a letter, a symbol or at least two numbers around an operator.
    return hasStrong || RegExp(r'[A-Za-z]').hasMatch(text) || _arithmetic.hasMatch(text);
  }

  /// LaTeX for a line that [isFormulaLine] accepted.
  static String toLatex(String expression) {
    var s = expression.trim();

    // Superscripts and subscripts written as single characters (x², aₙ is left alone as plain text).
    s = s.replaceAllMapped(_superRun, (m) => '^{${m[0]!.split('').map((c) => _superscripts[c]).join()}}');
    s = s.replaceAllMapped(_subRun, (m) => '_{${m[0]!.split('').map((c) => _subscripts[c]).join()}}');

    // Square roots: √(expr), √x, √12.
    s = s.replaceAllMapped(RegExp(r'√\s*\(([^()]*)\)'), (m) => '\\sqrt{${m[1]}}');
    s = s.replaceAllMapped(RegExp(r'√\s*([A-Za-z0-9.]+)'), (m) => '\\sqrt{${m[1]}}');

    // x^10, x^-1, x^(n+1) -> braces so the whole exponent is raised.
    s = s.replaceAllMapped(RegExp(r'\^\(([^()]+)\)'), (m) => '^{${m[1]}}');
    s = s.replaceAllMapped(RegExp(r'\^(-?[A-Za-z0-9]+)'), (m) => '^{${m[1]}}');
    s = s.replaceAllMapped(RegExp(r'_(-?[A-Za-z0-9]+)(?![}])'), (m) => '_{${m[1]}}');

    // Fractions written with a slash between simple groups.
    s = s.replaceAllMapped(RegExp(r'\(([^()]+)\)\s*/\s*\(([^()]+)\)'), (m) => '\\frac{${m[1]}}{${m[2]}}');
    s = s.replaceAllMapped(RegExp(r'(?<![\w.])(-?[A-Za-z0-9.]+)\s*/\s*([A-Za-z0-9.]+)(?![\w.^_])'), (m) => '\\frac{${m[1]}}{${m[2]}}');

    // Function names.
    s = s.replaceAllMapped(RegExp(r'\b(' + _functions.join('|') + r')\b'), (m) => '\\${m[1]}');

    // Letters and symbols.
    final out = StringBuffer();
    for (final rune in s.runes) {
      final ch = String.fromCharCode(rune);
      final mapped = _greek[ch] ?? _symbols[ch];
      if (mapped != null) {
        out
          ..write(mapped)
          ..write(' ');
      } else {
        out.write(ch);
      }
    }
    s = out.toString();

    s = s.replaceAll('*', r'\cdot ');
    s = s.replaceAllMapped(RegExp(r'(?<!\\)([%&#$])'), (m) => '\\${m[1]}');
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  // Fragments of math inside prose.
  static final _inlinePatterns = <RegExp>[
    // x^2, a_n, x_{i+1}, (a+b)^2, E=mc^2 pieces such as c^2.
    RegExp(r'(?<![\w$\\])(?:[A-Za-z]|\([^()\s][^()]*\))(?:[\^_]\{[^{}]+\}|[\^_]\([^()]+\)|[\^_]-?[A-Za-z0-9]+|[⁰¹²³⁴-⁹⁺⁻ⁿ₀-₉₊₋]+)+'),
    // √x, √(a+b)
    RegExp(r'√\s*(?:\([^()]*\)|[A-Za-z0-9.]+)'),
    // x = 5, y ≤ 10.5
    RegExp(r'(?<![\w$\\])[A-Za-z](?:_\w+)?\s*(?:=|<|>|≤|≥|≠|≈)\s*-?\d+(?:[.,]\d+)?(?![\w])'),
    // Greek letters and symbols standing alone in prose.
    RegExp('(?<![\\w\$\\\\])[αβγδεζηθικλμνξπρστυφχψωΓΔΘΛΞΠΣΦΨΩ∞∑∏∫∂∇≤≥≠≈±](?![\\w])'),
  ];

  /// Splits prose into plain text and formula fragments, in order.
  static List<MathPiece> splitInline(String text) {
    final spans = <(int, int)>[];
    for (final pattern in _inlinePatterns) {
      for (final m in pattern.allMatches(text)) {
        final overlaps = spans.any((s) => m.start < s.$2 && m.end > s.$1);
        if (!overlaps) spans.add((m.start, m.end));
      }
    }
    spans.sort((a, b) => a.$1.compareTo(b.$1));
    final pieces = <MathPiece>[];
    var cursor = 0;
    for (final s in spans) {
      if (s.$1 > cursor) pieces.add(MathPiece(text.substring(cursor, s.$1), math: false));
      pieces.add(MathPiece(text.substring(s.$1, s.$2), math: true));
      cursor = s.$2;
    }
    if (cursor < text.length) pieces.add(MathPiece(text.substring(cursor), math: false));
    return pieces;
  }
}

class MathPiece {
  const MathPiece(this.text, {required this.math});
  final String text;
  final bool math;
}

/// Writes an amount of money in words, for a cheque, an invoice or a receipt.
library;

enum WordsLanguage {
  /// Lakh and crore: 1,23,456 is "one lakh twenty-three thousand four hundred fifty-six".
  enIn('English (lakh and crore)', 'en'),
  en('English (million and billion)', 'en'),
  de('Deutsch', 'de'),

  /// Written from right to left; the wording should be checked by a native speaker before it goes on a legal document.
  ar('\u0627\u0644\u0639\u0631\u0628\u064A\u0629', 'ar');

  const WordsLanguage(this.label, this.code);
  final String label;
  final String code;
}

enum WordsCase { title, upper, lower }

/// The names of a currency and its hundredth part, in the languages the tool writes in.
class WordsCurrency {
  const WordsCurrency(this.code, this.name, this.en, this.de, this.ar, {this.minorFeminine = false});
  final String code;

  /// Shown in the list.
  final String name;

  /// (singular, plural, minor singular, minor plural)
  final (String, String, String, String) en;
  final (String, String, String, String) de;

  /// (major singular, dual, plural, singular after a number, minor singular, minor dual, minor plural, minor after a number)
  final (String, String, String, String, String, String, String, String) ar;

  /// Whether the Arabic word for the minor unit is feminine (hallah, paisa), which changes the form of the numbers 1 to 10.
  final bool minorFeminine;
}

const wordsCurrencies = <WordsCurrency>[
  WordsCurrency('INR', 'Indian rupee (INR)', ('Rupee', 'Rupees', 'Paisa', 'Paise'), ('Rupie', 'Rupien', 'Paisa', 'Paise'), (
    '\u0631\u0648\u0628\u064A\u0629',
    '\u0631\u0648\u0628\u064A\u062A\u0627\u0646',
    '\u0631\u0648\u0628\u064A\u0627\u062A',
    '\u0631\u0648\u0628\u064A\u0629\u064B',
    '\u0628\u064A\u0633\u0629',
    '\u0628\u064A\u0633\u062A\u0627\u0646',
    '\u0628\u064A\u0633\u0627\u062A',
    '\u0628\u064A\u0633\u0629\u064B',
  ), minorFeminine: true),
  WordsCurrency('USD', 'US dollar (USD)', ('Dollar', 'Dollars', 'Cent', 'Cents'), ('US-Dollar', 'US-Dollar', 'Cent', 'Cent'), (
    '\u062F\u0648\u0644\u0627\u0631',
    '\u062F\u0648\u0644\u0627\u0631\u0627\u0646',
    '\u062F\u0648\u0644\u0627\u0631\u0627\u062A',
    '\u062F\u0648\u0644\u0627\u0631\u0627\u064B',
    '\u0633\u0646\u062A',
    '\u0633\u0646\u062A\u0627\u0646',
    '\u0633\u0646\u062A\u0627\u062A',
    '\u0633\u0646\u062A\u0627\u064B',
  )),
  WordsCurrency('EUR', 'Euro (EUR)', ('Euro', 'Euros', 'Cent', 'Cents'), ('Euro', 'Euro', 'Cent', 'Cent'), (
    '\u064A\u0648\u0631\u0648',
    '\u064A\u0648\u0631\u0648',
    '\u064A\u0648\u0631\u0648',
    '\u064A\u0648\u0631\u0648',
    '\u0633\u0646\u062A',
    '\u0633\u0646\u062A\u0627\u0646',
    '\u0633\u0646\u062A\u0627\u062A',
    '\u0633\u0646\u062A\u0627\u064B',
  )),
  WordsCurrency('GBP', 'Pound sterling (GBP)', ('Pound', 'Pounds', 'Penny', 'Pence'), ('Pfund', 'Pfund', 'Penny', 'Pence'), (
    '\u062C\u0646\u064A\u0647 \u0625\u0633\u062A\u0631\u0644\u064A\u0646\u064A',
    '\u062C\u0646\u064A\u0647\u0627\u0646 \u0625\u0633\u062A\u0631\u0644\u064A\u0646\u064A\u0627\u0646',
    '\u062C\u0646\u064A\u0647\u0627\u062A \u0625\u0633\u062A\u0631\u0644\u064A\u0646\u064A\u0629',
    '\u062C\u0646\u064A\u0647\u0627\u064B \u0625\u0633\u062A\u0631\u0644\u064A\u0646\u064A\u0627\u064B',
    '\u0628\u0646\u0633',
    '\u0628\u0646\u0633',
    '\u0628\u0646\u0633',
    '\u0628\u0646\u0633',
  )),
  WordsCurrency('AED', 'UAE dirham (AED)', ('Dirham', 'Dirhams', 'Fils', 'Fils'), ('Dirham', 'Dirham', 'Fils', 'Fils'), (
    '\u062F\u0631\u0647\u0645',
    '\u062F\u0631\u0647\u0645\u0627\u0646',
    '\u062F\u0631\u0627\u0647\u0645',
    '\u062F\u0631\u0647\u0645\u0627\u064B',
    '\u0641\u0644\u0633',
    '\u0641\u0644\u0633\u0627\u0646',
    '\u0641\u0644\u0648\u0633',
    '\u0641\u0644\u0633\u0627\u064B',
  )),
  WordsCurrency('SAR', 'Saudi riyal (SAR)', ('Riyal', 'Riyals', 'Halala', 'Halalas'), ('Saudi-Riyal', 'Saudi-Riyal', 'Halala', 'Halalas'), (
    '\u0631\u064A\u0627\u0644',
    '\u0631\u064A\u0627\u0644\u0627\u0646',
    '\u0631\u064A\u0627\u0644\u0627\u062A',
    '\u0631\u064A\u0627\u0644\u0627\u064B',
    '\u0647\u0644\u0644\u0629',
    '\u0647\u0644\u0644\u062A\u0627\u0646',
    '\u0647\u0644\u0644\u0627\u062A',
    '\u0647\u0644\u0644\u0629\u064B',
  ), minorFeminine: true),
];

WordsCurrency? wordsCurrency(String code) => wordsCurrencies.where((c) => c.code == code).firstOrNull;

/// The biggest amount written: just under a trillion.
const wordsMax = 999999999999;

/// An amount split into whole units and hundredths.
typedef WordsAmount = ({int whole, int minor, bool hasMinor});

/// Reads an amount as typed: `1234`, `1,23,456.50`, `1.234,56`, `12,5`. Null when it is not an amount or is bigger than [wordsMax].
/// A comma or dot followed by three digits is a grouping mark, by one or two digits the decimal point.
WordsAmount? parseWordsAmount(String input) {
  final t = input.trim().replaceAll(RegExp(r'[\s\u00A0\u202F]'), '');
  if (t.isEmpty || !RegExp(r'^\d[\d.,]*$').hasMatch(t)) return null;
  final last = t.lastIndexOf(RegExp(r'[.,]'));
  String whole = t;
  String minor = '';
  if (last >= 0) {
    final tail = t.substring(last + 1);
    final head = t.substring(0, last);
    if (tail.isEmpty) return null;
    if (tail.length <= 2) {
      whole = head;
      minor = tail;
      final other = t[last] == '.' ? ',' : '.';
      if (head.contains(t[last])) return null;
      if (head.isNotEmpty && !RegExp('^\\d{1,3}(\\$other\\d{2,3})*\$|^\\d+\$').hasMatch(head)) return null;
    } else if (tail.length == 3) {
      // Grouping marks only: all marks must be the same kind and the groups well formed.
      final mark = t[last];
      if (!RegExp('^\\d{1,3}(\\$mark(\\d{2}|\\d{3}))*\$').hasMatch(t)) return null;
    } else {
      return null;
    }
  }
  final digits = whole.replaceAll(RegExp(r'[.,]'), '');
  if (digits.isEmpty || digits.length > 12) return null;
  final w = int.parse(digits);
  if (w > wordsMax) return null;
  return (whole: w, minor: int.parse(minor.padRight(2, '0').isEmpty ? '0' : minor.padRight(2, '0')), hasMinor: minor.isNotEmpty);
}

// ---- English ----

const _enOnes = [
  'zero',
  'one',
  'two',
  'three',
  'four',
  'five',
  'six',
  'seven',
  'eight',
  'nine',
  'ten',
  'eleven',
  'twelve',
  'thirteen',
  'fourteen',
  'fifteen',
  'sixteen',
  'seventeen',
  'eighteen',
  'nineteen',
];
const _enTens = ['', '', 'twenty', 'thirty', 'forty', 'fifty', 'sixty', 'seventy', 'eighty', 'ninety'];

String _enBelow100(int n, String hyphen) {
  if (n < 20) return _enOnes[n];
  final u = n % 10;
  return u == 0 ? _enTens[n ~/ 10] : '${_enTens[n ~/ 10]}$hyphen${_enOnes[u]}';
}

String _enBelow1000(int n, String hyphen) {
  final h = n ~/ 100;
  final r = n % 100;
  return [if (h > 0) '${_enOnes[h]} hundred', if (r > 0) _enBelow100(r, hyphen)].join(' ');
}

String _enGroups(int n, List<(int, String)> scales, String hyphen) {
  if (n == 0) return 'zero';
  final parts = <String>[];
  var rest = n;
  for (final (size, name) in scales) {
    final q = rest ~/ size;
    if (q > 0) {
      parts.add('${_enGroups(q, scales.where((s) => s.$1 < size).toList(), hyphen)} $name');
      rest %= size;
    }
  }
  if (rest > 0) parts.add(_enBelow1000(rest, hyphen));
  return parts.join(' ');
}

const _scalesInternational = [(1000000000, 'billion'), (1000000, 'million'), (1000, 'thousand')];
const _scalesIndian = [(10000000, 'crore'), (100000, 'lakh'), (1000, 'thousand')];

/// A whole number in English words, lower case.
String numberInEnglish(int n, {required bool indian, bool hyphen = true}) {
  final h = hyphen ? '-' : ' ';
  if (!indian) return _enGroups(n, _scalesInternational, h);
  if (n < 10000000) return _enGroups(n, _scalesIndian, h);
  // Above a crore the crores are counted in thousands and lakhs: 12,345 crore.
  final crore = n ~/ 10000000;
  final rest = n % 10000000;
  final head = '${_enGroups(crore, _scalesIndian.sublist(1), h)} crore';
  return rest == 0 ? head : '$head ${_enGroups(rest, _scalesIndian.sublist(1), h)}';
}

// ---- German ----

const _deOnes = [
  'null',
  'ein',
  'zwei',
  'drei',
  'vier',
  'f\u00FCnf',
  'sechs',
  'sieben',
  'acht',
  'neun',
  'zehn',
  'elf',
  'zw\u00F6lf',
  'dreizehn',
  'vierzehn',
  'f\u00FCnfzehn',
  'sechzehn',
  'siebzehn',
  'achtzehn',
  'neunzehn',
];
const _deTens = ['', '', 'zwanzig', 'drei\u00DFig', 'vierzig', 'f\u00FCnfzig', 'sechzig', 'siebzig', 'achtzig', 'neunzig'];

String _deBelow100(int n) {
  if (n < 20) return _deOnes[n];
  final u = n % 10;
  return u == 0 ? _deTens[n ~/ 10] : '${_deOnes[u]}und${_deTens[n ~/ 10]}';
}

String _deBelow1000(int n) {
  final h = n ~/ 100;
  final r = n % 100;
  return '${h > 0 ? '${_deOnes[h]}hundert' : ''}${r > 0 ? _deBelow100(r) : ''}';
}

String _deBelowMillion(int n) {
  final t = n ~/ 1000;
  final r = n % 1000;
  return '${t > 0 ? '${_deBelow1000(t)}tausend' : ''}${r > 0 ? _deBelow1000(r) : ''}';
}

/// A whole number in German words, lower case. Millions and billions are written as separate words, as in German.
String numberInGerman(int n) {
  if (n == 0) return 'null';
  final parts = <String>[];
  var rest = n;
  final billions = rest ~/ 1000000000;
  if (billions > 0) {
    parts.add(billions == 1 ? 'eine Milliarde' : '${_deBelowMillion(billions)} Milliarden');
    rest %= 1000000000;
  }
  final millions = rest ~/ 1000000;
  if (millions > 0) {
    parts.add(millions == 1 ? 'eine Million' : '${_deBelowMillion(millions)} Millionen');
    rest %= 1000000;
  }
  if (rest > 0) parts.add(_deBelowMillion(rest));
  return parts.join(' ');
}

// ---- Arabic ----

const _arOnesMasc = ['', '\u0648\u0627\u062D\u062F', '\u0627\u062B\u0646\u0627\u0646'];
const _arOnesFem = ['', '\u0648\u0627\u062D\u062F\u0629', '\u0627\u062B\u0646\u062A\u0627\u0646'];

// 3 to 10 with a masculine noun (the form with a final taa marbuta) and with a feminine one.
const _arThreeToTenForMasc = [
  '',
  '',
  '',
  '\u062B\u0644\u0627\u062B\u0629',
  '\u0623\u0631\u0628\u0639\u0629',
  '\u062E\u0645\u0633\u0629',
  '\u0633\u062A\u0629',
  '\u0633\u0628\u0639\u0629',
  '\u062B\u0645\u0627\u0646\u064A\u0629',
  '\u062A\u0633\u0639\u0629',
  '\u0639\u0634\u0631\u0629',
];
const _arThreeToTenForFem = [
  '',
  '',
  '',
  '\u062B\u0644\u0627\u062B',
  '\u0623\u0631\u0628\u0639',
  '\u062E\u0645\u0633',
  '\u0633\u062A',
  '\u0633\u0628\u0639',
  '\u062B\u0645\u0627\u0646',
  '\u062A\u0633\u0639',
  '\u0639\u0634\u0631',
];
const _arTens = [
  '',
  '',
  '\u0639\u0634\u0631\u0648\u0646',
  '\u062B\u0644\u0627\u062B\u0648\u0646',
  '\u0623\u0631\u0628\u0639\u0648\u0646',
  '\u062E\u0645\u0633\u0648\u0646',
  '\u0633\u062A\u0648\u0646',
  '\u0633\u0628\u0639\u0648\u0646',
  '\u062B\u0645\u0627\u0646\u0648\u0646',
  '\u062A\u0633\u0639\u0648\u0646',
];
const _arHundreds = [
  '',
  '\u0645\u0627\u0626\u0629',
  '\u0645\u0627\u0626\u062A\u0627\u0646',
  '\u062B\u0644\u0627\u062B\u0645\u0627\u0626\u0629',
  '\u0623\u0631\u0628\u0639\u0645\u0627\u0626\u0629',
  '\u062E\u0645\u0633\u0645\u0627\u0626\u0629',
  '\u0633\u062A\u0645\u0627\u0626\u0629',
  '\u0633\u0628\u0639\u0645\u0627\u0626\u0629',
  '\u062B\u0645\u0627\u0646\u0645\u0627\u0626\u0629',
  '\u062A\u0633\u0639\u0645\u0627\u0626\u0629',
];
const _arAnd = '\u0648';

String _arBelow20(int n, bool fem) {
  if (n < 3) return (fem ? _arOnesFem : _arOnesMasc)[n];
  if (n <= 10) return (fem ? _arThreeToTenForFem : _arThreeToTenForMasc)[n];
  switch (n) {
    case 11:
      return fem ? '\u0625\u062D\u062F\u0649 \u0639\u0634\u0631\u0629' : '\u0623\u062D\u062F \u0639\u0634\u0631';
    case 12:
      return fem ? '\u0627\u062B\u0646\u062A\u0627 \u0639\u0634\u0631\u0629' : '\u0627\u062B\u0646\u0627 \u0639\u0634\u0631';
    default:
      // 13 to 19: the unit as for a noun of the opposite gender, then "ten".
      return '${(fem ? _arThreeToTenForFem : _arThreeToTenForMasc)[n - 10]} ${fem ? '\u0639\u0634\u0631\u0629' : '\u0639\u0634\u0631'}';
  }
}

String _arBelow100(int n, bool fem) {
  if (n < 20) return _arBelow20(n, fem);
  final u = n % 10;
  return u == 0 ? _arTens[n ~/ 10] : '${_arBelow20(u, fem)} $_arAnd${_arTens[n ~/ 10]}';
}

String _arBelow1000(int n, bool fem) {
  final h = n ~/ 100;
  final r = n % 100;
  if (h == 0) return _arBelow100(r, fem);
  if (r == 0) return _arHundreds[h];
  return '${_arHundreds[h]} $_arAnd${_arBelow100(r, fem)}';
}

/// A group of thousands, millions or billions: the unit alone for 1, the dual for 2, the plural for 3 to 10, the singular after a number of hundreds
/// and with the ending -an for 11 to 99. [construct] is the dual joined to the noun that follows, as in "ألفا ريال".
String _arScale(int count, (String, String, String, String) names, {bool construct = false}) {
  final (one, two, few, many) = names;
  if (count == 1) return one;
  if (count == 2) return construct ? '${two.substring(0, two.length - 2)}\u0627' : two;
  final tail = count % 100;
  final words = count == 200 ? '\u0645\u0627\u0626\u062A\u0627' : _arBelow1000(count, false);
  return '$words ${tail == 0 ? one : (tail >= 3 && tail <= 10 ? few : many)}';
}

const _arThousand = ('\u0623\u0644\u0641', '\u0623\u0644\u0641\u0627\u0646', '\u0622\u0644\u0627\u0641', '\u0623\u0644\u0641\u0627\u064B');
const _arMillion = (
  '\u0645\u0644\u064A\u0648\u0646',
  '\u0645\u0644\u064A\u0648\u0646\u0627\u0646',
  '\u0645\u0644\u0627\u064A\u064A\u0646',
  '\u0645\u0644\u064A\u0648\u0646\u0627\u064B',
);
const _arBillion = (
  '\u0645\u0644\u064A\u0627\u0631',
  '\u0645\u0644\u064A\u0627\u0631\u0627\u0646',
  '\u0645\u0644\u064A\u0627\u0631\u0627\u062A',
  '\u0645\u0644\u064A\u0627\u0631\u0627\u064B',
);

/// A whole number in Arabic words. [feminine] is the gender of the thing counted, which changes the words for 1 to 19.
/// [beforeNoun] is for a number that a noun follows ("مائتا ريال"), which changes the dual of the last group.
String numberInArabic(int n, {bool feminine = false, bool beforeNoun = false}) {
  if (n == 0) return '\u0635\u0641\u0631';
  final groups = <(int, (String, String, String, String))>[];
  var rest = n;
  for (final (size, names) in [(1000000000, _arBillion), (1000000, _arMillion), (1000, _arThousand)]) {
    final q = rest ~/ size;
    if (q > 0) groups.add((q, names));
    rest %= size;
  }
  final parts = <String>[
    for (final (i, g) in groups.indexed) _arScale(g.$1, g.$2, construct: beforeNoun && rest == 0 && i == groups.length - 1),
    if (rest > 0) (beforeNoun && rest == 200 ? '\u0645\u0627\u0626\u062A\u0627' : _arBelow1000(rest, feminine)),
  ];
  return [for (final (i, p) in parts.indexed) i == 0 ? p : '$_arAnd$p'].join(' ');
}

/// The Arabic words for a count of the currency: "ريال واحد", "ريالان", "ثلاثة ريالات", "أحد عشر ريالاً", "مائة ريال".
String _arCounted(int n, bool feminine, String one, String two, String few, String after) {
  if (n == 1) return '$one ${feminine ? '\u0648\u0627\u062D\u062F\u0629' : '\u0648\u0627\u062D\u062F'}';
  if (n == 2) return two;
  final tail = n % 100;
  final words = numberInArabic(n, feminine: feminine, beforeNoun: true);
  return '$words ${tail == 0 ? one : (tail >= 3 && tail <= 10 ? few : after)}';
}

// ---- amounts ----

String _capitalWords(String s) => s.replaceAllMapped(RegExp(r'(^|[ -])([a-z])'), (m) => '${m[1]}${m[2]!.toUpperCase()}');

String _sentence(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

/// What is wrong with an amount typed for [amountInWords], or null when it is empty or fine.
String? wordsAmountProblem(String input, {required String currency}) {
  if (input.trim().isEmpty) return null;
  final a = parseWordsAmount(input);
  if (a == null) return 'The amount is not valid. Use numbers such as 12,345.50, up to 999,999,999,999.99.';
  if (currency == 'none' && a.hasMinor) return 'Choose a currency to write the cents, or enter a whole number.';
  return null;
}

/// The amount in words, or null when it cannot be written. [currency] is a code of [wordsCurrencies] or `none` for the number alone.
/// [only] adds "Only" (or "فقط ... لا غير"); [letters] sets capitals for the languages that have them.
String? amountInWords(String input, {required WordsLanguage language, required String currency, bool only = false, WordsCase letters = WordsCase.title}) {
  final a = parseWordsAmount(input);
  if (a == null || wordsAmountProblem(input, currency: currency) != null) return null;
  final cur = wordsCurrency(currency);
  final whole = a.whole;
  final minor = a.hasMinor ? a.minor : 0;
  final showMinor = cur != null && minor > 0;
  final showWhole = cur == null || whole > 0 || !showMinor;

  String text;
  switch (language) {
    case WordsLanguage.enIn:
    case WordsLanguage.en:
      final indian = language == WordsLanguage.enIn;
      final h = indian ? ' ' : '-';
      final names = cur?.en;
      String money(int n, String one, String many) => '${numberInEnglish(n, indian: indian, hyphen: h != ' ')} ${n == 1 ? one : many}'.toLowerCase();
      final w = names == null ? numberInEnglish(whole, indian: indian, hyphen: h != ' ') : (showWhole ? money(whole, names.$1, names.$2) : '');
      final m = showMinor ? money(minor, names!.$3, names.$4) : '';
      if (indian && names != null) {
        // The currency goes first, as on a cheque: "Rupees one lakh and fifty paise".
        final big = showWhole ? '${names.$2.toLowerCase()} ${numberInEnglish(whole, indian: true, hyphen: false)}' : '';
        final small = showMinor ? '${numberInEnglish(minor, indian: true, hyphen: false)} ${(minor == 1 ? names.$3 : names.$4).toLowerCase()}' : '';
        text = [big, small].where((s) => s.isNotEmpty).join(' and ');
      } else {
        text = [w, m].where((s) => s.isNotEmpty).join(' and ');
      }
      if (only) text = '$text only';
      switch (letters) {
        case WordsCase.title:
          text = _capitalWords(text).replaceAll(' And ', ' and ');
        case WordsCase.upper:
          text = text.toUpperCase();
        case WordsCase.lower:
          break;
      }
    case WordsLanguage.de:
      final names = cur?.de;
      String money(int n, String one, String many) {
        final words = numberInGerman(n);
        final unit = n == 1 ? one : many;
        return '${n == 1 ? 'ein' : words} $unit';
      }

      if (names == null) {
        text = numberInGerman(whole);
        if (text.endsWith('ein')) text = '${text}s';
      } else {
        final big = showWhole ? money(whole, names.$1, names.$2) : '';
        final small = showMinor ? money(minor, names.$3, names.$4) : '';
        text = [big, small].where((s) => s.isNotEmpty).join(' und ');
      }
      switch (letters) {
        case WordsCase.title:
          text = _sentence(text);
        case WordsCase.upper:
          text = text.replaceAll('\u00DF', 'SS').toUpperCase();
        case WordsCase.lower:
          text = text.toLowerCase();
      }
    case WordsLanguage.ar:
      final c = cur?.ar;
      if (c == null) {
        text = numberInArabic(whole);
      } else {
        final big = showWhole ? _arCounted(whole, false, c.$1, c.$2, c.$3, c.$4) : '';
        final small = showMinor ? _arCounted(minor, cur.minorFeminine, c.$5, c.$6, c.$7, c.$8) : '';
        text = [big, small].where((s) => s.isNotEmpty).join(' $_arAnd');
      }
      if (only) text = '\u0641\u0642\u0637 $text \u0644\u0627 \u063A\u064A\u0631';
  }
  return text;
}

/// The amount in figures as it is grouped on paper: `1,23,456.50` in the lakh system, `123,456.50` otherwise.
String wordsFigures(WordsAmount a, {required bool indian}) {
  final digits = '${a.whole}';
  final b = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    final left = digits.length - i;
    b.write(digits[i]);
    if (left > 1 && (indian ? (left == 4 || (left > 4 && (left - 3) % 2 == 1)) : left % 3 == 1)) b.write(',');
  }
  return a.hasMinor ? '$b.${a.minor.toString().padLeft(2, '0')}' : '$b';
}

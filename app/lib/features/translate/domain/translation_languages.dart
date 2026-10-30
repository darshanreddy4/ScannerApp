/// A language that text can be translated from or into on the phone.
class TranslationLanguage {
  const TranslationLanguage(this.code, this.name);

  /// BCP 47 code such as "hi" or "pt".
  final String code;
  final String name;
}

/// Every language of the on-device translator, by English name.
const translationLanguages = <TranslationLanguage>[
  TranslationLanguage('af', 'Afrikaans'),
  TranslationLanguage('sq', 'Albanian'),
  TranslationLanguage('ar', 'Arabic'),
  TranslationLanguage('be', 'Belarusian'),
  TranslationLanguage('bn', 'Bengali'),
  TranslationLanguage('bg', 'Bulgarian'),
  TranslationLanguage('ca', 'Catalan'),
  TranslationLanguage('zh', 'Chinese'),
  TranslationLanguage('hr', 'Croatian'),
  TranslationLanguage('cs', 'Czech'),
  TranslationLanguage('da', 'Danish'),
  TranslationLanguage('nl', 'Dutch'),
  TranslationLanguage('en', 'English'),
  TranslationLanguage('eo', 'Esperanto'),
  TranslationLanguage('et', 'Estonian'),
  TranslationLanguage('fi', 'Finnish'),
  TranslationLanguage('fr', 'French'),
  TranslationLanguage('gl', 'Galician'),
  TranslationLanguage('ka', 'Georgian'),
  TranslationLanguage('de', 'German'),
  TranslationLanguage('el', 'Greek'),
  TranslationLanguage('gu', 'Gujarati'),
  TranslationLanguage('ht', 'Haitian Creole'),
  TranslationLanguage('he', 'Hebrew'),
  TranslationLanguage('hi', 'Hindi'),
  TranslationLanguage('hu', 'Hungarian'),
  TranslationLanguage('is', 'Icelandic'),
  TranslationLanguage('id', 'Indonesian'),
  TranslationLanguage('ga', 'Irish'),
  TranslationLanguage('it', 'Italian'),
  TranslationLanguage('ja', 'Japanese'),
  TranslationLanguage('kn', 'Kannada'),
  TranslationLanguage('ko', 'Korean'),
  TranslationLanguage('lv', 'Latvian'),
  TranslationLanguage('lt', 'Lithuanian'),
  TranslationLanguage('mk', 'Macedonian'),
  TranslationLanguage('ms', 'Malay'),
  TranslationLanguage('mt', 'Maltese'),
  TranslationLanguage('mr', 'Marathi'),
  TranslationLanguage('no', 'Norwegian'),
  TranslationLanguage('fa', 'Persian'),
  TranslationLanguage('pl', 'Polish'),
  TranslationLanguage('pt', 'Portuguese'),
  TranslationLanguage('ro', 'Romanian'),
  TranslationLanguage('ru', 'Russian'),
  TranslationLanguage('sk', 'Slovak'),
  TranslationLanguage('sl', 'Slovenian'),
  TranslationLanguage('es', 'Spanish'),
  TranslationLanguage('sw', 'Swahili'),
  TranslationLanguage('sv', 'Swedish'),
  TranslationLanguage('tl', 'Tagalog'),
  TranslationLanguage('ta', 'Tamil'),
  TranslationLanguage('te', 'Telugu'),
  TranslationLanguage('th', 'Thai'),
  TranslationLanguage('tr', 'Turkish'),
  TranslationLanguage('uk', 'Ukrainian'),
  TranslationLanguage('ur', 'Urdu'),
  TranslationLanguage('vi', 'Vietnamese'),
  TranslationLanguage('cy', 'Welsh'),
];

/// The English name of a language code, or the code itself when it is not one the translator knows.
String languageName(String code) {
  for (final l in translationLanguages) {
    if (l.code == code) return l.name;
  }
  return code;
}

bool isTranslationLanguage(String code) => translationLanguages.any((l) => l.code == code);

/// The translator language for a code that may carry a region or script ("hi-Latn", "pt-BR", "zh-TW"), or null when it has none.
String? translationCodeFor(String? code) {
  if (code == null || code.isEmpty || code == 'und') return null;
  final base = code.split(RegExp(r'[-_]')).first.toLowerCase();
  // Norwegian is reported as "nb" or "nn" by some engines.
  final mapped = (base == 'nb' || base == 'nn') ? 'no' : (base == 'iw' ? 'he' : base);
  return isTranslationLanguage(mapped) ? mapped : null;
}

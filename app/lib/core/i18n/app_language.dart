import 'dart:ui' show Locale, PlatformDispatcher;

/// The languages the app text is offered in. [system] follows the phone when the phone's language is one of these, else English.
enum AppLanguage {
  system('System language', null),
  en('English', 'en'),
  hi('हिन्दी', 'hi'),
  es('Español', 'es'),
  fr('Français', 'fr'),
  de('Deutsch', 'de'),
  pt('Português', 'pt'),
  ar('العربية', 'ar'),
  ur('اردو', 'ur'),
  zh('中文（简体）', 'zh'),
  ja('日本語', 'ja'),
  kn('ಕನ್ನಡ', 'kn'),
  mr('मराठी', 'mr'),
  it('Italiano', 'it'),
  nl('Nederlands', 'nl'),
  pl('Polski', 'pl'),
  tr('Türkçe', 'tr'),
  ru('Русский', 'ru');

  const AppLanguage(this.label, this.code);

  /// Each language is named in itself, so it can be found when the app is in a language that cannot be read.
  final String label;
  final String? code;

  /// The locale to give the app, or null to follow the phone.
  Locale? get locale => code == null ? null : Locale(code!);

  static const supportedCodes = ['en', 'hi', 'es', 'fr', 'de', 'pt', 'ar', 'ur', 'zh', 'ja', 'kn', 'mr', 'it', 'nl', 'pl', 'tr', 'ru'];

  /// Languages written from right to left; the screens then mirror by themselves.
  static const rightToLeftCodes = ['ar', 'ur'];

  bool get rightToLeft => rightToLeftCodes.contains(resolved);

  /// The language code the text is shown in.
  String get resolved {
    if (code != null) return code!;
    final phone = PlatformDispatcher.instance.locale.languageCode;
    return supportedCodes.contains(phone) ? phone : 'en';
  }
}

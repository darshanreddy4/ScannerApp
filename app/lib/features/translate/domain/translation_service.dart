/// Translating text on the phone. The language data of each language is downloaded once and kept on the phone;
/// after that no network is needed.
abstract interface class TranslationService {
  /// The language the text is written in as a translator code, or null when it cannot be told.
  Future<String?> detectLanguage(String text);

  Future<bool> isDownloaded(String code);

  /// Downloads the language data (this is the only thing that uses the network). False when it failed.
  Future<bool> download(String code);

  Future<void> delete(String code);

  /// Translates [text], which is one short passage, from language [from] into [to]. Throws when it cannot.
  Future<String> translate(String text, {required String from, required String to});
}

/// The language data a translation needs: both languages, and English as well when neither is English, because the
/// translator goes through English.
List<String> languagesNeeded(String from, String to) => {from, to, if (from != 'en' && to != 'en') 'en'}.toList();

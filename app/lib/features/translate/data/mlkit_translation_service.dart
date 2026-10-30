import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import '../domain/translation_languages.dart';
import '../domain/translation_service.dart';

/// Google ML Kit translation running on the phone. Only the download of a language's data uses the network.
class MlKitTranslationService implements TranslationService {
  MlKitTranslationService();

  final _models = OnDeviceTranslatorModelManager();

  static TranslateLanguage? _language(String code) {
    for (final l in TranslateLanguage.values) {
      if (l.bcpCode == code) return l;
    }
    return null;
  }

  @override
  Future<String?> detectLanguage(String text) async {
    final sample = text.length > 1500 ? text.substring(0, 1500) : text;
    if (sample.trim().length < 8) return null;
    final identifier = LanguageIdentifier(confidenceThreshold: 0.4);
    try {
      return translationCodeFor(await identifier.identifyLanguage(sample));
    } finally {
      await identifier.close();
    }
  }

  @override
  Future<bool> isDownloaded(String code) => _models.isModelDownloaded(code);

  @override
  Future<bool> download(String code) async {
    try {
      return await _models.downloadModel(code, isWifiRequired: false);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> delete(String code) async {
    await _models.deleteModel(code);
  }

  @override
  Future<String> translate(String text, {required String from, required String to}) async {
    final source = _language(from), target = _language(to);
    if (source == null || target == null) throw ArgumentError('Unknown language');
    final translator = OnDeviceTranslator(sourceLanguage: source, targetLanguage: target);
    try {
      return await translator.translateText(text);
    } finally {
      await translator.close();
    }
  }
}

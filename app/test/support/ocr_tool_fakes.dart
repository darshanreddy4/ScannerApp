import 'dart:async';

import 'package:doculoom/core/error/failures.dart';
import 'package:doculoom/core/error/result.dart';
import 'package:doculoom/features/ocr/domain/ocr_engine.dart';
import 'package:doculoom/features/ocr/domain/ocr_models.dart';
import 'package:doculoom/features/translate/domain/translation_service.dart';

OcrPageResult pageOfText(String text) => OcrPageResult(
  width: 1000,
  height: 1400,
  blocks: [
    OcrBlock(
      lines: [for (final (i, l) in text.split('\n').indexed) OcrLine(text: l, left: 0, top: i * 20.0, right: 100, bottom: i * 20.0 + 18)],
    ),
  ],
);

/// A text reader that returns the text given for each file name (the last part of the path).
class FakeTextReader implements OcrEngine {
  FakeTextReader(this.texts);
  final Map<String, String> texts;
  final reads = <({String path, OcrScript script})>[];
  final failing = <String>{};
  Completer<void>? hold;

  @override
  Future<Result<OcrPageResult>> recognize(String imagePath, OcrScript script) async {
    reads.add((path: imagePath, script: script));
    if (hold != null) await hold!.future;
    final name = imagePath.split('/').last;
    if (failing.contains(name)) return const Err(OcrFailure('The text could not be read from this page.'));
    return Ok(pageOfText(texts[name] ?? ''));
  }
}

/// A translator that marks what it did: "[hi] text". Language data is kept in [downloaded].
class FakeTranslator implements TranslationService {
  String? detectResult = 'en';
  final downloaded = <String>{};
  final downloads = <String>[];
  final deleted = <String>[];
  final translations = <({String text, String from, String to})>[];
  var failDownload = false;
  Object? failTranslate;
  Completer<void>? hold;
  final detectCalls = <String>[];

  @override
  Future<String?> detectLanguage(String text) async {
    detectCalls.add(text);
    return detectResult;
  }

  @override
  Future<bool> isDownloaded(String code) async => downloaded.contains(code);

  @override
  Future<bool> download(String code) async {
    downloads.add(code);
    if (failDownload) return false;
    downloaded.add(code);
    return true;
  }

  @override
  Future<void> delete(String code) async {
    deleted.add(code);
    downloaded.remove(code);
  }

  @override
  Future<String> translate(String text, {required String from, required String to}) async {
    translations.add((text: text, from: from, to: to));
    if (hold != null) await hold!.future;
    if (failTranslate != null) throw failTranslate!;
    return '[$to] $text';
  }
}

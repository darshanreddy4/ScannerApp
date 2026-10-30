import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

import '../../../core/error/failures.dart';
import '../../ocr/domain/ocr_engine.dart';
import '../../ocr/domain/ocr_models.dart';
import '../../pdf_tools/data/pdf_picture_pages.dart';
import '../../translate/domain/translate_text.dart';
import '../../translate/domain/translation_languages.dart';
import '../../translate/domain/translation_service.dart';

enum OcrToolStatus { idle, reading, ready }

enum TranslateStatus { idle, checking, needsDownload, downloading, translating, done, failed }

class OcrToolState extends Equatable {
  const OcrToolState({
    this.status = OcrToolStatus.idle,
    this.text = '',
    this.done = 0,
    this.total = 0,
    this.label = '',
    this.notes = const [],
    this.script = OcrScript.latin,
    this.failure,
    this.source,
    this.sourceDetected = false,
    this.target = 'en',
    this.translate = TranslateStatus.idle,
    this.translated,
    this.pending = const [],
    this.translateDone = 0,
    this.translateTotal = 0,
    this.translateMessage,
  });

  final OcrToolStatus status;
  final String text;

  /// Files read so far, out of [total], and what is being read now.
  final int done;
  final int total;
  final String label;

  /// Things that went wrong with single files, shown under the text.
  final List<String> notes;
  final OcrScript script;
  final Failure? failure;

  /// Language of the text as a translator code, or null while it has not been found yet.
  final String? source;

  /// The [source] was found by the phone rather than chosen.
  final bool sourceDetected;
  final String target;
  final TranslateStatus translate;
  final String? translated;

  /// Languages whose data has to be downloaded before translating.
  final List<String> pending;
  final int translateDone;
  final int translateTotal;
  final String? translateMessage;

  bool get reading => status == OcrToolStatus.reading;
  bool get hasText => text.trim().isNotEmpty;
  bool get translating => translate == TranslateStatus.checking || translate == TranslateStatus.downloading || translate == TranslateStatus.translating;

  OcrToolState copyWith({
    OcrToolStatus? status,
    String? text,
    int? done,
    int? total,
    String? label,
    List<String>? notes,
    OcrScript? script,
    Object? failure = _keep,
    Object? source = _keep,
    bool? sourceDetected,
    String? target,
    TranslateStatus? translate,
    Object? translated = _keep,
    List<String>? pending,
    int? translateDone,
    int? translateTotal,
    Object? translateMessage = _keep,
  }) => OcrToolState(
    status: status ?? this.status,
    text: text ?? this.text,
    done: done ?? this.done,
    total: total ?? this.total,
    label: label ?? this.label,
    notes: notes ?? this.notes,
    script: script ?? this.script,
    failure: identical(failure, _keep) ? this.failure : failure as Failure?,
    source: identical(source, _keep) ? this.source : source as String?,
    sourceDetected: sourceDetected ?? this.sourceDetected,
    target: target ?? this.target,
    translate: translate ?? this.translate,
    translated: identical(translated, _keep) ? this.translated : translated as String?,
    pending: pending ?? this.pending,
    translateDone: translateDone ?? this.translateDone,
    translateTotal: translateTotal ?? this.translateTotal,
    translateMessage: identical(translateMessage, _keep) ? this.translateMessage : translateMessage as String?,
  );

  static const _keep = Object();

  @override
  List<Object?> get props => [
    status,
    text,
    done,
    total,
    label,
    notes,
    script,
    failure,
    source,
    sourceDetected,
    target,
    translate,
    translated,
    pending,
    translateDone,
    translateTotal,
    translateMessage,
  ];
}

const ocrToolImageExtensions = ['jpg', 'jpeg', 'png', 'webp', 'bmp', 'heic'];

/// Reads text from pictures and PDFs on the phone, keeps it as editable text, and translates it into another language on the phone.
class OcrToolCubit extends Cubit<OcrToolState> {
  OcrToolCubit({
    required OcrEngine engine,
    required TranslationService translator,
    required Future<Directory> Function() outputDir,
    OcrScript script = OcrScript.latin,
    String target = 'en',
    PdfPicturePages Function()? pdfPages,
    this.maxPdfPages = 60,
  }) : _engine = engine,
       _translator = translator,
       _outputDir = outputDir,
       _pdfPages = pdfPages ?? PdfxPicturePages.new,
       super(OcrToolState(script: script, target: isTranslationLanguage(target) ? target : 'en'));

  final OcrEngine _engine;
  final TranslationService _translator;
  final Future<Directory> Function() _outputDir;
  final PdfPicturePages Function() _pdfPages;

  /// Longer PDFs are read up to this many pages.
  final int maxPdfPages;
  var _cancelled = false;
  var _cancelTranslation = false;

  void setScript(OcrScript script) {
    if (!state.reading) emit(state.copyWith(script: script));
  }

  /// Reads the pictures and PDFs and adds what they say to the end of the text.
  Future<void> addFiles(List<String> paths) async {
    if (state.reading || paths.isEmpty) return;
    _cancelled = false;
    emit(state.copyWith(status: OcrToolStatus.reading, done: 0, total: paths.length, label: '', notes: const [], failure: null));
    final notes = <String>[];
    var text = state.text;
    final before = text.trim().length;

    void append(String more) {
      final t = more.trim();
      if (t.isNotEmpty) text = text.trim().isEmpty ? t : '${text.trim()}\n\n$t';
    }

    Future<void> readPicture(String path, String name) async {
      final result = await _engine.recognize(path, state.script);
      final page = result.valueOrNull;
      if (page == null) {
        notes.add('Could not read "$name": ${result.failureOrNull?.message ?? 'the text could not be read.'}');
      } else {
        append(page.plainText);
      }
    }

    for (var i = 0; i < paths.length; i++) {
      if (_cancelled || isClosed) break;
      final path = paths[i];
      final name = p.basename(path);
      final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
      emit(state.copyWith(done: i, label: name));
      try {
        if (ocrToolImageExtensions.contains(ext)) {
          await readPicture(path, name);
        } else if (ext == 'pdf') {
          final pages = _pdfPages();
          final work = await Directory(p.join((await _outputDir()).path, 'ocr_tool', '${DateTime.now().microsecondsSinceEpoch}_$i')).create(recursive: true);
          try {
            final count = await pages.open(path);
            final use = count > maxPdfPages ? maxPdfPages : count;
            if (count > maxPdfPages) notes.add('"$name" has $count pages; the first $maxPdfPages were read.');
            for (var k = 0; k < use; k++) {
              if (_cancelled || isClosed) break;
              emit(state.copyWith(label: '$name, page ${k + 1} of $use'));
              final picture = File(p.join(work.path, 'p$k.jpg'));
              await picture.writeAsBytes(await pages.render(k, width: 1654, png: false), flush: true);
              await readPicture(picture.path, '$name, page ${k + 1}');
              await picture.delete().then((_) {}, onError: (_) {});
            }
          } finally {
            await pages.close().then((_) {}, onError: (_) {});
            await work.delete(recursive: true).then((_) {}, onError: (_) {});
          }
        } else {
          notes.add('"$name" is not a picture or a PDF, so it was skipped.');
        }
      } catch (e) {
        notes.add('Could not open "$name". It may be damaged or protected.');
      }
    }
    if (isClosed) return;
    if (_cancelled) notes.add('Stopped. What was read so far is kept.');
    final gained = text.trim().length > before;
    emit(
      state.copyWith(
        status: OcrToolStatus.ready,
        text: text,
        done: paths.length,
        label: '',
        notes: notes,
        failure: gained || text.trim().isNotEmpty
            ? null
            : const OcrFailure('No text was found. Try a sharper picture with good light, and choose the right language of the text.'),
        translated: gained ? null : state.translated,
        translate: gained ? TranslateStatus.idle : state.translate,
        source: gained && state.sourceDetected ? null : state.source,
        sourceDetected: gained ? false : state.sourceDetected,
      ),
    );
  }

  void cancel() => _cancelled = true;

  /// Edits made by hand replace the text; an old translation no longer fits it.
  void setText(String text) {
    if (text == state.text) return;
    emit(
      state.copyWith(
        text: text,
        translated: null,
        translate: TranslateStatus.idle,
        translateMessage: null,
        source: state.sourceDetected ? null : state.source,
        sourceDetected: false,
      ),
    );
  }

  void clear() {
    if (state.reading) return;
    emit(OcrToolState(script: state.script, target: state.target));
  }

  /// The language of the text; null lets the phone find it.
  void setSource(String? code) {
    if (state.translating) return;
    emit(state.copyWith(source: code, sourceDetected: false, translated: null, translate: TranslateStatus.idle, translateMessage: null));
  }

  void setTarget(String code) {
    if (state.translating || !isTranslationLanguage(code)) return;
    emit(state.copyWith(target: code, translated: null, translate: TranslateStatus.idle, translateMessage: null));
  }

  /// Makes the translation the text, so it can be translated back or read aloud as the main text.
  void useTranslationAsText() {
    final t = state.translated;
    if (t == null || state.translating) return;
    emit(
      state.copyWith(
        text: t,
        source: state.target,
        sourceDetected: false,
        target: state.source != null && state.source != state.target ? state.source : (state.target == 'en' ? 'hi' : 'en'),
        translated: null,
        translate: TranslateStatus.idle,
        translateMessage: null,
      ),
    );
  }

  /// Translates; when language data is missing it stops with [TranslateStatus.needsDownload] so the person can agree to the download.
  Future<void> translate() => _translate(download: false);

  Future<void> confirmDownloadAndTranslate() => _translate(download: true);

  void cancelTranslation() => _cancelTranslation = true;

  /// The person does not want to download the language data now.
  void dismissDownload() {
    if (state.translate == TranslateStatus.needsDownload) emit(state.copyWith(translate: TranslateStatus.idle, pending: const []));
  }

  void _failTranslate(String message) => emit(state.copyWith(translate: TranslateStatus.failed, translateMessage: message));

  Future<void> _translate({required bool download}) async {
    if (state.translating || state.reading) return;
    final text = state.text;
    if (text.trim().isEmpty) {
      _failTranslate('There is no text to translate yet.');
      return;
    }
    _cancelTranslation = false;
    emit(state.copyWith(translate: TranslateStatus.checking, translated: null, translateMessage: null, pending: const []));
    try {
      var from = state.source;
      if (from == null) {
        from = await _translator.detectLanguage(text);
        if (isClosed) return;
        if (from == null) {
          _failTranslate('The language of the text could not be recognised. Choose it under "From".');
          return;
        }
        emit(state.copyWith(source: from, sourceDetected: true));
      }
      final to = state.target;
      if (from == to) {
        _failTranslate('The text is already in ${languageName(to)}. Choose another language to translate into.');
        return;
      }
      final missing = <String>[];
      for (final code in languagesNeeded(from, to)) {
        if (!await _translator.isDownloaded(code)) missing.add(code);
      }
      if (isClosed) return;
      if (missing.isNotEmpty) {
        if (!download) {
          emit(state.copyWith(translate: TranslateStatus.needsDownload, pending: missing));
          return;
        }
        emit(state.copyWith(translate: TranslateStatus.downloading, pending: missing));
        for (final code in missing) {
          if (!await _translator.download(code)) {
            if (!isClosed) _failTranslate('The ${languageName(code)} language data could not be downloaded. Check the internet connection and try again.');
            return;
          }
        }
      }
      emit(state.copyWith(translate: TranslateStatus.translating, pending: const [], translateDone: 0, translateTotal: 0));
      final result = await translateLongText(
        _translator,
        text,
        from: from,
        to: to,
        isCancelled: () => _cancelTranslation || isClosed,
        onProgress: (d, t) {
          if (!isClosed) emit(state.copyWith(translateDone: d, translateTotal: t));
        },
      );
      if (isClosed) return;
      emit(state.copyWith(translate: TranslateStatus.done, translated: result, translateMessage: null));
    } on TranslationCancelled {
      if (!isClosed) emit(state.copyWith(translate: TranslateStatus.idle, translateMessage: null));
    } catch (_) {
      if (!isClosed)
        _failTranslate('The text could not be translated. If it keeps happening, remove the language data in the language list and download it again.');
    }
  }

  /// The language data on the phone.
  Future<List<String>> downloadedLanguages() async => [
    for (final l in translationLanguages)
      if (await _translator.isDownloaded(l.code)) l.code,
  ];

  Future<void> deleteLanguage(String code) => _translator.delete(code);

  Future<bool> downloadLanguage(String code) => _translator.download(code);

  @override
  Future<void> close() {
    _cancelled = true;
    _cancelTranslation = true;
    return super.close();
  }
}

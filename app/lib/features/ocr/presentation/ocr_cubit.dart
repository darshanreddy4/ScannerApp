import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/error/failures.dart';
import '../../documents/domain/entities/scanned_document.dart';
import '../domain/ocr_models.dart';
import '../domain/recognize_document_text.dart';
import '../domain/text_repository.dart';

enum OcrStatus { loading, empty, running, ready, failed }

class OcrState extends Equatable {
  const OcrState({
    this.status = OcrStatus.loading,
    this.pages = const [],
    this.script = OcrScript.latin,
    this.done = 0,
    this.total = 0,
    this.selected = 0,
    this.failure,
  });

  final OcrStatus status;
  final List<PageText> pages;
  final OcrScript script;
  final int done;
  final int total;
  final int selected;
  final Failure? failure;

  PageText? get current => selected >= 0 && selected < pages.length ? pages[selected] : null;

  /// All pages in one Markdown text, with a heading per page when there are several.
  String get fullMarkdown =>
      pages.length <= 1 ? pages.map((p) => p.markdown).join() : pages.map((p) => '## Page ${p.position + 1}\n\n${p.markdown}').join('\n\n');

  OcrState copyWith({
    OcrStatus? status,
    List<PageText>? pages,
    OcrScript? script,
    int? done,
    int? total,
    int? selected,
    Failure? failure,
    bool clearFailure = false,
  }) => OcrState(
    status: status ?? this.status,
    pages: pages ?? this.pages,
    script: script ?? this.script,
    done: done ?? this.done,
    total: total ?? this.total,
    selected: selected ?? this.selected,
    failure: clearFailure ? null : (failure ?? this.failure),
  );

  @override
  List<Object?> get props => [status, pages, script, done, total, selected, failure];
}

class OcrCubit extends Cubit<OcrState> {
  OcrCubit({required this.document, required RecognizeDocumentText recognize, required TextRepository repository, OcrScript initialScript = OcrScript.latin})
    : _recognize = recognize,
      _repo = repository,
      super(OcrState(script: initialScript));

  final ScannedDocument document;
  final RecognizeDocumentText _recognize;
  final TextRepository _repo;
  bool _cancelled = false;

  /// Shows text saved by an earlier run, if any.
  Future<void> load() async {
    final result = await _repo.loadText(document.id);
    final failure = result.failureOrNull;
    if (failure != null) {
      emit(state.copyWith(status: OcrStatus.failed, failure: failure));
      return;
    }
    final pages = result.valueOrNull ?? const [];
    if (pages.isEmpty) {
      emit(state.copyWith(status: OcrStatus.empty));
    } else {
      emit(state.copyWith(status: OcrStatus.ready, pages: pages, script: pages.first.script, selected: 0));
    }
  }

  void setScript(OcrScript script) => emit(state.copyWith(script: script));

  Future<void> run() async {
    if (state.status == OcrStatus.running) return;
    _cancelled = false;
    emit(state.copyWith(status: OcrStatus.running, done: 0, total: document.pages.length, clearFailure: true));
    final result = await _recognize(
      document: document,
      script: state.script,
      onProgress: (done, total) {
        if (!isClosed) emit(state.copyWith(done: done, total: total));
      },
      isCancelled: () => _cancelled || isClosed,
    );
    if (isClosed) return;
    final pages = result.valueOrNull;
    if (pages != null) {
      emit(state.copyWith(status: OcrStatus.ready, pages: pages, selected: 0));
    } else if (_cancelled) {
      await load();
    } else {
      emit(state.copyWith(status: OcrStatus.failed, failure: result.failureOrNull));
    }
  }

  void cancel() => _cancelled = true;

  void selectPage(int index) {
    if (index < 0 || index >= state.pages.length) return;
    emit(state.copyWith(selected: index));
  }

  /// Saves a hand-corrected version of the current page's text.
  Future<void> saveEdit(String markdown) async {
    final page = state.current;
    if (page == null || markdown == page.markdown) return;
    final result = await _repo.updatePageMarkdown(document.id, page.position, markdown);
    final failure = result.failureOrNull;
    if (failure != null) {
      emit(state.copyWith(failure: failure));
      return;
    }
    final pages = [...state.pages];
    pages[state.selected] = page.copyWith(markdown: markdown, edited: true);
    emit(state.copyWith(pages: pages, clearFailure: true));
  }

  Future<void> deleteText() async {
    final result = await _repo.clearText(document.id);
    final failure = result.failureOrNull;
    if (failure != null) {
      emit(state.copyWith(failure: failure));
      return;
    }
    emit(state.copyWith(status: OcrStatus.empty, pages: const [], selected: 0, clearFailure: true));
  }

  void clearFailure() => emit(state.copyWith(clearFailure: true));
}

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

import '../../../../core/error/failures.dart';
import '../data/deck_editor.dart';
import '../data/pptx_package.dart';
import '../data/pptx_template.dart';
import '../data/pptx_writer.dart';
import '../data/slide_export.dart';
import '../data/slide_painter.dart';
import '../domain/slide_model.dart';

enum SlideExportFormat {
  pptx('PowerPoint presentation (.pptx)', 'pptx', 'application/vnd.openxmlformats-officedocument.presentationml.presentation'),
  pdf('PDF (one page per slide)', 'pdf', 'application/pdf'),
  images('Pictures (one JPG per slide)', 'jpg', 'image/jpeg');

  const SlideExportFormat(this.label, this.extension, this.mimeType);
  final String label;
  final String extension;
  final String mimeType;
}

class SlidesState extends Equatable {
  const SlidesState({
    this.loading = true,
    this.version = 0,
    this.imagesVersion = 0,
    this.slideIndex = 0,
    this.selectedId,
    this.busy,
    this.failure,
    this.notice,
    this.canUndo = false,
    this.canRedo = false,
    this.modified = false,
  });

  final bool loading;
  final int version;
  final int imagesVersion;
  final int slideIndex;
  final String? selectedId;
  final String? busy;
  final Failure? failure;
  final String? notice;
  final bool canUndo;
  final bool canRedo;
  final bool modified;

  SlidesState copyWith({
    bool? loading,
    int? version,
    int? imagesVersion,
    int? slideIndex,
    Object? selectedId = _keep,
    Object? busy = _keep,
    Object? failure = _keep,
    Object? notice = _keep,
    bool? canUndo,
    bool? canRedo,
    bool? modified,
  }) => SlidesState(
    loading: loading ?? this.loading,
    version: version ?? this.version,
    imagesVersion: imagesVersion ?? this.imagesVersion,
    slideIndex: slideIndex ?? this.slideIndex,
    selectedId: identical(selectedId, _keep) ? this.selectedId : selectedId as String?,
    busy: identical(busy, _keep) ? this.busy : busy as String?,
    failure: identical(failure, _keep) ? this.failure : failure as Failure?,
    notice: identical(notice, _keep) ? this.notice : notice as String?,
    canUndo: canUndo ?? this.canUndo,
    canRedo: canRedo ?? this.canRedo,
    modified: modified ?? this.modified,
  );

  static const _keep = Object();

  @override
  List<Object?> get props => [loading, version, imagesVersion, slideIndex, selectedId, busy, failure, notice, canUndo, canRedo, modified];
}

/// The work behind the presentation screen: opening, selecting, editing and saving slides.
class SlidesCubit extends Cubit<SlidesState> {
  SlidesCubit({required Future<Directory> Function() workDir}) : _workDir = workDir, super(const SlidesState());

  final Future<Directory> Function() _workDir;
  late PptxDeck deck;
  late DeckEditor editor;
  bool hasDeck = false;
  String name = 'Presentation';
  final Map<SlidePart, SlideView> _views = {};
  final Map<String, ui.Image> images = {};

  static const maxFileBytes = 60 * 1024 * 1024;

  SlidePart get slide => deck.slides[state.slideIndex.clamp(0, deck.slides.length - 1)];

  void startBlank() {
    deck = PptxDeck.fromFiles(newPresentationFiles());
    editor = DeckEditor(deck);
    hasDeck = true;
    name = 'New presentation';
    emit(state.copyWith(loading: false));
  }

  Future<void> open(String path) async {
    emit(const SlidesState());
    try {
      final file = File(path);
      if (!await file.exists()) throw const ImportFailure('The file could not be found.');
      if (await file.length() > maxFileBytes) throw const ImportFailure('This file is too large to open here (over 60 MB).');
      deck = await PptxDeck.open(await file.readAsBytes());
      editor = DeckEditor(deck);
      hasDeck = true;
      name = p.basenameWithoutExtension(path);
      emit(const SlidesState(loading: false));
    } on PptxFormatException catch (e) {
      emit(SlidesState(loading: false, failure: ImportFailure(e.message)));
    } on Failure catch (e) {
      emit(SlidesState(loading: false, failure: e));
    } catch (e) {
      emit(SlidesState(loading: false, failure: ImportFailure('This presentation could not be opened.', cause: e)));
    }
  }

  @override
  Future<void> close() {
    for (final i in images.values) {
      i.dispose();
    }
    images.clear();
    return super.close();
  }

  // ------------------------------------------------------------------ reading

  SlideView viewOf(SlidePart s) {
    final cached = _views[s];
    if (cached != null) return cached;
    final v = editor.view(s);
    _views[s] = v;
    _loadImages(v);
    return v;
  }

  SlideView get currentView => viewOf(slide);

  var _loading = false;

  Future<void> _loadImages(SlideView v) async {
    final missing = mediaOf(v).where((m) => !images.containsKey(m) && deck.files.containsKey(m)).toList();
    if (missing.isEmpty || _loading) return;
    _loading = true;
    try {
      await loadSlideImages(missing, deck.files, images);
    } finally {
      _loading = false;
    }
    if (!isClosed) emit(state.copyWith(imagesVersion: state.imagesVersion + 1));
  }

  ShapeView? get selected {
    final id = state.selectedId;
    if (id == null) return null;
    for (final s in currentView.shapes) {
      if (s.id == id && s.element != null) return s;
    }
    return null;
  }

  // --------------------------------------------------------------- bookkeeping

  void _changed({String? selectId, bool keepSelection = true, String? notice}) {
    _views.clear();
    final id = selectId ?? (keepSelection ? state.selectedId : null);
    emit(
      state.copyWith(
        version: state.version + 1,
        slideIndex: state.slideIndex.clamp(0, deck.slides.length - 1),
        selectedId: id,
        canUndo: editor.canUndo,
        canRedo: editor.canRedo,
        modified: editor.modified,
        notice: notice,
        failure: null,
      ),
    );
    // A selection that no longer exists (after undo) is dropped.
    if (state.selectedId != null && selected == null) emit(state.copyWith(selectedId: null));
  }

  void clearMessages() {
    if (state.failure != null || state.notice != null) emit(state.copyWith(failure: null, notice: null));
  }

  void _run(void Function() action, {String? selectId, bool keepSelection = true, String? notice}) {
    try {
      action();
      _changed(selectId: selectId, keepSelection: keepSelection, notice: notice);
    } catch (e) {
      emit(state.copyWith(failure: UnexpectedFailure('That change could not be made.', cause: e)));
    }
  }

  // ---------------------------------------------------------------- selection

  void selectSlide(int i) {
    if (i < 0 || i >= deck.slides.length) return;
    emit(state.copyWith(slideIndex: i, selectedId: null));
  }

  void select(String? id) => emit(state.copyWith(selectedId: id));

  /// The topmost shape that can be changed at ([x], [y]) in slide EMU.
  ShapeView? hit(double x, double y) {
    final shapes = currentView.shapes;
    for (var i = shapes.length - 1; i >= 0; i--) {
      final s = shapes[i];
      if (s.element != null && s.editable && s.frame.contains(x, y)) return s;
    }
    return null;
  }

  // ------------------------------------------------------------------ editing

  void setText(String text) {
    final id = state.selectedId;
    if (id == null) return;
    _run(() => editor.setText(slide, id, text));
  }

  void setFrame(String id, Frame frame) => _run(() => editor.setFrame(slide, id, frame));

  void _text({double? sizeDelta, bool? bold, bool? italic, bool? underline, int? color, String? align}) {
    final id = state.selectedId;
    if (id == null) return;
    _run(() => editor.styleText(slide, id, sizeDelta: sizeDelta, bold: bold, italic: italic, underline: underline, color: color, align: align));
  }

  void biggerText() => _text(sizeDelta: 2);
  void smallerText() => _text(sizeDelta: -2);

  void toggleBold() {
    final on = selected?.paragraphs.firstOrNull?.runs.firstOrNull?.bold ?? false;
    _text(bold: !on);
  }

  void toggleItalic() {
    final on = selected?.paragraphs.firstOrNull?.runs.firstOrNull?.italic ?? false;
    _text(italic: !on);
  }

  void toggleUnderline() {
    final on = selected?.paragraphs.firstOrNull?.runs.firstOrNull?.underline ?? false;
    _text(underline: !on);
  }

  void setTextColor(int color) => _text(color: color);

  /// Left, centre, right in turn.
  void cycleAlign() {
    final now = selected?.paragraphs.firstOrNull?.align ?? 'l';
    _text(align: now == 'l' ? 'ctr' : (now == 'ctr' ? 'r' : 'l'));
  }

  void setAlign(String align) => _text(align: align);

  void setFill(int? color) {
    final id = state.selectedId;
    if (id == null) return;
    _run(() => editor.setFill(slide, id, color));
  }

  void setOutline(int? color) {
    final id = state.selectedId;
    if (id == null) return;
    _run(() => editor.setOutline(slide, id, color));
  }

  void deleteSelected() {
    final id = state.selectedId;
    if (id == null) return;
    _run(() => editor.delete(slide, id), keepSelection: false);
  }

  void duplicateSelected() {
    final id = state.selectedId;
    if (id == null) return;
    String? copy;
    _run(() => copy = editor.duplicate(slide, id), selectId: copy);
    if (copy != null) emit(state.copyWith(selectedId: copy));
  }

  void reorderSelected({bool? toFront, int delta = 0}) {
    final id = state.selectedId;
    if (id == null) return;
    _run(() => editor.reorder(slide, id, toFront: toFront, delta: delta));
  }

  void addTextBox(String text) {
    String? id;
    _run(() => id = editor.addTextBox(slide, text.isEmpty ? 'Text' : text), keepSelection: false);
    emit(state.copyWith(selectedId: id));
  }

  void addShape(String preset, int color) {
    String? id;
    _run(() => id = editor.addShape(slide, preset, color: color), keepSelection: false);
    emit(state.copyWith(selectedId: id));
  }

  /// Adds a JPEG or PNG picture from [bytes].
  void addPicture(Uint8List bytes) {
    final info = imageInfo(bytes);
    if (info == null) {
      emit(state.copyWith(failure: const ImportFailure('Only JPG and PNG pictures can be added.')));
      return;
    }
    String? id;
    _run(() => id = editor.addPicture(slide, bytes, info.ext, info.width, info.height), keepSelection: false);
    emit(state.copyWith(selectedId: id));
  }

  void setBackground(int? color) => _run(() => editor.setBackground(slide, color));

  // ------------------------------------------------------------------- slides

  void addSlide({bool blank = false}) {
    _run(() {
      final s = editor.addSlide(blank: blank, after: state.slideIndex);
      emit(state.copyWith(slideIndex: deck.slides.indexOf(s), selectedId: null));
    }, keepSelection: false);
  }

  void duplicateSlide() {
    _run(() {
      final s = editor.duplicateSlide(state.slideIndex);
      emit(state.copyWith(slideIndex: deck.slides.indexOf(s), selectedId: null));
    }, keepSelection: false);
  }

  void deleteSlide() {
    var ok = false;
    final i = state.slideIndex;
    _run(() => ok = editor.deleteSlide(i), keepSelection: false);
    if (!ok) emit(state.copyWith(failure: const ExportFailure('A presentation needs at least one slide.')));
  }

  void moveSlide(int delta) {
    final from = state.slideIndex, to = from + delta;
    if (to < 0 || to >= deck.slides.length) return;
    _run(() => editor.moveSlide(from, to));
    emit(state.copyWith(slideIndex: to));
  }

  void undo() => _run(editor.undo);
  void redo() => _run(editor.redo);

  // ------------------------------------------------------------------- saving

  String exportName(SlideExportFormat f) => '${name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}.${f.extension}';

  /// Writes the presentation in [format] and returns the files, or null after an error.
  Future<List<String>?> export(SlideExportFormat format) async {
    if (state.busy != null) return null;
    emit(state.copyWith(busy: 'Preparing the file', failure: null));
    try {
      final dir = await Directory(p.join((await _workDir()).path, 'office_out', '${DateTime.now().microsecondsSinceEpoch}')).create(recursive: true);
      switch (format) {
        case SlideExportFormat.pptx:
          await Future<void>.delayed(const Duration(milliseconds: 50));
          final path = p.join(dir.path, exportName(format));
          await File(path).writeAsBytes(writePptx(deck), flush: true);
          emit(state.copyWith(busy: null));
          return [path];
        case SlideExportFormat.pdf:
          final exporter = SlideExporter(deck);
          try {
            final path = p.join(dir.path, exportName(format));
            await exporter.exportPdf(path, dir, onProgress: (d, t) => emit(state.copyWith(busy: 'Drawing slide $d of $t')));
            emit(state.copyWith(busy: null));
            return [path];
          } finally {
            exporter.dispose();
          }
        case SlideExportFormat.images:
          final exporter = SlideExporter(deck);
          try {
            final files = await exporter.renderFiles(dir, name, onProgress: (d, t) => emit(state.copyWith(busy: 'Drawing slide $d of $t')));
            emit(state.copyWith(busy: null));
            return [for (final f in files) f.path];
          } finally {
            exporter.dispose();
          }
      }
    } catch (e) {
      if (!isClosed) emit(state.copyWith(busy: null, failure: ExportFailure('The file could not be created.', cause: e)));
      return null;
    }
  }

  void markSaved() {
    editor.modified = false;
    emit(state.copyWith(modified: false));
  }
}

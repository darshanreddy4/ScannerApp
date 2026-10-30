import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/utils/format.dart';
import '../../../documents/domain/entities/scanned_document.dart';
import '../../../documents/domain/usecases/document_usecases.dart';
import '../../../importer/domain/importer.dart';
import '../../../markup/domain/markup.dart';
import '../../../markup/domain/markup_renderer.dart';
import '../../domain/entities/filter_settings.dart';
import '../../domain/entities/quad.dart';
import '../../domain/entities/scan_mode.dart';
import '../../domain/entities/scan_page.dart';
import '../../domain/usecases/scanner_usecases.dart';

enum ScanFlow { camera, import, recrop }

/// What the crop screen should do after Continue/Retake.
enum CropOutcome { failed, nextImage, finished }

/// Filters shown as thumbnails in the editor, in display order.
const thumbFilters = filterOrder;

class ScanSessionState {
  const ScanSessionState({
    this.pages = const [],
    this.draft,
    this.draftPreview,
    this.draftEditIndex,
    this.flow = ScanFlow.camera,
    this.pending = const [],
    this.currentFilter = ScanFilter.magicColor,
    this.mode = ScanMode.document,
    this.title = '',
    this.folderId,
    this.editingDocumentId,
    this.selected = 0,
    this.applyToAll = false,
    this.previews = const {},
    this.thumbs = const {},
    this.busy = false,
    this.busyLabel,
    this.error,
  });

  final List<ScanPage> pages;
  final ScanPage? draft;

  /// Filtered preview of the draft's raw image, shown on the crop screen (null = show original).
  final Uint8List? draftPreview;
  final int? draftEditIndex;
  final ScanFlow flow;
  final List<String> pending;
  final ScanFilter currentFilter;
  final ScanMode mode;
  final String title;
  final String? folderId;

  /// Set when an already-saved document is being edited; saving then replaces it.
  final String? editingDocumentId;
  final int selected;
  final bool applyToAll;
  final Map<String, PagePreview> previews;
  final Map<String, List<Uint8List>> thumbs;
  final bool busy;
  final String? busyLabel;
  final Failure? error;

  ScanPage? get selectedPage => selected >= 0 && selected < pages.length ? pages[selected] : null;

  ScanSessionState copyWith({
    List<ScanPage>? pages,
    ScanPage? draft,
    bool clearDraft = false,
    Uint8List? draftPreview,
    bool clearDraftPreview = false,
    int? draftEditIndex,
    ScanFlow? flow,
    List<String>? pending,
    ScanFilter? currentFilter,
    ScanMode? mode,
    String? title,
    int? selected,
    bool? applyToAll,
    Map<String, PagePreview>? previews,
    Map<String, List<Uint8List>>? thumbs,
    bool? busy,
    String? busyLabel,
    Failure? error,
    bool clearError = false,
  }) => ScanSessionState(
    pages: pages ?? this.pages,
    draft: clearDraft ? null : (draft ?? this.draft),
    draftPreview: clearDraft || clearDraftPreview ? null : (draftPreview ?? this.draftPreview),
    draftEditIndex: clearDraft ? null : (draftEditIndex ?? this.draftEditIndex),
    flow: flow ?? this.flow,
    pending: pending ?? this.pending,
    currentFilter: currentFilter ?? this.currentFilter,
    mode: mode ?? this.mode,
    title: title ?? this.title,
    folderId: folderId,
    editingDocumentId: editingDocumentId,
    selected: selected ?? this.selected,
    applyToAll: applyToAll ?? this.applyToAll,
    previews: previews ?? this.previews,
    thumbs: thumbs ?? this.thumbs,
    busy: busy ?? this.busy,
    busyLabel: busy == false ? null : (busyLabel ?? this.busyLabel),
    error: clearError ? null : (error ?? this.error),
  );
}

class ScanSessionCubit extends Cubit<ScanSessionState> {
  ScanSessionCubit({
    required PrepareImage prepareImage,
    required InspectImage inspectImage,
    required CropDocument cropDocument,
    required RotateImage rotateImage,
    required PreviewFilter previewFilter,
    required PreviewFilterBatch previewFilterBatch,
    required ApplyFilter applyFilter,
    required SaveDocument saveDocument,
    required UpdateDocument updateDocument,
    required ImportDocumentFile importDocumentFile,
    this.clearWorkFiles,
    MarkupRenderer? markupRenderer,
  }) : _prepareImage = prepareImage,
       _inspectImage = inspectImage,
       _cropDocument = cropDocument,
       _rotateImage = rotateImage,
       _previewFilter = previewFilter,
       _previewBatch = previewFilterBatch,
       _applyFilter = applyFilter,
       _saveDocument = saveDocument,
       _updateDocument = updateDocument,
       _importFile = importDocumentFile,
       _markup = markupRenderer,
       super(const ScanSessionState());

  final PrepareImage _prepareImage;
  final InspectImage _inspectImage;
  final CropDocument _cropDocument;
  final RotateImage _rotateImage;
  final PreviewFilter _previewFilter;
  final PreviewFilterBatch _previewBatch;
  final ApplyFilter _applyFilter;
  final SaveDocument _saveDocument;
  final UpdateDocument _updateDocument;
  final ImportDocumentFile _importFile;
  final MarkupRenderer? _markup;

  /// Deletes scan working copies up to the given time. Optional so tests need no file system.
  final Future<void> Function(DateTime cutoff)? clearWorkFiles;

  Timer? _debounce;
  int _idCounter = 0;

  /// Filter from Settings; scan modes fall back to it when they have no look of their own.
  ScanFilter _baseFilter = ScanFilter.magicColor;

  String _newId() => '${DateTime.now().microsecondsSinceEpoch}-${_idCounter++}';

  /// Starts a fresh scan session.
  void start({required ScanFilter defaultFilter, String? folderId}) {
    _debounce?.cancel();
    _baseFilter = defaultFilter;
    unawaited(clearWorkFiles?.call(DateTime.now()));
    emit(ScanSessionState(currentFilter: defaultFilter, title: defaultScanTitle(DateTime.now()), folderId: folderId));
  }

  void clearError() => emit(state.copyWith(clearError: true));

  /// Switches what is being scanned. A fresh scan also gets a matching name; the look of the photos is never changed.
  void setMode(ScanMode mode) {
    if (mode == state.mode) return;
    final fresh = state.pages.isEmpty && state.editingDocumentId == null;
    emit(state.copyWith(mode: mode, title: fresh ? mode.title(DateTime.now()) : null));
  }

  /// Opens a saved document in the editor with every page's crop and filter restored.
  void loadDocument(ScannedDocument doc, {required ScanFilter defaultFilter}) {
    _debounce?.cancel();
    _baseFilter = defaultFilter;
    emit(
      ScanSessionState(
        pages: [for (final p in doc.pages) _pageFromSaved(p)],
        currentFilter: defaultFilter,
        title: doc.title,
        folderId: doc.folderId,
        editingDocumentId: doc.id,
      ),
    );
  }

  ScanPage _pageFromSaved(DocumentPage p) {
    final edit = p.edit;
    if (edit == null) {
      // Saved before editing existed: the finished image becomes the new source.
      return ScanPage(
        id: _newId(),
        rawPath: p.imagePath,
        rawWidth: p.width,
        rawHeight: p.height,
        quad: Quad.fullFrame,
        detectedQuad: Quad.fullFrame,
        croppedPath: p.imagePath,
        croppedWidth: p.width,
        croppedHeight: p.height,
      );
    }
    final q = edit.quad;
    final quad = Quad(NormPoint(q[0], q[1]), NormPoint(q[2], q[3]), NormPoint(q[4], q[5]), NormPoint(q[6], q[7]));
    return ScanPage(
      id: _newId(),
      rawPath: p.rawPath,
      rawWidth: edit.rawWidth,
      rawHeight: edit.rawHeight,
      quad: quad,
      detectedQuad: quad,
      croppedPath: edit.croppedPath,
      croppedWidth: p.width,
      croppedHeight: p.height,
      settings: FilterSettings(filter: ScanFilter.values.asNameMap()[edit.filter] ?? ScanFilter.original, brightness: edit.brightness, contrast: edit.contrast),
    );
  }

  void setTitle(String title) => emit(state.copyWith(title: title));

  void setApplyToAll(bool value) => emit(state.copyWith(applyToAll: value));

  // Draft (capture / import / re-crop)

  /// Converts a PDF or Word file into pages (no crop step) and adds them to the session.
  Future<bool> importDocumentFile(ImportKind kind, String path) async {
    emit(state.copyWith(busy: true, busyLabel: 'Reading document', clearError: true));
    final result = await _importFile(
      kind: kind,
      path: path,
      onProgress: (done, total) {
        if (!isClosed) emit(state.copyWith(busyLabel: 'Converting page $done of $total'));
      },
    );
    final doc = result.valueOrNull;
    if (doc == null) {
      emit(state.copyWith(busy: false, error: result.failureOrNull));
      return false;
    }

    final firstNew = state.pages.length;
    final keepTitle = state.pages.isNotEmpty;
    final pages = [...state.pages];
    for (var i = 0; i < doc.imagePaths.length; i++) {
      emit(state.copyWith(busyLabel: 'Preparing page ${i + 1} of ${doc.imagePaths.length}'));
      // Imported pages are already final images: read the size only, no decode or re-encode.
      final prepared = await _inspectImage(doc.imagePaths[i]);
      final img = prepared.valueOrNull;
      if (img == null) {
        emit(state.copyWith(busy: false, error: prepared.failureOrNull));
        return false;
      }
      pages.add(
        ScanPage(
          id: _newId(),
          rawPath: img.path,
          rawWidth: img.width,
          rawHeight: img.height,
          quad: Quad.fullFrame,
          detectedQuad: Quad.fullFrame,
          croppedPath: img.path,
          croppedWidth: img.width,
          croppedHeight: img.height,
          settings: const FilterSettings(),
        ),
      );
    }
    emit(state.copyWith(busy: false, pages: pages, selected: firstNew, title: keepTitle ? state.title : doc.title));
    return true;
  }

  /// Prepares [sourcePath] as the current draft. Returns true on success.
  Future<bool> beginDraft(String sourcePath, {ScanFlow flow = ScanFlow.camera, List<String> pending = const []}) async {
    emit(state.copyWith(busy: true, busyLabel: 'Preparing image', clearError: true));
    final result = await _prepareImage(sourcePath);
    return result.when(
      ok: (img) {
        final quad = state.mode.pickQuad(img.detectedQuad, img.width / img.height);
        emit(
          state.copyWith(
            busy: false,
            flow: flow,
            pending: pending,
            draft: ScanPage(
              id: _newId(),
              rawPath: img.path,
              rawWidth: img.width,
              rawHeight: img.height,
              quad: quad,
              detectedQuad: quad,
              settings: FilterSettings(filter: state.currentFilter),
            ),
          ),
        );
        refreshDraftPreview();
        return true;
      },
      err: (f) {
        emit(state.copyWith(busy: false, error: f));
        return false;
      },
    );
  }

  /// Queues several images; the first becomes the draft.
  Future<bool> importMany(List<String> paths) async {
    if (paths.isEmpty) return false;
    return beginDraft(paths.first, flow: ScanFlow.import, pending: paths.sublist(1));
  }

  void editPageCrop(int index) {
    final page = state.pages[index];
    emit(state.copyWith(draft: page, draftEditIndex: index, flow: ScanFlow.recrop, pending: const [], clearDraftPreview: true));
    refreshDraftPreview();
  }

  void updateQuad(Quad quad) {
    final d = state.draft;
    if (d != null) emit(state.copyWith(draft: d.copyWith(quad: quad)));
  }

  void useFullFrame() => updateQuad(Quad.fullFrame);

  void resetToDetected() {
    final d = state.draft;
    if (d != null) updateQuad(d.detectedQuad);
  }

  void setCurrentFilter(ScanFilter filter) {
    final d = state.draft;
    emit(
      state.copyWith(
        currentFilter: filter,
        draft: d?.copyWith(settings: d.settings.copyWith(filter: filter)),
      ),
    );
    refreshDraftPreview();
  }

  /// Renders the draft's raw image with its current filter so the crop screen shows the real effect.
  Future<void> refreshDraftPreview() async {
    final d = state.draft;
    if (d == null) return;
    final s = d.settings;
    if (s.filter == ScanFilter.original && s.brightness == 0 && s.contrast == 0) {
      emit(state.copyWith(clearDraftPreview: true));
      return;
    }
    final result = await _previewFilter(imagePath: d.rawPath, settings: s);
    if (isClosed) return;
    final current = state.draft;
    if (current == null || current.rawPath != d.rawPath || current.settings != s) return;
    final bytes = result.valueOrNull;
    if (bytes != null) emit(state.copyWith(draftPreview: bytes));
  }

  Future<void> rotateDraft() async {
    final d = state.draft;
    if (d == null || state.busy) return;
    emit(state.copyWith(busy: true, busyLabel: 'Rotating'));
    final result = await _rotateImage(d.rawPath);
    result.when(
      ok: (info) => emit(
        state.copyWith(
          busy: false,
          draft: d.copyWith(
            rawPath: info.path,
            rawWidth: info.width,
            rawHeight: info.height,
            quad: d.quad.rotatedClockwise(),
            detectedQuad: d.detectedQuad.rotatedClockwise(),
          ),
          clearDraftPreview: true,
        ),
      ),
      err: (f) => emit(state.copyWith(busy: false, error: f)),
    );
    refreshDraftPreview();
  }

  /// Crops the draft into the page list, then moves to the next queued image if any.
  Future<CropOutcome> commitDraft() async {
    final d = state.draft;
    if (d == null) return CropOutcome.failed;
    emit(state.copyWith(busy: true, busyLabel: 'Cropping', clearError: true));

    final editIndex = state.draftEditIndex;
    final halves = editIndex == null && state.mode.split ? d.quad.splitVertically() : null;
    final quads = halves == null ? [d.quad] : [halves.$1, halves.$2];
    final made = <ScanPage>[];
    for (var i = 0; i < quads.length; i++) {
      final result = await _cropDocument(imagePath: d.rawPath, quad: quads[i]);
      final failure = result.failureOrNull;
      final info = result.valueOrNull;
      if (failure != null || info == null) {
        emit(state.copyWith(busy: false, error: failure));
        return CropOutcome.failed;
      }
      made.add(
        d.copyWith(
          id: i == 0 ? d.id : _newId(),
          quad: quads[i],
          detectedQuad: halves == null ? d.detectedQuad : quads[i],
          croppedPath: info.path,
          croppedWidth: info.width,
          croppedHeight: info.height,
          clearPreMarkup: true,
        ),
      );
    }

    final pages = [...state.pages];
    int selected;
    if (editIndex != null) {
      pages[editIndex] = made.first;
      selected = editIndex;
    } else {
      pages.addAll(made);
      selected = pages.length - made.length;
    }
    final previews = {...state.previews};
    final thumbs = {...state.thumbs};
    for (final page in made) {
      previews.remove(page.id);
      thumbs.remove(page.id);
    }

    emit(state.copyWith(busy: false, pages: pages, selected: selected, previews: previews, thumbs: thumbs, clearDraft: true));
    return _advanceQueue();
  }

  /// Skips the current draft (Retake). For queued imports, moves on to the next image.
  Future<CropOutcome> discardDraft() async {
    emit(state.copyWith(clearDraft: true));
    return _advanceQueue();
  }

  Future<CropOutcome> _advanceQueue() async {
    var queue = state.pending;
    while (queue.isNotEmpty) {
      final next = queue.first;
      queue = queue.sublist(1);
      if (await beginDraft(next, flow: ScanFlow.import, pending: queue)) return CropOutcome.nextImage;
    }
    emit(state.copyWith(pending: const []));
    return CropOutcome.finished;
  }

  /// Crops the draft and every queued image automatically (crop screen disabled in settings).
  Future<bool> commitAll() async {
    CropOutcome outcome;
    do {
      outcome = await commitDraft();
    } while (outcome == CropOutcome.nextImage);
    return outcome == CropOutcome.finished;
  }

  // Page editing

  /// Marks [index] as the visible page. Only emits when it actually changes.
  Future<void> selectPage(int index) async {
    if (index < 0 || index >= state.pages.length) return;
    if (index != state.selected) emit(state.copyWith(selected: index));
    await loadPageAssets(index);
  }

  /// Renders the preview and filter thumbnails for [index] without touching the selection.
  Future<void> loadPageAssets(int index) => Future.wait([loadPreview(index), loadThumbs(index)]);

  void updateSettings(FilterSettings settings, {bool immediate = false}) {
    final index = state.selected;
    if (index >= state.pages.length) return;
    final pages = [
      for (var i = 0; i < state.pages.length; i++)
        if (i == index || state.applyToAll) state.pages[i].copyWith(settings: settings) else state.pages[i],
    ];
    emit(state.copyWith(pages: pages));
    _debounce?.cancel();
    if (immediate) {
      loadPreview(index);
    } else {
      _debounce = Timer(const Duration(milliseconds: 180), () => loadPreview(index));
    }
  }

  Future<void> loadPreview(int index) async {
    if (index < 0 || index >= state.pages.length) return;
    final page = state.pages[index];
    final path = page.croppedPath;
    if (path == null || state.previews[page.id]?.settings == page.settings) return;

    final result = await _previewFilter(imagePath: path, settings: page.settings);
    if (isClosed) return;
    final bytes = result.valueOrNull;
    if (bytes == null) {
      emit(state.copyWith(error: result.failureOrNull));
      return;
    }
    final current = state.pages.where((p) => p.id == page.id);
    if (current.isEmpty || current.first.settings != page.settings) return;
    emit(state.copyWith(previews: {...state.previews, page.id: PagePreview(page.settings, bytes)}));
  }

  Future<void> loadThumbs(int index) async {
    if (index < 0 || index >= state.pages.length) return;
    final page = state.pages[index];
    final path = page.croppedPath;
    if (path == null || state.thumbs.containsKey(page.id)) return;

    final result = await _previewBatch(
      imagePath: path,
      variants: [for (final f in thumbFilters) FilterSettings(filter: f)],
    );
    if (isClosed) return;
    final list = result.valueOrNull;
    if (list != null) emit(state.copyWith(thumbs: {...state.thumbs, page.id: list}));
  }

  /// Rotates both the cropped result and the raw source so later re-cropping stays aligned.
  Future<void> rotatePage(int index) async {
    if (state.busy || index < 0 || index >= state.pages.length) return;
    final page = state.pages[index];
    final cropped = page.croppedPath;
    if (cropped == null) return;

    emit(state.copyWith(busy: true, busyLabel: 'Rotating'));
    final c = await _rotateImage(cropped);
    final r = await _rotateImage(page.rawPath);
    final failure = c.failureOrNull ?? r.failureOrNull;
    if (failure != null) {
      emit(state.copyWith(busy: false, error: failure));
      return;
    }
    final ci = c.valueOrNull!, ri = r.valueOrNull!;
    final pages = [...state.pages];
    pages[index] = page.copyWith(
      croppedPath: ci.path,
      croppedWidth: ci.width,
      croppedHeight: ci.height,
      rawPath: ri.path,
      rawWidth: ri.width,
      rawHeight: ri.height,
      quad: page.quad.rotatedClockwise(),
      detectedQuad: page.detectedQuad.rotatedClockwise(),
      clearPreMarkup: true,
    );
    final previews = {...state.previews}..remove(page.id);
    final thumbs = {...state.thumbs}..remove(page.id);
    emit(state.copyWith(busy: false, pages: pages, previews: previews, thumbs: thumbs));
    await Future.wait([loadPreview(index), loadThumbs(index)]);
  }

  /// Draws [items] on top of the page as it looks now (colour filter included) and makes that the page picture.
  Future<bool> applyMarkup(int index, List<MarkupItem> items) async {
    final markup = _markup;
    if (markup == null || state.busy || items.isEmpty || index < 0 || index >= state.pages.length) return false;
    final page = state.pages[index];
    final cropped = page.croppedPath;
    if (cropped == null) return false;

    emit(state.copyWith(busy: true, busyLabel: 'Adding markup', clearError: true));
    final result = await markup.render(imagePath: cropped, settings: page.settings, items: items);
    if (isClosed) return false;
    final info = result.valueOrNull;
    if (info == null) {
      emit(state.copyWith(busy: false, error: result.failureOrNull));
      return false;
    }
    final pages = [...state.pages];
    pages[index] = page.copyWith(
      croppedPath: info.path,
      croppedWidth: info.width,
      croppedHeight: info.height,
      // The colour filter is now part of the picture.
      settings: const FilterSettings(),
      preMarkup: page.preMarkup ?? PageSnapshot(croppedPath: cropped, width: page.croppedWidth!, height: page.croppedHeight!, settings: page.settings),
    );
    final previews = {...state.previews}..remove(page.id);
    final thumbs = {...state.thumbs}..remove(page.id);
    emit(state.copyWith(busy: false, pages: pages, previews: previews, thumbs: thumbs));
    await Future.wait([loadPreview(index), loadThumbs(index)]);
    return true;
  }

  /// Takes the marks drawn in this session off a page.
  Future<void> removeMarkup(int index) async {
    if (index < 0 || index >= state.pages.length) return;
    final page = state.pages[index];
    final before = page.preMarkup;
    if (before == null) return;
    final pages = [...state.pages];
    pages[index] = page.copyWith(
      croppedPath: before.croppedPath,
      croppedWidth: before.width,
      croppedHeight: before.height,
      settings: before.settings,
      clearPreMarkup: true,
    );
    final previews = {...state.previews}..remove(page.id);
    final thumbs = {...state.thumbs}..remove(page.id);
    emit(state.copyWith(pages: pages, previews: previews, thumbs: thumbs));
    await Future.wait([loadPreview(index), loadThumbs(index)]);
  }

  /// Puts back a page removed with [removePage] (used by the Undo action).
  void restorePage(int index, ScanPage page) {
    final pages = [...state.pages];
    pages.insert(index.clamp(0, pages.length), page);
    emit(state.copyWith(pages: pages, selected: index.clamp(0, pages.length - 1)));
  }

  void removePage(int index) {
    if (index < 0 || index >= state.pages.length) return;
    final pages = [...state.pages]..removeAt(index);
    final selected = pages.isEmpty ? 0 : state.selected.clamp(0, pages.length - 1);
    emit(state.copyWith(pages: pages, selected: selected));
  }

  /// [newIndex] is already adjusted for the removed item (ReorderableListView.onReorderItem).
  void reorderPages(int oldIndex, int newIndex) {
    final pages = [...state.pages];
    pages.insert(newIndex, pages.removeAt(oldIndex));
    emit(state.copyWith(pages: pages, selected: newIndex));
  }

  /// Renders every page at full resolution, then stores the document.
  Future<ScannedDocument?> save() async {
    if (state.pages.isEmpty || state.busy) return null;
    final total = state.pages.length;
    final out = <NewPage>[];
    bool untouched(ScanPage page) => page.settings.filter == ScanFilter.original && page.settings.brightness == 0 && page.settings.contrast == 0;

    // Pages that need a filter are rendered two at a time, each in its own isolate.
    final needed = state.pages.where((p) => !untouched(p)).length;
    final rendered = List<({String path, int width, int height})?>.filled(total, null);
    emit(state.copyWith(busy: true, busyLabel: needed == 0 ? 'Preparing pages' : 'Rendering ${needed == 1 ? 'page' : 'pages'}', clearError: true));
    var next = 0, done = 0;
    Failure? failure;
    Future<void> worker() async {
      while (failure == null) {
        final i = next++;
        if (i >= total) return;
        final page = state.pages[i];
        if (untouched(page)) continue;
        final result = await _applyFilter(imagePath: page.croppedPath!, settings: page.settings);
        final info = result.valueOrNull;
        if (info == null) {
          failure ??= result.failureOrNull;
          return;
        }
        rendered[i] = (path: info.path, width: info.width, height: info.height);
        done++;
        if (needed > 1) emit(state.copyWith(busy: true, busyLabel: 'Rendering pages: $done of $needed'));
      }
    }

    await Future.wait([for (var k = 0; k < math.min(2, total); k++) worker()]);
    if (failure != null) {
      emit(state.copyWith(busy: false, error: failure));
      return null;
    }

    for (var i = 0; i < total; i++) {
      final page = state.pages[i];
      final cropped = page.croppedPath!;
      final made = rendered[i];
      final imagePath = made?.path ?? cropped;
      final width = made?.width ?? page.croppedWidth!;
      final height = made?.height ?? page.croppedHeight!;
      final q = page.quad.points;
      out.add(
        NewPage(
          imagePath: imagePath,
          rawPath: page.rawPath,
          width: width,
          height: height,
          edit: PageEditInfo(
            croppedPath: cropped,
            quad: [
              for (final pt in q) ...[pt.x, pt.y],
            ],
            filter: page.settings.filter.name,
            brightness: page.settings.brightness,
            contrast: page.settings.contrast,
            rawWidth: page.rawWidth,
            rawHeight: page.rawHeight,
          ),
        ),
      );
    }

    emit(state.copyWith(busy: true, busyLabel: 'Saving securely'));
    final editingId = state.editingDocumentId;
    final saved = editingId != null
        ? await _updateDocument(id: editingId, title: state.title, pages: out)
        : await _saveDocument(title: state.title, pages: out, folderId: state.folderId);
    return saved.when(
      ok: (doc) {
        unawaited(clearWorkFiles?.call(DateTime.now()));
        emit(ScanSessionState(currentFilter: _baseFilter, title: defaultScanTitle(DateTime.now())));
        return doc;
      },
      err: (f) {
        emit(state.copyWith(busy: false, error: f));
        return null;
      },
    );
  }

  @override
  Future<void> close() {
    _debounce?.cancel();
    return super.close();
  }
}

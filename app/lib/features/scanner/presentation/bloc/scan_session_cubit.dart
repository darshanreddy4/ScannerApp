import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/error/failures.dart';
import '../../../documents/domain/entities/scanned_document.dart';
import '../../../documents/domain/usecases/document_usecases.dart';
import '../../domain/entities/filter_settings.dart';
import '../../domain/entities/quad.dart';
import '../../domain/usecases/scanner_usecases.dart';

/// Working state for the image currently being cropped/enhanced.
class ScanDraft {
  const ScanDraft({
    required this.rawPath,
    required this.rawWidth,
    required this.rawHeight,
    required this.quad,
    required this.autoDetected,
    this.croppedPath,
    this.croppedWidth,
    this.croppedHeight,
    this.settings = const FilterSettings(),
    this.preview,
  });

  final String rawPath;
  final int rawWidth;
  final int rawHeight;
  final Quad quad;
  final bool autoDetected;
  final String? croppedPath;
  final int? croppedWidth;
  final int? croppedHeight;
  final FilterSettings settings;
  final Uint8List? preview;

  ScanDraft copyWith({
    String? rawPath,
    int? rawWidth,
    int? rawHeight,
    Quad? quad,
    bool? autoDetected,
    String? croppedPath,
    int? croppedWidth,
    int? croppedHeight,
    FilterSettings? settings,
    Uint8List? preview,
  }) =>
      ScanDraft(
        rawPath: rawPath ?? this.rawPath,
        rawWidth: rawWidth ?? this.rawWidth,
        rawHeight: rawHeight ?? this.rawHeight,
        quad: quad ?? this.quad,
        autoDetected: autoDetected ?? this.autoDetected,
        croppedPath: croppedPath ?? this.croppedPath,
        croppedWidth: croppedWidth ?? this.croppedWidth,
        croppedHeight: croppedHeight ?? this.croppedHeight,
        settings: settings ?? this.settings,
        preview: preview ?? this.preview,
      );
}

class ScanSessionState {
  const ScanSessionState({
    this.pages = const [],
    this.draft,
    this.busy = false,
    this.previewBusy = false,
    this.error,
  });

  final List<NewPage> pages;
  final ScanDraft? draft;
  final bool busy;
  final bool previewBusy;
  final Failure? error;

  ScanSessionState copyWith({
    List<NewPage>? pages,
    ScanDraft? draft,
    bool clearDraft = false,
    bool? busy,
    bool? previewBusy,
    Failure? error,
    bool clearError = false,
  }) =>
      ScanSessionState(
        pages: pages ?? this.pages,
        draft: clearDraft ? null : (draft ?? this.draft),
        busy: busy ?? this.busy,
        previewBusy: previewBusy ?? this.previewBusy,
        error: clearError ? null : (error ?? this.error),
      );
}

class ScanSessionCubit extends Cubit<ScanSessionState> {
  ScanSessionCubit({
    required PrepareImage prepareImage,
    required CropDocument cropDocument,
    required RotateImage rotateImage,
    required PreviewFilter previewFilter,
    required ApplyFilter applyFilter,
    required SaveDocument saveDocument,
  })  : _prepareImage = prepareImage,
        _cropDocument = cropDocument,
        _rotateImage = rotateImage,
        _previewFilter = previewFilter,
        _applyFilter = applyFilter,
        _saveDocument = saveDocument,
        super(const ScanSessionState());

  final PrepareImage _prepareImage;
  final CropDocument _cropDocument;
  final RotateImage _rotateImage;
  final PreviewFilter _previewFilter;
  final ApplyFilter _applyFilter;
  final SaveDocument _saveDocument;

  Timer? _debounce;
  int _previewToken = 0;

  void reset() {
    _debounce?.cancel();
    emit(const ScanSessionState());
  }

  void clearError() => emit(state.copyWith(clearError: true));

  /// Loads a captured or imported image into the draft. Returns true on success.
  Future<bool> beginDraft(String sourcePath) async {
    emit(state.copyWith(busy: true, clearError: true));
    final result = await _prepareImage(sourcePath);
    return result.when(
      ok: (img) {
        emit(state.copyWith(
          busy: false,
          draft: ScanDraft(
            rawPath: img.path,
            rawWidth: img.width,
            rawHeight: img.height,
            quad: img.detectedQuad ?? Quad.defaultInset,
            autoDetected: img.detectedQuad != null,
          ),
        ));
        return true;
      },
      err: (f) {
        emit(state.copyWith(busy: false, error: f));
        return false;
      },
    );
  }

  void updateQuad(Quad quad) {
    final d = state.draft;
    if (d != null) emit(state.copyWith(draft: d.copyWith(quad: quad)));
  }

  void useFullFrame() => updateQuad(Quad.fullFrame);

  Future<void> rotateRaw() async {
    final d = state.draft;
    if (d == null || state.busy) return;
    emit(state.copyWith(busy: true));
    final result = await _rotateImage(d.rawPath);
    result.when(
      ok: (info) => emit(state.copyWith(
        busy: false,
        draft: d.copyWith(
          rawPath: info.path,
          rawWidth: info.width,
          rawHeight: info.height,
          quad: d.quad.rotatedClockwise(),
        ),
      )),
      err: (f) => emit(state.copyWith(busy: false, error: f)),
    );
  }

  /// Applies the perspective crop. Returns true when the enhance step can open.
  Future<bool> confirmCrop() async {
    final d = state.draft;
    if (d == null) return false;
    emit(state.copyWith(busy: true, clearError: true));
    final result = await _cropDocument(imagePath: d.rawPath, quad: d.quad);
    final ok = result.when(
      ok: (info) {
        emit(state.copyWith(
          busy: false,
          draft: d.copyWith(
            croppedPath: info.path,
            croppedWidth: info.width,
            croppedHeight: info.height,
            settings: const FilterSettings(filter: ScanFilter.documentBw),
          ),
        ));
        return true;
      },
      err: (f) {
        emit(state.copyWith(busy: false, error: f));
        return false;
      },
    );
    if (ok) await _refreshPreview();
    return ok;
  }

  void updateSettings(FilterSettings settings, {bool immediate = false}) {
    final d = state.draft;
    if (d == null) return;
    emit(state.copyWith(draft: d.copyWith(settings: settings)));
    _debounce?.cancel();
    if (immediate) {
      _refreshPreview();
    } else {
      _debounce = Timer(const Duration(milliseconds: 180), _refreshPreview);
    }
  }

  Future<void> _refreshPreview() async {
    final d = state.draft;
    final path = d?.croppedPath;
    if (d == null || path == null) return;

    final token = ++_previewToken;
    emit(state.copyWith(previewBusy: true));
    final result = await _previewFilter(imagePath: path, settings: d.settings);
    if (token != _previewToken || isClosed) return;

    result.when(
      ok: (bytes) {
        final current = state.draft;
        if (current != null) emit(state.copyWith(previewBusy: false, draft: current.copyWith(preview: bytes)));
      },
      err: (f) => emit(state.copyWith(previewBusy: false, error: f)),
    );
  }

  /// Renders the full-resolution result and appends it to the page list.
  Future<bool> commitDraft() async {
    final d = state.draft;
    final cropped = d?.croppedPath;
    if (d == null || cropped == null) return false;

    _debounce?.cancel();
    emit(state.copyWith(busy: true, clearError: true));
    final result = await _applyFilter(imagePath: cropped, settings: d.settings);
    return result.when(
      ok: (info) {
        emit(state.copyWith(
          busy: false,
          clearDraft: true,
          pages: [
            ...state.pages,
            NewPage(imagePath: info.path, rawPath: d.rawPath, width: info.width, height: info.height),
          ],
        ));
        return true;
      },
      err: (f) {
        emit(state.copyWith(busy: false, error: f));
        return false;
      },
    );
  }

  void discardDraft() {
    _debounce?.cancel();
    emit(state.copyWith(clearDraft: true));
  }

  void removePage(int index) {
    final pages = [...state.pages]..removeAt(index);
    emit(state.copyWith(pages: pages));
  }

  /// [newIndex] is already adjusted for the removed item (ReorderableListView.onReorderItem).
  void reorderPages(int oldIndex, int newIndex) {
    final pages = [...state.pages];
    pages.insert(newIndex, pages.removeAt(oldIndex));
    emit(state.copyWith(pages: pages));
  }

  Future<ScannedDocument?> save(String title) async {
    if (state.pages.isEmpty || state.busy) return null;
    emit(state.copyWith(busy: true, clearError: true));
    final result = await _saveDocument(title: title, pages: state.pages);
    return result.when(
      ok: (doc) {
        emit(const ScanSessionState());
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

import 'dart:io';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

import '../../../core/error/failures.dart';
import '../../text_edit/pdf/pdf_page_renderer.dart';
import '../domain/pdf_forms.dart';

enum CropStatus { idle, loading, ready, saving, done }

enum CropSide { left, top, right, bottom }

/// Width over height of a JPEG or PNG picture read from its header, or null when it cannot be told.
double? imageAspect(Uint8List b) {
  if (b.length > 24 && b[0] == 0x89 && b[1] == 0x50) {
    final w = (b[16] << 24) | (b[17] << 16) | (b[18] << 8) | b[19];
    final h = (b[20] << 24) | (b[21] << 16) | (b[22] << 8) | b[23];
    return w > 0 && h > 0 ? w / h : null;
  }
  if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) return null;
  var i = 2;
  while (i + 9 < b.length) {
    if (b[i] != 0xFF) {
      i++;
      continue;
    }
    final marker = b[i + 1];
    if (marker == 0xFF) {
      i++;
      continue;
    }
    if (marker == 0xD8 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
      i += 2;
      continue;
    }
    final length = (b[i + 2] << 8) | b[i + 3];
    final isFrame = marker >= 0xC0 && marker <= 0xCF && marker != 0xC4 && marker != 0xC8 && marker != 0xCC;
    if (isFrame) {
      final h = (b[i + 5] << 8) | b[i + 6];
      final w = (b[i + 7] << 8) | b[i + 8];
      return w > 0 && h > 0 ? w / h : null;
    }
    i += 2 + length;
  }
  return null;
}

class PdfCropState extends Equatable {
  const PdfCropState({
    this.path,
    this.pageCount = 0,
    this.page = 0,
    this.perPage = const {},
    this.shared = const CropInsets(),
    this.all = false,
    this.status = CropStatus.idle,
    this.result,
    this.failure,
  });

  final String? path;
  final int pageCount;
  final int page;
  final Map<int, CropInsets> perPage;

  /// The cut used for every page when [all] is on.
  final CropInsets shared;
  final bool all;
  final CropStatus status;
  final FilledPdf? result;
  final Failure? failure;

  bool get busy => status == CropStatus.loading || status == CropStatus.saving;

  CropInsets insetsOf(int index) => all ? shared : (perPage[index] ?? const CropInsets());

  /// The pages that will be cut, with how much.
  Map<int, CropInsets> get plan => {
    for (var i = 0; i < pageCount; i++)
      if (!insetsOf(i).isNone) i: insetsOf(i),
  };

  PdfCropState copyWith({
    Object? path = _keep,
    int? pageCount,
    int? page,
    Map<int, CropInsets>? perPage,
    CropInsets? shared,
    bool? all,
    CropStatus? status,
    Object? result = _keep,
    Object? failure = _keep,
  }) => PdfCropState(
    path: identical(path, _keep) ? this.path : path as String?,
    pageCount: pageCount ?? this.pageCount,
    page: page ?? this.page,
    perPage: perPage ?? this.perPage,
    shared: shared ?? this.shared,
    all: all ?? this.all,
    status: status ?? this.status,
    result: identical(result, _keep) ? this.result : result as FilledPdf?,
    failure: identical(failure, _keep) ? this.failure : failure as Failure?,
  );

  static const _keep = Object();

  @override
  List<Object?> get props => [path, pageCount, page, perPage, shared, all, status, result, failure];
}

class PdfCropCubit extends Cubit<PdfCropState> {
  PdfCropCubit({
    required PdfPageToolsService service,
    required Future<Directory> Function() outputDir,
    Future<PdfPageRenderer> Function(String path) openRenderer = PdfxPageRenderer.open,
    DateTime Function() now = DateTime.now,
  }) : _service = service,
       _outputDir = outputDir,
       _openRenderer = openRenderer,
       _now = now,
       super(const PdfCropState());

  final PdfPageToolsService _service;
  final Future<Directory> Function() _outputDir;
  final Future<PdfPageRenderer> Function(String path) _openRenderer;
  final DateTime Function() _now;
  PdfPageRenderer? _renderer;
  final _pages = <int, Future<({Uint8List bytes, double aspect})>>{};

  Future<void> pick(String path) async {
    if (state.busy) return;
    await _closeRenderer();
    emit(PdfCropState(path: path, status: CropStatus.loading));
    try {
      final renderer = await _openRenderer(path);
      if (isClosed) {
        await renderer.dispose();
        return;
      }
      _renderer = renderer;
      if (renderer.pageCount < 1) {
        await _closeRenderer();
        emit(const PdfCropState(failure: ExportFailure('Nothing could be read from this PDF.')));
        return;
      }
      emit(PdfCropState(path: path, pageCount: renderer.pageCount, status: CropStatus.ready));
    } catch (e) {
      if (!isClosed) emit(PdfCropState(failure: ExportFailure('This PDF could not be opened. It may be damaged or protected.', cause: e)));
    }
  }

  void clear() {
    if (state.busy) return;
    _closeRenderer();
    emit(const PdfCropState());
  }

  /// The picture of a page and its shape, drawn once.
  Future<({Uint8List bytes, double aspect})> picture(int index) {
    final renderer = _renderer;
    if (renderer == null) return Future.error(StateError('No PDF is open'));
    return _pages.putIfAbsent(index, () async {
      final bytes = await renderer.render(index, width: 900);
      return (bytes: bytes, aspect: imageAspect(bytes) ?? 0.707);
    });
  }

  void goTo(int index) {
    if (state.busy || index < 0 || index >= state.pageCount) return;
    emit(state.copyWith(page: index));
  }

  void setSide(CropSide side, double value) {
    if (state.busy || state.path == null) return;
    final v = value.clamp(0.0, 0.45);
    final now = state.insetsOf(state.page);
    final next = switch (side) {
      CropSide.left => now.copyWith(left: v),
      CropSide.top => now.copyWith(top: v),
      CropSide.right => now.copyWith(right: v),
      CropSide.bottom => now.copyWith(bottom: v),
    };
    emit(
      state.all
          ? state.copyWith(shared: next, result: null, failure: null)
          : state.copyWith(perPage: {...state.perPage, state.page: next}, result: null, failure: null),
    );
  }

  /// With this on, the cut of the page on view is used for every page.
  void setAll(bool on) {
    if (state.busy || state.all == on) return;
    emit(state.copyWith(all: on, shared: on ? state.insetsOf(state.page) : state.shared, result: null));
  }

  void reset() {
    if (state.busy) return;
    emit(state.copyWith(perPage: const {}, shared: const CropInsets(), result: null, failure: null));
  }

  Future<void> save() async {
    final path = state.path;
    if (path == null || state.busy || state.status == CropStatus.idle) return;
    final plan = state.plan;
    if (plan.isEmpty) {
      emit(state.copyWith(failure: const ExportFailure('Choose how much to cut off first.')));
      return;
    }
    emit(state.copyWith(status: CropStatus.saving, result: null, failure: null));
    final dir = await Directory(p.join((await _outputDir()).path, 'pdf_crop')).create(recursive: true);
    final out = p.join(dir.path, '${p.basenameWithoutExtension(path)}_cropped_${_now().millisecondsSinceEpoch}.pdf');
    final result = await _service.crop(sourcePath: path, outputPath: out, insets: plan);
    if (isClosed) return;
    emit(state.copyWith(status: CropStatus.done, result: result.valueOrNull, failure: result.failureOrNull));
  }

  Future<void> _closeRenderer() async {
    final r = _renderer;
    _renderer = null;
    _pages.clear();
    if (r != null) {
      try {
        await r.dispose();
      } catch (_) {}
    }
  }

  @override
  Future<void> close() async {
    await _closeRenderer();
    return super.close();
  }
}

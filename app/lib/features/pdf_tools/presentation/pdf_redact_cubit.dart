import 'dart:io';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

import '../../../core/error/failures.dart';
import '../data/pdf_picture_pages.dart';
import '../domain/pdf_forms.dart';
import '../domain/pdf_redact.dart';
import 'pdf_crop_cubit.dart' show imageAspect;

enum RedactStatus { idle, opening, ready, saving, done }

class PdfRedactState extends Equatable {
  const PdfRedactState({
    this.path,
    this.pageCount = 0,
    this.boxes = const [],
    this.drawing = false,
    this.high = false,
    this.status = RedactStatus.idle,
    this.result,
    this.failure,
  });

  final String? path;
  final int pageCount;
  final List<RedactBox> boxes;

  /// Dragging on a page draws a box (otherwise it scrolls the pages).
  final bool drawing;
  final bool high;
  final RedactStatus status;
  final FilledPdf? result;
  final Failure? failure;

  bool get busy => status == RedactStatus.opening || status == RedactStatus.saving;
  bool get open => pageCount > 0;

  PdfRedactState copyWith({
    Object? path = _keep,
    int? pageCount,
    List<RedactBox>? boxes,
    bool? drawing,
    bool? high,
    RedactStatus? status,
    Object? result = _keep,
    Object? failure = _keep,
  }) => PdfRedactState(
    path: identical(path, _keep) ? this.path : path as String?,
    pageCount: pageCount ?? this.pageCount,
    boxes: boxes ?? this.boxes,
    drawing: drawing ?? this.drawing,
    high: high ?? this.high,
    status: status ?? this.status,
    result: identical(result, _keep) ? this.result : result as FilledPdf?,
    failure: identical(failure, _keep) ? this.failure : failure as Failure?,
  );

  static const _keep = Object();

  @override
  List<Object?> get props => [path, pageCount, boxes, drawing, high, status, result, failure];
}

class PdfRedactCubit extends Cubit<PdfRedactState> {
  PdfRedactCubit({
    required PdfRedactService service,
    required Future<Directory> Function() outputDir,
    PdfPicturePages Function()? pages,
    DateTime Function() now = DateTime.now,
  }) : _service = service,
       _outputDir = outputDir,
       _pages = (pages ?? PdfxPicturePages.new)(),
       _now = now,
       super(const PdfRedactState());

  final PdfRedactService _service;
  final Future<Directory> Function() _outputDir;
  final PdfPicturePages _pages;
  final DateTime Function() _now;
  final _previews = <int, Future<({Uint8List bytes, double aspect})>>{};

  /// The smallest box that is kept; a tap or a tiny slip of the finger is not a box.
  static const minSize = 0.012;

  Future<void> pick(String path) async {
    if (state.busy) return;
    _previews.clear();
    emit(PdfRedactState(path: path, status: RedactStatus.opening));
    try {
      final count = await _pages.open(path);
      if (isClosed) return;
      if (count < 1) {
        emit(const PdfRedactState(failure: ExportFailure('Nothing could be read from this PDF.')));
        return;
      }
      emit(PdfRedactState(path: path, pageCount: count, status: RedactStatus.ready));
    } catch (e) {
      if (!isClosed) emit(PdfRedactState(failure: ExportFailure('This PDF could not be opened. It may be damaged or protected.', cause: e)));
    }
  }

  void clear() {
    if (state.busy) return;
    _previews.clear();
    _pages.close();
    emit(const PdfRedactState());
  }

  Future<({Uint8List bytes, double aspect})> preview(int index) => _previews.putIfAbsent(index, () async {
    final bytes = await _pages.render(index, width: 1000, png: false);
    return (bytes: bytes, aspect: imageAspect(bytes) ?? 0.707);
  });

  void setDrawing(bool on) {
    if (!state.busy) emit(state.copyWith(drawing: on));
  }

  void setHigh(bool on) {
    if (!state.busy) emit(state.copyWith(high: on, result: null));
  }

  /// Adds a box from two corners given as shares of the page, in any order. Boxes that are too small are ignored.
  bool addBox(int page, double x1, double y1, double x2, double y2) {
    if (state.busy || page < 0 || page >= state.pageCount) return false;
    final l = x1 < x2 ? x1 : x2, r = x1 < x2 ? x2 : x1, t = y1 < y2 ? y1 : y2, b = y1 < y2 ? y2 : y1;
    final box = RedactBox(page: page, left: l.clamp(0.0, 1.0), top: t.clamp(0.0, 1.0), right: r.clamp(0.0, 1.0), bottom: b.clamp(0.0, 1.0));
    if (box.width < minSize || box.height < minSize) return false;
    emit(state.copyWith(boxes: [...state.boxes, box], result: null, failure: null, status: RedactStatus.ready));
    return true;
  }

  void removeBox(RedactBox box) {
    if (!state.busy) emit(state.copyWith(boxes: [...state.boxes]..remove(box), result: null));
  }

  void undo() {
    if (!state.busy && state.boxes.isNotEmpty) emit(state.copyWith(boxes: [...state.boxes]..removeLast(), result: null));
  }

  Future<void> save() async {
    final path = state.path;
    if (path == null || state.busy || !state.open) return;
    if (state.boxes.isEmpty) {
      emit(state.copyWith(failure: const ExportFailure('Draw over what to hide first.')));
      return;
    }
    emit(state.copyWith(status: RedactStatus.saving, result: null, failure: null));
    final dir = await Directory(p.join((await _outputDir()).path, 'pdf_redact')).create(recursive: true);
    final out = p.join(dir.path, '${p.basenameWithoutExtension(path)}_redacted_${_now().millisecondsSinceEpoch}.pdf');
    final result = await _service.redact(sourcePath: path, outputPath: out, boxes: state.boxes, highDetail: state.high);
    if (isClosed) return;
    emit(state.copyWith(status: RedactStatus.done, result: result.valueOrNull, failure: result.failureOrNull));
  }

  @override
  Future<void> close() async {
    try {
      await _pages.close();
    } catch (_) {}
    return super.close();
  }
}

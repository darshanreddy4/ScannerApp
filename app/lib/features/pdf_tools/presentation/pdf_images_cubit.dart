import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

import '../../../core/error/failures.dart';
import '../data/pdf_picture_pages.dart';
import '../domain/pdf_forms.dart';
import '../domain/pdf_pages.dart';

enum ImagesMode { pages, inside }

enum ImagesStatus { idle, opening, ready, working, done }

class PdfImagesState extends Equatable {
  const PdfImagesState({
    this.path,
    this.pageCount = 0,
    this.mode = ImagesMode.pages,
    this.range = '',
    this.png = false,
    this.high = false,
    this.status = ImagesStatus.idle,
    this.progress = 0,
    this.files = const [],
    this.skipped = 0,
    this.searched = false,
    this.failure,
  });

  final String? path;
  final int pageCount;
  final ImagesMode mode;

  /// Pages to turn into pictures, such as "1-3, 5"; empty means all.
  final String range;
  final bool png;
  final bool high;
  final ImagesStatus status;

  /// Pictures made so far while working.
  final int progress;
  final List<String> files;

  /// With [ImagesMode.inside]: pictures found that cannot be saved as a picture file.
  final int skipped;

  /// The pictures inside the PDF have been looked for.
  final bool searched;
  final Failure? failure;

  bool get busy => status == ImagesStatus.opening || status == ImagesStatus.working;
  bool get open => pageCount > 0;
  String get mime => mode == ImagesMode.pages ? (png ? 'image/png' : 'image/jpeg') : 'image/*';

  PdfImagesState copyWith({
    Object? path = _keep,
    int? pageCount,
    ImagesMode? mode,
    String? range,
    bool? png,
    bool? high,
    ImagesStatus? status,
    int? progress,
    List<String>? files,
    int? skipped,
    bool? searched,
    Object? failure = _keep,
  }) => PdfImagesState(
    path: identical(path, _keep) ? this.path : path as String?,
    pageCount: pageCount ?? this.pageCount,
    mode: mode ?? this.mode,
    range: range ?? this.range,
    png: png ?? this.png,
    high: high ?? this.high,
    status: status ?? this.status,
    progress: progress ?? this.progress,
    files: files ?? this.files,
    skipped: skipped ?? this.skipped,
    searched: searched ?? this.searched,
    failure: identical(failure, _keep) ? this.failure : failure as Failure?,
  );

  static const _keep = Object();

  @override
  List<Object?> get props => [path, pageCount, mode, range, png, high, status, progress, files, skipped, searched, failure];
}

class PdfImagesCubit extends Cubit<PdfImagesState> {
  PdfImagesCubit({
    required PdfPageToolsService tools,
    required Future<Directory> Function() outputDir,
    PdfPicturePages Function()? pages,
    DateTime Function() now = DateTime.now,
  }) : _tools = tools,
       _outputDir = outputDir,
       _pages = (pages ?? PdfxPicturePages.new)(),
       _now = now,
       super(const PdfImagesState());

  final PdfPageToolsService _tools;
  final Future<Directory> Function() _outputDir;
  final PdfPicturePages _pages;
  final DateTime Function() _now;

  Future<void> pick(String path) async {
    if (state.busy) return;
    emit(PdfImagesState(path: path, status: ImagesStatus.opening, mode: state.mode, png: state.png, high: state.high));
    try {
      final count = await _pages.open(path);
      if (isClosed) return;
      if (count < 1) {
        emit(const PdfImagesState(failure: ExportFailure('Nothing could be read from this PDF.')));
        return;
      }
      emit(PdfImagesState(path: path, pageCount: count, status: ImagesStatus.ready, mode: state.mode, png: state.png, high: state.high));
    } catch (e) {
      if (!isClosed) emit(PdfImagesState(failure: ExportFailure('This PDF could not be opened. It may be damaged or protected.', cause: e)));
    }
  }

  void clear() {
    if (state.busy) return;
    _pages.close();
    emit(PdfImagesState(mode: state.mode, png: state.png, high: state.high));
  }

  void setMode(ImagesMode mode) {
    if (!state.busy)
      emit(state.copyWith(mode: mode, files: const [], skipped: 0, searched: false, failure: null, status: state.open ? ImagesStatus.ready : state.status));
  }

  void setRange(String text) {
    if (!state.busy) emit(state.copyWith(range: text, failure: null));
  }

  void setPng(bool on) {
    if (!state.busy) emit(state.copyWith(png: on, files: const [], failure: null));
  }

  void setHigh(bool on) {
    if (!state.busy) emit(state.copyWith(high: on, files: const [], failure: null));
  }

  Future<Directory> _folder(String kind) async {
    final base = p.basenameWithoutExtension(state.path!);
    return Directory(p.join((await _outputDir()).path, 'pdf_pictures', '${base}_${kind}_${_now().millisecondsSinceEpoch}')).create(recursive: true);
  }

  /// Draws the chosen pages as pictures, one file each.
  Future<void> makePages() async {
    final path = state.path;
    if (path == null || state.busy || !state.open) return;
    final text = state.range.trim();
    final parsed = PageRanges.parse(text.isEmpty ? '1-${state.pageCount}' : text, state.pageCount);
    if (!parsed.ok) {
      emit(state.copyWith(failure: ExportFailure(parsed.error ?? 'Type the pages, for example 1-3, 5.')));
      return;
    }
    final pages = parsed.pages;
    emit(state.copyWith(status: ImagesStatus.working, progress: 0, files: const [], failure: null));
    try {
      final dir = await _folder('pages');
      final base = p.basenameWithoutExtension(path);
      final files = <String>[];
      for (final index in pages) {
        final bytes = await _pages.render(index, width: state.high ? 2480 : 1240, png: state.png);
        final name = '${base}_page_${(index + 1).toString().padLeft(pages.last >= 99 ? 3 : 2, '0')}.${state.png ? 'png' : 'jpg'}';
        final file = File(p.join(dir.path, name));
        await file.writeAsBytes(bytes, flush: true);
        files.add(file.path);
        if (isClosed) return;
        emit(state.copyWith(progress: files.length));
      }
      emit(state.copyWith(status: ImagesStatus.done, files: files));
    } catch (e) {
      if (!isClosed)
        emit(
          state.copyWith(
            status: ImagesStatus.ready,
            failure: ExportFailure('The pictures could not be made.', cause: e),
          ),
        );
    }
  }

  /// Saves the pictures that are inside the PDF, as they were put there.
  Future<void> findPictures() async {
    final path = state.path;
    if (path == null || state.busy || !state.open) return;
    emit(state.copyWith(status: ImagesStatus.working, files: const [], skipped: 0, searched: false, failure: null));
    final dir = await _folder('inside');
    final result = await _tools.extractImages(sourcePath: path, outputDir: dir.path);
    if (isClosed) return;
    final found = result.valueOrNull;
    emit(
      state.copyWith(
        status: found == null ? ImagesStatus.ready : ImagesStatus.done,
        files: [for (final i in found?.images ?? const <ExtractedImage>[]) i.path],
        skipped: found?.skipped ?? 0,
        searched: found != null,
        failure: result.failureOrNull,
      ),
    );
  }

  @override
  Future<void> close() async {
    try {
      await _pages.close();
    } catch (_) {}
    return super.close();
  }
}

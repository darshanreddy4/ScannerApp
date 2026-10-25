import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

import '../../../core/error/failures.dart';
import '../domain/pdf_compressor.dart';

enum PdfCompressStatus { idle, running, done }

class PdfCompressState extends Equatable {
  const PdfCompressState({
    this.path,
    this.bytes = 0,
    this.targetBytes = 500 * 1024,
    this.status = PdfCompressStatus.idle,
    this.attempt = 0,
    this.attempts = 0,
    this.result,
    this.failure,
  });

  final String? path;
  final int bytes;

  /// Null means "just make it smaller" with a balanced setting.
  final int? targetBytes;
  final PdfCompressStatus status;
  final int attempt;
  final int attempts;
  final CompressedPdf? result;
  final Failure? failure;

  String? get name => path == null ? null : p.basename(path!);

  PdfCompressState copyWith({
    Object? path = _keep,
    int? bytes,
    Object? targetBytes = _keep,
    PdfCompressStatus? status,
    int? attempt,
    int? attempts,
    Object? result = _keep,
    Object? failure = _keep,
  }) => PdfCompressState(
    path: identical(path, _keep) ? this.path : path as String?,
    bytes: bytes ?? this.bytes,
    targetBytes: identical(targetBytes, _keep) ? this.targetBytes : targetBytes as int?,
    status: status ?? this.status,
    attempt: attempt ?? this.attempt,
    attempts: attempts ?? this.attempts,
    result: identical(result, _keep) ? this.result : result as CompressedPdf?,
    failure: identical(failure, _keep) ? this.failure : failure as Failure?,
  );

  static const _keep = Object();

  @override
  List<Object?> get props => [path, bytes, targetBytes, status, attempt, attempts, result?.path, result?.bytes, result?.unchanged, failure];
}

class PdfCompressCubit extends Cubit<PdfCompressState> {
  PdfCompressCubit({required PdfCompressor compressor, required Future<Directory> Function() outputDir})
    : _compressor = compressor,
      _outputDir = outputDir,
      super(const PdfCompressState());

  final PdfCompressor _compressor;
  final Future<Directory> Function() _outputDir;

  Future<void> pick(String path) async {
    if (state.status == PdfCompressStatus.running) return;
    final file = File(path);
    if (!await file.exists()) {
      emit(state.copyWith(failure: const ExportFailure('The file could not be found.')));
      return;
    }
    emit(state.copyWith(path: path, bytes: await file.length(), status: PdfCompressStatus.idle, result: null, failure: null));
  }

  void clear() {
    if (state.status == PdfCompressStatus.running) return;
    emit(PdfCompressState(targetBytes: state.targetBytes));
  }

  void setTarget(int? bytes) {
    if (state.status == PdfCompressStatus.running) return;
    emit(state.copyWith(targetBytes: bytes, status: PdfCompressStatus.idle, result: null, failure: null));
  }

  Future<void> run() async {
    final path = state.path;
    if (state.status == PdfCompressStatus.running || path == null) return;
    emit(state.copyWith(status: PdfCompressStatus.running, attempt: 0, attempts: 0, result: null, failure: null));
    final dir = await Directory(p.join((await _outputDir()).path, 'pdfs')).create(recursive: true);
    final out = p.join(dir.path, '${p.basenameWithoutExtension(path)}_compressed_${DateTime.now().millisecondsSinceEpoch}.pdf');
    final result = await _compressor.compress(
      sourcePath: path,
      outputPath: out,
      options: PdfCompressOptions(targetBytes: state.targetBytes),
      onProgress: (a, total) {
        if (!isClosed) emit(state.copyWith(attempt: a, attempts: total));
      },
    );
    if (isClosed) return;
    emit(state.copyWith(status: PdfCompressStatus.done, result: result.valueOrNull, failure: result.failureOrNull));
  }
}

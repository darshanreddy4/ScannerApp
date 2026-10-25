import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

import '../../../core/error/failures.dart';
import '../domain/photo_compressor.dart';

enum CompressStatus { idle, running, done }

class CompressItem extends Equatable {
  const CompressItem({required this.path, required this.bytes, this.result, this.failure});

  final String path;
  final int bytes;
  final CompressedPhoto? result;
  final Failure? failure;

  String get name => p.basename(path);

  CompressItem withResult(CompressedPhoto? r, Failure? f) => CompressItem(path: path, bytes: bytes, result: r, failure: f);
  CompressItem cleared() => CompressItem(path: path, bytes: bytes);

  @override
  List<Object?> get props => [path, bytes, result?.path, result?.bytes, failure];
}

class CompressState extends Equatable {
  const CompressState({
    this.items = const [],
    this.targetBytes = 100 * 1024,
    this.maxSide,
    this.format = PhotoFormat.jpg,
    this.status = CompressStatus.idle,
    this.progress = 0,
  });

  final List<CompressItem> items;

  /// Null means "no size limit", only resize and convert.
  final int? targetBytes;
  final int? maxSide;
  final PhotoFormat format;
  final CompressStatus status;
  final int progress;

  List<CompressedPhoto> get results => [
    for (final i in items)
      if (i.result != null) i.result!,
  ];

  CompressState copyWith({
    List<CompressItem>? items,
    Object? targetBytes = _keep,
    Object? maxSide = _keep,
    PhotoFormat? format,
    CompressStatus? status,
    int? progress,
  }) => CompressState(
    items: items ?? this.items,
    targetBytes: identical(targetBytes, _keep) ? this.targetBytes : targetBytes as int?,
    maxSide: identical(maxSide, _keep) ? this.maxSide : maxSide as int?,
    format: format ?? this.format,
    status: status ?? this.status,
    progress: progress ?? this.progress,
  );

  static const _keep = Object();

  @override
  List<Object?> get props => [items, targetBytes, maxSide, format, status, progress];
}

class CompressCubit extends Cubit<CompressState> {
  CompressCubit({required PhotoCompressor compressor, required Future<Directory> Function() outputDir})
    : _compressor = compressor,
      _outputDir = outputDir,
      super(const CompressState());

  final PhotoCompressor _compressor;
  final Future<Directory> Function() _outputDir;

  static const maxPhotos = 30;

  Future<void> add(List<String> paths) async {
    final known = {for (final i in state.items) i.path};
    final added = <CompressItem>[];
    for (final path in paths) {
      if (known.contains(path) || state.items.length + added.length >= maxPhotos) continue;
      known.add(path);
      final file = File(path);
      if (!await file.exists()) continue;
      added.add(CompressItem(path: path, bytes: await file.length()));
    }
    if (isClosed || added.isEmpty) return;
    emit(state.copyWith(items: [...state.items.map((i) => i.cleared()), ...added], status: CompressStatus.idle));
  }

  void remove(String path) {
    if (state.status == CompressStatus.running) return;
    emit(
      state.copyWith(
        items: [
          for (final i in state.items)
            if (i.path != path) i.cleared(),
        ],
        status: CompressStatus.idle,
      ),
    );
  }

  void clear() {
    if (state.status == CompressStatus.running) return;
    emit(state.copyWith(items: const [], status: CompressStatus.idle));
  }

  void setTarget(int? bytes) => _option(() => emit(state.copyWith(targetBytes: bytes)));
  void setMaxSide(int? side) => _option(() => emit(state.copyWith(maxSide: side)));
  void setFormat(PhotoFormat format) => _option(() => emit(state.copyWith(format: format)));

  /// A new setting makes earlier results out of date.
  void _option(void Function() change) {
    if (state.status == CompressStatus.running) return;
    change();
    emit(state.copyWith(items: [for (final i in state.items) i.cleared()], status: CompressStatus.idle));
  }

  Future<void> run() async {
    if (state.status == CompressStatus.running || state.items.isEmpty) return;
    emit(state.copyWith(status: CompressStatus.running, progress: 0, items: [for (final i in state.items) i.cleared()]));
    final dir = Directory(p.join((await _outputDir()).path, 'photos'));
    await dir.create(recursive: true);
    final options = CompressOptions(targetBytes: state.targetBytes, maxSide: state.maxSide, format: state.format);
    final stamp = DateTime.now().millisecondsSinceEpoch;

    for (var i = 0; i < state.items.length; i++) {
      if (isClosed) return;
      final item = state.items[i];
      final out = p.join(dir.path, '${p.basenameWithoutExtension(item.path)}_compressed_$stamp-$i.${options.format.extension}');
      final result = await _compressor.compress(sourcePath: item.path, outputPath: out, options: options);
      if (isClosed) return;
      final items = [...state.items];
      items[i] = item.withResult(result.valueOrNull, result.failureOrNull);
      emit(state.copyWith(items: items, progress: i + 1));
    }
    if (!isClosed) emit(state.copyWith(status: CompressStatus.done));
  }
}

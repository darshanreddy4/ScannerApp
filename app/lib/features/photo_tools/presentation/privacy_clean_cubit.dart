import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

import '../../../core/error/failures.dart';
import '../domain/metadata_cleaner.dart';

enum CleanStatus { idle, running, done }

class CleanItem extends Equatable {
  const CleanItem({required this.path, required this.bytes, this.metadata, this.failure, this.result});

  final String path;
  final int bytes;
  final PhotoMetadata? metadata;
  final Failure? failure;
  final CleanedPhoto? result;

  String get name => p.basename(path);

  CleanItem withResult(CleanedPhoto? r, Failure? f) => CleanItem(path: path, bytes: bytes, metadata: metadata, failure: f ?? failure, result: r);

  @override
  List<Object?> get props => [path, bytes, metadata?.hiddenBytes, metadata?.hasLocation, failure, result?.path];
}

class PrivacyCleanState extends Equatable {
  const PrivacyCleanState({this.items = const [], this.status = CleanStatus.idle, this.progress = 0, this.checking = false});

  final List<CleanItem> items;
  final CleanStatus status;
  final int progress;

  /// Photos are being looked at right after they were added.
  final bool checking;

  List<CleanItem> get cleanable => [
    for (final i in items)
      if (i.failure == null && i.metadata != null) i,
  ];
  List<CleanedPhoto> get results => [
    for (final i in items)
      if (i.result != null) i.result!,
  ];

  PrivacyCleanState copyWith({List<CleanItem>? items, CleanStatus? status, int? progress, bool? checking}) =>
      PrivacyCleanState(items: items ?? this.items, status: status ?? this.status, progress: progress ?? this.progress, checking: checking ?? this.checking);

  @override
  List<Object?> get props => [items, status, progress, checking];
}

class PrivacyCleanCubit extends Cubit<PrivacyCleanState> {
  PrivacyCleanCubit({required MetadataCleaner cleaner, required Future<Directory> Function() outputDir})
    : _cleaner = cleaner,
      _outputDir = outputDir,
      super(const PrivacyCleanState());

  final MetadataCleaner _cleaner;
  final Future<Directory> Function() _outputDir;

  static const maxPhotos = 50;

  /// Adds photos and looks at what each one carries.
  Future<void> add(List<String> paths) async {
    if (state.status == CleanStatus.running) return;
    final known = {for (final i in state.items) i.path};
    final added = <CleanItem>[];
    emit(state.copyWith(checking: true));
    for (final path in paths) {
      if (known.contains(path) || state.items.length + added.length >= maxPhotos) continue;
      final file = File(path);
      if (!await file.exists()) continue;
      known.add(path);
      final info = await _cleaner.inspect(path);
      added.add(CleanItem(path: path, bytes: await file.length(), metadata: info.valueOrNull, failure: info.failureOrNull));
    }
    if (isClosed) return;
    emit(
      state.copyWith(
        items: [
          for (final i in state.items) CleanItem(path: i.path, bytes: i.bytes, metadata: i.metadata, failure: i.failure),
          ...added,
        ],
        status: CleanStatus.idle,
        checking: false,
      ),
    );
  }

  void remove(String path) {
    if (state.status == CleanStatus.running) return;
    emit(
      state.copyWith(
        items: [
          for (final i in state.items)
            if (i.path != path) CleanItem(path: i.path, bytes: i.bytes, metadata: i.metadata, failure: i.failure),
        ],
        status: CleanStatus.idle,
      ),
    );
  }

  void clear() {
    if (state.status == CleanStatus.running) return;
    emit(state.copyWith(items: const [], status: CleanStatus.idle));
  }

  Future<void> run() async {
    if (state.status == CleanStatus.running || state.cleanable.isEmpty) return;
    emit(state.copyWith(status: CleanStatus.running, progress: 0));
    final dir = Directory(p.join((await _outputDir()).path, 'clean'));
    await dir.create(recursive: true);
    final stamp = DateTime.now().millisecondsSinceEpoch;

    for (var i = 0; i < state.items.length; i++) {
      if (isClosed) return;
      final item = state.items[i];
      if (item.failure != null || item.metadata == null) continue;
      final out = p.join(dir.path, '${p.basenameWithoutExtension(item.path)}_clean_$stamp-$i${item.metadata!.isPng ? '.png' : '.jpg'}');
      final result = await _cleaner.clean(sourcePath: item.path, outputPath: out);
      if (isClosed) return;
      final items = [...state.items];
      items[i] = item.withResult(result.valueOrNull, result.failureOrNull);
      emit(state.copyWith(items: items, progress: state.progress + 1));
    }
    if (!isClosed) emit(state.copyWith(status: CleanStatus.done));
  }
}

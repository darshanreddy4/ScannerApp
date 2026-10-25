import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

import '../../../core/error/failures.dart';
import '../domain/watermark.dart';
import '../domain/watermark_service.dart';

enum WatermarkStatus { idle, running, done }

class WatermarkInput extends Equatable {
  const WatermarkInput({required this.path, required this.bytes});
  final String path;
  final int bytes;

  String get name => p.basename(path);
  bool get isPdf => p.extension(path).toLowerCase() == '.pdf';

  @override
  List<Object?> get props => [path, bytes];
}

class WatermarkOutcome extends Equatable {
  const WatermarkOutcome({required this.input, this.output, this.failure});
  final WatermarkInput input;
  final WatermarkOutput? output;
  final Failure? failure;

  @override
  List<Object?> get props => [input, output?.path, failure];
}

class WatermarkState extends Equatable {
  const WatermarkState({
    this.inputs = const [],
    this.style = const WatermarkStyle(),
    this.profile = const BusinessProfile(),
    this.status = WatermarkStatus.idle,
    this.progress = 0,
    this.outcomes = const [],
    this.skipped = 0,
    this.failure,
  });

  final List<WatermarkInput> inputs;
  final WatermarkStyle style;
  final BusinessProfile profile;
  final WatermarkStatus status;
  final int progress;
  final List<WatermarkOutcome> outcomes;

  /// Files that were not added because they are not pictures or PDFs.
  final int skipped;
  final Failure? failure;

  List<WatermarkOutput> get outputs => [
    for (final o in outcomes)
      if (o.output != null) o.output!,
  ];

  WatermarkState copyWith({
    List<WatermarkInput>? inputs,
    WatermarkStyle? style,
    BusinessProfile? profile,
    WatermarkStatus? status,
    int? progress,
    List<WatermarkOutcome>? outcomes,
    int? skipped,
    Object? failure = _keep,
  }) => WatermarkState(
    inputs: inputs ?? this.inputs,
    style: style ?? this.style,
    profile: profile ?? this.profile,
    status: status ?? this.status,
    progress: progress ?? this.progress,
    outcomes: outcomes ?? this.outcomes,
    skipped: skipped ?? this.skipped,
    failure: identical(failure, _keep) ? this.failure : failure as Failure?,
  );

  static const _keep = Object();

  @override
  List<Object?> get props => [inputs, style, profile.name, profile.details, profile.logoPath, status, progress, outcomes, skipped, failure];
}

class WatermarkCubit extends Cubit<WatermarkState> {
  WatermarkCubit({required WatermarkService service, required BusinessProfileStore profiles, required Future<Directory> Function() outputDir})
    : _service = service,
      _profiles = profiles,
      _outputDir = outputDir,
      super(const WatermarkState());

  final WatermarkService _service;
  final BusinessProfileStore _profiles;
  final Future<Directory> Function() _outputDir;

  static const maxFiles = 30;
  static const _allowed = {'.jpg', '.jpeg', '.png', '.pdf'};

  Future<void> load() async {
    final profile = await _profiles.load();
    if (isClosed) return;
    emit(state.copyWith(profile: profile));
  }

  Future<void> add(List<String> paths) async {
    final known = {for (final i in state.inputs) i.path};
    final added = <WatermarkInput>[];
    var skipped = 0;
    for (final path in paths) {
      if (known.contains(path)) continue;
      if (!_allowed.contains(p.extension(path).toLowerCase())) {
        skipped++;
        continue;
      }
      if (state.inputs.length + added.length >= maxFiles) break;
      final file = File(path);
      if (!await file.exists()) continue;
      known.add(path);
      added.add(WatermarkInput(path: path, bytes: await file.length()));
    }
    if (isClosed) return;
    emit(state.copyWith(inputs: [...state.inputs, ...added], outcomes: const [], status: WatermarkStatus.idle, skipped: skipped));
  }

  void remove(String path) {
    if (state.status == WatermarkStatus.running) return;
    emit(
      state.copyWith(
        inputs: [
          for (final i in state.inputs)
            if (i.path != path) i,
        ],
        outcomes: const [],
        status: WatermarkStatus.idle,
      ),
    );
  }

  void clear() {
    if (state.status == WatermarkStatus.running) return;
    emit(state.copyWith(inputs: const [], outcomes: const [], status: WatermarkStatus.idle, skipped: 0));
  }

  // region style

  void _style(WatermarkStyle style) {
    if (state.status == WatermarkStatus.running) return;
    emit(state.copyWith(style: style, outcomes: const [], status: WatermarkStatus.idle));
  }

  void setText(String text) => _style(state.style.copyWith(text: text));
  void setLayout(WatermarkLayout layout) =>
      _style(state.style.copyWith(layout: layout, size: layout == WatermarkLayout.tiled ? state.style.size.clamp(0.02, 0.09) : state.style.size));
  void setPosition(WatermarkPosition position) => _style(state.style.copyWith(position: position));
  void setOpacity(double value) => _style(state.style.copyWith(opacity: value));
  void setSize(double value) => _style(state.style.copyWith(size: value));
  void setRotation(double value) => _style(state.style.copyWith(rotation: value));
  void setColor(WatermarkColor color) => _style(state.style.copyWith(color: color));
  void setBold(bool bold) => _style(state.style.copyWith(bold: bold));
  void setLogo(String? path) => _style(state.style.copyWith(logoPath: path));

  /// Uses the saved name, details and logo as the watermark.
  void useBusinessDetails() {
    final profile = state.profile;
    if (profile.isEmpty) return;
    _style(state.style.copyWith(text: profile.text, logoPath: profile.logoPath));
  }

  Future<void> saveProfile(BusinessProfile profile, {String? newLogoSource}) async {
    try {
      final saved = await _profiles.save(profile, newLogoSource: newLogoSource);
      if (isClosed) return;
      emit(state.copyWith(profile: saved));
    } on Object catch (e) {
      if (!isClosed) emit(state.copyWith(failure: StorageFailure('The business details could not be saved.', cause: e)));
    }
  }

  void clearFailure() => emit(state.copyWith(failure: null));

  // endregion

  Future<void> run() async {
    if (state.status == WatermarkStatus.running || state.inputs.isEmpty) return;
    if (state.style.isEmpty) {
      emit(state.copyWith(failure: const ExportFailure('Type the words for the watermark or add a logo first.')));
      return;
    }
    emit(state.copyWith(status: WatermarkStatus.running, progress: 0, outcomes: const [], failure: null));
    final dir = Directory(p.join((await _outputDir()).path, 'watermark'));
    await dir.create(recursive: true);

    final outcomes = <WatermarkOutcome>[];
    for (var i = 0; i < state.inputs.length; i++) {
      if (isClosed) return;
      final input = state.inputs[i];
      final result = await _service.apply(inputPath: input.path, style: state.style, outputDir: dir.path, businessName: state.profile.name);
      outcomes.add(WatermarkOutcome(input: input, output: result.valueOrNull, failure: result.failureOrNull));
      if (isClosed) return;
      emit(state.copyWith(progress: i + 1, outcomes: List.of(outcomes)));
    }
    if (!isClosed) emit(state.copyWith(status: WatermarkStatus.done));
  }
}

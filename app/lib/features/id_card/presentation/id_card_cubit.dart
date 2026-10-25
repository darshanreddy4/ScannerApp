import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

import '../../../core/error/failures.dart';
import '../../photo_tools/domain/crop_math.dart';
import '../../photo_tools/domain/passport_maker.dart';
import '../domain/id_card.dart';

enum CardSideId {
  front('Front'),
  back('Back');

  const CardSideId(this.label);
  final String label;
}

class CardSideState extends Equatable {
  const CardSideState({this.photo, this.view});
  final WorkingPhoto? photo;
  final CropView? view;

  bool get has => photo != null && view != null;

  @override
  List<Object?> get props => [photo?.path, view?.zoom, view?.centerX, view?.centerY];
}

class IdCardState extends Equatable {
  const IdCardState({
    this.front = const CardSideState(),
    this.back = const CardSideState(),
    this.editing,
    this.options = const IdCardOptions(),
    this.busy = false,
    this.result,
    this.failure,
  });

  final CardSideState front;
  final CardSideState back;

  /// The side being cropped, or null on the overview.
  final CardSideId? editing;
  final IdCardOptions options;
  final bool busy;
  final CardSheetFiles? result;
  final Failure? failure;

  CardSideState side(CardSideId id) => id == CardSideId.front ? front : back;

  double get frameW => options.size.widthMm;
  double get frameH => options.size.heightMm;

  IdCardState copyWith({
    CardSideState? front,
    CardSideState? back,
    Object? editing = _keep,
    IdCardOptions? options,
    bool? busy,
    Object? result = _keep,
    Object? failure = _keep,
  }) => IdCardState(
    front: front ?? this.front,
    back: back ?? this.back,
    editing: identical(editing, _keep) ? this.editing : editing as CardSideId?,
    options: options ?? this.options,
    busy: busy ?? this.busy,
    result: identical(result, _keep) ? this.result : result as CardSheetFiles?,
    failure: identical(failure, _keep) ? this.failure : failure as Failure?,
  );

  static const _keep = Object();

  @override
  List<Object?> get props => [front, back, editing, options, busy, result?.pdfPath, failure];
}

class IdCardCubit extends Cubit<IdCardState> {
  IdCardCubit({required IdCardMaker maker, required Future<Directory> Function() workDir}) : _maker = maker, _workDir = workDir, super(const IdCardState());

  final IdCardMaker _maker;
  final Future<Directory> Function() _workDir;
  int _counter = 0;

  Future<String> _next() async {
    final dir = await Directory(p.join((await _workDir()).path, 'id_card')).create(recursive: true);
    return p.join(dir.path, 'work_${DateTime.now().microsecondsSinceEpoch}_${_counter++}.jpg');
  }

  IdCardState _withSide(CardSideId id, CardSideState side, {Object? editing = _same}) =>
      (id == CardSideId.front ? state.copyWith(front: side) : state.copyWith(back: side)).copyWith(
        editing: identical(editing, _same) ? state.editing : editing,
        result: null,
      );

  static const _same = Object();

  void clearFailure() {
    if (state.failure != null) emit(state.copyWith(failure: null));
  }

  /// Loads a photo for [id] and opens the crop.
  Future<void> setPhoto(CardSideId id, String path) async {
    if (state.busy) return;
    emit(state.copyWith(busy: true, failure: null));
    final result = await _maker.prepare(sourcePath: path, outputPath: await _next());
    if (isClosed) return;
    final photo = result.valueOrNull;
    if (photo == null) {
      emit(state.copyWith(busy: false, failure: result.failureOrNull));
      return;
    }
    emit(
      _withSide(
        id,
        CardSideState(photo: photo, view: CropView.initial(photo.width, photo.height)),
        editing: id,
      ).copyWith(busy: false),
    );
  }

  void edit(CardSideId id) {
    if (!state.busy && state.side(id).has) emit(state.copyWith(editing: id));
  }

  void done() => emit(state.copyWith(editing: null));

  void remove(CardSideId id) {
    if (state.busy) return;
    emit(_withSide(id, const CardSideState(), editing: null));
  }

  Future<void> rotate() async {
    final id = state.editing;
    if (id == null || state.busy) return;
    final photo = state.side(id).photo;
    if (photo == null) return;
    emit(state.copyWith(busy: true));
    final result = await _maker.prepare(sourcePath: photo.path, outputPath: await _next(), rotateRight: true);
    if (isClosed) return;
    final turned = result.valueOrNull;
    if (turned == null) {
      emit(state.copyWith(busy: false, failure: result.failureOrNull));
      return;
    }
    emit(_withSide(id, CardSideState(photo: turned, view: CropView.initial(turned.width, turned.height))).copyWith(busy: false));
  }

  /// Moves the photo by a share of the frame width and height (positive moves it right and down).
  void pan(double dxShare, double dyShare) {
    final id = state.editing;
    if (id == null) return;
    final s = state.side(id);
    if (!s.has) return;
    emit(
      _withSide(
        id,
        CardSideState(
          photo: s.photo,
          view: s.view!.panned(dxShare * state.frameW, dyShare * state.frameH, s.photo!.width, s.photo!.height, state.frameW, state.frameH),
        ),
      ),
    );
  }

  void setZoom(double zoom) {
    final id = state.editing;
    if (id == null) return;
    final s = state.side(id);
    if (!s.has) return;
    emit(_withSide(id, CardSideState(photo: s.photo, view: s.view!.withZoom(zoom, s.photo!.width, s.photo!.height, state.frameW, state.frameH))));
  }

  void resetView() {
    final id = state.editing;
    if (id == null) return;
    final s = state.side(id);
    if (!s.has) return;
    emit(_withSide(id, CardSideState(photo: s.photo, view: CropView.initial(s.photo!.width, s.photo!.height))));
  }

  /// A new card size changes the shape of the crop, so every crop starts again.
  void setOptions(IdCardOptions options) {
    if (state.busy) return;
    final sizeChanged = options.size != state.options.size;
    CardSideState fresh(CardSideState s) => s.has ? CardSideState(photo: s.photo, view: CropView.initial(s.photo!.width, s.photo!.height)) : s;
    emit(
      state.copyWith(
        options: options,
        front: sizeChanged ? fresh(state.front) : null,
        back: sizeChanged ? fresh(state.back) : null,
        result: null,
        failure: null,
      ),
    );
  }

  Future<void> create() async {
    if (state.busy) return;
    if (!state.front.has) {
      emit(state.copyWith(failure: const ExportFailure('Add the front of the card first.')));
      return;
    }
    emit(state.copyWith(busy: true, result: null, failure: null));
    CardCrop crop(CardSideState s) {
      final r = s.view!.rect(s.photo!.width, s.photo!.height, state.frameW, state.frameH);
      return CardCrop(path: s.photo!.path, left: r.left, top: r.top, width: r.width, height: r.height);
    }

    final base = (await _next()).replaceAll(RegExp(r'\.jpg$'), '_page');
    final result = await _maker.sheet(sides: [crop(state.front), if (state.back.has) crop(state.back)], options: state.options, outputBase: base);
    if (isClosed) return;
    emit(state.copyWith(busy: false, result: result.valueOrNull, failure: result.failureOrNull));
  }
}

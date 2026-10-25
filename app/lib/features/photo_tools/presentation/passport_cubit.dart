import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

import '../../../core/error/failures.dart';
import '../domain/crop_math.dart';
import '../domain/passport_maker.dart';
import '../domain/photo_compressor.dart';
import '../domain/photo_specs.dart';

enum PassportStep { choose, edit, result }

class PassportState extends Equatable {
  const PassportState({
    this.step = PassportStep.choose,
    this.countryCode = PhotoCatalog.defaultCountryCode,
    required this.spec,
    this.custom,
    this.working,
    this.view,
    this.replaceBackground = false,
    this.background = PhotoBackground.white,
    this.cleanStrength = 50,
    this.dpi = 300,
    this.busy = false,
    this.rendered,
    this.compressNote,
    this.sheet,
    this.failure,
  });

  final PassportStep step;
  final String countryCode;
  final PhotoSpec spec;

  /// The size typed in by the person, kept so it can be picked again.
  final PhotoSpec? custom;
  final WorkingPhoto? working;
  final CropView? view;
  final bool replaceBackground;
  final PhotoBackground background;
  final int cleanStrength;
  final int dpi;
  final bool busy;
  final RenderedPhoto? rendered;

  /// What happened when the photo was compressed for upload.
  final String? compressNote;
  final SheetFiles? sheet;
  final Failure? failure;

  PhotoCountry get country => PhotoCatalog.byCode(countryCode) ?? PhotoCatalog.countries.first;

  /// The frame the crop is calculated in. Only its shape matters, so it is the real size in tenths of a millimetre.
  double get frameW => spec.widthMm * 10;
  double get frameH => spec.heightMm * 10;

  PassportState copyWith({
    PassportStep? step,
    String? countryCode,
    PhotoSpec? spec,
    Object? custom = _keep,
    Object? working = _keep,
    Object? view = _keep,
    bool? replaceBackground,
    PhotoBackground? background,
    int? cleanStrength,
    int? dpi,
    bool? busy,
    Object? rendered = _keep,
    Object? compressNote = _keep,
    Object? sheet = _keep,
    Object? failure = _keep,
  }) => PassportState(
    step: step ?? this.step,
    countryCode: countryCode ?? this.countryCode,
    spec: spec ?? this.spec,
    custom: identical(custom, _keep) ? this.custom : custom as PhotoSpec?,
    working: identical(working, _keep) ? this.working : working as WorkingPhoto?,
    view: identical(view, _keep) ? this.view : view as CropView?,
    replaceBackground: replaceBackground ?? this.replaceBackground,
    background: background ?? this.background,
    cleanStrength: cleanStrength ?? this.cleanStrength,
    dpi: dpi ?? this.dpi,
    busy: busy ?? this.busy,
    rendered: identical(rendered, _keep) ? this.rendered : rendered as RenderedPhoto?,
    compressNote: identical(compressNote, _keep) ? this.compressNote : compressNote as String?,
    sheet: identical(sheet, _keep) ? this.sheet : sheet as SheetFiles?,
    failure: identical(failure, _keep) ? this.failure : failure as Failure?,
  );

  static const _keep = Object();

  @override
  List<Object?> get props => [
    step,
    countryCode,
    spec.id,
    spec.widthMm,
    spec.heightMm,
    spec.exactWidthPx,
    custom?.widthMm,
    working?.path,
    view?.zoom,
    view?.centerX,
    view?.centerY,
    replaceBackground,
    background,
    cleanStrength,
    dpi,
    busy,
    rendered?.path,
    rendered?.bytes,
    compressNote,
    sheet?.pdfPath,
    failure,
  ];
}

class PassportCubit extends Cubit<PassportState> {
  PassportCubit({required PassportMaker maker, required PhotoCompressor compressor, required Future<Directory> Function() workDir, String? countryCode})
    : _maker = maker,
      _compressor = compressor,
      _workDir = workDir,
      super(_initial(countryCode));

  final PassportMaker _maker;
  final PhotoCompressor _compressor;
  final Future<Directory> Function() _workDir;
  int _counter = 0;

  static PassportState _initial(String? code) {
    final country = PhotoCatalog.byCode(code ?? PhotoCatalog.defaultCountryCode) ?? PhotoCatalog.countries.first;
    return PassportState(countryCode: country.code, spec: country.specs.first);
  }

  // region choose

  void selectCountry(String code) {
    final country = PhotoCatalog.byCode(code);
    if (country == null || state.busy) return;
    emit(state.copyWith(countryCode: country.code, spec: country.specs.first));
  }

  void selectSpec(PhotoSpec spec) {
    if (state.busy) return;
    emit(state.copyWith(spec: spec));
  }

  void useCustom(PhotoSpec spec) {
    if (state.busy) return;
    emit(state.copyWith(spec: spec, custom: spec));
  }

  /// Opens the picked photo for cropping.
  Future<void> pickPhoto(String path) async {
    if (state.busy) return;
    emit(state.copyWith(busy: true, failure: null));
    final dir = await _dir();
    final result = await _maker.prepare(sourcePath: path, outputPath: p.join(dir.path, 'work_${DateTime.now().microsecondsSinceEpoch}_${_counter++}.jpg'));
    if (isClosed) return;
    final photo = result.valueOrNull;
    if (photo == null) {
      emit(state.copyWith(busy: false, failure: result.failureOrNull));
      return;
    }
    emit(
      state.copyWith(
        busy: false,
        step: PassportStep.edit,
        working: photo,
        view: CropView.initial(photo.width, photo.height),
        rendered: null,
        sheet: null,
        compressNote: null,
      ),
    );
  }

  // endregion

  // region edit

  Future<void> rotate() async {
    final photo = state.working;
    if (photo == null || state.busy) return;
    emit(state.copyWith(busy: true));
    final dir = await _dir();
    final result = await _maker.prepare(
      sourcePath: photo.path,
      outputPath: p.join(dir.path, 'work_${DateTime.now().microsecondsSinceEpoch}_${_counter++}.jpg'),
      rotateRight: true,
    );
    if (isClosed) return;
    final rotated = result.valueOrNull;
    if (rotated == null) {
      emit(state.copyWith(busy: false, failure: result.failureOrNull));
      return;
    }
    emit(state.copyWith(busy: false, working: rotated, view: CropView.initial(rotated.width, rotated.height)));
  }

  /// Moves the photo by a share of the frame width and height (positive moves the photo right and down).
  void pan(double dxShare, double dyShare) {
    final photo = state.working, view = state.view;
    if (photo == null || view == null) return;
    emit(state.copyWith(view: view.panned(dxShare * state.frameW, dyShare * state.frameH, photo.width, photo.height, state.frameW, state.frameH)));
  }

  void setZoom(double zoom) {
    final photo = state.working, view = state.view;
    if (photo == null || view == null) return;
    emit(state.copyWith(view: view.withZoom(zoom, photo.width, photo.height, state.frameW, state.frameH)));
  }

  void resetView() {
    final photo = state.working;
    if (photo == null) return;
    emit(state.copyWith(view: CropView.initial(photo.width, photo.height)));
  }

  void setReplaceBackground(bool on) => emit(state.copyWith(replaceBackground: on));
  void setBackground(PhotoBackground background) => emit(state.copyWith(background: background));
  void setStrength(int value) => emit(state.copyWith(cleanStrength: value.clamp(0, 100)));
  void setDpi(int dpi) => emit(state.copyWith(dpi: dpi));

  void clearFailure() => emit(state.copyWith(failure: null));

  // endregion

  // region result

  Future<void> create() async {
    final photo = state.working, view = state.view;
    if (photo == null || view == null || state.busy) return;
    emit(state.copyWith(busy: true, failure: null));
    final dir = await _dir();
    final rect = view.rect(photo.width, photo.height, state.frameW, state.frameH);
    final spec = state.spec;
    final result = await _maker.render(
      RenderRequest(
        sourcePath: photo.path,
        left: rect.left,
        top: rect.top,
        width: rect.width,
        height: rect.height,
        outWidth: spec.pixelWidth(state.dpi),
        outHeight: spec.pixelHeight(state.dpi),
        outputPath: p.join(dir.path, 'photo_${DateTime.now().microsecondsSinceEpoch}_${_counter++}.jpg'),
        backgroundArgb: state.replaceBackground ? state.background.argb : null,
        cleanStrength: state.cleanStrength,
      ),
    );
    if (isClosed) return;
    final rendered = result.valueOrNull;
    if (rendered == null) {
      emit(state.copyWith(busy: false, failure: result.failureOrNull));
      return;
    }
    emit(state.copyWith(busy: false, step: PassportStep.result, rendered: rendered, sheet: null, compressNote: null));
  }

  void backToEdit() => emit(state.copyWith(step: PassportStep.edit, sheet: null, compressNote: null));

  /// One step back: the result returns to the crop, the crop to the choice of size.
  void back() {
    switch (state.step) {
      case PassportStep.result:
        backToEdit();
      case PassportStep.edit:
        startOver();
      case PassportStep.choose:
        break;
    }
  }

  void startOver() => emit(PassportState(countryCode: state.countryCode, spec: state.spec, custom: state.custom));

  /// Makes the finished photo fit an upload limit while keeping its exact pixel size.
  Future<void> compressTo(int targetBytes) async {
    final photo = state.rendered;
    if (photo == null || state.busy) return;
    emit(state.copyWith(busy: true, failure: null));
    final dir = await _dir();
    final out = p.join(dir.path, 'photo_${DateTime.now().microsecondsSinceEpoch}_${_counter++}.jpg');
    final result = await _compressor.compress(
      sourcePath: photo.path,
      outputPath: out,
      options: CompressOptions(targetBytes: targetBytes, keepPixelSize: true),
    );
    if (isClosed) return;
    final small = result.valueOrNull;
    if (small == null) {
      emit(state.copyWith(busy: false, failure: result.failureOrNull));
      return;
    }
    emit(
      state.copyWith(
        busy: false,
        rendered: RenderedPhoto(path: small.path, bytes: small.bytes, width: small.width, height: small.height),
        sheet: null,
        compressNote: small.metTarget ? null : 'The smallest this photo can get at ${small.width} x ${small.height} px is a little above the limit.',
      ),
    );
  }

  Future<void> makeSheet({required SheetPaper paper, int? copies}) async {
    final photo = state.rendered;
    if (photo == null || state.busy) return;
    emit(state.copyWith(busy: true, failure: null));
    final dir = await _dir();
    final result = await _maker.sheet(
      photoPath: photo.path,
      spec: state.spec,
      paper: paper,
      copies: copies,
      outputBase: p.join(dir.path, 'sheet_${DateTime.now().microsecondsSinceEpoch}_${_counter++}'),
    );
    if (isClosed) return;
    emit(state.copyWith(busy: false, sheet: result.valueOrNull, failure: result.failureOrNull));
  }

  // endregion

  Future<Directory> _dir() async {
    final dir = Directory(p.join((await _workDir()).path, 'photo_id'));
    await dir.create(recursive: true);
    return dir;
  }
}

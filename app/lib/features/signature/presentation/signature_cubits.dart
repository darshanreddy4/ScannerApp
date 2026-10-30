import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

import '../../../core/error/failures.dart';
import '../../../core/i18n/tr.dart';
import '../domain/signature.dart';

// region hub

class SignatureHubState extends Equatable {
  const SignatureHubState({this.signatures = const [], this.loaded = false, this.filter, this.failure});
  final List<SavedSignature> signatures;
  final bool loaded;

  /// Shows only this kind; null shows all.
  final SignatureKind? filter;
  final Failure? failure;

  List<SavedSignature> get visible => filter == null ? signatures : signatures.where((s) => s.kind == filter).toList();

  /// The label shown for a picture: its name, or its kind and its number among that kind.
  String labelOf(SavedSignature s) {
    if (s.name.isNotEmpty) return s.name;
    final n = signatures.where((e) => e.kind == s.kind).toList().indexWhere((e) => e.id == s.id) + 1;
    return '${tr(s.kind.label)} $n';
  }

  @override
  List<Object?> get props => [
    [for (final s in signatures) (s.id, s.name, s.kind, s.isDefault)],
    loaded,
    filter,
    failure,
  ];
}

class SignatureHubCubit extends Cubit<SignatureHubState> {
  SignatureHubCubit(this._store) : super(const SignatureHubState());
  final SignatureStore _store;

  Future<void> load({Failure? failure}) async {
    final list = await _store.list();
    if (!isClosed) emit(SignatureHubState(signatures: list, loaded: true, filter: state.filter, failure: failure));
  }

  void setFilter(SignatureKind? kind) => emit(SignatureHubState(signatures: state.signatures, loaded: state.loaded, filter: kind));

  Future<void> delete(String id) async {
    await _store.delete(id);
    await load();
  }

  Future<void> rename(String id, String name) async {
    await _store.update(id, name: name);
    await load();
  }

  Future<void> setKind(String id, SignatureKind kind) async {
    await _store.update(id, kind: kind);
    await load();
  }

  Future<void> makeDefault(String id) async {
    await _store.setDefault(id);
    await load();
  }

  /// Moves one place up (-1) or down (+1) in the full list.
  Future<void> shift(String id, int by) async {
    final i = state.signatures.indexWhere((s) => s.id == id);
    if (i < 0) return;
    await _store.move(id, (i + by).clamp(0, state.signatures.length - 1));
    await load();
  }

  Future<void> recolor(String id, InkColor ink) async {
    final r = await _store.recolor(id, ink);
    await load(failure: r.failureOrNull);
  }

  Future<void> duplicate(String id) async {
    final r = await _store.duplicate(id);
    await load(failure: r.failureOrNull);
  }
}

// endregion

// region draw

class SignatureDrawState extends Equatable {
  const SignatureDrawState({this.strokes = const [], this.pen = 3.0, this.ink = InkColor.black, this.busy = false, this.saved, this.failure});

  final List<Stroke> strokes;
  final double pen;
  final InkColor ink;
  final bool busy;
  final SavedSignature? saved;
  final Failure? failure;

  bool get isEmpty => strokes.isEmpty;

  SignatureDrawState copyWith({List<Stroke>? strokes, double? pen, InkColor? ink, bool? busy, Object? saved = _keep, Object? failure = _keep}) =>
      SignatureDrawState(
        strokes: strokes ?? this.strokes,
        pen: pen ?? this.pen,
        ink: ink ?? this.ink,
        busy: busy ?? this.busy,
        saved: identical(saved, _keep) ? this.saved : saved as SavedSignature?,
        failure: identical(failure, _keep) ? this.failure : failure as Failure?,
      );

  static const _keep = Object();

  /// Used by the pad to repaint as the finger moves.
  int get version => strokes.fold<int>(strokes.length, (sum, s) => sum + s.points.length);

  @override
  List<Object?> get props => [version, pen, ink, busy, saved?.id, failure];
}

class SignatureDrawCubit extends Cubit<SignatureDrawState> {
  SignatureDrawCubit({
    required SignatureMaker maker,
    required SignatureStore store,
    required Future<Directory> Function() workDir,
    this.kind = SignatureKind.signature,
  }) : _maker = maker,
       _store = store,
       _workDir = workDir,
       super(const SignatureDrawState());

  final SignatureMaker _maker;
  final SignatureStore _store;
  final Future<Directory> Function() _workDir;
  final SignatureKind kind;

  static const pens = <(String, double)>[('Thin', 2.0), ('Medium', 3.5), ('Thick', 5.5)];

  void begin(double x, double y) {
    if (state.busy) return;
    emit(
      state.copyWith(
        strokes: [
          ...state.strokes,
          Stroke([(x: x, y: y)]),
        ],
      ),
    );
  }

  void extend(double x, double y) {
    if (state.busy || state.strokes.isEmpty) return;
    final last = state.strokes.last;
    final prev = last.points.last;
    if ((prev.x - x).abs() + (prev.y - y).abs() < 1.2) return;
    emit(
      state.copyWith(
        strokes: [
          ...state.strokes.sublist(0, state.strokes.length - 1),
          Stroke([...last.points, (x: x, y: y)]),
        ],
      ),
    );
  }

  void undo() {
    if (state.busy || state.strokes.isEmpty) return;
    emit(state.copyWith(strokes: state.strokes.sublist(0, state.strokes.length - 1)));
  }

  void clear() {
    if (!state.busy) emit(state.copyWith(strokes: const []));
  }

  void setPen(double pen) => emit(state.copyWith(pen: pen));
  void setInk(InkColor ink) => emit(state.copyWith(ink: ink));
  void clearFailure() {
    if (state.failure != null) emit(state.copyWith(failure: null));
  }

  Future<void> save({required double padWidth, required double padHeight}) async {
    if (state.busy) return;
    emit(state.copyWith(busy: true, failure: null));
    final dir = await Directory(p.join((await _workDir()).path, 'signature')).create(recursive: true);
    final out = p.join(dir.path, 'drawn_${DateTime.now().microsecondsSinceEpoch}.png');
    final png = await _maker.fromStrokes(
      strokes: state.strokes,
      padWidth: padWidth,
      padHeight: padHeight,
      penWidth: state.pen,
      ink: state.ink,
      outputPath: out,
    );
    final made = png.valueOrNull;
    if (made == null) {
      if (!isClosed) emit(state.copyWith(busy: false, failure: png.failureOrNull));
      return;
    }
    final saved = await _store.save(made.path, kind: kind);
    if (isClosed) return;
    emit(state.copyWith(busy: false, saved: saved.valueOrNull, failure: saved.failureOrNull));
  }
}

// endregion

// region photo

class SignaturePhotoState extends Equatable {
  const SignaturePhotoState({this.sourcePath, this.preview, this.sensitivity = 0.5, this.ink = InkColor.black, this.busy = false, this.saved, this.failure});

  final String? sourcePath;
  final SignaturePng? preview;
  final double sensitivity;

  /// Null keeps the colour of the pen in the photo.
  final InkColor? ink;
  final bool busy;
  final SavedSignature? saved;
  final Failure? failure;

  SignaturePhotoState copyWith({
    Object? sourcePath = _keep,
    Object? preview = _keep,
    double? sensitivity,
    Object? ink = _keep,
    bool? busy,
    Object? saved = _keep,
    Object? failure = _keep,
  }) => SignaturePhotoState(
    sourcePath: identical(sourcePath, _keep) ? this.sourcePath : sourcePath as String?,
    preview: identical(preview, _keep) ? this.preview : preview as SignaturePng?,
    sensitivity: sensitivity ?? this.sensitivity,
    ink: identical(ink, _keep) ? this.ink : ink as InkColor?,
    busy: busy ?? this.busy,
    saved: identical(saved, _keep) ? this.saved : saved as SavedSignature?,
    failure: identical(failure, _keep) ? this.failure : failure as Failure?,
  );

  static const _keep = Object();

  @override
  List<Object?> get props => [sourcePath, preview?.path, sensitivity, ink, busy, saved?.id, failure];
}

class SignaturePhotoCubit extends Cubit<SignaturePhotoState> {
  SignaturePhotoCubit({
    required SignatureMaker maker,
    required SignatureStore store,
    required Future<Directory> Function() workDir,
    this.kind = SignatureKind.signature,
  }) : _maker = maker,
       _store = store,
       _workDir = workDir,
       super(const SignaturePhotoState());

  final SignatureMaker _maker;
  final SignatureStore _store;
  final Future<Directory> Function() _workDir;
  final SignatureKind kind;
  int _request = 0;

  Future<void> pick(String path) async {
    emit(state.copyWith(sourcePath: path, preview: null, failure: null));
    await _extract();
  }

  Future<void> setSensitivity(double value) async {
    if (state.sourcePath == null) return emit(state.copyWith(sensitivity: value));
    emit(state.copyWith(sensitivity: value));
    await _extract();
  }

  Future<void> setInk(InkColor? ink) async {
    emit(state.copyWith(ink: ink));
    if (state.sourcePath != null) await _extract();
  }

  void clearFailure() {
    if (state.failure != null) emit(state.copyWith(failure: null));
  }

  Future<void> _extract() async {
    final source = state.sourcePath;
    if (source == null) return;
    final mine = ++_request;
    emit(state.copyWith(busy: true, failure: null));
    final dir = await Directory(p.join((await _workDir()).path, 'signature')).create(recursive: true);
    final out = p.join(dir.path, 'photo_${DateTime.now().microsecondsSinceEpoch}_$mine.png');
    final result = await _maker.fromPhoto(sourcePath: source, outputPath: out, sensitivity: state.sensitivity, ink: state.ink);
    if (isClosed || mine != _request) return;
    emit(state.copyWith(busy: false, preview: result.valueOrNull, failure: result.failureOrNull));
  }

  Future<void> save() async {
    final preview = state.preview;
    if (preview == null || state.busy) return;
    emit(state.copyWith(busy: true, failure: null));
    final saved = await _store.save(preview.path, kind: kind);
    if (isClosed) return;
    emit(state.copyWith(busy: false, saved: saved.valueOrNull, failure: saved.failureOrNull));
  }
}

// endregion

// region sign

enum SignStatus { idle, opening, signing, done }

class SignDocumentState extends Equatable {
  const SignDocumentState({
    this.document,
    this.signatures = const [],
    this.selected,
    this.page = 0,
    this.placement = const SignPlacement(),
    this.target = SignPages.thisPage,
    this.status = SignStatus.idle,
    this.done = 0,
    this.total = 0,
    this.result,
    this.failure,
  });

  final SignDocument? document;
  final List<SavedSignature> signatures;
  final SavedSignature? selected;
  final int page;
  final SignPlacement placement;
  final SignPages target;
  final SignStatus status;
  final int done;
  final int total;
  final SignedFile? result;
  final Failure? failure;

  int get pageCount => document?.pages.length ?? 0;
  bool get busy => status == SignStatus.opening || status == SignStatus.signing;

  SignDocumentState copyWith({
    Object? document = _keep,
    List<SavedSignature>? signatures,
    Object? selected = _keep,
    int? page,
    SignPlacement? placement,
    SignPages? target,
    SignStatus? status,
    int? done,
    int? total,
    Object? result = _keep,
    Object? failure = _keep,
  }) => SignDocumentState(
    document: identical(document, _keep) ? this.document : document as SignDocument?,
    signatures: signatures ?? this.signatures,
    selected: identical(selected, _keep) ? this.selected : selected as SavedSignature?,
    page: page ?? this.page,
    placement: placement ?? this.placement,
    target: target ?? this.target,
    status: status ?? this.status,
    done: done ?? this.done,
    total: total ?? this.total,
    result: identical(result, _keep) ? this.result : result as SignedFile?,
    failure: identical(failure, _keep) ? this.failure : failure as Failure?,
  );

  static const _keep = Object();

  @override
  List<Object?> get props => [
    document?.name,
    pageCount,
    signatures.map((s) => s.id).toList(),
    selected?.id,
    page,
    placement,
    target,
    status,
    done,
    total,
    result?.path,
    failure,
  ];
}

class SignDocumentCubit extends Cubit<SignDocumentState> {
  SignDocumentCubit({required DocumentSigner signer, required SignatureStore store, required Future<Directory> Function() outputDir})
    : _signer = signer,
      _store = store,
      _outputDir = outputDir,
      super(const SignDocumentState());

  final DocumentSigner _signer;
  final SignatureStore _store;
  final Future<Directory> Function() _outputDir;

  Future<void> loadSignatures() async {
    final list = await _store.list();
    if (isClosed) return;
    final keep = state.selected == null ? null : list.where((s) => s.id == state.selected!.id).firstOrNull;
    emit(
      state.copyWith(signatures: list, selected: keep ?? list.where((s) => s.isDefault && s.kind == SignatureKind.signature).firstOrNull ?? list.firstOrNull),
    );
  }

  Future<void> open(String path) async {
    if (state.busy) return;
    emit(state.copyWith(status: SignStatus.opening, failure: null, result: null));
    final result = await _signer.open(path);
    if (isClosed) return;
    final doc = result.valueOrNull;
    if (doc == null) {
      emit(state.copyWith(status: SignStatus.idle, failure: result.failureOrNull));
      return;
    }
    emit(
      state.copyWith(
        document: doc,
        page: 0,
        placement: const SignPlacement(),
        target: doc.pages.length > 1 ? SignPages.lastPage : SignPages.thisPage,
        status: SignStatus.idle,
        result: null,
      ),
    );
  }

  void select(SavedSignature signature) => _edit((s) => s.copyWith(selected: signature));
  void setPage(int page) => _edit((s) => s.copyWith(page: page.clamp(0, s.pageCount - 1)));
  void setTarget(SignPages target) => _edit((s) => s.copyWith(target: target));

  /// Moves the signature by a share of the page width and height.
  void move(double dxShare, double dyShare) => _edit(
    (s) => s.copyWith(
      placement: _fit(s, s.placement.copyWith(centerX: s.placement.centerX + dxShare, centerY: s.placement.centerY + dyShare)),
    ),
  );

  void resize(double width) => _edit((s) => s.copyWith(placement: _fit(s, s.placement.copyWith(width: width))));

  SignPlacement _fit(SignDocumentState s, SignPlacement placement) {
    final sig = s.selected, doc = s.document;
    if (sig == null || doc == null) return placement;
    return placement.clamped(aspect: sig.aspect, pageAspect: doc.aspectOf(s.page));
  }

  void clearFailure() {
    if (state.failure != null) emit(state.copyWith(failure: null));
  }

  void _edit(SignDocumentState Function(SignDocumentState s) change) {
    if (state.busy || state.document == null) return;
    emit(change(state).copyWith(result: null));
  }

  Future<void> sign() async {
    final doc = state.document, sig = state.selected;
    if (state.busy || doc == null) return;
    if (sig == null) {
      emit(state.copyWith(failure: const ExportFailure('Create a signature first.')));
      return;
    }
    final pages = state.target.resolve(current: state.page, count: doc.pages.length);
    emit(state.copyWith(status: SignStatus.signing, done: 0, total: pages.length, result: null, failure: null));
    final dir = p.join((await _outputDir()).path, 'signed');
    final result = await _signer.sign(
      document: doc,
      signaturePath: sig.path,
      placement: _fit(state, state.placement),
      pages: pages,
      outputDir: dir,
      onProgress: (done, total) {
        if (!isClosed) emit(state.copyWith(done: done, total: total));
      },
    );
    if (isClosed) return;
    emit(state.copyWith(status: SignStatus.done, result: result.valueOrNull, failure: result.failureOrNull));
  }
}

// endregion

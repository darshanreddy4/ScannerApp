import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

import '../../../core/error/failures.dart';
import '../domain/pdf_protector.dart';

enum PasswordStatus { idle, checking, working, done }

class PdfPasswordState extends Equatable {
  const PdfPasswordState({
    this.path,
    this.protection,
    this.password = '',
    this.confirm = '',
    this.status = PasswordStatus.idle,
    this.result,
    this.lockedNow = false,
    this.failure,
  });

  final String? path;
  final PdfProtectionStatus? protection;
  final String password;
  final String confirm;
  final PasswordStatus status;
  final ProtectedPdf? result;

  /// The result is a freshly locked file (as opposed to an unlocked one).
  final bool lockedNow;
  final Failure? failure;

  String? get name => path == null ? null : p.basename(path!);
  bool get busy => status == PasswordStatus.checking || status == PasswordStatus.working;

  /// The chosen file has no protection yet, so it can be locked.
  bool get canLock => protection != null && !protection!.encrypted;
  bool get canUnlock => protection != null && protection!.encrypted;
  bool get needsPassword => protection?.needsPassword ?? false;

  static const minLength = 4;

  /// Why the button cannot be used yet, or null when it can.
  String? get blocker {
    if (path == null || protection == null) return 'Choose a PDF first.';
    if (canLock) {
      if (password.length < minLength) return 'Use at least $minLength characters.';
      if (password != confirm) return 'The two passwords are not the same.';
      return null;
    }
    if (needsPassword && password.isEmpty) return 'Type the password.';
    return null;
  }

  PdfPasswordState copyWith({
    Object? path = _keep,
    Object? protection = _keep,
    String? password,
    String? confirm,
    PasswordStatus? status,
    Object? result = _keep,
    bool? lockedNow,
    Object? failure = _keep,
  }) => PdfPasswordState(
    path: identical(path, _keep) ? this.path : path as String?,
    protection: identical(protection, _keep) ? this.protection : protection as PdfProtectionStatus?,
    password: password ?? this.password,
    confirm: confirm ?? this.confirm,
    status: status ?? this.status,
    result: identical(result, _keep) ? this.result : result as ProtectedPdf?,
    lockedNow: lockedNow ?? this.lockedNow,
    failure: identical(failure, _keep) ? this.failure : failure as Failure?,
  );

  static const _keep = Object();

  @override
  List<Object?> get props => [path, protection?.encrypted, protection?.needsPassword, password, confirm, status, result?.path, lockedNow, failure];
}

class PdfPasswordCubit extends Cubit<PdfPasswordState> {
  PdfPasswordCubit({required PdfProtector protector, required Future<Directory> Function() outputDir})
    : _protector = protector,
      _outputDir = outputDir,
      super(const PdfPasswordState());

  final PdfProtector _protector;
  final Future<Directory> Function() _outputDir;

  Future<void> pick(String path) async {
    if (state.busy) return;
    emit(PdfPasswordState(path: path, status: PasswordStatus.checking));
    final result = await _protector.inspect(path);
    if (isClosed) return;
    final info = result.valueOrNull;
    emit(info == null ? PdfPasswordState(failure: result.failureOrNull) : PdfPasswordState(path: path, protection: info));
  }

  void clear() {
    if (!state.busy) emit(const PdfPasswordState());
  }

  void setPassword(String value) {
    if (!state.busy) emit(state.copyWith(password: value, status: PasswordStatus.idle, result: null, failure: null));
  }

  void setConfirm(String value) {
    if (!state.busy) emit(state.copyWith(confirm: value, status: PasswordStatus.idle, result: null, failure: null));
  }

  Future<void> run() async {
    final path = state.path;
    if (state.busy || path == null) return;
    final blocked = state.blocker;
    if (blocked != null) {
      emit(state.copyWith(failure: PasswordFailure(blocked)));
      return;
    }
    final locking = state.canLock;
    emit(state.copyWith(status: PasswordStatus.working, result: null, failure: null));
    final dir = await Directory(p.join((await _outputDir()).path, 'pdf_password')).create(recursive: true);
    final base = p.basenameWithoutExtension(path);
    final out = p.join(dir.path, '${base}_${locking ? 'locked' : 'unlocked'}_${DateTime.now().millisecondsSinceEpoch}.pdf');
    final result = locking
        ? await _protector.lock(sourcePath: path, outputPath: out, password: state.password)
        : await _protector.unlock(sourcePath: path, outputPath: out, password: state.password);
    if (isClosed) return;
    emit(state.copyWith(status: PasswordStatus.done, result: result.valueOrNull, lockedNow: locking, failure: result.failureOrNull));
  }
}

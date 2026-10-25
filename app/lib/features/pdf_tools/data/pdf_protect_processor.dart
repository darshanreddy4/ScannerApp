import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../../../core/error/failures.dart';
import '../../../core/error/result.dart';
import '../domain/pdf_protector.dart';
import 'security/pdf_model.dart';
import 'security/pdf_rewriter.dart';
import 'security/pdf_security.dart';

class PdfProtectProcessor implements PdfProtector {
  const PdfProtectProcessor();

  static const maxBytes = 150 * 1024 * 1024;

  Future<Uint8List> _read(String path) async {
    final file = File(path);
    if (!await file.exists()) throw const ExportFailure('The file could not be found.');
    if (await file.length() > maxBytes) throw const ExportFailure('This PDF is larger than 150 MB. Compress it first.');
    return file.readAsBytes();
  }

  @override
  Future<Result<PdfProtectionStatus>> inspect(String path) => guard(() async {
    final bytes = await _read(path);
    final r = await Isolate.run(() => _run(() => inspectPdf(bytes)));
    final info = _unwrap(r);
    return PdfProtectionStatus(encrypted: info.encrypted, needsPassword: info.needsPassword, bytes: bytes.length);
  }, onError: _unexpected);

  @override
  Future<Result<ProtectedPdf>> lock({required String sourcePath, required String outputPath, required String password}) => guard(() async {
    if (password.isEmpty) throw const PasswordFailure('Type a password first.');
    final bytes = await _read(sourcePath);
    final out = _unwrap(await Isolate.run(() => _run(() => lockPdf(bytes, password: password))));
    await File(outputPath).writeAsBytes(out, flush: true);
    return ProtectedPdf(path: outputPath, bytes: out.length, originalBytes: bytes.length);
  }, onError: _unexpected);

  @override
  Future<Result<ProtectedPdf>> unlock({required String sourcePath, required String outputPath, required String password}) => guard(() async {
    final bytes = await _read(sourcePath);
    final out = _unwrap(await Isolate.run(() => _run(() => unlockPdf(bytes, password: password))));
    await File(outputPath).writeAsBytes(out, flush: true);
    return ProtectedPdf(path: outputPath, bytes: out.length, originalBytes: bytes.length);
  }, onError: _unexpected);

  static Failure _unexpected(Object e) => ExportFailure('The PDF could not be processed.', cause: e);
}

/// Errors cross the isolate boundary as plain text so they arrive intact.
typedef _Outcome<T> = ({T? value, Failure? failure});

_Outcome<T> _run<T>(T Function() body) {
  try {
    return (value: body(), failure: null);
  } on WrongPasswordException {
    return (value: null, failure: const PasswordFailure('That password is not correct.'));
  } on UnsupportedProtectionException catch (e) {
    return (value: null, failure: ExportFailure(e.message));
  } on NotProtectedException {
    return (value: null, failure: const ExportFailure('This PDF has no password, so there is nothing to unlock.'));
  } on AlreadyProtectedException {
    return (value: null, failure: const ExportFailure('This PDF already has a password. Unlock it first to set a new one.'));
  } on PdfFormatException {
    return (value: null, failure: const ExportFailure('This file is not a readable PDF. It may be damaged.'));
  } on FormatException {
    return (value: null, failure: const ExportFailure('This file is not a readable PDF. It may be damaged.'));
  }
}

T _unwrap<T>(_Outcome<T> r) {
  final f = r.failure;
  if (f != null) throw f;
  return r.value as T;
}

import '../../../core/error/result.dart';

class PdfProtectionStatus {
  const PdfProtectionStatus({required this.encrypted, required this.needsPassword, required this.bytes});

  /// The file has a password or restrictions.
  final bool encrypted;

  /// A password is needed to open it. False for files that only restrict printing or copying.
  final bool needsPassword;
  final int bytes;
}

class ProtectedPdf {
  const ProtectedPdf({required this.path, required this.bytes, required this.originalBytes});
  final String path;
  final int bytes;
  final int originalBytes;
}

abstract interface class PdfProtector {
  Future<Result<PdfProtectionStatus>> inspect(String path);

  /// Writes a copy that needs [password] to open. Text, images and links stay as they are.
  Future<Result<ProtectedPdf>> lock({required String sourcePath, required String outputPath, required String password});

  /// Writes a copy without password or restrictions. Fails with a PasswordFailure when [password] is wrong.
  Future<Result<ProtectedPdf>> unlock({required String sourcePath, required String outputPath, required String password});
}

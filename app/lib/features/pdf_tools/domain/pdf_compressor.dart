import '../../../core/error/result.dart';

class PdfCompressOptions {
  const PdfCompressOptions({this.targetBytes});

  /// The result should be at most this many bytes. Null means a balanced setting without a limit.
  final int? targetBytes;
}

class CompressedPdf {
  const CompressedPdf({
    required this.path,
    required this.bytes,
    required this.originalBytes,
    required this.pages,
    required this.metTarget,
    this.unchanged = false,
  });

  final String path;
  final int bytes;
  final int originalBytes;
  final int pages;

  /// False when the smallest acceptable setting still gives a larger file than asked for.
  final bool metTarget;

  /// The file was left as it is, either because it already fits or because it could not be made smaller.
  final bool unchanged;

  int get savedBytes => originalBytes - bytes;
}

abstract interface class PdfCompressor {
  /// [onProgress] reports which of the [attempts] quality settings is being tried.
  Future<Result<CompressedPdf>> compress({
    required String sourcePath,
    required String outputPath,
    required PdfCompressOptions options,
    void Function(int attempt, int attempts)? onProgress,
  });
}

import '../../../core/error/result.dart';

enum PhotoFormat {
  jpg('JPG', 'jpg', 'image/jpeg'),
  png('PNG', 'png', 'image/png');

  const PhotoFormat(this.label, this.extension, this.mimeType);
  final String label;
  final String extension;
  final String mimeType;
}

class CompressOptions {
  const CompressOptions({this.targetBytes, this.maxSide, this.format = PhotoFormat.jpg, this.keepPixelSize = false});

  /// The result should be at most this many bytes. Null means only resize and convert.
  final int? targetBytes;

  /// Longest side in pixels after resizing; null keeps the original size.
  final int? maxSide;
  final PhotoFormat format;

  /// For photos that must keep exact pixel dimensions: only quality is lowered, the picture is never made smaller.
  final bool keepPixelSize;
}

class CompressedPhoto {
  const CompressedPhoto({
    required this.path,
    required this.bytes,
    required this.width,
    required this.height,
    required this.originalBytes,
    required this.metTarget,
    this.quality,
  });

  final String path;
  final int bytes;
  final int width;
  final int height;
  final int originalBytes;

  /// False when the smallest acceptable picture is still bigger than the target.
  final bool metTarget;

  /// JPEG quality that was used; null for PNG.
  final int? quality;
}

abstract interface class PhotoCompressor {
  Future<Result<CompressedPhoto>> compress({required String sourcePath, required String outputPath, required CompressOptions options});
}

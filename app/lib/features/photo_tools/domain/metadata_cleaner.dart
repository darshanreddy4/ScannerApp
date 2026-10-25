import '../../../core/error/result.dart';

/// What a photo file carries besides the picture.
class PhotoMetadata {
  const PhotoMetadata({
    this.hasLocation = false,
    this.camera,
    this.takenAt,
    this.software,
    this.hasOtherData = false,
    this.hiddenBytes = 0,
    this.isPng = false,
  });

  /// GPS position of where the photo was taken.
  final bool hasLocation;
  final String? camera;
  final String? takenAt;
  final String? software;

  /// Other embedded data such as XMP, thumbnails, comments or text chunks.
  final bool hasOtherData;

  /// How many bytes cleaning would remove.
  final int hiddenBytes;
  final bool isPng;

  bool get isClean => !hasLocation && camera == null && takenAt == null && software == null && !hasOtherData && hiddenBytes == 0;
}

class CleanedPhoto {
  const CleanedPhoto({required this.path, required this.bytes, required this.removedBytes});
  final String path;
  final int bytes;
  final int removedBytes;
}

abstract interface class MetadataCleaner {
  Future<Result<PhotoMetadata>> inspect(String path);

  /// Writes a copy of the photo without private data. The picture itself is not re-compressed.
  Future<Result<CleanedPhoto>> clean({required String sourcePath, required String outputPath});
}

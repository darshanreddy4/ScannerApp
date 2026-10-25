import '../../../core/error/result.dart';
import 'watermark.dart';

class WatermarkOutput {
  const WatermarkOutput({required this.path, required this.mimeType, required this.name, this.pages = 1});
  final String path;
  final String mimeType;
  final String name;
  final int pages;

  bool get isPdf => mimeType == 'application/pdf';
}

abstract interface class WatermarkService {
  /// Adds the watermark to a picture, or to every page of a PDF, and saves the result in [outputDir].
  Future<Result<WatermarkOutput>> apply({
    required String inputPath,
    required WatermarkStyle style,
    required String outputDir,
    String businessName = '',
    void Function(int done, int total)? onProgress,
  });
}

abstract interface class BusinessProfileStore {
  Future<BusinessProfile> load();

  /// Saves the details; a picked logo is copied into the app so it stays available.
  Future<BusinessProfile> save(BusinessProfile profile, {String? newLogoSource});
}

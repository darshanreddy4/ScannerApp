import '../../../../core/error/result.dart';
import '../../../documents/domain/entities/scanned_document.dart';
import '../entities/export_options.dart';

abstract interface class ExportRepository {
  /// Builds the file and returns its absolute path (app temp storage).
  Future<Result<String>> export({required ScannedDocument document, required ExportFormat format, required ExportQuality quality});
}

abstract interface class ShareService {
  Future<Result<void>> shareFile({required String path, required String mimeType, String? subject});

  Future<Result<void>> shareFiles({required List<String> paths, required String mimeType, String? subject});

  /// Opens the share sheet with plain text, such as a message with a link.
  Future<Result<void>> shareText({required String text, String? subject});
}

abstract interface class SaveService {
  /// Opens the system file saver (Files, Drive or any storage provider). Returns false if cancelled.
  Future<Result<bool>> saveToFiles({required String sourcePath, required String fileName, required String mimeType});

  /// Adds the images to the phone's photo gallery.
  Future<Result<int>> saveImagesToGallery(List<String> paths);
}

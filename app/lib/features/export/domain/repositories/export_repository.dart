import '../../../../core/error/result.dart';
import '../../../documents/domain/entities/scanned_document.dart';
import '../entities/export_options.dart';

abstract interface class ExportRepository {
  /// Builds the file and returns its absolute path (app temp storage).
  Future<Result<String>> export({
    required ScannedDocument document,
    required ExportFormat format,
    required ExportQuality quality,
  });
}

abstract interface class ShareService {
  Future<Result<void>> shareFile({required String path, required String mimeType, String? subject});
}

import '../../../../core/error/result.dart';
import '../../../documents/domain/entities/scanned_document.dart';
import '../entities/export_options.dart';
import '../repositories/export_repository.dart';

class ExportDocument {
  const ExportDocument(this._repo);
  final ExportRepository _repo;

  Future<Result<String>> call({
    required ScannedDocument document,
    required ExportFormat format,
    required ExportQuality quality,
  }) =>
      _repo.export(document: document, format: format, quality: quality);
}

class ShareFile {
  const ShareFile(this._service);
  final ShareService _service;

  Future<Result<void>> call({required String path, required ExportFormat format, String? subject}) =>
      _service.shareFile(path: path, mimeType: format.mimeType, subject: subject);
}

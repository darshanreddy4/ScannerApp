import '../../../../core/error/result.dart';
import '../entities/scanned_document.dart';

abstract interface class DocumentRepository {
  Future<Result<List<ScannedDocument>>> listDocuments();
  Future<Result<ScannedDocument>> getDocument(String id);
  Future<Result<ScannedDocument>> saveDocument({required String title, required List<NewPage> pages});
  Future<Result<ScannedDocument>> renameDocument(String id, String title);
  Future<Result<void>> deleteDocument(String id);
}

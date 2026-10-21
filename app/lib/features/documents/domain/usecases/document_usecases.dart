import '../../../../core/error/result.dart';
import '../entities/scanned_document.dart';
import '../repositories/document_repository.dart';

class ListDocuments {
  const ListDocuments(this._repo);
  final DocumentRepository _repo;
  Future<Result<List<ScannedDocument>>> call() => _repo.listDocuments();
}

class GetDocument {
  const GetDocument(this._repo);
  final DocumentRepository _repo;
  Future<Result<ScannedDocument>> call(String id) => _repo.getDocument(id);
}

class SaveDocument {
  const SaveDocument(this._repo);
  final DocumentRepository _repo;
  Future<Result<ScannedDocument>> call({required String title, required List<NewPage> pages}) =>
      _repo.saveDocument(title: title, pages: pages);
}

class RenameDocument {
  const RenameDocument(this._repo);
  final DocumentRepository _repo;
  Future<Result<ScannedDocument>> call(String id, String title) => _repo.renameDocument(id, title);
}

class DeleteDocument {
  const DeleteDocument(this._repo);
  final DocumentRepository _repo;
  Future<Result<void>> call(String id) => _repo.deleteDocument(id);
}

import '../../../../core/error/result.dart';
import '../entities/compress_level.dart';
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
  Future<Result<ScannedDocument>> call({required String title, required List<NewPage> pages, String? folderId}) =>
      _repo.saveDocument(title: title, pages: pages, folderId: folderId);
}

class RenameDocument {
  const RenameDocument(this._repo);
  final DocumentRepository _repo;
  Future<Result<ScannedDocument>> call(String id, String title) => _repo.renameDocument(id, title);
}

class UpdateDocument {
  const UpdateDocument(this._repo);
  final DocumentRepository _repo;
  Future<Result<ScannedDocument>> call({required String id, required String title, required List<NewPage> pages}) =>
      _repo.updateDocument(id: id, title: title, pages: pages);
}

class UpdateDocumentMeta {
  const UpdateDocumentMeta(this._repo);
  final DocumentRepository _repo;
  Future<Result<ScannedDocument>> call(
    String id, {
    bool? favorite,
    bool? pinned,
    bool? locked,
    List<String>? tags,
    DateTime? date,
    DateTime? expires,
    bool clearExpiry = false,
  }) => _repo.updateMeta(id, favorite: favorite, pinned: pinned, locked: locked, tags: tags, date: date, expires: expires, clearExpiry: clearExpiry);
}

class DuplicateDocument {
  const DuplicateDocument(this._repo);
  final DocumentRepository _repo;
  Future<Result<ScannedDocument>> call(String id) => _repo.duplicateDocument(id);
}

class SplitDocument {
  const SplitDocument(this._repo);
  final DocumentRepository _repo;
  Future<Result<ScannedDocument>> call({required String id, required int startPage}) => _repo.splitDocument(id: id, startPage: startPage);
}

class CompressDocument {
  const CompressDocument(this._repo);
  final DocumentRepository _repo;
  Future<Result<ScannedDocument>> call({required String id, required CompressLevel level}) => _repo.compressDocument(id: id, level: level);
}

class GetDocumentSize {
  const GetDocumentSize(this._repo);
  final DocumentRepository _repo;
  Future<Result<int>> call(String id) => _repo.documentSize(id);
}

class MoveDocument {
  const MoveDocument(this._repo);
  final DocumentRepository _repo;
  Future<Result<void>> call(String id, String? folderId) => _repo.moveDocument(id, folderId);
}

class MergeDocuments {
  const MergeDocuments(this._repo);
  final DocumentRepository _repo;
  Future<Result<ScannedDocument>> call({required List<String> ids, required String title, String? folderId, required bool deleteOriginals}) =>
      _repo.mergeDocuments(ids: ids, title: title, folderId: folderId, deleteOriginals: deleteOriginals);
}

class DeleteDocument {
  const DeleteDocument(this._repo);
  final DocumentRepository _repo;
  Future<Result<void>> call(String id) => _repo.deleteDocument(id);
}

class ListFolders {
  const ListFolders(this._repo);
  final FolderRepository _repo;
  Future<Result<List<Folder>>> call() => _repo.listFolders();
}

class CreateFolder {
  const CreateFolder(this._repo);
  final FolderRepository _repo;
  Future<Result<Folder>> call(String name, {FolderStyle style = const FolderStyle()}) => _repo.createFolder(name, style: style);
}

class RenameFolder {
  const RenameFolder(this._repo);
  final FolderRepository _repo;
  Future<Result<void>> call(String id, String name) => _repo.renameFolder(id, name);
}

class UpdateFolderMeta {
  const UpdateFolderMeta(this._repo);
  final FolderRepository _repo;
  Future<Result<void>> call(String id, {bool? favorite, bool? locked, FolderStyle? style}) =>
      _repo.updateFolderMeta(id, favorite: favorite, locked: locked, style: style);
}

class DeleteFolder {
  const DeleteFolder(this._repo);
  final FolderRepository _repo;
  Future<Result<void>> call(String id) => _repo.deleteFolder(id);
}

/// Removes every document and folder (the "delete all my data" request).
class DeleteAllData {
  const DeleteAllData(this._documents, this._folders);
  final DocumentRepository _documents;
  final FolderRepository _folders;

  Future<Result<void>> call() async {
    final docs = await _documents.listDocuments();
    final failure = docs.failureOrNull;
    if (failure != null) return Err(failure);
    for (final doc in docs.valueOrNull ?? const <ScannedDocument>[]) {
      final r = await _documents.deleteDocument(doc.id);
      if (r.failureOrNull != null) return r;
    }
    final folders = await _folders.listFolders();
    for (final f in folders.valueOrNull ?? const <Folder>[]) {
      final r = await _folders.deleteFolder(f.id);
      if (r.failureOrNull != null) return r;
    }
    return const Ok(null);
  }
}

import '../../../../core/error/failures.dart';
import '../../../../core/error/result.dart';
import '../../domain/entities/scanned_document.dart';
import '../../domain/repositories/document_repository.dart';
import '../datasources/document_local_data_source.dart';

class DocumentRepositoryImpl implements DocumentRepository {
  DocumentRepositoryImpl(this._local);

  final DocumentLocalDataSource _local;

  Failure _db(Object e) => DatabaseFailure('Could not access your document library.', cause: e);

  @override
  Future<Result<List<ScannedDocument>>> listDocuments() => guard(_local.list, onError: _db);

  @override
  Future<Result<ScannedDocument>> getDocument(String id) => guard(() async {
        final doc = await _local.get(id);
        if (doc == null) throw const DatabaseFailure('This document no longer exists.');
        return doc;
      }, onError: _db);

  @override
  Future<Result<ScannedDocument>> saveDocument({required String title, required List<NewPage> pages}) =>
      guard(() async {
        if (pages.isEmpty) throw const StorageFailure('Add at least one page before saving.');
        return _local.insert(title.trim().isEmpty ? 'Untitled scan' : title.trim(), pages);
      }, onError: _db);

  @override
  Future<Result<ScannedDocument>> renameDocument(String id, String title) => guard(() async {
        final trimmed = title.trim();
        if (trimmed.isEmpty) throw const StorageFailure('The title cannot be empty.');
        await _local.rename(id, trimmed);
        return (await _local.get(id))!;
      }, onError: _db);

  @override
  Future<Result<void>> deleteDocument(String id) => guard(() => _local.delete(id), onError: _db);
}

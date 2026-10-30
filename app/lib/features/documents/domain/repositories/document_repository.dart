import '../../../../core/error/result.dart';
import '../entities/compress_level.dart';
import '../entities/scanned_document.dart';

abstract interface class DocumentRepository {
  Future<Result<List<ScannedDocument>>> listDocuments();
  Future<Result<ScannedDocument>> getDocument(String id);
  Future<Result<ScannedDocument>> saveDocument({required String title, required List<NewPage> pages, String? folderId});
  Future<Result<ScannedDocument>> renameDocument(String id, String title);

  /// Replaces the title and all pages of an existing document (end-to-end edit).
  Future<Result<ScannedDocument>> updateDocument({required String id, required String title, required List<NewPage> pages});
  Future<Result<void>> moveDocument(String id, String? folderId);

  /// Changes only the given fields. [date] sets the document's created and updated time; [expires] sets when it stops being valid and [clearExpiry] removes that.
  Future<Result<ScannedDocument>> updateMeta(
    String id, {
    bool? favorite,
    bool? pinned,
    bool? locked,
    List<String>? tags,
    DateTime? date,
    DateTime? expires,
    bool clearExpiry = false,
  });

  Future<Result<ScannedDocument>> duplicateDocument(String id);

  /// The pages from [startPage] (1-based, 2 or more) onwards move to a new document; the rest stay.
  Future<Result<ScannedDocument>> splitDocument({required String id, required int startPage});

  /// Re-encodes the pages smaller. The original photos are replaced by the smaller version.
  Future<Result<ScannedDocument>> compressDocument({required String id, required CompressLevel level});

  Future<Result<int>> documentSize(String id);

  /// Combines the pages of [ids] (in the given order) into a new document.
  Future<Result<ScannedDocument>> mergeDocuments({required List<String> ids, required String title, String? folderId, required bool deleteOriginals});
  Future<Result<void>> deleteDocument(String id);
}

abstract interface class FolderRepository {
  Future<Result<List<Folder>>> listFolders();
  Future<Result<Folder>> createFolder(String name, {FolderStyle style = const FolderStyle()});
  Future<Result<void>> renameFolder(String id, String name);

  /// Changes only the given fields.
  Future<Result<void>> updateFolderMeta(String id, {bool? favorite, bool? locked, FolderStyle? style});

  /// Documents inside the folder are kept and moved back to the root.
  Future<Result<void>> deleteFolder(String id);
}

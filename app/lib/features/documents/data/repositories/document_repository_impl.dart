import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/error/result.dart';
import '../../domain/entities/compress_level.dart';
import '../../domain/entities/scanned_document.dart';
import '../../domain/repositories/document_repository.dart';
import '../datasources/document_local_data_source.dart';
import '../document_compressor.dart';

NewPage _toNewPage(DocumentPage p) => NewPage(imagePath: p.imagePath, rawPath: p.rawPath, width: p.width, height: p.height, edit: p.edit);

class DocumentRepositoryImpl implements DocumentRepository, FolderRepository {
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
  Future<Result<ScannedDocument>> saveDocument({required String title, required List<NewPage> pages, String? folderId}) => guard(() async {
    if (pages.isEmpty) throw const StorageFailure('Add at least one page before saving.');
    return _local.insert(title.trim().isEmpty ? 'Untitled scan' : title.trim(), pages, folderId);
  }, onError: _db);

  @override
  Future<Result<ScannedDocument>> renameDocument(String id, String title) => guard(() async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) throw const StorageFailure('The title cannot be empty.');
    await _local.rename(id, trimmed);
    return (await _local.get(id))!;
  }, onError: _db);

  @override
  Future<Result<ScannedDocument>> updateDocument({required String id, required String title, required List<NewPage> pages}) => guard(() async {
    if (pages.isEmpty) throw const StorageFailure('A document needs at least one page.');
    if (await _local.get(id) == null) throw const DatabaseFailure('This document no longer exists.');
    return _local.replacePages(id, title.trim().isEmpty ? 'Untitled scan' : title.trim(), pages);
  }, onError: _db);

  @override
  Future<Result<void>> moveDocument(String id, String? folderId) => guard(() => _local.move(id, folderId), onError: _db);

  @override
  Future<Result<ScannedDocument>> mergeDocuments({required List<String> ids, required String title, String? folderId, required bool deleteOriginals}) =>
      guard(() async {
        if (ids.length < 2) throw const StorageFailure('Select at least two documents to merge.');
        final pages = <NewPage>[];
        var anyLocked = false;
        for (final id in ids) {
          final doc = await _local.get(id);
          if (doc == null) throw const DatabaseFailure('One of the selected documents no longer exists.');
          anyLocked = anyLocked || doc.locked;
          pages.addAll(doc.pages.map(_toNewPage));
        }
        var merged = await _local.insert(title.trim().isEmpty ? 'Merged document' : title.trim(), pages, folderId);
        if (anyLocked) {
          await _local.updateMeta(merged.id, locked: true);
          merged = (await _local.get(merged.id))!;
        }
        if (deleteOriginals) {
          for (final id in ids) {
            try {
              await _local.delete(id);
            } catch (_) {
              // The merged copy is already saved; a leftover original is harmless.
            }
          }
        }
        return merged;
      }, onError: _db);

  @override
  Future<Result<ScannedDocument>> updateMeta(
    String id, {
    bool? favorite,
    bool? pinned,
    bool? locked,
    List<String>? tags,
    DateTime? date,
    DateTime? expires,
    bool clearExpiry = false,
  }) => guard(() async {
    final cleanTags = tags == null ? null : {for (final t in tags) t.trim()}.where((t) => t.isNotEmpty).toList();
    await _local.updateMeta(id, favorite: favorite, pinned: pinned, locked: locked, tags: cleanTags, date: date, expires: expires, clearExpiry: clearExpiry);
    final doc = await _local.get(id);
    if (doc == null) throw const DatabaseFailure('This document no longer exists.');
    return doc;
  }, onError: _db);

  @override
  Future<Result<ScannedDocument>> duplicateDocument(String id) => guard(() async {
    final doc = await _local.get(id);
    if (doc == null) throw const DatabaseFailure('This document no longer exists.');
    final copy = await _local.insert('${doc.title} (copy)', doc.pages.map(_toNewPage).toList(), doc.folderId);
    await _local.updateMeta(copy.id, locked: doc.locked, tags: doc.tags);
    return (await _local.get(copy.id))!;
  }, onError: _db);

  @override
  Future<Result<ScannedDocument>> splitDocument({required String id, required int startPage}) => guard(() async {
    final doc = await _local.get(id);
    if (doc == null) throw const DatabaseFailure('This document no longer exists.');
    if (startPage < 2 || startPage > doc.pageCount) {
      throw StorageFailure('Choose a page between 2 and ${doc.pageCount}.');
    }
    final all = doc.pages.map(_toNewPage).toList();
    // Create the new document first so a failure never loses pages.
    final second = await _local.insert('${doc.title} (part 2)', all.sublist(startPage - 1), doc.folderId);
    await _local.updateMeta(second.id, locked: doc.locked, tags: doc.tags);
    await _local.replacePages(id, doc.title, all.sublist(0, startPage - 1));
    return (await _local.get(second.id))!;
  }, onError: _db);

  @override
  Future<Result<ScannedDocument>> compressDocument({required String id, required CompressLevel level}) => guard(() async {
    final doc = await _local.get(id);
    if (doc == null) throw const DatabaseFailure('This document no longer exists.');
    final tmp = Directory(p.join((await getTemporaryDirectory()).path, 'compress_${DateTime.now().microsecondsSinceEpoch}'));
    try {
      final inputs = [for (final pg in doc.pages) pg.imagePath];
      final out = await Isolate.run(() => compressImages(inputs: inputs, outDir: tmp.path, maxSide: level.maxSide, quality: level.quality));
      // The smaller file becomes both the page and its source, so only one copy is stored.
      final pages = [for (final r in out) NewPage(imagePath: r.path, rawPath: r.path, width: r.width, height: r.height)];
      return await _local.replacePages(id, doc.title, pages);
    } finally {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    }
  }, onError: (e) => StorageFailure('The document could not be compressed.', cause: e));

  @override
  Future<Result<int>> documentSize(String id) => guard(() async {
    final doc = await _local.get(id);
    if (doc == null) return 0;
    final paths = <String>{
      for (final pg in doc.pages) ...[pg.imagePath, pg.rawPath, if (pg.edit != null) pg.edit!.croppedPath],
    };
    var total = 0;
    for (final path in paths) {
      final f = File(path);
      if (await f.exists()) total += await f.length();
    }
    return total;
  }, onError: _db);

  @override
  Future<Result<void>> deleteDocument(String id) => guard(() => _local.delete(id), onError: _db);

  @override
  Future<Result<List<Folder>>> listFolders() => guard(_local.listFolders, onError: _db);

  @override
  Future<Result<Folder>> createFolder(String name, {FolderStyle style = const FolderStyle()}) => guard(() async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw const StorageFailure('The folder name cannot be empty.');
    return _local.createFolder(trimmed, icon: style.icon, color: style.color);
  }, onError: _db);

  @override
  Future<Result<void>> renameFolder(String id, String name) => guard(() async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw const StorageFailure('The folder name cannot be empty.');
    await _local.renameFolder(id, trimmed);
  }, onError: _db);

  @override
  Future<Result<void>> updateFolderMeta(String id, {bool? favorite, bool? locked, FolderStyle? style}) => guard(
    () => _local.updateFolderMeta(id, favorite: favorite, locked: locked, style: style),
    onError: _db,
  );

  @override
  Future<Result<void>> deleteFolder(String id) => guard(() => _local.deleteFolder(id), onError: _db);
}

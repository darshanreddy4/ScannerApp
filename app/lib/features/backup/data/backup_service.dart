import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../../../core/error/failures.dart';
import '../../../core/error/result.dart';
import '../../documents/domain/entities/scanned_document.dart';
import '../../documents/domain/repositories/document_repository.dart';
import 'backup_container.dart';

class BackupSummary {
  const BackupSummary({required this.documents, required this.pages, required this.bytes});
  final int documents;
  final int pages;
  final int bytes;
}

class RestoreSummary {
  const RestoreSummary({required this.added, required this.alreadyHere, required this.pages});
  final int added;

  /// Documents that were skipped because this phone already has them.
  final int alreadyHere;
  final int pages;
}

abstract interface class BackupService {
  /// Writes every document and folder, encrypted with [password], to [outputPath].
  Future<Result<BackupSummary>> create({required String password, required String outputPath});

  /// Adds the documents of a backup to this phone. Documents that are already here are left alone.
  Future<Result<RestoreSummary>> restore({required String path, required String password});
}

const minBackupPasswordLength = 8;

Failure _failureOf(Object e) {
  if (e is BackupException) {
    return e.problem == BackupProblem.wrongPassword ? PasswordFailure(e.message) : StorageFailure(e.message);
  }
  return const UnexpectedFailure('The backup could not be completed.');
}

class LocalBackupService implements BackupService {
  LocalBackupService({
    required DocumentRepository documents,
    required FolderRepository folders,
    required Future<Directory> Function() tempDir,
    this.iterations = defaultBackupIterations,
  }) : _docs = documents,
       _folders = folders,
       _tempDir = tempDir;

  final DocumentRepository _docs;
  final FolderRepository _folders;
  final Future<Directory> Function() _tempDir;
  final int iterations;

  T _need<T>(Result<T> r) => r.when(ok: (v) => v, err: (f) => throw f);

  @override
  Future<Result<BackupSummary>> create({required String password, required String outputPath}) => guard(() async {
    final docs = _need(await _docs.listDocuments());
    final folders = _need(await _folders.listFolders());

    final files = <(String, String)>[];
    final docJson = <Map<String, Object?>>[];
    var pageCount = 0;
    for (var d = 0; d < docs.length; d++) {
      final doc = docs[d];
      final pages = <Map<String, Object?>>[];
      for (var i = 0; i < doc.pages.length; i++) {
        final page = doc.pages[i];
        if (!File(page.imagePath).existsSync()) continue;
        final image = 'd$d/page_$i.jpg';
        files.add((image, page.imagePath));
        String? raw, cropped;
        if (page.rawPath != page.imagePath && File(page.rawPath).existsSync()) {
          raw = 'd$d/raw_$i.jpg';
          files.add((raw, page.rawPath));
        }
        final edit = page.edit;
        if (edit != null && edit.croppedPath != page.imagePath && File(edit.croppedPath).existsSync()) {
          cropped = 'd$d/cropped_$i.jpg';
          files.add((cropped, edit.croppedPath));
        }
        pages.add({
          'image': image,
          'raw': raw,
          'cropped': cropped,
          'width': page.width,
          'height': page.height,
          if (edit != null)
            'edit': {
              'quad': edit.quad,
              'filter': edit.filter,
              'brightness': edit.brightness,
              'contrast': edit.contrast,
              'rawWidth': edit.rawWidth,
              'rawHeight': edit.rawHeight,
            },
        });
      }
      if (pages.isEmpty) continue;
      pageCount += pages.length;
      docJson.add({
        'title': doc.title,
        'createdAt': doc.createdAt.millisecondsSinceEpoch,
        'updatedAt': doc.updatedAt.millisecondsSinceEpoch,
        'folder': doc.folderId,
        'favorite': doc.favorite,
        'pinned': doc.pinned,
        'locked': doc.locked,
        'tags': doc.tags,
        'expires': doc.expiresAt?.millisecondsSinceEpoch,
        'pages': pages,
      });
    }
    final manifest = jsonEncode({
      'format': 'doculoom-backup',
      'version': 1,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'folders': [
        for (final f in folders)
          {
            'id': f.id,
            'name': f.name,
            'createdAt': f.createdAt.millisecondsSinceEpoch,
            'favorite': f.favorite,
            'locked': f.locked,
            'icon': f.icon,
            'color': f.color,
          },
      ],
      'documents': docJson,
    });

    final iterations = this.iterations;
    await Isolate.run(() async {
      final writer = await BackupWriter.open(outputPath, password, iterations: iterations);
      try {
        await writer.addBytes('manifest.json', utf8.encode(manifest));
        for (final (name, path) in files) {
          await writer.addFile(name, path);
        }
        await writer.close();
      } catch (_) {
        await writer.abort();
        rethrow;
      }
    });
    return BackupSummary(documents: docJson.length, pages: pageCount, bytes: await File(outputPath).length());
  }, onError: _failureOf);

  @override
  Future<Result<RestoreSummary>> restore({required String path, required String password}) => guard(() async {
    final dir = await Directory(p.join((await _tempDir()).path, 'restore_${DateTime.now().microsecondsSinceEpoch}')).create(recursive: true);
    try {
      await Isolate.run(() => readBackup(path, password, dir));
      final manifestFile = File(p.join(dir.path, 'manifest.json'));
      if (!manifestFile.existsSync()) throw const BackupException(BackupProblem.damaged, 'This backup file is damaged.');
      final Map<String, Object?> manifest;
      try {
        manifest = jsonDecode(await manifestFile.readAsString()) as Map<String, Object?>;
      } catch (_) {
        throw const BackupException(BackupProblem.damaged, 'This backup file is damaged.');
      }
      // Backups made before the rename carry the old tag and still restore.
      if (manifest['format'] != 'doculoom-backup' && manifest['format'] != 'scanvault-backup')
        throw const BackupException(BackupProblem.notABackup, 'This file is not a Doculoom backup.');
      if ((manifest['version'] as int? ?? 1) > 1)
        throw const BackupException(BackupProblem.newerVersion, 'This backup was made by a newer version of Doculoom. Update the app to open it.');

      // Folders are matched by name so restoring twice does not double them.
      final existingFolders = {for (final f in _need(await _folders.listFolders())) f.name.toLowerCase(): f.id};
      final folderIds = <String, String?>{};
      for (final f in (manifest['folders'] as List? ?? const []).cast<Map<String, Object?>>()) {
        final name = f['name'] as String? ?? '';
        if (name.isEmpty) continue;
        var id = existingFolders[name.toLowerCase()];
        if (id == null) {
          final created = _need(
            await _folders.createFolder(
              name,
              style: FolderStyle(icon: f['icon'] as String?, color: f['color'] as int?),
            ),
          );
          id = created.id;
          existingFolders[name.toLowerCase()] = id;
          if (f['favorite'] == true || f['locked'] == true) {
            _need(await _folders.updateFolderMeta(id, favorite: f['favorite'] == true, locked: f['locked'] == true));
          }
        }
        folderIds[f['id'] as String? ?? ''] = id;
      }

      final have = {for (final d in _need(await _docs.listDocuments())) '${d.title}\u0000${d.createdAt.millisecondsSinceEpoch}'};
      var added = 0, skipped = 0, pageCount = 0;
      for (final d in (manifest['documents'] as List? ?? const []).cast<Map<String, Object?>>()) {
        final title = d['title'] as String? ?? 'Untitled scan';
        final created = d['createdAt'] as int? ?? DateTime.now().millisecondsSinceEpoch;
        if (!have.add('$title\u0000$created')) {
          skipped++;
          continue;
        }
        final pages = <NewPage>[];
        for (final pg in (d['pages'] as List? ?? const []).cast<Map<String, Object?>>()) {
          final image = File(p.join(dir.path, pg['image'] as String? ?? ''));
          if (!image.existsSync()) continue;
          final rawName = pg['raw'] as String?;
          final croppedName = pg['cropped'] as String?;
          final raw = rawName == null ? image.path : p.join(dir.path, rawName);
          final e = pg['edit'] as Map<String, Object?>?;
          pages.add(
            NewPage(
              imagePath: image.path,
              rawPath: raw,
              width: pg['width'] as int? ?? 0,
              height: pg['height'] as int? ?? 0,
              edit: e == null
                  ? null
                  : PageEditInfo(
                      croppedPath: croppedName == null ? image.path : p.join(dir.path, croppedName),
                      quad: [for (final v in (e['quad'] as List)) (v as num).toDouble()],
                      filter: e['filter'] as String? ?? 'original',
                      brightness: (e['brightness'] as num? ?? 0).toDouble(),
                      contrast: (e['contrast'] as num? ?? 0).toDouble(),
                      rawWidth: e['rawWidth'] as int? ?? 0,
                      rawHeight: e['rawHeight'] as int? ?? 0,
                    ),
            ),
          );
        }
        if (pages.isEmpty) continue;
        final saved = _need(await _docs.saveDocument(title: title, pages: pages, folderId: folderIds[d['folder'] as String? ?? '']));
        _need(
          await _docs.updateMeta(
            saved.id,
            favorite: d['favorite'] == true,
            pinned: d['pinned'] == true,
            locked: d['locked'] == true,
            tags: [for (final t in (d['tags'] as List? ?? const [])) t.toString()],
            date: DateTime.fromMillisecondsSinceEpoch(created),
            expires: d['expires'] is int ? DateTime.fromMillisecondsSinceEpoch(d['expires'] as int) : null,
          ),
        );
        added++;
        pageCount += pages.length;
      }
      return RestoreSummary(added: added, alreadyHere: skipped, pages: pageCount);
    } finally {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
  }, onError: _failureOf);
}

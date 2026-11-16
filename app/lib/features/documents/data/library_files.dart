import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/error/result.dart';
import '../domain/entities/scanned_document.dart';
import '../domain/repositories/document_repository.dart';

/// Keeps what the app makes (Word, Excel, PowerPoint, PDF, text and picture files) in the library, so it shows on the home screen,
/// can be opened again in its tool and can be picked as the input of any other tool.
class LibraryFiles {
  LibraryFiles({
    required DocumentRepository documents,
    required LibraryFileRepository files,
    Future<Directory> Function()? rootDir,
    Future<Directory> Function()? tempDir,
  }) : _documents = documents,
       _files = files,
       _rootDir = rootDir ?? getApplicationDocumentsDirectory,
       _tempDir = tempDir ?? getTemporaryDirectory;

  final DocumentRepository _documents;
  final LibraryFileRepository _files;
  final Future<Directory> Function() _rootDir;
  final Future<Directory> Function() _tempDir;

  final _changes = StreamController<void>.broadcast();
  final _skip = <String>{};
  final _stagedFrom = <String, String>{};

  /// The library document a staged copy was made from, or null when [path] is not such a copy.
  String? stagedFrom(String path) => _stagedFrom[path];

  /// Fires after something was added to or changed in the library.
  Stream<void> get changes => _changes.stream;

  /// Marks a file that is a copy of something already in the library (an export of a scan, a backup) so it is not kept again.
  void dontKeep(String path) => _skip.add(path);

  static const _keptKinds = {
    LibraryFileKind.pdf,
    LibraryFileKind.word,
    LibraryFileKind.excel,
    LibraryFileKind.powerpoint,
    LibraryFileKind.text,
    LibraryFileKind.image,
  };

  static bool canKeep(String path) => _keptKinds.contains(LibraryFileKind.of(p.extension(path).replaceFirst('.', '')));

  /// Folders in the cache that only hold copies of things already in the library (a scan exported to PDF, a library file made ready to share).
  static const _copyFolders = ['exports', 'share_out', 'share_images', 'library_files'];

  Future<bool> _isCopyOfLibraryItem(String path) async {
    final tmp = (await _tempDir()).path;
    return _copyFolders.any((f) => p.isWithin(p.join(tmp, f), path));
  }

  /// Keeps the files after they were shared or saved. Pictures become one document with a page each; every other file is kept as it is.
  /// A file the library already holds with the same name and content is not added twice. Returns what was added or found.
  Future<List<ScannedDocument>> keep(List<String> paths, {String? title, String? folderId}) async {
    final kept = <ScannedDocument>[];
    try {
      final root = p.join((await _rootDir()).path, 'scans');
      final candidates = <String>[
        for (final path in paths)
          if (!_skip.contains(path) &&
              !p.isWithin(root, path) &&
              canKeep(path) &&
              !await _isCopyOfLibraryItem(path) &&
              await File(path).exists() &&
              await File(path).length() > 0)
            path,
      ];
      if (candidates.isEmpty) return kept;
      final existing = (await _documents.listDocuments()).valueOrNull ?? const <ScannedDocument>[];

      final pictures = [
        for (final c in candidates)
          if (LibraryFileKind.of(p.extension(c).replaceFirst('.', '')) == LibraryFileKind.image) c,
      ];
      if (pictures.isNotEmpty) {
        final doc = await _keepPictures(pictures, title: title, folderId: folderId, existing: existing);
        if (doc != null) kept.add(doc);
      }
      for (final path in candidates.where((c) => !pictures.contains(c))) {
        final name = title ?? _titleOf(path);
        final same = await _findSameFile(existing, name, path);
        if (same != null) {
          kept.add(same);
          continue;
        }
        final saved = (await _files.saveFile(title: name, sourcePath: path, folderId: folderId)).valueOrNull;
        if (saved != null) kept.add(saved);
      }
      if (kept.isNotEmpty) _changes.add(null);
    } catch (_) {
      // Keeping a copy is a convenience; sharing or saving the file has already worked.
    }
    return kept;
  }

  /// Saves the work of an editor: a new library file, or a new version of [existingId] when the file came from the library.
  Future<Result<ScannedDocument>> store({required String path, String? title, String? existingId, String? folderId}) async {
    final result = existingId != null
        ? await _files.replaceFile(id: existingId, sourcePath: path, title: title)
        : await _files.saveFile(title: title ?? _titleOf(path), sourcePath: path, folderId: folderId);
    if (result.valueOrNull != null) _changes.add(null);
    return result;
  }

  /// A copy of a library file under its own name in the cache folder, ready to hand to another app or tool.
  Future<String> stage(ScannedDocument doc) async {
    final source = doc.filePath;
    if (source == null) throw StateError('Not a file');
    final dir = Directory(p.join((await _tempDir()).path, 'library_files', doc.id));
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    final target = p.join(dir.path, '${safeFileName(doc.title)}.${doc.fileExtension}');
    await File(source).copy(target);
    _skip.add(target);
    _stagedFrom[target] = doc.id;
    return target;
  }

  /// Copies [path] into the staging area under [name], leaving the original alone.
  Future<String> stageCopy(String path, String name) async {
    final dir = await Directory(p.join((await _tempDir()).path, 'library_files', 'copy_${DateTime.now().microsecondsSinceEpoch}')).create(recursive: true);
    final target = p.join(dir.path, name);
    await File(path).copy(target);
    return target;
  }

  /// Copies the pages of a scanned document as pictures, named after the document.
  Future<List<String>> stagePages(ScannedDocument doc) async {
    final dir = await Directory(
      p.join((await _tempDir()).path, 'library_files', 'pages_${doc.id}_${DateTime.now().microsecondsSinceEpoch}'),
    ).create(recursive: true);
    final base = safeFileName(doc.title);
    final out = <String>[];
    for (var i = 0; i < doc.pages.length; i++) {
      final target = p.join(dir.path, doc.pageCount == 1 ? '$base.jpg' : '$base-${i + 1}.jpg');
      await File(doc.pages[i].imagePath).copy(target);
      out.add(target);
    }
    return out;
  }

  static String safeFileName(String title) {
    final cleaned = title.replaceAll(RegExp(r'[\\/:*?"<>|]+'), '').trim();
    return cleaned.isEmpty ? 'document' : cleaned;
  }

  static String _titleOf(String path) {
    final base = p.basenameWithoutExtension(path).replaceAll('_', ' ').trim();
    return base.isEmpty ? 'Document' : base;
  }

  Future<ScannedDocument?> _findSameFile(List<ScannedDocument> existing, String name, String path) async {
    final extension = p.extension(path).replaceFirst('.', '').toLowerCase();
    final length = await File(path).length();
    for (final d in existing) {
      if (!d.isFile || d.fileExtension != extension || d.title != name) continue;
      final f = File(d.filePath!);
      if (!await f.exists() || await f.length() != length) continue;
      if (await _sameBytes(f, File(path))) return d;
    }
    return null;
  }

  Future<ScannedDocument?> _keepPictures(List<String> paths, {String? title, String? folderId, required List<ScannedDocument> existing}) async {
    final name = title ?? _titleOf(paths.first);
    for (final d in existing) {
      if (d.isFile || d.title != name || d.pageCount != paths.length) continue;
      var same = true;
      for (var i = 0; i < paths.length && same; i++) {
        final f = File(d.pages[i].imagePath);
        same = await f.exists() && await f.length() == await File(paths[i]).length() && await _sameBytes(f, File(paths[i]));
      }
      if (same) return d;
    }
    final pages = <NewPage>[];
    for (final path in paths) {
      final size = _sizeOf(await File(path).readAsBytes());
      pages.add(NewPage(imagePath: path, rawPath: path, width: size.$1, height: size.$2));
    }
    return (await _documents.saveDocument(title: name, pages: pages, folderId: folderId)).valueOrNull;
  }

  static (int, int) _sizeOf(Uint8List bytes) {
    final info = img.findDecoderForData(bytes)?.startDecode(bytes);
    return (info?.width ?? 1, info?.height ?? 1);
  }

  static Future<bool> _sameBytes(File a, File b) async {
    final x = await a.readAsBytes();
    final y = await b.readAsBytes();
    if (x.length != y.length) return false;
    for (var i = 0; i < x.length; i++) {
      if (x[i] != y[i]) return false;
    }
    return true;
  }
}

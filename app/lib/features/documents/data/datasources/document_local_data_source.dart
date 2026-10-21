import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/scanned_document.dart';

/// SQLite persistence plus app-private file storage.
/// All file paths in the database are relative to the app documents directory,
/// because absolute container paths can change between app updates on iOS.
class DocumentLocalDataSource {
  DocumentLocalDataSource({Database? database, Directory? rootDir})
      : _db = database,
        _root = rootDir;

  static const _dbName = 'scanvault.db';
  static const _version = 1;

  Database? _db;
  Directory? _root;
  final _uuid = const Uuid();

  Future<Directory> _rootDir() async => _root ??= await getApplicationDocumentsDirectory();

  Future<Database> _database() async {
    final existing = _db;
    if (existing != null) return existing;
    final root = await _rootDir();
    return _db = await openDatabase(
      p.join(root.path, _dbName),
      version: _version,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE documents(
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )''');
        await db.execute('''
          CREATE TABLE pages(
            id TEXT PRIMARY KEY,
            document_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
            position INTEGER NOT NULL,
            image_path TEXT NOT NULL,
            raw_path TEXT NOT NULL,
            width INTEGER NOT NULL,
            height INTEGER NOT NULL
          )''');
        await db.execute('CREATE INDEX idx_pages_doc ON pages(document_id, position)');
      },
    );
  }

  Future<List<ScannedDocument>> list() async {
    final db = await _database();
    final docs = await db.query('documents', orderBy: 'updated_at DESC');
    final pages = await db.query('pages', orderBy: 'document_id, position');
    final root = (await _rootDir()).path;

    final byDoc = <String, List<DocumentPage>>{};
    for (final row in pages) {
      byDoc.putIfAbsent(row['document_id'] as String, () => []).add(_pageFrom(row, root));
    }
    return [for (final d in docs) _docFrom(d, byDoc[d['id']] ?? const [])];
  }

  Future<ScannedDocument?> get(String id) async {
    final db = await _database();
    final docs = await db.query('documents', where: 'id = ?', whereArgs: [id]);
    if (docs.isEmpty) return null;
    final pages = await db.query('pages', where: 'document_id = ?', whereArgs: [id], orderBy: 'position');
    final root = (await _rootDir()).path;
    return _docFrom(docs.first, [for (final r in pages) _pageFrom(r, root)]);
  }

  /// Copies page files into private storage first, then writes DB rows in one transaction.
  /// On any failure the partial folder is removed so no orphan files are left behind.
  Future<ScannedDocument> insert(String title, List<NewPage> pages) async {
    final db = await _database();
    final root = await _rootDir();
    final docId = _uuid.v4();
    final dir = Directory(p.join(root.path, 'scans', docId));
    final now = DateTime.now();

    try {
      await dir.create(recursive: true);
      final rows = <Map<String, Object?>>[];
      for (var i = 0; i < pages.length; i++) {
        final page = pages[i];
        final pageId = _uuid.v4();
        final img = 'page_$i.jpg';
        final raw = 'raw_$i.jpg';
        await File(page.imagePath).copy(p.join(dir.path, img));
        await File(page.rawPath).copy(p.join(dir.path, raw));
        rows.add({
          'id': pageId,
          'document_id': docId,
          'position': i,
          'image_path': p.join('scans', docId, img),
          'raw_path': p.join('scans', docId, raw),
          'width': page.width,
          'height': page.height,
        });
      }

      await db.transaction((txn) async {
        await txn.insert('documents', {
          'id': docId,
          'title': title,
          'created_at': now.millisecondsSinceEpoch,
          'updated_at': now.millisecondsSinceEpoch,
        });
        for (final r in rows) {
          await txn.insert('pages', r);
        }
      });
    } catch (_) {
      if (await dir.exists()) await dir.delete(recursive: true);
      rethrow;
    }
    return (await get(docId))!;
  }

  Future<void> rename(String id, String title) async {
    final db = await _database();
    await db.update(
      'documents',
      {'title': title, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> delete(String id) async {
    final db = await _database();
    final root = await _rootDir();
    await db.delete('documents', where: 'id = ?', whereArgs: [id]);
    final dir = Directory(p.join(root.path, 'scans', id));
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  ScannedDocument _docFrom(Map<String, Object?> row, List<DocumentPage> pages) => ScannedDocument(
        id: row['id'] as String,
        title: row['title'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
        pages: pages,
      );

  DocumentPage _pageFrom(Map<String, Object?> row, String root) => DocumentPage(
        id: row['id'] as String,
        position: row['position'] as int,
        imagePath: p.join(root, row['image_path'] as String),
        rawPath: p.join(root, row['raw_path'] as String),
        width: row['width'] as int,
        height: row['height'] as int,
      );
}

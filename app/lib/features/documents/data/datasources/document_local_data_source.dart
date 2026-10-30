import 'dart:convert';
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
  DocumentLocalDataSource({Database? database, Directory? rootDir}) : _db = database, _root = rootDir;

  static const _dbName = 'doculoom.db';
  static const _version = 8;

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
          CREATE TABLE folders(
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            favorite INTEGER NOT NULL DEFAULT 0,
            locked INTEGER NOT NULL DEFAULT 0,
            icon TEXT,
            color INTEGER
          )''');
        await db.execute('''
          CREATE TABLE documents(
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            folder_id TEXT REFERENCES folders(id) ON DELETE SET NULL,
            favorite INTEGER NOT NULL DEFAULT 0,
            pinned INTEGER NOT NULL DEFAULT 0,
            locked INTEGER NOT NULL DEFAULT 0,
            tags TEXT,
            expires_at INTEGER
          )''');
        await db.execute('''
          CREATE TABLE pages(
            id TEXT PRIMARY KEY,
            document_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
            position INTEGER NOT NULL,
            image_path TEXT NOT NULL,
            raw_path TEXT NOT NULL,
            width INTEGER NOT NULL,
            height INTEGER NOT NULL,
            cropped_path TEXT,
            quad TEXT,
            filter TEXT,
            brightness REAL,
            contrast REAL,
            raw_width INTEGER,
            raw_height INTEGER
          )''');
        await db.execute('CREATE INDEX idx_pages_doc ON pages(document_id, position)');
        await _createPageText(db);
      },
      onUpgrade: (db, from, to) async {
        if (from < 2) {
          await db.execute('''
            CREATE TABLE folders(
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              created_at INTEGER NOT NULL
            )''');
          await db.execute('ALTER TABLE documents ADD COLUMN folder_id TEXT REFERENCES folders(id) ON DELETE SET NULL');
        }
        if (from < 3) {
          for (final column in const [
            'cropped_path TEXT',
            'quad TEXT',
            'filter TEXT',
            'brightness REAL',
            'contrast REAL',
            'raw_width INTEGER',
            'raw_height INTEGER',
          ]) {
            await db.execute('ALTER TABLE pages ADD COLUMN $column');
          }
        }
        if (from < 4) {
          for (final column in const [
            'favorite INTEGER NOT NULL DEFAULT 0',
            'pinned INTEGER NOT NULL DEFAULT 0',
            'locked INTEGER NOT NULL DEFAULT 0',
            'tags TEXT',
          ]) {
            await db.execute('ALTER TABLE documents ADD COLUMN $column');
          }
        }
        if (from < 6) await _createPageText(db);
        if (from < 5) {
          await db.execute('ALTER TABLE folders ADD COLUMN favorite INTEGER NOT NULL DEFAULT 0');
          await db.execute('ALTER TABLE folders ADD COLUMN locked INTEGER NOT NULL DEFAULT 0');
        }
        if (from < 7) {
          final have = {for (final c in await db.rawQuery('PRAGMA table_info(folders)')) c['name']};
          if (!have.contains('icon')) await db.execute('ALTER TABLE folders ADD COLUMN icon TEXT');
          if (!have.contains('color')) await db.execute('ALTER TABLE folders ADD COLUMN color INTEGER');
        }
        if (from < 8) {
          final have = {for (final c in await db.rawQuery('PRAGMA table_info(documents)')) c['name']};
          if (!have.contains('expires_at')) await db.execute('ALTER TABLE documents ADD COLUMN expires_at INTEGER');
        }
      },
    );
  }

  static Future<void> _createPageText(Database db) => db.execute('''
    CREATE TABLE page_text(
      document_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
      position INTEGER NOT NULL,
      script TEXT NOT NULL,
      markdown TEXT NOT NULL,
      plain TEXT NOT NULL,
      edited INTEGER NOT NULL DEFAULT 0,
      updated_at INTEGER NOT NULL,
      PRIMARY KEY (document_id, position)
    )''');

  // Recognised text

  Future<List<Map<String, Object?>>> pageTexts(String documentId) async {
    final db = await _database();
    return db.query('page_text', where: 'document_id = ?', whereArgs: [documentId], orderBy: 'position');
  }

  Future<void> replacePageTexts(String documentId, List<Map<String, Object?>> rows) async {
    final db = await _database();
    await db.transaction((txn) async {
      await txn.delete('page_text', where: 'document_id = ?', whereArgs: [documentId]);
      for (final r in rows) {
        await txn.insert('page_text', {...r, 'document_id': documentId, 'updated_at': DateTime.now().millisecondsSinceEpoch});
      }
    });
  }

  Future<void> updatePageTextMarkdown(String documentId, int position, String markdown) async {
    final db = await _database();
    await db.update(
      'page_text',
      {'markdown': markdown, 'edited': 1, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'document_id = ? AND position = ?',
      whereArgs: [documentId, position],
    );
  }

  Future<void> clearPageTexts(String documentId) async {
    final db = await _database();
    await db.delete('page_text', where: 'document_id = ?', whereArgs: [documentId]);
  }

  /// Documents with recognised text containing [query] (the search is case-insensitive for plain letters).
  Future<Set<String>> documentIdsWithText(String query) async {
    final db = await _database();
    final escaped = query.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
    final rows = await db.rawQuery("SELECT DISTINCT document_id FROM page_text WHERE plain LIKE ? ESCAPE '\\' OR markdown LIKE ? ESCAPE '\\'", [
      '%$escaped%',
      '%$escaped%',
    ]);
    return {for (final r in rows) r['document_id'] as String};
  }

  // Documents

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

  /// Copies page files into [relDir] (relative to the app folder) and returns the DB rows for them.
  Future<List<Map<String, Object?>>> _storePages(String docId, String relDir, List<NewPage> pages) async {
    final root = await _rootDir();
    final dir = Directory(p.join(root.path, relDir));
    await dir.create(recursive: true);

    final rows = <Map<String, Object?>>[];
    for (var i = 0; i < pages.length; i++) {
      final page = pages[i];
      final imgName = 'page_$i.jpg';
      final rawName = 'raw_$i.jpg';
      await File(page.imagePath).copy(p.join(dir.path, imgName));
      // A page whose raw copy is the finished image (after compression) stores the file once.
      final rawShared = page.rawPath == page.imagePath;
      if (!rawShared) await File(page.rawPath).copy(p.join(dir.path, rawName));

      final edit = page.edit;
      String? croppedRel;
      if (edit != null) {
        if (edit.croppedPath == page.imagePath) {
          croppedRel = p.join(relDir, imgName);
        } else {
          final croppedName = 'cropped_$i.jpg';
          await File(edit.croppedPath).copy(p.join(dir.path, croppedName));
          croppedRel = p.join(relDir, croppedName);
        }
      }

      rows.add({
        'id': _uuid.v4(),
        'document_id': docId,
        'position': i,
        'image_path': p.join(relDir, imgName),
        'raw_path': p.join(relDir, rawShared ? imgName : rawName),
        'width': page.width,
        'height': page.height,
        'cropped_path': croppedRel,
        'quad': edit == null ? null : jsonEncode(edit.quad),
        'filter': edit?.filter,
        'brightness': edit?.brightness,
        'contrast': edit?.contrast,
        'raw_width': edit?.rawWidth,
        'raw_height': edit?.rawHeight,
      });
    }
    return rows;
  }

  /// Copies page files into private storage first, then writes DB rows in one transaction.
  /// On any failure the partial folder is removed so no orphan files are left behind.
  Future<ScannedDocument> insert(String title, List<NewPage> pages, String? folderId) async {
    final db = await _database();
    final root = await _rootDir();
    final docId = _uuid.v4();
    final dir = Directory(p.join(root.path, 'scans', docId));
    final now = DateTime.now();

    try {
      final rows = await _storePages(docId, p.join('scans', docId), pages);
      await db.transaction((txn) async {
        await txn.insert('documents', {
          'id': docId,
          'title': title,
          'created_at': now.millisecondsSinceEpoch,
          'updated_at': now.millisecondsSinceEpoch,
          'folder_id': folderId,
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

  /// Replaces all pages of [id]. New files go into a fresh subfolder; the old files are deleted only
  /// after the database commit, so a failure leaves the original document untouched.
  Future<ScannedDocument> replacePages(String id, String title, List<NewPage> pages) async {
    final db = await _database();
    final root = await _rootDir();
    final relDir = p.join('scans', id, 'r${DateTime.now().microsecondsSinceEpoch}');
    final newDir = Directory(p.join(root.path, relDir));

    try {
      final rows = await _storePages(id, relDir, pages);
      await db.transaction((txn) async {
        await txn.delete('pages', where: 'document_id = ?', whereArgs: [id]);
        // Recognised text belongs to the old pages, so it would no longer match.
        await txn.delete('page_text', where: 'document_id = ?', whereArgs: [id]);
        for (final r in rows) {
          await txn.insert('pages', r);
        }
        await txn.update('documents', {'title': title, 'updated_at': DateTime.now().millisecondsSinceEpoch}, where: 'id = ?', whereArgs: [id]);
      });
    } catch (_) {
      if (await newDir.exists()) await newDir.delete(recursive: true);
      rethrow;
    }

    final docDir = Directory(p.join(root.path, 'scans', id));
    await for (final entity in docDir.list()) {
      if (entity.path != newDir.path) {
        try {
          await entity.delete(recursive: true);
        } catch (_) {
          // Leftover old files are harmless and cleaned up when the document is deleted.
        }
      }
    }
    return (await get(id))!;
  }

  Future<void> rename(String id, String title) async {
    final db = await _database();
    await db.update('documents', {'title': title, 'updated_at': DateTime.now().millisecondsSinceEpoch}, where: 'id = ?', whereArgs: [id]);
  }

  /// Updates flags, tags or the document date. Only the given fields change; the date also sets "updated".
  Future<void> updateMeta(
    String id, {
    bool? favorite,
    bool? pinned,
    bool? locked,
    List<String>? tags,
    DateTime? date,
    DateTime? expires,
    bool clearExpiry = false,
  }) async {
    final db = await _database();
    final values = <String, Object?>{
      if (favorite != null) 'favorite': favorite ? 1 : 0,
      if (pinned != null) 'pinned': pinned ? 1 : 0,
      if (locked != null) 'locked': locked ? 1 : 0,
      if (tags != null) 'tags': jsonEncode(tags),
      if (date != null) 'created_at': date.millisecondsSinceEpoch,
      if (date != null) 'updated_at': date.millisecondsSinceEpoch,
      if (expires != null) 'expires_at': expires.millisecondsSinceEpoch,
      if (clearExpiry) 'expires_at': null,
    };
    if (values.isEmpty) return;
    await db.update('documents', values, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> move(String id, String? folderId) async {
    final db = await _database();
    await db.update('documents', {'folder_id': folderId}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> delete(String id) async {
    final db = await _database();
    final root = await _rootDir();
    await db.delete('documents', where: 'id = ?', whereArgs: [id]);
    final dir = Directory(p.join(root.path, 'scans', id));
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  /// Removes page folders no document refers to (left behind by an interrupted save). Run only at startup.
  Future<int> removeOrphanFiles() async {
    final db = await _database();
    final scans = Directory(p.join((await _rootDir()).path, 'scans'));
    if (!await scans.exists()) return 0;
    final known = {
      for (final r in await db.query('documents', columns: ['id'])) r['id'] as String,
    };
    var removed = 0;
    await for (final entity in scans.list()) {
      if (entity is Directory && !known.contains(p.basename(entity.path))) {
        await entity.delete(recursive: true);
        removed++;
      }
    }
    return removed;
  }

  // Folders

  Future<List<Folder>> listFolders() async {
    final db = await _database();
    final rows = await db.query('folders', orderBy: 'name COLLATE NOCASE');
    return [for (final r in rows) _folderFrom(r)];
  }

  Future<Folder> createFolder(String name, {String? icon, int? color}) async {
    final db = await _database();
    final folder = Folder(id: _uuid.v4(), name: name, createdAt: DateTime.now(), icon: icon, color: color);
    await db.insert('folders', {'id': folder.id, 'name': folder.name, 'created_at': folder.createdAt.millisecondsSinceEpoch, 'icon': icon, 'color': color});
    return folder;
  }

  Future<void> renameFolder(String id, String name) async {
    final db = await _database();
    await db.update('folders', {'name': name}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateFolderMeta(String id, {bool? favorite, bool? locked, FolderStyle? style}) async {
    final db = await _database();
    final values = <String, Object?>{
      if (favorite != null) 'favorite': favorite ? 1 : 0,
      if (locked != null) 'locked': locked ? 1 : 0,
      if (style != null) ...{'icon': style.icon, 'color': style.color},
    };
    if (values.isEmpty) return;
    await db.update('folders', values, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteFolder(String id) async {
    final db = await _database();
    await db.transaction((txn) async {
      await txn.update('documents', {'folder_id': null}, where: 'folder_id = ?', whereArgs: [id]);
      await txn.delete('folders', where: 'id = ?', whereArgs: [id]);
    });
  }

  Folder _folderFrom(Map<String, Object?> r) => Folder(
    id: r['id'] as String,
    name: r['name'] as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
    favorite: (r['favorite'] as int? ?? 0) == 1,
    locked: (r['locked'] as int? ?? 0) == 1,
    icon: r['icon'] as String?,
    color: r['color'] as int?,
  );

  ScannedDocument _docFrom(Map<String, Object?> row, List<DocumentPage> pages) => ScannedDocument(
    id: row['id'] as String,
    title: row['title'] as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
    pages: pages,
    folderId: row['folder_id'] as String?,
    favorite: (row['favorite'] as int? ?? 0) == 1,
    pinned: (row['pinned'] as int? ?? 0) == 1,
    locked: (row['locked'] as int? ?? 0) == 1,
    tags: _decodeTags(row['tags'] as String?),
    expiresAt: (row['expires_at'] as int?) == null ? null : DateTime.fromMillisecondsSinceEpoch(row['expires_at'] as int),
  );

  static List<String> _decodeTags(String? json) => json == null || json.isEmpty ? const [] : [for (final t in jsonDecode(json) as List) t as String];

  DocumentPage _pageFrom(Map<String, Object?> row, String root) {
    final cropped = row['cropped_path'] as String?;
    final quadJson = row['quad'] as String?;
    final hasEdit = cropped != null && quadJson != null && row['raw_width'] != null && row['raw_height'] != null;

    return DocumentPage(
      id: row['id'] as String,
      position: row['position'] as int,
      imagePath: p.join(root, row['image_path'] as String),
      rawPath: p.join(root, row['raw_path'] as String),
      width: row['width'] as int,
      height: row['height'] as int,
      edit: !hasEdit
          ? null
          : PageEditInfo(
              croppedPath: p.join(root, cropped),
              quad: [for (final v in jsonDecode(quadJson) as List) (v as num).toDouble()],
              filter: (row['filter'] as String?) ?? 'original',
              brightness: (row['brightness'] as num?)?.toDouble() ?? 0,
              contrast: (row['contrast'] as num?)?.toDouble() ?? 0,
              rawWidth: row['raw_width'] as int,
              rawHeight: row['raw_height'] as int,
            ),
    );
  }
}

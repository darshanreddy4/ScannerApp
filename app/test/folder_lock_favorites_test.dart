import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:scanvault/features/documents/data/datasources/document_local_data_source.dart';
import 'package:scanvault/features/documents/data/repositories/document_repository_impl.dart';
import 'package:scanvault/features/documents/domain/entities/scanned_document.dart';
import 'package:scanvault/features/documents/presentation/bloc/documents_cubit.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory work;
  late Directory root;
  late DocumentRepositoryImpl repo;

  setUp(() {
    work = Directory.systemTemp.createTempSync('sv_fold_work');
    root = Directory.systemTemp.createTempSync('sv_fold_root');
    repo = DocumentRepositoryImpl(DocumentLocalDataSource(rootDir: root));
  });

  tearDown(() {
    work.deleteSync(recursive: true);
    root.deleteSync(recursive: true);
  });

  NewPage page(String tag) {
    final f = File(p.join(work.path, 'p_$tag.jpg'))..writeAsStringSync('page-$tag');
    return NewPage(imagePath: f.path, rawPath: f.path, width: 10, height: 10);
  }

  Future<ScannedDocument> doc(String title, {String? folderId}) async =>
      (await repo.saveDocument(title: title, pages: [page(title)], folderId: folderId)).valueOrNull!;

  test('folder favourite and lock are saved and only the given field changes', () async {
    final folder = (await repo.createFolder('Taxes')).valueOrNull!;
    expect(folder.favorite || folder.locked, isFalse);

    await repo.updateFolderMeta(folder.id, locked: true);
    await repo.updateFolderMeta(folder.id, favorite: true);
    var saved = (await repo.listFolders()).valueOrNull!.single;
    expect(saved.locked, isTrue);
    expect(saved.favorite, isTrue);

    await repo.updateFolderMeta(folder.id, locked: false);
    saved = (await repo.listFolders()).valueOrNull!.single;
    expect(saved.locked, isFalse);
    expect(saved.favorite, isTrue);
  });

  test('a version 4 database gains folder columns with safe defaults', () async {
    final path = p.join(root.path, 'scanvault.db');
    final v4 = await openDatabase(
      path,
      version: 4,
      onCreate: (db, _) async {
        await db.execute('CREATE TABLE folders(id TEXT PRIMARY KEY, name TEXT NOT NULL, created_at INTEGER NOT NULL)');
        await db.execute(
          'CREATE TABLE documents(id TEXT PRIMARY KEY, title TEXT NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, folder_id TEXT, favorite INTEGER NOT NULL DEFAULT 0, pinned INTEGER NOT NULL DEFAULT 0, locked INTEGER NOT NULL DEFAULT 0, tags TEXT)',
        );
        await db.execute(
          'CREATE TABLE pages(id TEXT PRIMARY KEY, document_id TEXT NOT NULL, position INTEGER NOT NULL, image_path TEXT NOT NULL, raw_path TEXT NOT NULL, width INTEGER NOT NULL, height INTEGER NOT NULL, cropped_path TEXT, quad TEXT, filter TEXT, brightness REAL, contrast REAL, raw_width INTEGER, raw_height INTEGER)',
        );
        await db.insert('folders', {'id': 'f1', 'name': 'Old folder', 'created_at': 1});
      },
    );
    await v4.close();

    final folder = (await repo.listFolders()).valueOrNull!.single;
    expect(folder.name, 'Old folder');
    expect(folder.favorite, isFalse);
    expect(folder.locked, isFalse);
  });

  test('search and favourites never reveal documents inside a locked folder', () async {
    final open = (await repo.createFolder('Open')).valueOrNull!;
    final secret = (await repo.createFolder('Secret')).valueOrNull!;
    await repo.updateFolderMeta(secret.id, locked: true);

    final a = await doc('Invoice open', folderId: open.id);
    final b = await doc('Invoice secret', folderId: secret.id);
    final c = await doc('Invoice loose');
    for (final d in [a, b, c]) {
      await repo.updateMeta(d.id, favorite: true, tags: ['bill']);
    }

    final state = DocumentsState(
      status: LoadStatus.ready,
      documents: (await repo.listDocuments()).valueOrNull!,
      folders: (await repo.listFolders()).valueOrNull!,
    );

    expect(state.searchDocuments('invoice').map((d) => d.title), unorderedEquals(['Invoice open', 'Invoice loose']));
    expect(state.searchDocuments('#bill').map((d) => d.title), isNot(contains('Invoice secret')));
    expect(state.favoriteDocuments.map((d) => d.title), unorderedEquals(['Invoice open', 'Invoice loose']));
    // The folder itself still lists its own documents once opened.
    expect(state.inFolder(secret.id).single.title, 'Invoice secret');
  });

  test('favourite folders are listed on their own', () async {
    final a = (await repo.createFolder('A')).valueOrNull!;
    await repo.createFolder('B');
    await repo.updateFolderMeta(a.id, favorite: true);

    final state = DocumentsState(status: LoadStatus.ready, folders: (await repo.listFolders()).valueOrNull!);
    expect(state.favoriteFolders.map((f) => f.name), ['A']);
  });
}

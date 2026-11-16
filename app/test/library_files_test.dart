import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:doculoom/features/documents/data/datasources/document_local_data_source.dart';
import 'package:doculoom/features/documents/data/library_files.dart';
import 'package:doculoom/features/documents/data/repositories/document_repository_impl.dart';
import 'package:doculoom/features/documents/domain/entities/scanned_document.dart';
import 'package:doculoom/features/documents/presentation/library_picker.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory work;
  late Directory root;
  late Directory temp;
  late DocumentRepositoryImpl repo;
  late LibraryFiles library;

  setUp(() {
    work = Directory.systemTemp.createTempSync('sv_lib_work');
    root = Directory.systemTemp.createTempSync('sv_lib_root');
    temp = Directory.systemTemp.createTempSync('sv_lib_temp');
    repo = DocumentRepositoryImpl(DocumentLocalDataSource(rootDir: root));
    library = LibraryFiles(documents: repo, files: repo, rootDir: () async => root, tempDir: () async => temp);
  });

  tearDown(() {
    work.deleteSync(recursive: true);
    root.deleteSync(recursive: true);
    temp.deleteSync(recursive: true);
  });

  File make(String name, String content, {Directory? dir}) => File(p.join((dir ?? work).path, name))
    ..createSync(recursive: true)
    ..writeAsStringSync(content);

  Future<List<ScannedDocument>> all() async => (await repo.listDocuments()).valueOrNull!;

  group('files in the library', () {
    test('a file is kept as a document with no pages, and keeps its type', () async {
      final saved = (await repo.saveFile(title: 'Budget', sourcePath: make('b.xlsx', 'sheet').path)).valueOrNull!;
      expect(saved.isFile, isTrue);
      expect(saved.pageCount, 0);
      expect(saved.fileExtension, 'xlsx');
      expect(saved.fileKind, LibraryFileKind.excel);
      expect(File(saved.filePath!).readAsStringSync(), 'sheet');
      expect(p.isWithin(root.path, saved.filePath!), isTrue);
      expect((await all()).single.filePath, saved.filePath);
    });

    test('a new version replaces the old file and keeps the folder, tags and flags', () async {
      final folder = (await repo.createFolder('Work')).valueOrNull!;
      final first = (await repo.saveFile(title: 'Report', sourcePath: make('r.docx', 'one').path, folderId: folder.id)).valueOrNull!;
      await repo.updateMeta(first.id, favorite: true, tags: ['q1']);
      final second = (await repo.replaceFile(id: first.id, sourcePath: make('r2.docx', 'two').path)).valueOrNull!;
      expect(File(second.filePath!).readAsStringSync(), 'two');
      expect(File(first.filePath!).existsSync(), isFalse, reason: 'the old version is removed');
      expect(second.folderId, folder.id);
      expect(second.favorite, isTrue);
      expect(second.tags, ['q1']);
      expect(second.title, 'Report');
      expect((await all()), hasLength(1));
    });

    test('deleting the document deletes its file; duplicating makes an independent copy', () async {
      final doc = (await repo.saveFile(title: 'Deck', sourcePath: make('d.pptx', 'slides').path)).valueOrNull!;
      final copy = (await repo.duplicateDocument(doc.id)).valueOrNull!;
      expect(copy.isFile, isTrue);
      expect(copy.title, 'Deck (copy)');
      expect(copy.filePath, isNot(doc.filePath));
      await repo.deleteDocument(doc.id);
      expect(File(doc.filePath!).existsSync(), isFalse);
      expect(File(copy.filePath!).readAsStringSync(), 'slides');
    });

    test('a file cannot be merged into a scan', () async {
      final a = (await repo.saveFile(title: 'A', sourcePath: make('a.pdf', 'x').path)).valueOrNull!;
      final b = (await repo.saveFile(title: 'B', sourcePath: make('b.pdf', 'y').path)).valueOrNull!;
      final merged = await repo.mergeDocuments(ids: [a.id, b.id], title: 'M', deleteOriginals: false);
      expect(merged.failureOrNull, isNotNull);
    });

    test('the size of a file document counts the file', () async {
      final doc = (await repo.saveFile(title: 'Big', sourcePath: make('big.docx', 'x' * 500).path)).valueOrNull!;
      expect((await repo.documentSize(doc.id)).valueOrNull, 500);
    });

    test('a library file survives a version 8 database upgrade', () async {
      final path = p.join(root.path, 'doculoom.db');
      final v8 = await openDatabase(
        path,
        version: 8,
        onCreate: (db, _) async {
          await db.execute('CREATE TABLE folders(id TEXT PRIMARY KEY, name TEXT NOT NULL, created_at INTEGER NOT NULL, favorite INTEGER NOT NULL DEFAULT 0, locked INTEGER NOT NULL DEFAULT 0, icon TEXT, color INTEGER)');
          await db.execute(
            'CREATE TABLE documents(id TEXT PRIMARY KEY, title TEXT NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, folder_id TEXT, favorite INTEGER NOT NULL DEFAULT 0, pinned INTEGER NOT NULL DEFAULT 0, locked INTEGER NOT NULL DEFAULT 0, tags TEXT, expires_at INTEGER)',
          );
          await db.execute(
            'CREATE TABLE pages(id TEXT PRIMARY KEY, document_id TEXT NOT NULL, position INTEGER NOT NULL, image_path TEXT NOT NULL, raw_path TEXT NOT NULL, width INTEGER NOT NULL, height INTEGER NOT NULL, cropped_path TEXT, quad TEXT, filter TEXT, brightness REAL, contrast REAL, raw_width INTEGER, raw_height INTEGER)',
          );
          await db.execute('CREATE TABLE page_text(document_id TEXT NOT NULL, position INTEGER NOT NULL, script TEXT NOT NULL, markdown TEXT NOT NULL, plain TEXT NOT NULL, edited INTEGER NOT NULL DEFAULT 0, updated_at INTEGER NOT NULL, PRIMARY KEY (document_id, position))');
          await db.insert('documents', {'id': 'old', 'title': 'Old scan', 'created_at': 1, 'updated_at': 1});
        },
      );
      await v8.close();
      final docs = await all();
      expect(docs.single.title, 'Old scan');
      expect(docs.single.isFile, isFalse);
      final saved = (await repo.saveFile(title: 'New', sourcePath: make('n.docx', 'n').path)).valueOrNull!;
      expect(saved.isFile, isTrue);
    });
  });

  group('keeping what the app makes', () {
    test('a shared file is kept once, and sharing it again does not add another', () async {
      final f = make('Letter.docx', 'hello');
      final first = await library.keep([f.path]);
      expect(first.single.title, 'Letter');
      await library.keep([f.path]);
      expect(await all(), hasLength(1));
      // The same name with other content is a different file.
      make('Letter.docx', 'hello again');
      await library.keep([f.path]);
      expect(await all(), hasLength(2));
    });

    test('things already in the library, copies made from it, and other file types are not kept', () async {
      final saved = (await repo.saveFile(title: 'Mine', sourcePath: make('m.pdf', 'm').path)).valueOrNull!;
      await library.keep([saved.filePath!]);
      await library.keep([make('exported.pdf', 'e', dir: Directory(p.join(temp.path, 'exports'))).path]);
      await library.keep([make('send.zip', 'z').path, make('card.vcf', 'v').path]);
      final staged = await library.stage(saved);
      await library.keep([staged]);
      expect(await all(), hasLength(1));
    });

    test('a file marked as a copy is skipped', () async {
      final f = make('Copy.pdf', 'c');
      library.dontKeep(f.path);
      await library.keep([f.path]);
      expect(await all(), isEmpty);
    });

    test('pictures become one document with a page each', () async {
      final shots = [make('a.jpg', 'one'), make('b.jpg', 'two')];
      final kept = await library.keep([for (final f in shots) f.path], title: 'Photos');
      final doc = kept.single;
      expect(doc.isFile, isFalse);
      expect(doc.title, 'Photos');
      expect(doc.pageCount, 2);
      await library.keep([for (final f in shots) f.path], title: 'Photos');
      expect(await all(), hasLength(1));
    });

    test('an editor saves a new file first and then new versions of the same one', () async {
      final v1 = await library.store(path: make('Essay.docx', 'v1').path, title: 'Essay');
      final id = v1.valueOrNull!.id;
      final v2 = await library.store(path: make('Essay_edited.docx', 'v2').path, existingId: id);
      expect(v2.valueOrNull!.id, id);
      expect(File(v2.valueOrNull!.filePath!).readAsStringSync(), 'v2');
      expect(v2.valueOrNull!.title, 'Essay');
      expect(await all(), hasLength(1));
    });

    test('announces changes so the home list refreshes', () async {
      var changes = 0;
      final sub = library.changes.listen((_) => changes++);
      await library.keep([make('N.pdf', 'n').path]);
      await Future<void>.delayed(Duration.zero);
      expect(changes, 1);
      await sub.cancel();
    });

    test('a library file is made ready under its own name, and remembers where it came from', () async {
      final saved = (await repo.saveFile(title: 'My: Plan?', sourcePath: make('stored.docx', 'plan').path)).valueOrNull!;
      final staged = await library.stage(saved);
      expect(p.basename(staged), 'My Plan.docx');
      expect(File(staged).readAsStringSync(), 'plan');
      expect(library.stagedFrom(staged), saved.id);
      expect(library.stagedFrom(make('other.docx', 'o').path), isNull);
    });

    test('the pages of a scan are staged as pictures named after it', () async {
      final f = make('p.jpg', 'page');
      final scan = (await repo.saveDocument(title: 'Receipt', pages: [NewPage(imagePath: f.path, rawPath: f.path, width: 1, height: 1)])).valueOrNull!;
      final out = await library.stagePages(scan);
      expect(out.map(p.basename), ['Receipt.jpg']);
      expect(File(out.single).readAsStringSync(), 'page');
    });
  });

  group('what a tool can take from the library', () {
    final pdf = ScannedDocument(id: '1', title: 'a', createdAt: DateTime(2026), updatedAt: DateTime(2026), pages: const [], filePath: '/x/a.pdf');
    final docx = ScannedDocument(id: '2', title: 'b', createdAt: DateTime(2026), updatedAt: DateTime(2026), pages: const [], filePath: '/x/b.docx');
    final scan = ScannedDocument(
      id: '3',
      title: 'c',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      pages: const [DocumentPage(id: 'p', position: 0, imagePath: '/x/p.jpg', rawPath: '/x/p.jpg', width: 1, height: 1)],
    );

    test('files are matched by their type', () {
      expect(libraryUseOf(pdf, ['pdf']), LibraryUse.file);
      expect(libraryUseOf(pdf, ['.PDF']), LibraryUse.file);
      expect(libraryUseOf(docx, ['pdf']), isNull);
      expect(libraryUseOf(docx, ['pdf', 'docx']), LibraryUse.file);
    });

    test('a scan is a PDF where PDFs are taken, otherwise its pages are pictures', () {
      expect(libraryUseOf(scan, ['pdf']), LibraryUse.pdf);
      expect(libraryUseOf(scan, ['jpg', 'png', 'pdf']), LibraryUse.pdf);
      expect(libraryUseOf(scan, ['jpg', 'jpeg', 'png']), LibraryUse.images);
      expect(libraryUseOf(scan, ['xlsx']), isNull);
    });

    test('a scan with no pages is not offered', () {
      final empty = ScannedDocument(id: '4', title: 'd', createdAt: DateTime(2026), updatedAt: DateTime(2026), pages: const []);
      expect(libraryUseOf(empty, ['pdf']), isNull);
    });
  });
}

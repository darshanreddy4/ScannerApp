import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:scanvault/core/utils/format.dart';
import 'package:scanvault/features/documents/data/datasources/document_local_data_source.dart';
import 'package:scanvault/features/documents/data/document_compressor.dart';
import 'package:scanvault/features/documents/data/repositories/document_repository_impl.dart';
import 'package:scanvault/features/documents/domain/entities/scanned_document.dart';
import 'package:scanvault/features/documents/domain/usecases/document_usecases.dart';
import 'package:scanvault/features/settings/domain/feature_access.dart';
import 'package:scanvault/features/monetization/domain/entities/plan_status.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory work;
  late Directory root;
  late DocumentRepositoryImpl repo;

  setUp(() {
    work = Directory.systemTemp.createTempSync('sv_act_work');
    root = Directory.systemTemp.createTempSync('sv_act_root');
    repo = DocumentRepositoryImpl(DocumentLocalDataSource(rootDir: root));
  });

  tearDown(() {
    work.deleteSync(recursive: true);
    root.deleteSync(recursive: true);
  });

  NewPage page(String tag) {
    final f = File(p.join(work.path, 'p_$tag.jpg'))..writeAsStringSync('page-$tag');
    return NewPage(imagePath: f.path, rawPath: f.path, width: 100, height: 100);
  }

  Future<ScannedDocument> make(String title, int pages) async =>
      (await repo.saveDocument(title: title, pages: [for (var i = 0; i < pages; i++) page('$title$i')])).valueOrNull!;

  test('favorite, pin, lock and tags are saved and trimmed', () async {
    final doc = await make('Invoice', 1);
    expect(doc.favorite || doc.pinned || doc.locked, isFalse);

    final updated = (await repo.updateMeta(doc.id, favorite: true, pinned: true, locked: true, tags: [' work ', 'work', '', 'tax'])).valueOrNull!;
    expect(updated.favorite, isTrue);
    expect(updated.pinned, isTrue);
    expect(updated.locked, isTrue);
    expect(updated.tags, ['work', 'tax']);

    final partial = (await repo.updateMeta(doc.id, favorite: false)).valueOrNull!;
    expect(partial.favorite, isFalse);
    expect(partial.pinned, isTrue, reason: 'fields that were not passed must not change');
    expect(partial.tags, ['work', 'tax']);
  });

  test('setting the date changes the created and updated time', () async {
    final doc = await make('Old receipt', 1);
    final when = DateTime(2023, 5, 17, 9, 30);
    final updated = (await repo.updateMeta(doc.id, date: when)).valueOrNull!;
    expect(updated.createdAt, when);
    expect(updated.updatedAt, when);
  });

  test('updating a missing document reports a failure', () async {
    final result = await repo.updateMeta('nope', favorite: true);
    expect(result.isOk, isFalse);
  });

  test('duplicate copies pages as separate files and keeps tags and lock', () async {
    final doc = await make('Contract', 2);
    await repo.updateMeta(doc.id, tags: ['legal'], locked: true);

    final copy = (await repo.duplicateDocument(doc.id)).valueOrNull!;
    expect(copy.id, isNot(doc.id));
    expect(copy.title, 'Contract (copy)');
    expect(copy.pageCount, 2);
    expect(copy.tags, ['legal']);
    expect(copy.locked, isTrue);

    final original = (await repo.getDocument(doc.id)).valueOrNull!;
    for (var i = 0; i < 2; i++) {
      expect(copy.pages[i].imagePath, isNot(original.pages[i].imagePath));
      expect(File(copy.pages[i].imagePath).readAsStringSync(), File(original.pages[i].imagePath).readAsStringSync());
    }

    // Deleting the original must not break the copy.
    await repo.deleteDocument(doc.id);
    expect(File(copy.pages.first.imagePath).existsSync(), isTrue);
  });

  test('split moves the later pages to a new document and keeps the earlier ones', () async {
    final doc = await make('Report', 4);
    final second = (await repo.splitDocument(id: doc.id, startPage: 3)).valueOrNull!;
    final first = (await repo.getDocument(doc.id)).valueOrNull!;

    expect(first.pageCount, 2);
    expect(second.pageCount, 2);
    expect(second.title, 'Report (part 2)');
    expect(File(first.pages.first.imagePath).readAsStringSync(), 'page-Report0');
    expect(File(second.pages.first.imagePath).readAsStringSync(), 'page-Report2');
    expect(File(second.pages.last.imagePath).readAsStringSync(), 'page-Report3');
  });

  test('split rejects a start page that would leave an empty document', () async {
    final doc = await make('Short', 2);
    expect((await repo.splitDocument(id: doc.id, startPage: 1)).isOk, isFalse);
    expect((await repo.splitDocument(id: doc.id, startPage: 3)).isOk, isFalse);
    expect((await repo.getDocument(doc.id)).valueOrNull!.pageCount, 2);
  });

  test('document size adds up each stored file once', () async {
    final doc = await make('Sized', 2);
    final size = (await repo.documentSize(doc.id)).valueOrNull!;
    final expected = [for (final pg in doc.pages) File(pg.imagePath).lengthSync()].fold<int>(0, (a, b) => a + b);
    expect(size, greaterThan(0));
    // raw and processed are the same content here, so the stored raw copy is counted too.
    expect(size, greaterThanOrEqualTo(expected));
  });

  test('delete all data removes every document and folder', () async {
    await make('One', 1);
    await make('Two', 2);
    await repo.createFolder('Work');

    final result = await DeleteAllData(repo, repo)();
    expect(result.isOk, isTrue);
    expect((await repo.listDocuments()).valueOrNull, isEmpty);
    expect((await repo.listFolders()).valueOrNull, isEmpty);
  });

  test('a version 3 database gains the new columns with safe defaults', () async {
    final path = p.join(root.path, 'scanvault.db');
    final v3 = await openDatabase(
      path,
      version: 3,
      onCreate: (db, _) async {
        await db.execute('CREATE TABLE folders(id TEXT PRIMARY KEY, name TEXT NOT NULL, created_at INTEGER NOT NULL)');
        await db.execute(
          'CREATE TABLE documents(id TEXT PRIMARY KEY, title TEXT NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, folder_id TEXT)',
        );
        await db.execute(
          'CREATE TABLE pages(id TEXT PRIMARY KEY, document_id TEXT NOT NULL, position INTEGER NOT NULL, image_path TEXT NOT NULL, raw_path TEXT NOT NULL, width INTEGER NOT NULL, height INTEGER NOT NULL, cropped_path TEXT, quad TEXT, filter TEXT, brightness REAL, contrast REAL, raw_width INTEGER, raw_height INTEGER)',
        );
        await db.insert('documents', {'id': 'd1', 'title': 'Before update', 'created_at': 1, 'updated_at': 1});
      },
    );
    await v3.close();

    final docs = (await repo.listDocuments()).valueOrNull!;
    expect(docs.single.title, 'Before update');
    expect(docs.single.favorite, isFalse);
    expect(docs.single.pinned, isFalse);
    expect(docs.single.locked, isFalse);
    expect(docs.single.tags, isEmpty);
  });

  test('compression shrinks a large photo and keeps small pages as they are', () {
    final big = img.Image(width: 3000, height: 2000);
    for (final px in big) {
      px.setRgb((px.x * 7) % 256, (px.y * 3) % 256, (px.x + px.y) % 256);
    }
    final bigFile = File(p.join(work.path, 'big.jpg'))..writeAsBytesSync(Uint8List.fromList(img.encodeJpg(big, quality: 95)));
    final smallFile = File(p.join(work.path, 'small.jpg'))
      ..writeAsBytesSync(Uint8List.fromList(img.encodeJpg(img.Image(width: 300, height: 400), quality: 90)));

    final out = compressImages(inputs: [bigFile.path, smallFile.path], outDir: p.join(work.path, 'out'), maxSide: 1400, quality: 60);

    expect(out[0].width, 1400);
    expect(out[0].height, 933);
    expect(File(out[0].path).lengthSync(), lessThan(bigFile.lengthSync()));
    expect(out[1].width, 300);
    expect(out[1].height, 400);
  });

  test('formatBytes picks a readable unit', () {
    expect(formatBytes(512), '512 B');
    expect(formatBytes(2048), '2.0 kB');
    expect(formatBytes(452 * 1024), '452 kB');
    expect(formatBytes(3 * 1024 * 1024), '3.0 MB');
  });

  test('edit access is never locked while purchases are unavailable', () {
    expect(FeatureAccess.editSavedDocuments(plan: PlanStatus.free, enabled: true, billingEnabled: false), FeatureState.available);
    expect(FeatureAccess.editSavedDocuments(plan: PlanStatus.free, enabled: false, billingEnabled: false), FeatureState.hidden);
    expect(FeatureAccess.editSavedDocuments(plan: PlanStatus.free, enabled: true), FeatureState.locked);
  });
}

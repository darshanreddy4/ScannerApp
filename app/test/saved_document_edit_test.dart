import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:scanvault/features/documents/data/datasources/document_local_data_source.dart';
import 'package:scanvault/features/documents/domain/entities/scanned_document.dart';
import 'package:scanvault/features/monetization/domain/entities/plan_status.dart';
import 'package:scanvault/features/settings/domain/feature_access.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

File _file(Directory dir, String name, [String content = 'x']) => File(p.join(dir.path, name))..writeAsStringSync(content);

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory work;
  late Directory root;
  late DocumentLocalDataSource ds;

  setUp(() {
    work = Directory.systemTemp.createTempSync('sv_work');
    root = Directory.systemTemp.createTempSync('sv_root');
    ds = DocumentLocalDataSource(rootDir: root);
  });

  tearDown(() {
    work.deleteSync(recursive: true);
    root.deleteSync(recursive: true);
  });

  NewPage page(String tag, {bool withEdit = true, bool filtered = true}) {
    final processed = _file(work, 'proc_$tag.jpg', 'processed-$tag');
    final raw = _file(work, 'raw_$tag.jpg', 'raw-$tag');
    final cropped = filtered ? _file(work, 'crop_$tag.jpg', 'cropped-$tag') : processed;
    return NewPage(
      imagePath: processed.path,
      rawPath: raw.path,
      width: 800,
      height: 1200,
      edit: withEdit
          ? PageEditInfo(
              croppedPath: cropped.path,
              quad: const [0.1, 0.1, 0.9, 0.1, 0.9, 0.9, 0.1, 0.9],
              filter: 'documentBw',
              brightness: 12,
              contrast: -5,
              rawWidth: 4000,
              rawHeight: 3000,
            )
          : null,
    );
  }

  test('edit metadata round-trips and the cropped image is stored separately', () async {
    final doc = await ds.insert('Contract', [page('a')], null);
    final saved = doc.pages.single;

    expect(saved.edit, isNotNull);
    expect(saved.edit!.filter, 'documentBw');
    expect(saved.edit!.brightness, 12);
    expect(saved.edit!.contrast, -5);
    expect(saved.edit!.quad.length, 8);
    expect(saved.edit!.rawWidth, 4000);
    expect(saved.edit!.croppedPath, isNot(saved.imagePath));
    expect(File(saved.edit!.croppedPath).readAsStringSync(), 'cropped-a');
    expect(File(saved.imagePath).readAsStringSync(), 'processed-a');
  });

  test('an unfiltered page reuses the processed file as its cropped image', () async {
    final doc = await ds.insert('Plain', [page('a', filtered: false)], null);
    final saved = doc.pages.single;
    expect(saved.edit!.croppedPath, saved.imagePath);
  });

  test('pages saved without edit info come back with edit == null', () async {
    final doc = await ds.insert('Old style', [page('a', withEdit: false)], null);
    expect(doc.pages.single.edit, isNull);
  });

  test('replacePages swaps pages and title and removes the old files', () async {
    final folder = await ds.createFolder('Work');
    final doc = await ds.insert('Before', [page('a'), page('b')], folder.id);
    final oldFiles = [for (final pg in doc.pages) pg.imagePath];

    final updated = await ds.replacePages(doc.id, 'After', [page('c')]);

    expect(updated.title, 'After');
    expect(updated.pages.length, 1);
    expect(File(updated.pages.single.imagePath).readAsStringSync(), 'processed-c');
    expect(updated.folderId, folder.id);
    for (final f in oldFiles) {
      expect(File(f).existsSync(), isFalse, reason: '$f should be removed');
    }
    expect(updated.updatedAt.isBefore(doc.createdAt), isFalse);
  });

  test('replacePages can reuse files that already belong to the document', () async {
    final doc = await ds.insert('Doc', [page('a')], null);
    final existing = doc.pages.single;

    final updated = await ds.replacePages(doc.id, 'Doc', [
      NewPage(imagePath: existing.imagePath, rawPath: existing.rawPath, width: existing.width, height: existing.height, edit: existing.edit),
    ]);

    final pg = updated.pages.single;
    expect(File(pg.imagePath).readAsStringSync(), 'processed-a');
    expect(File(pg.rawPath).readAsStringSync(), 'raw-a');
    expect(File(pg.edit!.croppedPath).readAsStringSync(), 'cropped-a');
  });

  test('a failed replace leaves the original document intact', () async {
    final doc = await ds.insert('Keep me', [page('a')], null);
    final broken = NewPage(imagePath: p.join(work.path, 'missing.jpg'), rawPath: p.join(work.path, 'missing_raw.jpg'), width: 1, height: 1);

    await expectLater(ds.replacePages(doc.id, 'Changed', [broken]), throwsA(isA<FileSystemException>()));

    final after = (await ds.get(doc.id))!;
    expect(after.title, 'Keep me');
    expect(File(after.pages.single.imagePath).existsSync(), isTrue);
  });

  test('a version 2 database is upgraded and old pages open without edit info', () async {
    final path = p.join(root.path, 'scanvault.db');
    final v2 = await openDatabase(
      path,
      version: 2,
      onCreate: (db, _) async {
        await db.execute('CREATE TABLE folders(id TEXT PRIMARY KEY, name TEXT NOT NULL, created_at INTEGER NOT NULL)');
        await db.execute(
          'CREATE TABLE documents(id TEXT PRIMARY KEY, title TEXT NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, folder_id TEXT)',
        );
        await db.execute(
          'CREATE TABLE pages(id TEXT PRIMARY KEY, document_id TEXT NOT NULL, position INTEGER NOT NULL, image_path TEXT NOT NULL, raw_path TEXT NOT NULL, width INTEGER NOT NULL, height INTEGER NOT NULL)',
        );
        await db.insert('documents', {'id': 'd1', 'title': 'Legacy', 'created_at': 1, 'updated_at': 1});
        await db.insert('pages', {
          'id': 'p1',
          'document_id': 'd1',
          'position': 0,
          'image_path': 'scans/d1/page_0.jpg',
          'raw_path': 'scans/d1/raw_0.jpg',
          'width': 10,
          'height': 20,
        });
      },
    );
    await v2.close();

    final docs = await ds.list();
    expect(docs.single.title, 'Legacy');
    expect(docs.single.pages.single.edit, isNull);

    final updated = await ds.insert('New after upgrade', [page('a')], null);
    expect(updated.pages.single.edit, isNotNull);
  });

  group('FeatureAccess.editSavedDocuments', () {
    test('switch off hides it for everyone', () {
      expect(FeatureAccess.editSavedDocuments(plan: PlanStatus.premium, enabled: false), FeatureState.hidden);
      expect(FeatureAccess.editSavedDocuments(plan: PlanStatus.free, enabled: false), FeatureState.hidden);
    });

    test('switch on unlocks it for premium and locks it for free', () {
      expect(FeatureAccess.editSavedDocuments(plan: PlanStatus.premium, enabled: true), FeatureState.available);
      expect(FeatureAccess.editSavedDocuments(plan: PlanStatus.free, enabled: true), FeatureState.locked);
    });
  });
}

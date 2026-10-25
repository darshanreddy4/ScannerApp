import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:scanvault/app/incoming_files.dart';
import 'package:scanvault/core/storage/temp_files.dart';
import 'package:scanvault/features/documents/data/datasources/document_local_data_source.dart';
import 'package:scanvault/features/documents/domain/entities/scanned_document.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tmp;
  late TempFiles temp;

  File touch(String rel, {Duration age = Duration.zero}) {
    final f = File(p.join(tmp.path, rel))
      ..createSync(recursive: true)
      ..writeAsStringSync('x');
    f.setLastModifiedSync(DateTime.now().subtract(age));
    return f;
  }

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sv_tmp');
    temp = TempFiles(tempDir: () async => tmp);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  group('TempFiles', () {
    test('startup clears the cache but keeps fresh received files and SDK caches', () async {
      touch('scan_work/a.jpg');
      touch('exports/doc.pdf');
      touch('file_picker/x.pdf');
      touch('qr_code.png');
      final fresh = touch('incoming/1-1/new.pdf');
      final stale = touch('incoming/0-1/old.pdf', age: const Duration(days: 3));
      // Dart cannot back-date a folder, so use touch.
      Process.runSync('touch', ['-t', '202001010000', p.join(tmp.path, 'incoming/0-1')]);
      final webview = touch('WebView/Default/data');

      await temp.clearAtStartup();

      expect(Directory(p.join(tmp.path, 'scan_work')).existsSync(), isFalse);
      expect(Directory(p.join(tmp.path, 'exports')).existsSync(), isFalse);
      expect(Directory(p.join(tmp.path, 'file_picker')).existsSync(), isFalse);
      expect(File(p.join(tmp.path, 'qr_code.png')).existsSync(), isFalse);
      expect(fresh.existsSync(), isTrue);
      expect(stale.existsSync(), isFalse);
      expect(webview.existsSync(), isTrue);
    });

    test('clearing scan work spares files created after the cutoff', () async {
      final before = touch('scan_work/old.jpg', age: const Duration(minutes: 5));
      final cutoff = DateTime.now().subtract(const Duration(minutes: 1));
      final after = touch('scan_work/new.jpg');

      await temp.clearScanWork(cutoff);

      expect(before.existsSync(), isFalse);
      expect(after.existsSync(), isTrue);
      expect(Directory(p.join(tmp.path, 'scan_work')).existsSync(), isTrue, reason: 'the folder itself must stay for later writes');
    });

    test('pruning removes old exports but not recent ones or the scan work in use', () async {
      final oldExport = touch('exports/old.pdf', age: const Duration(hours: 2));
      final newExport = touch('exports/new.pdf');
      final oldShare = touch('share_images/a-1.jpg', age: const Duration(hours: 2));
      final work = touch('scan_work/live.jpg', age: const Duration(hours: 5));
      final received = touch('incoming/1-1/a.pdf', age: const Duration(hours: 5));

      await temp.pruneStale();

      expect(oldExport.existsSync(), isFalse);
      expect(oldShare.existsSync(), isFalse);
      expect(newExport.existsSync(), isTrue);
      expect(work.existsSync(), isTrue);
      expect(received.existsSync(), isTrue);
    });
  });

  group('orphan page folders', () {
    test('only folders without a document are removed', () async {
      final root = Directory.systemTemp.createTempSync('sv_orphan');
      addTearDown(() => root.deleteSync(recursive: true));
      final work = File(p.join(root.path, 'src.jpg'))..writeAsStringSync('img');
      final ds = DocumentLocalDataSource(rootDir: root);

      final doc = await ds.insert('Keep', [NewPage(imagePath: work.path, rawPath: work.path, width: 1, height: 1)], null);
      Directory(p.join(root.path, 'scans', 'leftover-from-crash')).createSync(recursive: true);

      expect(await ds.removeOrphanFiles(), 1);
      expect(Directory(p.join(root.path, 'scans', 'leftover-from-crash')).existsSync(), isFalse);
      expect(File((await ds.get(doc.id))!.pages.single.imagePath).existsSync(), isTrue);
    });
  });

  group('incoming file kinds', () {
    test('are recognised by extension or mime type', () {
      expect(classifyIncoming('/c/a.PDF', ''), IncomingKind.pdf);
      expect(classifyIncoming('/c/noext', 'application/pdf'), IncomingKind.pdf);
      expect(classifyIncoming('/c/a.docx', ''), IncomingKind.docx);
      expect(classifyIncoming('/c/a.jpeg', ''), IncomingKind.image);
      expect(classifyIncoming('/c/b', 'image/png'), IncomingKind.image);
      expect(classifyIncoming('/c/a.zip', 'application/zip'), IncomingKind.unsupported);
    });
  });
}

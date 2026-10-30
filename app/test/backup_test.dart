import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:doculoom/core/error/failures.dart';
import 'package:doculoom/features/backup/data/backup_container.dart';
import 'package:doculoom/features/backup/data/backup_service.dart';
import 'package:doculoom/features/documents/data/datasources/document_local_data_source.dart';
import 'package:doculoom/features/documents/data/repositories/document_repository_impl.dart';
import 'package:doculoom/features/documents/domain/entities/scanned_document.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _iterations = 1000;

Uint8List _bytes(int n, int seed) {
  final r = Random(seed);
  return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory work;
  setUp(() => work = Directory.systemTemp.createTempSync('sv_backup'));
  tearDown(() => work.deleteSync(recursive: true));

  String path(String name) => p.join(work.path, name);

  Future<void> write(String file, String password, Map<String, List<int>> records) async {
    final w = await BackupWriter.open(file, password, iterations: _iterations);
    for (final e in records.entries) {
      await w.addBytes(e.key, e.value);
    }
    await w.close();
  }

  Future<Directory> read(String file, String password) async {
    final out = Directory(path('out_${DateTime.now().microsecondsSinceEpoch}'))..createSync();
    await readBackup(file, password, out);
    return out;
  }

  Future<BackupProblem?> problemOf(Future<void> Function() body) async {
    try {
      await body();
      return null;
    } on BackupException catch (e) {
      return e.problem;
    }
  }

  group('backup file', () {
    test('records of every size come back unchanged, including ones that cross chunk edges', () async {
      final records = {
        'manifest.json': utf8.encode('{"a":1}'),
        'empty.bin': <int>[],
        'd0/small.jpg': _bytes(10, 1),
        'd0/exactly_a_chunk.bin': _bytes(1 << 20, 2),
        'd1/big.jpg': _bytes((2.5 * (1 << 20)).toInt() + 7, 3),
        'd1/last.jpg': _bytes(1, 4),
      };
      await write(path('a.svbackup'), 'correct horse', records);
      final out = await read(path('a.svbackup'), 'correct horse');
      for (final e in records.entries) {
        expect(File(p.join(out.path, e.key)).readAsBytesSync(), e.value, reason: e.key);
      }
    });

    test('files are streamed from disk and an empty backup is valid', () async {
      final src = File(path('src.bin'))..writeAsBytesSync(_bytes(3 * (1 << 20) + 5, 9));
      final w = await BackupWriter.open(path('f.svbackup'), 'pw-pw-pw-pw', iterations: _iterations);
      await w.addFile('d0/src.bin', src.path);
      await w.close();
      final out = await read(path('f.svbackup'), 'pw-pw-pw-pw');
      expect(File(p.join(out.path, 'd0/src.bin')).readAsBytesSync(), src.readAsBytesSync());

      await write(path('empty.svbackup'), 'pw-pw-pw-pw', {});
      final none = await read(path('empty.svbackup'), 'pw-pw-pw-pw');
      expect(none.listSync(), isEmpty);
    });

    test('the file does not contain the content in the clear', () async {
      final secret = utf8.encode('PASSPORT-NUMBER-X1234567');
      await write(path('s.svbackup'), 'correct horse', {'manifest.json': secret});
      final raw = File(path('s.svbackup')).readAsBytesSync();
      expect(utf8.decode(raw, allowMalformed: true).contains('PASSPORT'), isFalse);
    });

    test('a wrong password is reported as such and writes nothing', () async {
      await write(path('a.svbackup'), 'correct horse', {'manifest.json': _bytes(100, 5)});
      final out = Directory(path('o'))..createSync();
      expect(await problemOf(() => readBackup(path('a.svbackup'), 'wrong horse', out)), BackupProblem.wrongPassword);
      expect(out.listSync(), isEmpty);
    });

    test('files that are not backups are refused', () async {
      File(path('x.txt')).writeAsStringSync('hello');
      File(path('empty')).writeAsBytesSync([]);
      final out = Directory(path('o'))..createSync();
      expect(await problemOf(() => readBackup(path('x.txt'), 'pw', out)), BackupProblem.notABackup);
      expect(await problemOf(() => readBackup(path('empty'), 'pw', out)), BackupProblem.notABackup);
      expect(await looksLikeBackup(path('x.txt')), isFalse);
      await write(path('a.svbackup'), 'pw-pw-pw-pw', {
        'manifest.json': [1],
      });
      expect(await looksLikeBackup(path('a.svbackup')), isTrue);
    });

    test('a backup that was cut off is detected, at any point', () async {
      await write(path('a.svbackup'), 'correct horse', {'manifest.json': _bytes(2500000, 6)});
      final full = File(path('a.svbackup')).readAsBytesSync();
      for (final cut in [full.length - 1, full.length - 40, full.length ~/ 2, 40, 30]) {
        File(path('cut.svbackup')).writeAsBytesSync(full.sublist(0, cut));
        final out = Directory(path('o$cut'))..createSync();
        expect(await problemOf(() => readBackup(path('cut.svbackup'), 'correct horse', out)), BackupProblem.damaged, reason: 'cut at $cut of ${full.length}');
      }
    });

    test('a whole chunk removed from the end is detected through the last-chunk mark', () async {
      await write(path('a.svbackup'), 'correct horse', {'manifest.json': _bytes(2500000, 6)});
      final full = File(path('a.svbackup')).readAsBytesSync();
      // Frames: 29 header, then [5 + 1MiB + 16] twice, then the short last one.
      final firstTwo = 29 + 2 * (5 + (1 << 20) + 16);
      File(path('cut.svbackup')).writeAsBytesSync(full.sublist(0, firstTwo));
      final out = Directory(path('o'))..createSync();
      expect(await problemOf(() => readBackup(path('cut.svbackup'), 'correct horse', out)), BackupProblem.damaged);
    });

    test('any changed byte is detected', () async {
      await write(path('a.svbackup'), 'correct horse', {'manifest.json': _bytes(5000, 7), 'd0/p.jpg': _bytes(5000, 8)});
      final full = File(path('a.svbackup')).readAsBytesSync();
      for (final at in [40, 200, full.length - 3, full.length - 20]) {
        final copy = Uint8List.fromList(full)..[at] ^= 0x01;
        File(path('t.svbackup')).writeAsBytesSync(copy);
        final out = Directory(path('o$at'))..createSync();
        expect(await problemOf(() => readBackup(path('t.svbackup'), 'correct horse', out)), isNotNull, reason: 'byte $at');
      }
    });

    test('extra bytes after the end are refused', () async {
      await write(path('a.svbackup'), 'correct horse', {'manifest.json': _bytes(50, 7)});
      final f = File(path('a.svbackup'));
      f.writeAsBytesSync([...f.readAsBytesSync(), 1, 2, 3]);
      final out = Directory(path('o'))..createSync();
      expect(await problemOf(() => readBackup(f.path, 'correct horse', out)), BackupProblem.damaged);
    });

    test('a backup from a newer version says so', () async {
      await write(path('a.svbackup'), 'correct horse', {'manifest.json': _bytes(50, 7)});
      final bytes = File(path('a.svbackup')).readAsBytesSync()..[4] = 9;
      File(path('n.svbackup')).writeAsBytesSync(bytes);
      final out = Directory(path('o'))..createSync();
      expect(await problemOf(() => readBackup(path('n.svbackup'), 'correct horse', out)), BackupProblem.newerVersion);
    });

    test('names that would leave the folder are refused', () async {
      for (final name in ['../evil.txt', '/abs.txt', 'a/../../evil.txt', 'a\\b.txt', 'a//b.txt', '']) {
        await write(path('z.svbackup'), 'correct horse', {name: utf8.encode('x')});
        final out = Directory(path('o_${name.hashCode}'))..createSync();
        expect(await problemOf(() => readBackup(path('z.svbackup'), 'correct horse', out)), BackupProblem.damaged, reason: 'name "$name"');
      }
      expect(File(p.join(work.path, 'evil.txt')).existsSync(), isFalse);
    });

    test('the same name twice is refused', () async {
      final w = await BackupWriter.open(path('d.svbackup'), 'correct horse', iterations: _iterations);
      await w.addBytes('a.txt', [1]);
      await w.addBytes('a.txt', [2]);
      await w.close();
      final out = Directory(path('o'))..createSync();
      expect(await problemOf(() => readBackup(path('d.svbackup'), 'correct horse', out)), BackupProblem.damaged);
    });

    test('two backups of the same data differ, so nothing can be compared between them', () async {
      await write(path('a.svbackup'), 'correct horse', {'manifest.json': _bytes(100, 1)});
      await write(path('b.svbackup'), 'correct horse', {'manifest.json': _bytes(100, 1)});
      expect(File(path('a.svbackup')).readAsBytesSync(), isNot(File(path('b.svbackup')).readAsBytesSync()));
    });
  });

  group('backup and restore of documents', () {
    late Directory rootA, rootB, files;
    late DocumentRepositoryImpl a, b;
    late LocalBackupService backupA, backupB;

    setUp(() {
      rootA = Directory.systemTemp.createTempSync('sv_bk_a');
      rootB = Directory.systemTemp.createTempSync('sv_bk_b');
      files = Directory.systemTemp.createTempSync('sv_bk_files');
      a = DocumentRepositoryImpl(DocumentLocalDataSource(rootDir: rootA));
      b = DocumentRepositoryImpl(DocumentLocalDataSource(rootDir: rootB));
      backupA = LocalBackupService(documents: a, folders: a, tempDir: () async => work, iterations: _iterations);
      backupB = LocalBackupService(documents: b, folders: b, tempDir: () async => work, iterations: _iterations);
    });

    tearDown(() {
      for (final d in [rootA, rootB, files]) {
        d.deleteSync(recursive: true);
      }
    });

    NewPage page(String tag, {bool edited = false}) {
      final img = File(p.join(files.path, 'img_$tag.jpg'))..writeAsBytesSync(_bytes(300, tag.hashCode));
      if (!edited) return NewPage(imagePath: img.path, rawPath: img.path, width: 30, height: 40);
      final raw = File(p.join(files.path, 'raw_$tag.jpg'))..writeAsBytesSync(_bytes(300, tag.hashCode + 1));
      final crop = File(p.join(files.path, 'crop_$tag.jpg'))..writeAsBytesSync(_bytes(300, tag.hashCode + 2));
      return NewPage(
        imagePath: img.path,
        rawPath: raw.path,
        width: 30,
        height: 40,
        edit: PageEditInfo(
          croppedPath: crop.path,
          quad: const [0.1, 0.1, 0.9, 0.1, 0.9, 0.9, 0.1, 0.9],
          filter: 'magicColor',
          brightness: 0.2,
          contrast: -0.1,
          rawWidth: 60,
          rawHeight: 80,
        ),
      );
    }

    test('everything comes back: pages, edit info, folders, flags, tags and dates', () async {
      final folder = (await a.createFolder('Taxes', style: const FolderStyle(icon: 'work', color: 0xFF112233))).valueOrNull!;
      await a.updateFolderMeta(folder.id, favorite: true);
      final plain = (await a.saveDocument(title: 'Receipt', pages: [page('r1'), page('r2')])).valueOrNull!;
      final edited = (await a.saveDocument(title: 'Contract', pages: [page('c1', edited: true)], folderId: folder.id)).valueOrNull!;
      await a.updateMeta(edited.id, favorite: true, pinned: true, locked: true, tags: ['legal', 'work'], date: DateTime(2024, 3, 4, 5, 6));
      await a.updateMeta(plain.id, date: DateTime(2023, 1, 2));
      await a.updateMeta(edited.id, expires: DateTime(2031, 8, 9, 12));

      final made = (await backupA.create(password: 'long enough pw', outputPath: path('all.svbackup'))).valueOrNull!;
      expect(made.documents, 2);
      expect(made.pages, 3);
      expect(made.bytes, greaterThan(900));

      final restored = (await backupB.restore(path: path('all.svbackup'), password: 'long enough pw')).valueOrNull!;
      expect(restored.added, 2);
      expect(restored.alreadyHere, 0);
      expect(restored.pages, 3);

      final docs = (await b.listDocuments()).valueOrNull!;
      expect(docs.map((d) => d.title), unorderedEquals(['Receipt', 'Contract']));
      final contract = docs.firstWhere((d) => d.title == 'Contract');
      expect(contract.favorite && contract.pinned && contract.locked, isTrue);
      expect(contract.tags, ['legal', 'work']);
      expect(contract.createdAt, DateTime(2024, 3, 4, 5, 6));
      expect(contract.expiresAt, DateTime(2031, 8, 9, 12));
      final page0 = contract.pages.single;
      expect(page0.edit!.filter, 'magicColor');
      expect(page0.edit!.quad, [0.1, 0.1, 0.9, 0.1, 0.9, 0.9, 0.1, 0.9]);
      expect(page0.edit!.rawWidth, 60);
      expect(File(page0.imagePath).readAsBytesSync(), File(edited.pages.single.imagePath).readAsBytesSync());
      expect(File(page0.rawPath).readAsBytesSync(), File(edited.pages.single.rawPath).readAsBytesSync());
      expect(File(page0.edit!.croppedPath).readAsBytesSync(), File(edited.pages.single.edit!.croppedPath).readAsBytesSync());
      expect(contract.folderId, isNotNull);

      final receipt = docs.firstWhere((d) => d.title == 'Receipt');
      expect(receipt.pages.length, 2);
      expect(receipt.pages.first.edit, isNull);
      expect(receipt.createdAt, DateTime(2023, 1, 2));
      expect(receipt.expiresAt, isNull);

      final folders = (await b.listFolders()).valueOrNull!;
      expect(folders.single.name, 'Taxes');
      expect(folders.single.favorite, isTrue);
      expect(folders.single.icon, 'work');
      expect(folders.single.color, 0xFF112233);
      expect(contract.folderId, folders.single.id);
      expect(work.listSync().whereType<Directory>().where((d) => p.basename(d.path).startsWith('restore_')), isEmpty, reason: 'temporary files are removed');
    });

    test('restoring again adds nothing twice, and a partly present library gets only what is missing', () async {
      await a.saveDocument(title: 'One', pages: [page('1')]);
      await a.saveDocument(title: 'Two', pages: [page('2')]);
      await backupA.create(password: 'long enough pw', outputPath: path('all.svbackup'));

      final first = (await backupB.restore(path: path('all.svbackup'), password: 'long enough pw')).valueOrNull!;
      expect(first.added, 2);
      final again = (await backupB.restore(path: path('all.svbackup'), password: 'long enough pw')).valueOrNull!;
      expect(again.added, 0);
      expect(again.alreadyHere, 2);
      expect((await b.listDocuments()).valueOrNull!.length, 2);

      await a.saveDocument(title: 'Three', pages: [page('3')]);
      await backupA.create(password: 'long enough pw', outputPath: path('more.svbackup'));
      final more = (await backupB.restore(path: path('more.svbackup'), password: 'long enough pw')).valueOrNull!;
      expect(more.added, 1);
      expect(more.alreadyHere, 2);
    });

    test('restoring into a phone that has its own documents keeps them', () async {
      await b.saveDocument(title: 'Mine', pages: [page('mine')]);
      await a.saveDocument(title: 'Theirs', pages: [page('theirs')]);
      await backupA.create(password: 'long enough pw', outputPath: path('x.svbackup'));
      await backupB.restore(path: path('x.svbackup'), password: 'long enough pw');
      expect((await b.listDocuments()).valueOrNull!.map((d) => d.title), unorderedEquals(['Mine', 'Theirs']));
    });

    test('a wrong password changes nothing and says so', () async {
      await a.saveDocument(title: 'One', pages: [page('1')]);
      await backupA.create(password: 'long enough pw', outputPath: path('all.svbackup'));
      final r = await backupB.restore(path: path('all.svbackup'), password: 'not the password');
      expect(r.failureOrNull, isA<PasswordFailure>());
      expect((await b.listDocuments()).valueOrNull, isEmpty);
    });

    test('damaged and foreign files give a readable message and change nothing', () async {
      File(path('notes.txt')).writeAsStringSync('hello');
      final r = await backupB.restore(path: path('notes.txt'), password: 'long enough pw');
      expect(r.failureOrNull!.message, contains('not a Doculoom backup'));

      await a.saveDocument(title: 'One', pages: [page('1')]);
      await backupA.create(password: 'long enough pw', outputPath: path('all.svbackup'));
      final bytes = File(path('all.svbackup')).readAsBytesSync();
      File(path('cut.svbackup')).writeAsBytesSync(bytes.sublist(0, bytes.length - 20));
      final cut = await backupB.restore(path: path('cut.svbackup'), password: 'long enough pw');
      expect(cut.failureOrNull!.message, contains('incomplete'));
      expect((await b.listDocuments()).valueOrNull, isEmpty);
    });

    test('an empty library makes a valid backup', () async {
      final made = (await backupA.create(password: 'long enough pw', outputPath: path('none.svbackup'))).valueOrNull!;
      expect(made.documents, 0);
      final restored = (await backupB.restore(path: path('none.svbackup'), password: 'long enough pw')).valueOrNull!;
      expect(restored.added, 0);
    });

    test('a backup made before the rename, with the old format tag, still restores', () async {
      await backupA.create(password: 'long enough pw', outputPath: path('new.dlbackup'));
      final out = await read(path('new.dlbackup'), 'long enough pw');
      final manifest = File(p.join(out.path, 'manifest.json')).readAsStringSync();
      expect(manifest, contains('"doculoom-backup"'));
      await write(path('old.svbackup'), 'long enough pw', {'manifest.json': utf8.encode(manifest.replaceFirst('doculoom-backup', 'scanvault-backup'))});
      final restored = await backupB.restore(path: path('old.svbackup'), password: 'long enough pw');
      expect(restored.failureOrNull, isNull);
      expect(restored.valueOrNull!.added, 0);
    });

    test('a page whose picture is missing is left out instead of stopping the backup', () async {
      final doc = (await a.saveDocument(title: 'Broken', pages: [page('x1'), page('x2')])).valueOrNull!;
      File(doc.pages.first.imagePath).deleteSync();
      final made = (await backupA.create(password: 'long enough pw', outputPath: path('b.svbackup'))).valueOrNull!;
      expect(made.pages, 1);
      await backupB.restore(path: path('b.svbackup'), password: 'long enough pw');
      expect((await b.listDocuments()).valueOrNull!.single.pages.length, 1);
    });
  });
}

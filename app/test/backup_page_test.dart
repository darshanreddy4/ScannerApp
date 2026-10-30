import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:doculoom/core/error/failures.dart';
import 'package:doculoom/core/error/result.dart';
import 'package:doculoom/core/theme/app_theme.dart';
import 'package:doculoom/features/backup/data/backup_service.dart';
import 'package:doculoom/features/backup/presentation/backup_page.dart';

class _Service implements BackupService {
  final creates = <({String password, String path})>[];
  final restores = <({String path, String password})>[];
  Completer<void>? hold;
  Result<BackupSummary> createResult = const Ok(BackupSummary(documents: 12, pages: 40, bytes: 38 * 1024 * 1024));
  Result<RestoreSummary> restoreResult = const Ok(RestoreSummary(added: 5, alreadyHere: 2, pages: 11));

  @override
  Future<Result<BackupSummary>> create({required String password, required String outputPath}) async {
    creates.add((password: password, path: outputPath));
    await hold?.future;
    return createResult;
  }

  @override
  Future<Result<RestoreSummary>> restore({required String path, required String password}) async {
    restores.add((path: path, password: password));
    await hold?.future;
    return restoreResult;
  }
}

void main() {
  late Directory work;
  late _Service service;
  late String? picked;
  var restoredCalls = 0;

  setUp(() {
    work = Directory.systemTemp.createTempSync('sv_bk_page');
    service = _Service();
    picked = null;
    restoredCalls = 0;
  });
  tearDown(() => work.deleteSync(recursive: true));

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: BackupPage(service: service, workDir: () async => work, pickBackup: () async => picked, onRestored: () => restoredCalls++),
      ),
    );
    await tester.pump();
  }

  Future<void> typePassword(WidgetTester tester, String a, {String? again}) async {
    await tester.enterText(find.byKey(const ValueKey('backup-password')), a);
    if (again != null) await tester.enterText(find.byKey(const ValueKey('backup-password-again')), again);
    await tester.pump();
  }

  bool okEnabled(WidgetTester tester) => tester.widget<FilledButton>(find.byKey(const ValueKey('backup-password-ok'))).onPressed != null;

  Future<void> pumpAsync(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('explains backup and restore and warns that the password cannot be recovered', (tester) async {
    await open(tester);
    expect(find.byKey(const ValueKey('backup-create')), findsOneWidget);
    expect(find.byKey(const ValueKey('backup-restore')), findsOneWidget);
    expect(find.textContaining('cannot be recovered'), findsOneWidget);
  });

  testWidgets('a backup needs a password of 8 characters typed twice', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('backup-create')));
    await tester.pumpAndSettle();
    expect(okEnabled(tester), isFalse);

    await typePassword(tester, 'short', again: 'short');
    expect(okEnabled(tester), isFalse);
    expect(find.textContaining('at least 8'), findsOneWidget);

    await typePassword(tester, 'long enough pw', again: 'long enough px');
    expect(okEnabled(tester), isFalse);
    expect(find.textContaining('do not match'), findsOneWidget);

    await typePassword(tester, 'long enough pw', again: 'long enough pw');
    expect(okEnabled(tester), isTrue);
    expect(service.creates, isEmpty, reason: 'nothing happens before Continue');
  });

  testWidgets('cancelling the password question makes no backup', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('backup-create')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(service.creates, isEmpty);
  });

  testWidgets('creating a backup shows progress, then how much was saved and how to keep it', (tester) async {
    service.hold = Completer<void>();
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('backup-create')));
    await tester.pumpAndSettle();
    await typePassword(tester, 'long enough pw', again: 'long enough pw');
    await tester.tap(find.byKey(const ValueKey('backup-password-ok')));
    await tester.pump();
    await pumpAsync(tester);

    expect(service.creates.single.password, 'long enough pw');
    expect(p.dirname(service.creates.single.path), p.join(work.path, 'exports'));
    expect(p.basename(service.creates.single.path), matches(RegExp(r'^Doculoom-backup-\d{4}-\d{2}-\d{2}\.dlbackup$')));
    expect(find.text('Encrypting backup'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('backup-create'))).onPressed, isNull, reason: 'no second backup while one runs');

    service.hold!.complete();
    await pumpAsync(tester);
    expect(find.text('Encrypting backup'), findsNothing);
    expect(find.textContaining('12 documents, 40 pages, 38 MB'), findsOneWidget);
    expect(find.byKey(const ValueKey('backup-share')), findsOneWidget);
    expect(find.byKey(const ValueKey('backup-save')), findsOneWidget);
  });

  testWidgets('a backup that fails says why and offers nothing to share', (tester) async {
    service.createResult = const Err(StorageFailure('The device is out of storage space.'));
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('backup-create')));
    await tester.pumpAndSettle();
    await typePassword(tester, 'long enough pw', again: 'long enough pw');
    await tester.tap(find.byKey(const ValueKey('backup-password-ok')));
    await pumpAsync(tester);
    expect(find.textContaining('out of storage'), findsOneWidget);
    expect(find.byKey(const ValueKey('backup-share')), findsNothing);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('backup-create'))).onPressed, isNotNull, reason: 'can try again');
  });

  testWidgets('choosing nothing, or a file that is not a backup, restores nothing', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('backup-restore')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('backup-password')), findsNothing);

    picked = (File(p.join(work.path, 'photo.jpg'))..writeAsBytesSync([1, 2, 3, 4, 5])).path;
    await tester.tap(find.byKey(const ValueKey('backup-restore')));
    await pumpAsync(tester);
    expect(find.text('This file is not a Doculoom backup.'), findsOneWidget);
    expect(find.byKey(const ValueKey('backup-password')), findsNothing);
    expect(service.restores, isEmpty);
  });

  testWidgets('restoring asks for the password, then reports what was added and what was already there', (tester) async {
    picked = (File(p.join(work.path, 'mine.svbackup'))..writeAsBytesSync([0x53, 0x56, 0x42, 0x4B, 1, 2, 3])).path;
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('backup-restore')));
    await pumpAsync(tester);
    expect(find.byKey(const ValueKey('backup-password-again')), findsNothing, reason: 'restoring needs the password once');
    expect(okEnabled(tester), isFalse);

    await typePassword(tester, 'the password');
    await tester.tap(find.byKey(const ValueKey('backup-password-ok')));
    await pumpAsync(tester);

    expect(service.restores.single, (path: picked!, password: 'the password'));
    expect(restoredCalls, 1, reason: 'the document list is refreshed');
    final text = tester.widget<Text>(find.byKey(const ValueKey('restore-result'))).data!;
    expect(text, contains('Added 5 documents (11 pages)'));
    expect(text, contains('2 were already on this phone'));
  });

  testWidgets('a wrong password or damaged file shows the message and does not refresh the list', (tester) async {
    picked = (File(p.join(work.path, 'mine.svbackup'))..writeAsBytesSync([0x53, 0x56, 0x42, 0x4B, 1])).path;
    service.restoreResult = const Err(PasswordFailure('The password is not correct.'));
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('backup-restore')));
    await pumpAsync(tester);
    await typePassword(tester, 'wrong');
    await tester.tap(find.byKey(const ValueKey('backup-password-ok')));
    await pumpAsync(tester);
    expect(find.textContaining('password is not correct'), findsOneWidget);
    expect(restoredCalls, 0);
    expect(find.byKey(const ValueKey('restore-result')), findsNothing);
  });

  testWidgets('a backup with nothing new says so plainly', (tester) async {
    picked = (File(p.join(work.path, 'mine.svbackup'))..writeAsBytesSync([0x53, 0x56, 0x42, 0x4B, 1])).path;
    service.restoreResult = const Ok(RestoreSummary(added: 0, alreadyHere: 3, pages: 0));
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('backup-restore')));
    await pumpAsync(tester);
    await typePassword(tester, 'pw');
    await tester.tap(find.byKey(const ValueKey('backup-password-ok')));
    await pumpAsync(tester);
    expect(tester.widget<Text>(find.byKey(const ValueKey('restore-result'))).data, contains('All 3 documents in it are already on this phone'));
  });
}

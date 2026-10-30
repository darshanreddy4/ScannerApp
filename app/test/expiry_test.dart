import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:doculoom/core/theme/app_theme.dart';
import 'package:doculoom/features/documents/data/datasources/document_local_data_source.dart';
import 'package:doculoom/features/documents/data/repositories/document_repository_impl.dart';
import 'package:doculoom/features/documents/domain/entities/scanned_document.dart';
import 'package:doculoom/features/documents/domain/expiry.dart';
import 'package:doculoom/features/documents/presentation/widgets/expiring_banner.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

ScannedDocument _doc(String id, String title, DateTime? expires) =>
    ScannedDocument(id: id, title: title, createdAt: DateTime(2026), updatedAt: DateTime(2026), pages: const [], expiresAt: expires);

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final now = DateTime(2026, 10, 25, 14, 30);

  group('days and wording', () {
    test('whole calendar days, whatever the time of day', () {
      expect(daysUntil(DateTime(2026, 10, 25, 0, 1), DateTime(2026, 10, 25, 23, 59)), 0);
      expect(daysUntil(DateTime(2026, 10, 26, 12), DateTime(2026, 10, 25, 23, 59)), 1);
      expect(daysUntil(DateTime(2026, 10, 24, 23, 59), DateTime(2026, 10, 25, 0, 1)), -1);
      expect(daysUntil(DateTime(2027, 10, 25), DateTime(2026, 10, 25)), 365);
    });

    test('wording for past, today, tomorrow, soon and far away', () {
      expect(expiryLabel(DateTime(2026, 10, 20), now), 'Expired 5 days ago');
      expect(expiryLabel(DateTime(2026, 10, 24), now), 'Expired yesterday');
      expect(expiryLabel(DateTime(2026, 10, 25), now), 'Expires today');
      expect(expiryLabel(DateTime(2026, 10, 26), now), 'Expires tomorrow');
      expect(expiryLabel(DateTime(2026, 11, 4), now), 'Expires in 10 days');
      expect(expiryLabel(DateTime(2027, 6, 1), now), startsWith('Expires '));
      expect(expiryLabel(DateTime(2027, 6, 1), now), isNot(contains('in ')));
    });

    test('the state changes exactly at the soon limit', () {
      expect(expiryState(DateTime(2026, 10, 24), now), ExpiryState.expired);
      expect(expiryState(DateTime(2026, 10, 25), now), ExpiryState.soon, reason: 'today is not expired yet');
      expect(expiryState(now.add(const Duration(days: expirySoonDays)), now), ExpiryState.soon);
      expect(expiryState(now.add(const Duration(days: expirySoonDays + 1)), now), ExpiryState.later);
    });

    test('the list holds only what needs attention, soonest first, and ignores documents without a date', () {
      final docs = [
        _doc('a', 'Far', DateTime(2028)),
        _doc('b', 'Soon', DateTime(2026, 11, 20)),
        _doc('c', 'Gone', DateTime(2026, 9, 1)),
        _doc('d', 'None', null),
        _doc('e', 'Sooner', DateTime(2026, 10, 30)),
      ];
      expect(expiringDocuments(docs, now).map((d) => d.id), ['c', 'e', 'b']);
      expect(expiringDocuments(const [], now), isEmpty);
    });
  });

  group('saving the date', () {
    late Directory root;
    late Directory files;
    late DocumentRepositoryImpl repo;

    setUp(() {
      root = Directory.systemTemp.createTempSync('sv_exp_root');
      files = Directory.systemTemp.createTempSync('sv_exp_files');
      repo = DocumentRepositoryImpl(DocumentLocalDataSource(rootDir: root));
    });
    tearDown(() {
      root.deleteSync(recursive: true);
      files.deleteSync(recursive: true);
    });

    Future<ScannedDocument> make(String title) async {
      final f = File(p.join(files.path, '$title.jpg'))..writeAsStringSync(title);
      return (await repo.saveDocument(
        title: title,
        pages: [NewPage(imagePath: f.path, rawPath: f.path, width: 1, height: 1)],
      )).valueOrNull!;
    }

    test('a new document has no expiry; one can be set, kept through other changes, and removed', () async {
      final d = await make('Passport');
      expect(d.expiresAt, isNull);

      final set = (await repo.updateMeta(d.id, expires: DateTime(2031, 3, 4, 12))).valueOrNull!;
      expect(set.expiresAt, DateTime(2031, 3, 4, 12));

      final tagged = (await repo.updateMeta(d.id, tags: ['id'], favorite: true)).valueOrNull!;
      expect(tagged.expiresAt, DateTime(2031, 3, 4, 12), reason: 'other changes keep it');
      expect((await repo.getDocument(d.id)).valueOrNull!.expiresAt, DateTime(2031, 3, 4, 12));
      expect((await repo.listDocuments()).valueOrNull!.single.expiresAt, DateTime(2031, 3, 4, 12));

      final changed = (await repo.updateMeta(d.id, expires: DateTime(2032, 1, 1, 12))).valueOrNull!;
      expect(changed.expiresAt, DateTime(2032, 1, 1, 12));

      final cleared = (await repo.updateMeta(d.id, clearExpiry: true)).valueOrNull!;
      expect(cleared.expiresAt, isNull);
      expect((await repo.getDocument(d.id)).valueOrNull!.expiresAt, isNull);
    });

    test('a database from before expiry dates gains the column and keeps its documents', () async {
      final d = await make('Old document');
      final path = p.join(root.path, 'doculoom.db');
      final raw = await openDatabase(path);
      await raw.execute('ALTER TABLE documents DROP COLUMN expires_at');
      await raw.execute('PRAGMA user_version = 7');
      await raw.close();

      final reopened = DocumentRepositoryImpl(DocumentLocalDataSource(rootDir: root));
      final listed = (await reopened.listDocuments()).valueOrNull!;
      expect(listed.single.title, 'Old document');
      expect(listed.single.expiresAt, isNull);
      final set = (await reopened.updateMeta(d.id, expires: DateTime(2030, 6, 1, 12))).valueOrNull!;
      expect(set.expiresAt, DateTime(2030, 6, 1, 12));
    });
  });

  group('what the person sees', () {
    Future<void> show(WidgetTester tester, Widget child) async {
      tester.view.physicalSize = const Size(400 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      );
    }

    testWidgets('the chip says how close the date is', (tester) async {
      await show(tester, ExpiryChip(expires: DateTime(2026, 10, 30), now: now));
      expect(find.text('Expires in 5 days'), findsOneWidget);
    });

    testWidgets('the banner lists the soonest three and counts the rest, and a tap opens the document', (tester) async {
      ScannedDocument? opened;
      final docs = [
        _doc('1', 'Passport', DateTime(2026, 10, 20)),
        _doc('2', 'Car insurance', DateTime(2026, 11, 1)),
        _doc('3', 'Visa', DateTime(2026, 11, 15)),
        _doc('4', 'Gym card', DateTime(2026, 12, 1)),
        _doc('5', 'Warranty', DateTime(2029)),
        _doc('6', 'Receipt', null),
      ];
      await show(tester, ExpiringBanner(documents: docs, now: now, onOpen: (d) => opened = d));
      expect(find.text('Needs attention'), findsOneWidget, reason: 'something has already expired');
      expect(find.text('Passport'), findsOneWidget);
      expect(find.text('Expired 5 days ago'), findsOneWidget);
      expect(find.text('Car insurance'), findsOneWidget);
      expect(find.text('Visa'), findsOneWidget);
      expect(find.text('Gym card'), findsNothing);
      expect(find.text('and 1 more'), findsOneWidget);
      expect(find.text('Warranty'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('expiring-2')));
      expect(opened?.title, 'Car insurance');
    });

    testWidgets('only upcoming dates say "Ending soon", and nothing shows when nothing is near', (tester) async {
      await show(tester, ExpiringBanner(documents: [_doc('1', 'Visa', DateTime(2026, 11, 15))], now: now, onOpen: (_) {}));
      expect(find.text('Ending soon'), findsOneWidget);
      expect(find.text('Needs attention'), findsNothing);

      await show(tester, ExpiringBanner(documents: [_doc('1', 'Warranty', DateTime(2029)), _doc('2', 'Plain', null)], now: now, onOpen: (_) {}));
      expect(find.byKey(const ValueKey('expiring-banner')), findsNothing);
    });
  });
}

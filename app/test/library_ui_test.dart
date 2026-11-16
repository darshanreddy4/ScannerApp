import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:doculoom/app/di.dart';
import 'package:doculoom/core/error/result.dart';
import 'package:doculoom/features/documents/data/datasources/document_local_data_source.dart';
import 'package:doculoom/features/documents/data/library_files.dart';
import 'package:doculoom/features/documents/data/repositories/document_repository_impl.dart';
import 'package:doculoom/features/documents/domain/entities/scanned_document.dart';
import 'package:doculoom/features/documents/domain/library_target.dart';
import 'package:doculoom/features/documents/domain/usecases/document_usecases.dart';
import 'package:doculoom/features/documents/presentation/library_actions.dart';
import 'package:doculoom/features/documents/presentation/library_picker.dart';
import 'package:doculoom/features/documents/presentation/widgets/document_widgets.dart';
import 'package:doculoom/features/export/domain/repositories/export_repository.dart';
import 'package:doculoom/features/office/sheets/presentation/sheet_page.dart';
import 'package:doculoom/features/reader/presentation/reader_page.dart';

class _Share implements ShareService {
  final shared = <String>[];

  @override
  Future<Result<void>> shareFile({required String path, required String mimeType, String? subject}) async {
    shared.add(path);
    return const Ok(null);
  }

  @override
  Future<Result<void>> shareFiles({required List<String> paths, required String mimeType, String? subject}) async {
    shared.addAll(paths);
    return const Ok(null);
  }

  @override
  Future<Result<void>> shareText({required String text, String? subject}) async => const Ok(null);
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // Real file and database work does not advance under a widget test's fake time, so it runs outside it.
  late WidgetTester current;
  Future<T> _io<T>(Future<T> Function() work) async => (await current.runAsync(work))!;
  void testUi(String name, Future<void> Function(WidgetTester) body) => testWidgets(name, (tester) async {
    current = tester;
    await body(tester);
  });

  late Directory work;
  late Directory root;
  late Directory temp;
  late DocumentRepositoryImpl repo;
  late _Share share;

  setUp(() async {
    work = Directory.systemTemp.createTempSync('sv_ui_work');
    root = Directory.systemTemp.createTempSync('sv_ui_root');
    temp = Directory.systemTemp.createTempSync('sv_ui_temp');
    repo = DocumentRepositoryImpl(DocumentLocalDataSource(rootDir: root));
    share = _Share();
    await sl.reset();
    sl
      ..registerSingleton<ShareService>(share)
      ..registerSingleton(LibraryFiles(documents: repo, files: repo, rootDir: () async => root, tempDir: () async => temp))
      ..registerSingleton(ListDocuments(repo))
      ..registerSingleton(ListFolders(repo));
  });

  tearDown(() async {
    await sl.reset();
    work.deleteSync(recursive: true);
    root.deleteSync(recursive: true);
    temp.deleteSync(recursive: true);
  });

  File make(String name, String content) => File(p.join(work.path, name))
    ..createSync(recursive: true)
    ..writeAsStringSync(content);

  Future<ScannedDocument> file(String title, String name, {String? folderId}) async =>
      (await _io(() async => (await repo.saveFile(title: title, sourcePath: make(name, title).path, folderId: folderId)).valueOrNull!));

  Future<ScannedDocument> scan(String title) async {
    final f = make('$title.jpg', title);
    return _io(() async => (await repo.saveDocument(title: title, pages: [NewPage(imagePath: f.path, rawPath: f.path, width: 1, height: 1)])).valueOrNull!);
  }

  /// Waits for real file and database work that fake time does not advance.
  Future<void> settle(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 100 && !done(); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    await tester.pump();
  }

  group('the Doculoom picker', () {
    Future<List<Object?>> open(WidgetTester tester, {required List<String> extensions, bool multiple = false}) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final results = <Object?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async => results.add(
                  await showModalBottomSheet<List<ScannedDocument>>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => FractionallySizedBox(heightFactor: 0.9, child: LibraryPickerSheet(extensions: extensions, multiple: multiple)),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await settle(tester, () => find.byType(CircularProgressIndicator).evaluate().isEmpty);
      await tester.pumpAndSettle();
      return results;
    }

    testUi('shows only what the tool can use, scans as PDFs where PDFs are taken', (tester) async {
      final report = await file('Report', 'report.docx');
      final contract = await file('Contract', 'contract.pdf');
      final receipt = await scan('Receipt');
      await open(tester, extensions: ['pdf']);
      expect(find.byKey(ValueKey('library-item-${contract.id}')), findsOneWidget);
      expect(find.byKey(ValueKey('library-item-${receipt.id}')), findsOneWidget);
      expect(find.byKey(ValueKey('library-item-${report.id}')), findsNothing, reason: 'a Word file is not a PDF');
      expect(find.text('Scan, used as a PDF'), findsOneWidget);
    });

    testUi('tapping an item chooses it when one is wanted', (tester) async {
      final report = await file('Report', 'report.docx');
      final results = await open(tester, extensions: ['docx']);
      await tester.tap(find.byKey(ValueKey('library-item-${report.id}')));
      await tester.pumpAndSettle();
      expect((results.single! as List<ScannedDocument>).single.id, report.id);
    });

    testUi('several can be chosen and are returned together', (tester) async {
      final a = await file('Alpha', 'a.pdf');
      final b = await file('Beta', 'b.pdf');
      await file('Gamma', 'g.pdf');
      final results = await open(tester, extensions: ['pdf'], multiple: true);
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('library-use'))).onPressed, isNull);
      await tester.tap(find.byKey(ValueKey('library-item-${b.id}')));
      await tester.pump();
      await tester.tap(find.byKey(ValueKey('library-item-${a.id}')));
      await tester.pump();
      expect(find.text('Use 2 selected'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('library-use')));
      await tester.pumpAndSettle();
      expect([for (final d in results.single! as List<ScannedDocument>) d.id], [b.id, a.id], reason: 'in the order chosen');
    });

    testUi('files in folders are reached through the folder, and search looks everywhere', (tester) async {
      final folder = (await _io(() => repo.createFolder('Taxes'))).valueOrNull!;
      final inside = await file('Return 2025', 'return.pdf', folderId: folder.id);
      final outside = await file('Loose', 'loose.pdf');
      await open(tester, extensions: ['pdf']);
      expect(find.byKey(ValueKey('library-item-${inside.id}')), findsNothing);
      expect(find.byKey(ValueKey('library-item-${outside.id}')), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('library-folder-${folder.id}')));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('library-item-${inside.id}')), findsOneWidget);
      expect(find.byKey(ValueKey('library-item-${outside.id}')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('library-back')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('library-search')), 'return');
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('library-item-${inside.id}')), findsOneWidget);
      expect(find.byKey(ValueKey('library-item-${outside.id}')), findsNothing);
    });

    testUi('says so when nothing fits', (tester) async {
      await file('Report', 'report.docx');
      await open(tester, extensions: ['xlsx']);
      expect(find.text('Nothing here that this tool can use'), findsOneWidget);
    });
  });

  group('files on the home screen', () {
    testUi('a file shows its type and a scan keeps its pages', (tester) async {
      final word = await file('Essay', 'essay.docx');
      final receipt = await scan('Receipt');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                SizedBox(width: 80, height: 100, child: DocThumb(document: word)),
                SizedBox(width: 80, height: 100, child: DocThumb(document: receipt)),
              ],
            ),
          ),
        ),
      );
      expect(find.text('DOCX'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
    });

    testUi('each kind of file opens in its own tool, ready to save back in place', (tester) async {
      final docs = {
        'word': await file('Essay', 'essay.docx'),
        'sheet': await file('Budget', 'budget.xlsx'),
        'deck': await file('Talk', 'talk.pptx'),
        'pdf': await file('Form', 'form.pdf'),
        'text': await file('Notes', 'notes.txt'),
      };
      final opened = <String, Object?>{};
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, _) => Scaffold(
              body: Column(
                children: [
                  for (final e in docs.entries) TextButton(key: ValueKey(e.key), onPressed: () => openLibraryFile(context, e.value), child: Text(e.key)),
                ],
              ),
            ),
          ),
          for (final route in const ['docx-edit', 'sheet', 'slides', 'reader', 'text-file'])
            GoRoute(
              path: '/$route',
              builder: (_, state) {
                opened[route] = state.extra;
                return Scaffold(body: Text('screen $route'));
              },
            ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));

      Future<void> tapAndBack(String key) async {
        await tester.tap(find.byKey(ValueKey(key)));
        await tester.pumpAndSettle();
        router.pop();
        await tester.pumpAndSettle();
      }

      for (final key in docs.keys) {
        await tapAndBack(key);
      }
      final word = opened['docx-edit']! as LibraryTarget;
      expect(word.id, docs['word']!.id);
      expect(word.path, docs['word']!.filePath);
      expect((opened['sheet']! as SheetArgs).libraryId, docs['sheet']!.id);
      expect((opened['slides']! as LibraryTarget).id, docs['deck']!.id);
      expect((opened['reader']! as ReaderArgs).libraryId, docs['pdf']!.id);
      expect((opened['text-file']! as LibraryTarget).path, docs['text']!.filePath);
    });

    testUi('sharing a file sends a copy under its own name', (tester) async {
      final doc = await file('Quarterly plan', 'stored.docx');
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(onPressed: () => shareLibraryFile(context, doc), child: const Text('share')),
          ),
        ),
      );
      await tester.tap(find.text('share'));
      await settle(tester, () => share.shared.isNotEmpty);
      expect(p.basename(share.shared.single), 'Quarterly plan.docx');
      expect(File(share.shared.single).readAsStringSync(), 'Quarterly plan');
    });
  });
}

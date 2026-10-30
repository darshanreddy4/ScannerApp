import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:doculoom/app/di.dart';
import 'package:doculoom/core/error/failures.dart';
import 'package:doculoom/core/theme/app_theme.dart';
import 'package:doculoom/core/error/result.dart';
import 'package:doculoom/features/documents/data/datasources/document_local_data_source.dart';
import 'package:doculoom/features/documents/data/repositories/document_repository_impl.dart';
import 'package:doculoom/features/documents/domain/entities/scanned_document.dart';
import 'package:doculoom/features/documents/domain/usecases/document_usecases.dart';
import 'package:doculoom/features/documents/presentation/bloc/documents_cubit.dart';
import 'package:doculoom/features/ocr/data/text_repository_impl.dart';
import 'package:doculoom/features/ocr/domain/ocr_engine.dart';
import 'package:doculoom/features/ocr/domain/ocr_models.dart';
import 'package:doculoom/features/ocr/domain/recognize_document_text.dart';
import 'package:doculoom/features/ocr/domain/text_repository.dart';
import 'package:doculoom/features/ocr/presentation/ocr_cubit.dart';
import 'package:doculoom/features/ocr/presentation/ocr_page.dart';
import 'package:doculoom/features/settings/data/settings_repository.dart';
import 'package:doculoom/features/settings/domain/app_settings.dart';
import 'package:doculoom/features/settings/presentation/settings_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

OcrLine _line(String text, {double top = 0, double height = 20}) => OcrLine(text: text, left: 10, top: top, right: 310, bottom: top + height);

/// Answers by page number so tests control exactly what "the camera read".
class FakeEngine implements OcrEngine {
  FakeEngine(this.pages, {this.failOn});
  final List<OcrPageResult> pages;
  final int? failOn;
  final calls = <(String, OcrScript)>[];

  @override
  Future<Result<OcrPageResult>> recognize(String imagePath, OcrScript script) async {
    final index = calls.length;
    calls.add((imagePath, script));
    if (failOn == index) return const Err(OcrFailure('The text could not be read from this page.'));
    return Ok(pages[index % pages.length]);
  }
}

OcrPageResult _result(List<List<OcrLine>> blocks) => OcrPageResult(width: 800, height: 1000, blocks: [for (final b in blocks) OcrBlock(lines: b)]);

final _report = _result([
  [_line('Annual Report', height: 44)],
  [_line('The area is A = 25 and it grows.', top: 80)],
  [_line('a² + b² = c²', top: 140)],
]);

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory root;
  late Directory work;
  late DocumentLocalDataSource local;
  late DocumentRepositoryImpl docs;
  late TextRepositoryImpl texts;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    root = Directory.systemTemp.createTempSync('sv_ocr_root');
    work = Directory.systemTemp.createTempSync('sv_ocr_work');
    local = DocumentLocalDataSource(rootDir: root);
    docs = DocumentRepositoryImpl(local);
    texts = TextRepositoryImpl(local);
  });

  tearDown(() {
    root.deleteSync(recursive: true);
    work.deleteSync(recursive: true);
  });

  Future<ScannedDocument> makeDoc(String title, int pages) async {
    NewPage page(int i) {
      final f = File(p.join(work.path, '${title}_$i.jpg'))..writeAsStringSync('img$i');
      return NewPage(imagePath: f.path, rawPath: f.path, width: 10, height: 10);
    }

    return (await docs.saveDocument(title: title, pages: [for (var i = 0; i < pages; i++) page(i)])).valueOrNull!;
  }

  group('saved text', () {
    test('is stored per page, loaded in order and can be corrected', () async {
      final doc = await makeDoc('Contract', 2);
      await texts.saveText(doc.id, const [
        PageText(position: 1, script: OcrScript.devanagari, markdown: 'दूसरा', plain: 'दूसरा'),
        PageText(position: 0, script: OcrScript.devanagari, markdown: '# नमस्ते', plain: 'नमस्ते'),
      ]);

      var loaded = (await texts.loadText(doc.id)).valueOrNull!;
      expect(loaded.map((t) => t.position), [0, 1]);
      expect(loaded.first.script, OcrScript.devanagari);
      expect(loaded.first.markdown, '# नमस्ते');
      expect(loaded.first.edited, isFalse);

      await texts.updatePageMarkdown(doc.id, 0, '# Hello');
      loaded = (await texts.loadText(doc.id)).valueOrNull!;
      expect(loaded.first.markdown, '# Hello');
      expect(loaded.first.plain, 'नमस्ते', reason: 'the original reading is kept for search');
      expect(loaded.first.edited, isTrue);
    });

    test('saving again replaces the old text, and deleting the document removes it', () async {
      final doc = await makeDoc('Notes', 1);
      await texts.saveText(doc.id, const [PageText(position: 0, script: OcrScript.latin, markdown: 'old', plain: 'old')]);
      await texts.saveText(doc.id, const [PageText(position: 0, script: OcrScript.latin, markdown: 'new', plain: 'new')]);
      expect((await texts.loadText(doc.id)).valueOrNull!.single.markdown, 'new');

      await docs.deleteDocument(doc.id);
      expect((await texts.loadText(doc.id)).valueOrNull, isEmpty);
    });

    test('editing the pages of a document discards text that no longer matches', () async {
      final doc = await makeDoc('Edit me', 1);
      await texts.saveText(doc.id, const [PageText(position: 0, script: OcrScript.latin, markdown: 'text', plain: 'text')]);

      final f = File(p.join(work.path, 'replacement.jpg'))..writeAsStringSync('new');
      await docs.updateDocument(
        id: doc.id,
        title: 'Edit me',
        pages: [NewPage(imagePath: f.path, rawPath: f.path, width: 10, height: 10)],
      );

      expect((await texts.loadText(doc.id)).valueOrNull, isEmpty);
    });

    test('search finds words in any page, ignores case, treats % and _ literally and needs two characters', () async {
      final a = await makeDoc('Alpha', 1);
      final b = await makeDoc('Beta', 1);
      await texts.saveText(a.id, const [
        PageText(position: 0, script: OcrScript.latin, markdown: 'Quarterly **Revenue**', plain: 'Quarterly Revenue grew 50% in snake_case'),
      ]);
      await texts.saveText(b.id, const [PageText(position: 0, script: OcrScript.latin, markdown: 'Invoice', plain: 'Invoice 5001')]);

      Future<Set<String>> find(String q) async => (await texts.searchText(q)).valueOrNull!;
      expect(await find('revenue'), {a.id});
      expect(await find('INVOICE'), {b.id});
      expect(await find('50%'), {a.id});
      expect(await find('snake_case'), {a.id});
      expect(await find('5%'), isEmpty, reason: '% is not a wildcard');
      expect(await find('snake-case'), isEmpty);
      expect(await find('a'), isEmpty);
      expect(await find('zzz'), isEmpty);
    });

    test('a version 5 database gains the text table', () async {
      await makeDoc('Old', 1);
      final path = p.join(root.path, 'doculoom.db');
      final raw = await openDatabase(path);
      await raw.execute('DROP TABLE page_text');
      await raw.execute('PRAGMA user_version = 5');
      await raw.close();

      final reopened = DocumentLocalDataSource(rootDir: root);
      expect((await DocumentRepositoryImpl(reopened).listDocuments()).valueOrNull!.single.title, 'Old');
      final text = TextRepositoryImpl(reopened);
      await text.saveText('x', const []);
      final id = (await DocumentRepositoryImpl(reopened).listDocuments()).valueOrNull!.single.id;
      await text.saveText(id, const [PageText(position: 0, script: OcrScript.latin, markdown: 'hello', plain: 'hello')]);
      expect((await text.searchText('hello')).valueOrNull, {id});
    });
  });

  group('RecognizeDocumentText', () {
    test('reads every page in order, reports progress, structures the text and saves it', () async {
      final doc = await makeDoc('Report', 2);
      final engine = FakeEngine([
        _report,
        _result([
          [_line('Second page text here.')],
        ]),
      ]);
      final progress = <(int, int)>[];

      final result = await RecognizeDocumentText(engine, texts)(document: doc, script: OcrScript.latin, onProgress: (d, t) => progress.add((d, t)));

      final pages = result.valueOrNull!;
      expect(engine.calls.map((c) => c.$1), [doc.pages[0].imagePath, doc.pages[1].imagePath]);
      expect(progress, [(0, 2), (1, 2), (2, 2)]);
      expect(pages.first.markdown, contains('# Annual Report'));
      expect(pages.first.markdown, contains(r'$$a^{2} + b^{2} = c^{2}$$'));
      expect(pages.first.markdown, contains(r'$A = 25$'));
      expect(pages.first.plain, contains('Annual Report'));
      expect(pages.last.markdown, 'Second page text here.');
      expect((await texts.loadText(doc.id)).valueOrNull!.length, 2);
    });

    test('a page that cannot be read stops the run and saves nothing', () async {
      final doc = await makeDoc('Broken', 3);
      final engine = FakeEngine([_report], failOn: 1);
      final result = await RecognizeDocumentText(engine, texts)(document: doc, script: OcrScript.latin);

      expect(result.failureOrNull, isA<OcrFailure>());
      expect((await texts.loadText(doc.id)).valueOrNull, isEmpty);
    });

    test('cancelling stops before the next page and saves nothing', () async {
      final doc = await makeDoc('Cancel', 3);
      final engine = FakeEngine([_report]);
      var cancel = false;
      final result = await RecognizeDocumentText(engine, texts)(
        document: doc,
        script: OcrScript.latin,
        onProgress: (done, total) => cancel = done == 1,
        isCancelled: () => cancel,
      );

      expect(result.failureOrNull, isA<OcrFailure>());
      expect(engine.calls.length, 2, reason: 'stops before the third page');
      expect((await texts.loadText(doc.id)).valueOrNull, isEmpty);
    });
  });

  group('OcrCubit', () {
    test('starts empty, runs, then shows saved text on the next visit', () async {
      final doc = await makeDoc('Cubit', 1);
      OcrCubit cubit([OcrScript s = OcrScript.latin]) =>
          OcrCubit(document: doc, recognize: RecognizeDocumentText(FakeEngine([_report]), texts), repository: texts, initialScript: s);

      final first = cubit();
      await first.load();
      expect(first.state.status, OcrStatus.empty);
      first.setScript(OcrScript.devanagari);
      await first.run();
      expect(first.state.status, OcrStatus.ready);
      expect(first.state.script, OcrScript.devanagari);

      final second = cubit();
      await second.load();
      expect(second.state.status, OcrStatus.ready);
      expect(second.state.script, OcrScript.devanagari, reason: 'remembers the language used');
      expect(second.state.current!.markdown, contains('Annual Report'));
    });

    test('edits are saved, flagged, and survive a reload; deleting returns to empty', () async {
      final doc = await makeDoc('Edits', 1);
      final cubit = OcrCubit(document: doc, recognize: RecognizeDocumentText(FakeEngine([_report]), texts), repository: texts);
      await cubit.run();
      await cubit.saveEdit('Corrected text');
      expect(cubit.state.current!.markdown, 'Corrected text');
      expect(cubit.state.current!.edited, isTrue);

      final again = OcrCubit(document: doc, recognize: RecognizeDocumentText(FakeEngine([_report]), texts), repository: texts);
      await again.load();
      expect(again.state.current!.markdown, 'Corrected text');

      await again.deleteText();
      expect(again.state.status, OcrStatus.empty);
      expect((await texts.loadText(doc.id)).valueOrNull, isEmpty);
    });

    test('a failed run ends in failed with the reason and can be retried', () async {
      final doc = await makeDoc('Fail', 1);
      final cubit = OcrCubit(document: doc, recognize: RecognizeDocumentText(FakeEngine([_report], failOn: 0), texts), repository: texts);
      await cubit.run();
      expect(cubit.state.status, OcrStatus.failed);
      expect(cubit.state.failure!.message, contains('could not be read'));
      await cubit.run();
      expect(cubit.state.status, OcrStatus.ready);
    });

    test('several pages are joined with page headings', () async {
      final doc = await makeDoc('Multi', 2);
      final cubit = OcrCubit(
        document: doc,
        recognize: RecognizeDocumentText(
          FakeEngine([
            _result([
              [_line('One')],
            ]),
            _result([
              [_line('Two')],
            ]),
          ]),
          texts,
        ),
        repository: texts,
      );
      await cubit.run();
      expect(cubit.state.fullMarkdown, '## Page 1\n\nOne\n\n## Page 2\n\nTwo');
      cubit.selectPage(1);
      expect(cubit.state.current!.markdown, 'Two');
    });
  });

  group('library search', () {
    test('finds a document by words that only appear in its recognised text', () async {
      final doc = await makeDoc('Scan 001', 1);
      await makeDoc('Scan 002', 1);
      await texts.saveText(doc.id, const [PageText(position: 0, script: OcrScript.latin, markdown: 'Lease agreement', plain: 'Lease agreement for the flat')]);

      final cubit = DocumentsCubit(
        textRepository: texts,
        listDocuments: ListDocuments(docs),
        listFolders: ListFolders(docs),
        deleteDocument: DeleteDocument(docs),
        renameDocument: RenameDocument(docs),
        moveDocument: MoveDocument(docs),
        mergeDocuments: MergeDocuments(docs),
        createFolder: CreateFolder(docs),
        renameFolder: RenameFolder(docs),
        updateFolderMeta: UpdateFolderMeta(docs),
        deleteFolder: DeleteFolder(docs),
      );
      await cubit.load();
      expect(cubit.state.searchDocuments('lease').map((d) => d.title), isEmpty, reason: 'before the text search runs only titles match');

      await cubit.searchInText('lease');
      expect(cubit.state.searchDocuments('lease').map((d) => d.title), ['Scan 001']);

      await cubit.searchInText('');
      expect(cubit.state.textMatches, isEmpty);
    });
  });

  group('OCR screen', () {
    Future<(ScannedDocument, FakeEngine)> open(WidgetTester tester, {int pages = 1, FakeEngine? engine}) async {
      tester.view.physicalSize = const Size(400 * 3, 900 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final doc = (await tester.runAsync(() => makeDoc('Physics', pages)))!;
      final fake = engine ?? FakeEngine([_report]);
      await sl.reset();
      sl
        ..registerSingleton<RecognizeDocumentText>(RecognizeDocumentText(fake, texts))
        ..registerSingleton<TextRepository>(texts);

      final settings = SettingsCubit(_Prefs());
      await tester.pumpWidget(
        BlocProvider.value(
          value: settings,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: OcrPage(document: doc),
          ),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      return (doc, fake);
    }

    testWidgets('offers language choice and an honest note, then shows headings and typeset formulas', (tester) async {
      final (_, engine) = await open(tester);
      expect(find.text('Extract the text'), findsOneWidget);
      expect(find.textContaining('Arabic is not supported yet'), findsOneWidget);
      expect(find.textContaining('Nothing is uploaded'), findsOneWidget);

      await tester.tap(find.text('Extract text'));
      await tester.pump();
      for (var i = 0; i < 40 && find.text('Annual Report').evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(engine.calls.single.$2, OcrScript.latin);
      expect(find.textContaining('Annual Report', findRichText: true), findsOneWidget);
      expect(find.byType(Math), findsNWidgets(2), reason: 'one display formula and one inline formula');
      expect(tester.takeException(), isNull);
    });

    testWidgets('edit mode saves a correction and the formatted view follows', (tester) async {
      await open(tester);
      await tester.tap(find.text('Extract text'));
      await tester.pump();
      for (var i = 0; i < 40 && find.byType(SegmentedButton<bool>).evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 50));
      }

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save')).onPressed, isNull, reason: 'nothing to save yet');

      await tester.enterText(find.byType(TextField), 'Fixed title');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();
      expect(find.text('Edited by you'), findsOneWidget);

      await tester.tap(find.text('Formatted'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Fixed title', findRichText: true), findsOneWidget);
    });

    testWidgets('a failed read explains why and offers another try', (tester) async {
      await open(tester, engine: FakeEngine([_report], failOn: 0));
      await tester.tap(find.text('Extract text'));
      await tester.pump();
      for (var i = 0; i < 40 && find.text('Try again').evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.textContaining('could not be read'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('pages can be stepped through', (tester) async {
      await open(
        tester,
        pages: 2,
        engine: FakeEngine([
          _result([
            [_line('First page words')],
          ]),
          _result([
            [_line('Second page words')],
          ]),
        ]),
      );
      await tester.tap(find.text('Extract text'));
      await tester.pump();
      for (var i = 0; i < 40 && find.text('Page 1 of 2').evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.textContaining('First page words', findRichText: true), findsOneWidget);
      await tester.tap(find.byTooltip('Next page'));
      await tester.pumpAndSettle();
      expect(find.text('Page 2 of 2'), findsOneWidget);
      expect(find.textContaining('Second page words', findRichText: true), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('edit mode works on a long, many-page document', (tester) async {
      final lines = [for (var i = 0; i < 60; i++) _line('Line number $i of a long page with several words', top: i * 30.0)];
      await open(
        tester,
        pages: 41,
        engine: FakeEngine([
          _result([lines]),
        ]),
      );
      await tester.tap(find.text('Extract text'));
      await tester.pump();
      for (var i = 0; i < 100 && find.text('Page 1 of 41').evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.tap(find.text('Edit'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      expect(tester.getSize(find.byType(TextField)).height, greaterThan(200));
    });

    for (final width in [320.0, 1280.0]) {
      testWidgets('the screen fits a ${width.toInt()} dp wide window', (tester) async {
        await open(tester, pages: 2, engine: FakeEngine([_report]));
        tester.view.physicalSize = Size(width * 3, 900 * 3);
        await tester.pump();
        await tester.tap(find.text('Extract text'));
        await tester.pump();
        for (var i = 0; i < 40 && find.text('Page 1 of 2').evaluate().isEmpty; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
          await tester.pump(const Duration(milliseconds: 50));
        }
        await tester.pumpAndSettle();
        expect(find.text('Page 1 of 2'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  test('the chosen language is remembered between launches', () async {
    final repo = SettingsRepositoryImpl();
    expect((await repo.load()).ocrScript, OcrScript.latin);
    await repo.save((await repo.load()).copyWith(ocrScript: OcrScript.devanagari));
    expect((await SettingsRepositoryImpl().load()).ocrScript, OcrScript.devanagari);
  });

  test('the text and icon size is remembered between launches', () async {
    final repo = SettingsRepositoryImpl();
    expect((await repo.load()).interfaceSize, InterfaceSize.medium);
    await repo.save((await repo.load()).copyWith(interfaceSize: InterfaceSize.large));
    expect((await SettingsRepositoryImpl().load()).interfaceSize, InterfaceSize.large);
  });
}

class _Prefs implements SettingsRepository {
  @override
  Future<AppSettings> load() async => const AppSettings();
  @override
  Future<void> save(AppSettings settings) async {}
}

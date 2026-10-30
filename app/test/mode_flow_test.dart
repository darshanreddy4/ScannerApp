import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:doculoom/app/di.dart';
import 'package:doculoom/core/error/result.dart';
import 'package:doculoom/core/theme/app_theme.dart';
import 'package:doculoom/features/documents/domain/entities/scanned_document.dart';
import 'package:doculoom/features/documents/domain/repositories/document_repository.dart';
import 'package:doculoom/features/documents/domain/usecases/document_usecases.dart';
import 'package:doculoom/features/importer/domain/importer.dart';
import 'package:doculoom/features/monetization/domain/entities/plan_status.dart';
import 'package:doculoom/features/monetization/domain/repositories/monetization_contracts.dart';
import 'package:doculoom/features/monetization/presentation/plan_cubit.dart';
import 'package:doculoom/features/ocr/domain/ocr_engine.dart';
import 'package:doculoom/features/ocr/domain/ocr_models.dart';
import 'package:doculoom/features/ocr/domain/recognize_document_text.dart';
import 'package:doculoom/features/ocr/domain/text_repository.dart';
import 'package:doculoom/features/scanner/domain/entities/filter_settings.dart';
import 'package:doculoom/features/scanner/domain/entities/prepared_image.dart';
import 'package:doculoom/features/scanner/domain/entities/quad.dart';
import 'package:doculoom/features/scanner/domain/entities/scan_mode.dart';
import 'package:doculoom/features/scanner/domain/repositories/scanner_repository.dart';
import 'package:doculoom/features/scanner/domain/usecases/scanner_usecases.dart';
import 'package:doculoom/features/scanner/presentation/bloc/scan_session_cubit.dart';
import 'package:doculoom/features/scanner/presentation/mode_flow.dart';
import 'package:doculoom/features/settings/data/settings_repository.dart';
import 'package:doculoom/features/settings/domain/app_settings.dart';
import 'package:doculoom/features/settings/presentation/settings_cubit.dart';

import 'package:doculoom/features/tables/presentation/table_page.dart';
import 'support/folder_fakes.dart';
import 'support/coins_fakes.dart';

class _Scanner implements ScannerRepository {
  var n = 0;
  String _next() => '/tmp/flow_${n++}.jpg';

  @override
  Future<Result<PreparedImage>> prepareImage(String sourcePath) async => Ok(PreparedImage(path: _next(), width: 100, height: 200, detectedQuad: null));
  @override
  Future<Result<ImageFileInfo>> cropToQuad({required String imagePath, required Quad quad}) async => Ok(ImageFileInfo(path: _next(), width: 80, height: 160));
  @override
  Future<Result<ImageFileInfo>> imageInfo(String imagePath) async => Ok(ImageFileInfo(path: imagePath, width: 100, height: 200));
  @override
  Future<Result<ImageFileInfo>> rotate90(String imagePath) async => Ok(ImageFileInfo(path: _next(), width: 160, height: 80));
  @override
  Future<Result<Uint8List>> previewFilter({required String imagePath, required FilterSettings settings}) async => Ok(Uint8List.fromList([1]));
  @override
  Future<Result<List<Uint8List>>> previewFilterBatch({required String imagePath, required List<FilterSettings> variants, int maxSide = 180}) async => Ok([
    for (final _ in variants) Uint8List.fromList([1]),
  ]);
  @override
  Future<Result<ImageFileInfo>> applyFilter({required String imagePath, required FilterSettings settings}) async =>
      Ok(ImageFileInfo(path: _next(), width: 80, height: 160));
}

class _NoImport implements DocumentImporter {
  @override
  Future<Result<ImportedDocument>> import({required ImportKind kind, required String path, ImportProgress? onProgress}) => throw UnimplementedError();
}

class _Docs implements DocumentRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();

  final saved = <List<NewPage>>[];
  List<String>? tags;

  @override
  Future<Result<ScannedDocument>> saveDocument({required String title, required List<NewPage> pages, String? folderId}) async {
    saved.add(pages);
    return Ok(ScannedDocument(id: 'd1', title: title, createdAt: DateTime(2026), updatedAt: DateTime(2026), pages: const []));
  }

  @override
  Future<Result<ScannedDocument>> updateMeta(
    String id, {
    bool? favorite,
    bool? pinned,
    bool? locked,
    List<String>? tags,
    DateTime? date,
    DateTime? expires,
    bool clearExpiry = false,
  }) async {
    this.tags = tags ?? this.tags;
    return Ok(ScannedDocument(id: id, title: 'x', createdAt: DateTime(2026), updatedAt: DateTime(2026), pages: const [], tags: tags ?? const []));
  }
}

class _Engine implements OcrEngine {
  @override
  Future<Result<OcrPageResult>> recognize(String imagePath, OcrScript script) async => const Ok(OcrPageResult(width: 1, height: 1, blocks: []));
}

class _Texts implements TextRepository {
  @override
  Future<Result<void>> saveText(String documentId, List<PageText> pages) async => const Ok(null);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Plans implements PlanRepository {
  @override
  Future<PlanStatus> current() async => PlanStatus.free;
  @override
  Future<void> setPlan(PlanStatus plan) async {}
}

class _Prefs implements SettingsRepository {
  @override
  Future<AppSettings> load() async => const AppSettings();
  @override
  Future<void> save(AppSettings settings) async {}
}

void main() {
  late _Docs docs;
  late ScanSessionCubit session;
  late GoRouter router;
  var result = false;
  var done = false;

  setUp(() async {
    await sl.reset();
    docs = _Docs();
    final scanner = _Scanner();
    session = ScanSessionCubit(
      prepareImage: PrepareImage(scanner),
      inspectImage: InspectImage(scanner),
      cropDocument: CropDocument(scanner),
      rotateImage: RotateImage(scanner),
      previewFilter: PreviewFilter(scanner),
      previewFilterBatch: PreviewFilterBatch(scanner),
      applyFilter: ApplyFilter(scanner),
      saveDocument: SaveDocument(docs),
      updateDocument: UpdateDocument(docs),
      importDocumentFile: ImportDocumentFile(_NoImport()),
    )..start(defaultFilter: ScanFilter.original);
    sl
      ..registerSingleton<AdService>(ScriptedAds())
      ..registerSingleton(UpdateDocumentMeta(docs))
      ..registerSingleton(RenameDocument(docs))
      ..registerSingleton(RecognizeDocumentText(_Engine(), _Texts()));
    registerFolderFakes();
    result = false;
    done = false;
  });

  tearDown(() => session.close());

  Future<void> addPages(int count) async {
    for (var i = 0; i < count; i++) {
      await session.beginDraft('/p$i.jpg');
      await session.commitDraft();
    }
  }

  Future<void> open(WidgetTester tester) async {
    router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                key: const ValueKey('go'),
                onPressed: () async {
                  result = await continueModeScan(context);
                  done = true;
                },
                child: const Text('go'),
              ),
            ),
          ),
        ),
        GoRoute(path: '/document/:id', builder: (_, s) => Text('document ${s.pathParameters['id']}')),
        GoRoute(path: '/contact', builder: (_, s) => Text('contact "${s.extra}"')),
        GoRoute(path: '/id-card', builder: (_, s) => Text('id-card ${s.extra}')),
        GoRoute(path: '/table', builder: (_, s) => Text('table ${(s.extra! as TableArgs).imagePaths.length} pages "${(s.extra! as TableArgs).title}"')),
      ],
    );
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: session),
          BlocProvider(create: (_) => PlanCubit(_Plans())),
          BlocProvider(create: (_) => SettingsCubit(_Prefs())),
        ],
        child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('go')));
    await tester.pumpAndSettle();
  }

  testWidgets('a plain document is not taken over: the page editor follows', (tester) async {
    await tester.runAsync(() => addPages(1));
    await open(tester);
    expect(result, isFalse);
    expect(docs.saved, isEmpty);
  });

  testWidgets('Book and Whiteboard are not taken over either', (tester) async {
    session.setMode(ScanMode.whiteboard);
    await tester.runAsync(() => addPages(1));
    await open(tester);
    expect(result, isFalse);
    expect(docs.saved, isEmpty);
  });

  testWidgets('nothing happens without a page', (tester) async {
    session.setMode(ScanMode.card);
    await open(tester);
    expect(result, isFalse);
    expect(find.text('Front scanned'), findsNothing);
  });

  testWidgets('a card with only its front asks for the back and, when told to scan it, stays on the camera without saving', (tester) async {
    session.setMode(ScanMode.card);
    await tester.runAsync(() => addPages(1));
    await open(tester);
    expect(find.text('Front scanned'), findsOneWidget);
    expect(find.text('Scan the back of the card too?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('back-scan')));
    await tester.pumpAndSettle();
    expect(result, isFalse);
    expect(docs.saved, isEmpty);
    expect(session.state.pages.length, 1, reason: 'the front is kept for the back to join');
  });

  testWidgets('"Only the front" saves the card and opens the contact screen', (tester) async {
    session.setMode(ScanMode.card);
    await tester.runAsync(() => addPages(1));
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('back-skip')));
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(docs.saved.single.length, 1);
    expect(docs.tags, ['Card']);
    expect(find.textContaining('contact'), findsOneWidget);
  });

  testWidgets('front and back of a card are saved as one scan without asking again', (tester) async {
    session.setMode(ScanMode.card);
    await tester.runAsync(() => addPages(2));
    await open(tester);
    expect(find.text('Front scanned'), findsNothing);
    expect(result, isTrue);
    expect(docs.saved.single.length, 2);
    expect(find.textContaining('contact'), findsOneWidget);
  });

  testWidgets('an ID also asks for its back, in its own words', (tester) async {
    session.setMode(ScanMode.id);
    await tester.runAsync(() => addPages(1));
    await open(tester);
    expect(find.text('Scan the back of the id too?'), findsOneWidget);
  });

  testWidgets('a receipt is a single photo: it is saved and read without asking for a back', (tester) async {
    session.setMode(ScanMode.receipt);
    await tester.runAsync(() => addPages(1));
    await open(tester);
    expect(find.text('Front scanned'), findsNothing);
    expect(find.text('Receipt saved'), findsOneWidget, reason: 'it was saved and read; the result is waiting for Done or Share PDF');
    await tester.tap(find.byKey(const ValueKey('receipt-done')));
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(docs.saved.single.length, 1);
    expect(docs.tags, ['Receipt']);
    expect(find.text('document d1'), findsOneWidget);
  });

  testWidgets('a table is a single photo: it is saved, filed and opened as a spreadsheet without asking for a back', (tester) async {
    session.setMode(ScanMode.table);
    await tester.runAsync(() => addPages(1));
    await open(tester);
    expect(find.text('Front scanned'), findsNothing);
    expect(result, isTrue);
    expect(docs.saved.single.length, 1);
    expect(docs.tags, ['Table']);
    expect(find.textContaining('table '), findsOneWidget, reason: 'the table screen is on top of the saved document');
  });

  testWidgets('a scan that is being edited is never taken over', (tester) async {
    session.setMode(ScanMode.card);
    await tester.runAsync(() => addPages(1));
    session.loadDocument(
      ScannedDocument(id: 'old', title: 'Old', createdAt: DateTime(2026), updatedAt: DateTime(2026), pages: const []),
      defaultFilter: ScanFilter.original,
    );
    await open(tester);
    expect(result, isFalse);
    expect(done, isTrue);
  });
}

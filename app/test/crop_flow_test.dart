import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
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
import 'package:doculoom/features/scanner/presentation/pages/crop_page.dart';
import 'package:doculoom/features/settings/data/settings_repository.dart';
import 'package:doculoom/features/settings/domain/app_settings.dart';
import 'package:doculoom/features/settings/presentation/settings_cubit.dart';

import 'support/folder_fakes.dart';
import 'support/coins_fakes.dart';

late String _photo;

class _Scanner implements ScannerRepository {
  var n = 0;
  @override
  Future<Result<PreparedImage>> prepareImage(String sourcePath) async => Ok(PreparedImage(path: _photo, width: 100, height: 200, detectedQuad: null));
  @override
  Future<Result<ImageFileInfo>> cropToQuad({required String imagePath, required Quad quad}) async => Ok(ImageFileInfo(path: _photo, width: 80, height: 160));
  @override
  Future<Result<ImageFileInfo>> imageInfo(String imagePath) async => Ok(ImageFileInfo(path: imagePath, width: 100, height: 200));
  @override
  Future<Result<ImageFileInfo>> rotate90(String imagePath) async => Ok(ImageFileInfo(path: _photo, width: 160, height: 80));
  @override
  Future<Result<Uint8List>> previewFilter({required String imagePath, required FilterSettings settings}) async => Ok(Uint8List.fromList([1]));
  @override
  Future<Result<List<Uint8List>>> previewFilterBatch({required String imagePath, required List<FilterSettings> variants, int maxSide = 180}) async => Ok([
    for (final _ in variants) Uint8List.fromList([1]),
  ]);
  @override
  Future<Result<ImageFileInfo>> applyFilter({required String imagePath, required FilterSettings settings}) async =>
      Ok(ImageFileInfo(path: _photo, width: 80, height: 160));
}

class _NoImport implements DocumentImporter {
  @override
  Future<Result<ImportedDocument>> import({required ImportKind kind, required String path, ImportProgress? onProgress}) => throw UnimplementedError();
}

class _Docs implements DocumentRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
  final saved = <List<NewPage>>[];
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
  }) async => Ok(ScannedDocument(id: id, title: 'x', createdAt: DateTime(2026), updatedAt: DateTime(2026), pages: const [], tags: tags ?? const []));
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
  late Directory dir;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('sv_flow');
    _photo = p.join(dir.path, 'photo.jpg');
    File(_photo).writeAsBytesSync(img.encodeJpg(img.Image(width: 20, height: 40, numChannels: 3)));
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
  });

  tearDown(() async {
    await session.close();
    dir.deleteSync(recursive: true);
  });

  // The same route shape as the app: camera at /scan, crop above it. Keeps a handle on the router to push the crop again for the back side.
  late GoRouter router;

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Text('home')),
        GoRoute(path: '/document/:id', builder: (_, s) => Text('document ${s.pathParameters['id']}')),
        GoRoute(path: '/contact', builder: (_, s) => Text('contact "${s.extra}"')),
        GoRoute(path: '/id-card', builder: (_, s) => Text('id-card ${s.extra}')),
        GoRoute(
          path: '/scan',
          builder: (_, _) => const Text('camera'),
          routes: [GoRoute(path: 'crop', builder: (_, _) => const CropPage())],
        ),
      ],
      initialLocation: '/scan',
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
    await tester.runAsync(() => session.beginDraft('/shot.jpg'));
    router.push('/scan/crop');
    await tester.pumpAndSettle();
  }

  Future<void> tapContinue(WidgetTester tester) async {
    await tester.tap(find.text('CONTINUE'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
  }

  testWidgets('document: Continue returns to the camera', (tester) async {
    await open(tester);
    await tapContinue(tester);
    expect(find.text('camera'), findsOneWidget);
  });

  for (final mode in [ScanMode.book, ScanMode.whiteboard]) {
    testWidgets('${mode.name}: Continue returns to the camera', (tester) async {
      session.setMode(mode);
      await open(tester);
      await tapContinue(tester);
      expect(find.text('camera'), findsOneWidget);
    });
  }

  testWidgets('card front: Scan the back returns to the camera', (tester) async {
    session.setMode(ScanMode.card);
    await open(tester);
    await tapContinue(tester);
    expect(find.text('Front scanned'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('back-scan')));
    await tester.pumpAndSettle();
    expect(find.text('camera'), findsOneWidget);
  });

  testWidgets('card front: Only the front opens the contact', (tester) async {
    session.setMode(ScanMode.card);
    await open(tester);
    await tapContinue(tester);
    await tester.tap(find.byKey(const ValueKey('back-skip')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(find.textContaining('contact'), findsOneWidget);
  });

  testWidgets('receipt: Continue saves, reads and shows the result', (tester) async {
    session.setMode(ScanMode.receipt);
    await open(tester);
    await tapContinue(tester);
    expect(find.text('Receipt saved'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('receipt-done')));
    await tester.pumpAndSettle();
    expect(find.text('document d1'), findsOneWidget);
  });

  testWidgets('card: front, then the back, saves one scan of two pages and opens the contact without asking again', (tester) async {
    session.setMode(ScanMode.card);
    await open(tester);
    await tapContinue(tester);
    await tester.tap(find.byKey(const ValueKey('back-scan')));
    await tester.pumpAndSettle();
    expect(find.text('camera'), findsOneWidget);

    await tester.runAsync(() => session.beginDraft('/back.jpg'));
    router.push('/scan/crop');
    await tester.pumpAndSettle();
    await tapContinue(tester);
    expect(find.text('Front scanned'), findsNothing);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(docs.saved.single.length, 2);
    expect(find.textContaining('contact'), findsOneWidget);
  });

  testWidgets('ID: Only the front goes on to the expiry date', (tester) async {
    session.setMode(ScanMode.id);
    await open(tester);
    await tapContinue(tester);
    await tester.tap(find.byKey(const ValueKey('back-skip')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(find.text('When does this ID expire?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('id-expiry-skip')));
    await tester.pumpAndSettle();
    expect(find.text('document d1'), findsOneWidget);
  });

  testWidgets('while a receipt is being saved there is a progress screen, never an empty one', (tester) async {
    session.setMode(ScanMode.receipt);
    await open(tester);
    await tester.tap(find.text('CONTINUE'));
    await tester.pump();
    // The draft is gone at once; the page must still be the crop route showing progress or a result.
    expect(find.byType(CropPage), findsOneWidget);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(find.text('Receipt saved'), findsOneWidget);
  });
}

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:doculoom/app/di.dart';
import 'package:doculoom/core/error/result.dart';
import 'package:doculoom/core/theme/app_icons.dart';
import 'package:doculoom/core/theme/app_theme.dart';
import 'package:doculoom/features/documents/domain/entities/scanned_document.dart';
import 'package:doculoom/features/documents/domain/repositories/document_repository.dart';
import 'package:doculoom/features/documents/domain/usecases/document_usecases.dart';
import 'package:doculoom/features/documents/presentation/bloc/document_detail_cubit.dart';
import 'package:doculoom/features/documents/presentation/pages/document_detail_page.dart';
import 'package:doculoom/features/export/domain/repositories/export_repository.dart';
import 'package:doculoom/features/export/domain/usecases/export_usecases.dart';
import 'package:doculoom/features/importer/domain/importer.dart';
import 'package:doculoom/features/markup/domain/markup.dart';
import 'package:doculoom/features/markup/domain/markup_renderer.dart';
import 'package:doculoom/features/monetization/domain/entities/plan_status.dart';
import 'package:doculoom/features/monetization/domain/repositories/monetization_contracts.dart';
import 'package:doculoom/features/monetization/presentation/plan_cubit.dart';
import 'package:doculoom/features/scanner/domain/entities/filter_settings.dart';
import 'package:doculoom/features/scanner/domain/entities/prepared_image.dart';
import 'package:doculoom/features/scanner/domain/entities/quad.dart';
import 'package:doculoom/features/scanner/domain/repositories/scanner_repository.dart';
import 'package:doculoom/features/scanner/domain/usecases/scanner_usecases.dart';
import 'package:doculoom/features/scanner/presentation/bloc/scan_session_cubit.dart';
import 'package:doculoom/features/scanner/presentation/pages/edit_page.dart';
import 'package:doculoom/features/settings/data/settings_repository.dart';
import 'package:doculoom/features/settings/domain/app_settings.dart';
import 'package:doculoom/features/settings/presentation/settings_cubit.dart';

late Directory _dir;
late Uint8List _jpeg;
int _n = 0;

String _imageFile([String prefix = 'img']) => (File('${_dir.path}/${prefix}_${_n++}.jpg')..writeAsBytesSync(_jpeg)).path;

class _Scanner implements ScannerRepository {
  @override
  Future<Result<PreparedImage>> prepareImage(String sourcePath) async =>
      Ok(PreparedImage(path: _imageFile(), width: 40, height: 60, detectedQuad: Quad.defaultInset));
  @override
  Future<Result<ImageFileInfo>> cropToQuad({required String imagePath, required Quad quad}) async =>
      Ok(ImageFileInfo(path: _imageFile('crop'), width: 40, height: 60));
  @override
  Future<Result<ImageFileInfo>> imageInfo(String imagePath) async => Ok(ImageFileInfo(path: imagePath, width: 40, height: 60));
  @override
  Future<Result<ImageFileInfo>> rotate90(String imagePath) async => Ok(ImageFileInfo(path: _imageFile(), width: 60, height: 40));
  @override
  Future<Result<Uint8List>> previewFilter({required String imagePath, required FilterSettings settings}) async => Ok(_jpeg);
  @override
  Future<Result<List<Uint8List>>> previewFilterBatch({required String imagePath, required List<FilterSettings> variants, int maxSide = 180}) async =>
      Ok([for (final _ in variants) _jpeg]);
  @override
  Future<Result<ImageFileInfo>> applyFilter({required String imagePath, required FilterSettings settings}) async =>
      Ok(ImageFileInfo(path: _imageFile(), width: 40, height: 60));
}

/// Draws nothing, but returns a new picture file like the real renderer does.
class _Markup implements MarkupRenderer {
  @override
  Future<Result<ImageFileInfo>> render({required String imagePath, required FilterSettings settings, required List<MarkupItem> items}) async =>
      Ok(ImageFileInfo(path: _imageFile('marked'), width: 40, height: 60));
}

/// Keeps the saved document in memory, so that editing it changes what is read back.
class _Docs implements DocumentRepository {
  _Docs(this.stored);
  ScannedDocument stored;
  var updates = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();

  @override
  Future<Result<ScannedDocument>> getDocument(String id) async => Ok(stored);

  @override
  Future<Result<ScannedDocument>> updateDocument({required String id, required String title, required List<NewPage> pages}) async {
    updates++;
    // Like the real store: the pages are written to new files and the old ones are removed.
    for (final p in stored.pages) {
      File(p.imagePath).deleteSync();
    }
    stored = ScannedDocument(
      id: id,
      title: title,
      createdAt: stored.createdAt,
      updatedAt: DateTime(2026, 10, 25),
      pages: [
        for (var i = 0; i < pages.length; i++)
          DocumentPage(id: 'new$i', position: i, imagePath: _imageFile('r2_page'), rawPath: _imageFile('r2_raw'), width: 40, height: 60),
      ],
    );
    return Ok(stored);
  }
}

class _Importer implements DocumentImporter {
  @override
  Future<Result<ImportedDocument>> import({required ImportKind kind, required String path, ImportProgress? onProgress}) async =>
      const Ok(ImportedDocument(title: 't', imagePaths: []));
}

class _Plans implements PlanRepository {
  @override
  Future<PlanStatus> current() async => PlanStatus.premium;
  @override
  Future<void> setPlan(PlanStatus plan) async {}
}

class _Prefs implements SettingsRepository {
  @override
  Future<AppSettings> load() async => const AppSettings();
  @override
  Future<void> save(AppSettings settings) async {}
}

class _NoAds implements AdService {
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> privacyOptionsRequired() async => false;
  @override
  Future<void> showPrivacyOptions() async {}
  @override
  Future<RewardResult> showRewarded() async => RewardResult.unavailable;
  @override
  Future<void> showInterstitialIfEligible(PlanStatus plan) async {}
}

ScanSessionCubit _session(_Docs docs) {
  final scanner = _Scanner();
  return ScanSessionCubit(
    prepareImage: PrepareImage(scanner),
    inspectImage: InspectImage(scanner),
    cropDocument: CropDocument(scanner),
    rotateImage: RotateImage(scanner),
    previewFilter: PreviewFilter(scanner),
    previewFilterBatch: PreviewFilterBatch(scanner),
    applyFilter: ApplyFilter(scanner),
    saveDocument: SaveDocument(docs),
    updateDocument: UpdateDocument(docs),
    importDocumentFile: ImportDocumentFile(_Importer()),
    markupRenderer: _Markup(),
  )..start(defaultFilter: ScanFilter.original);
}

/// The files of the pictures on screen (pages and thumbnails).
List<String> _shownFiles(WidgetTester tester) => [
  for (final image in tester.widgetList<Image>(find.byType(Image)))
    switch (image.image) {
      final ResizeImage r when r.imageProvider is FileImage => (r.imageProvider as FileImage).file.path,
      final FileImage f => f.file.path,
      _ => '',
    },
];

void main() {
  setUpAll(() {
    _dir = Directory.systemTemp.createTempSync('sv_saved_doc');
    _jpeg = Uint8List.fromList(img.encodeJpg(img.Image(width: 40, height: 60)..clear(img.ColorRgb8(200, 200, 200))));
    if (!sl.isRegistered<AdService>()) sl.registerSingleton<AdService>(_NoAds());
  });
  tearDownAll(() => _dir.deleteSync(recursive: true));

  Widget app(ScanSessionCubit session, GoRouter router) => MultiBlocProvider(
    providers: [
      BlocProvider.value(value: session),
      BlocProvider(create: (_) => PlanCubit(_Plans())..load()),
      BlocProvider(create: (_) => SettingsCubit(_Prefs())),
    ],
    child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
  );

  testWidgets('holding the compare button shows the page as it was before the marks, not the marked picture', (tester) async {
    tester.view.physicalSize = const Size(400 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final session = _session(_Docs(ScannedDocument(id: 'x', title: 't', createdAt: DateTime(2026), updatedAt: DateTime(2026), pages: const [])));
    late String beforeMarks;
    late String withMarks;
    await tester.runAsync(() async {
      await session.importMany(['/a.jpg']);
      await session.commitAll();
      beforeMarks = session.state.pages.first.croppedPath!;
      await session.applyMarkup(0, const [MarkupSticker(id: 1, text: 'Hello', center: Offset(0.5, 0.5), size: 0.1)]);
      withMarks = session.state.pages.first.croppedPath!;
    });
    expect(withMarks, isNot(beforeMarks));
    expect(session.state.pages.first.preMarkup, isNotNull);

    final router = GoRouter(
      initialLocation: '/scan/edit',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('HOME')),
        ),
        GoRoute(
          path: '/scan',
          builder: (_, _) => const Scaffold(body: Text('CAMERA')),
          routes: [GoRoute(path: 'edit', builder: (_, _) => const EditPage())],
        ),
      ],
    );
    await tester.pumpWidget(app(session, router));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const ValueKey('remove-markup')), findsOneWidget);
    expect(find.text('Original'), findsNWidgets(1), reason: 'only the filter name, no overlay label yet');
    expect(_shownFiles(tester), isNot(contains(beforeMarks)));

    final hold = await tester.startGesture(tester.getCenter(find.byIcon(AppIcons.compare)));
    await tester.pump();
    expect(_shownFiles(tester), contains(beforeMarks), reason: 'the original has no marks');
    expect(_shownFiles(tester), isNot(contains(withMarks)));

    await hold.up();
    await tester.pump();
    expect(_shownFiles(tester), isNot(contains(beforeMarks)));
    expect(tester.takeException(), isNull);
  });

  testWidgets('after editing a saved document and saving, the document screen shows the new pages', (tester) async {
    tester.view.physicalSize = const Size(400 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final docs = _Docs(
      ScannedDocument(
        id: 'doc-1',
        title: 'Original title',
        createdAt: DateTime(2026, 10, 25, 12, 10),
        updatedAt: DateTime(2026, 10, 25, 12, 10),
        pages: [
          for (var i = 0; i < 3; i++) DocumentPage(id: 'p$i', position: i, imagePath: _imageFile('page'), rawPath: _imageFile('raw'), width: 40, height: 60),
        ],
      ),
    );
    final oldFiles = [for (final p in docs.stored.pages) p.imagePath];
    final session = _session(docs);
    if (sl.isRegistered<DocumentDetailCubit>()) sl.unregister<DocumentDetailCubit>();
    sl.registerFactoryParam<DocumentDetailCubit, String, void>(
      (id, _) => DocumentDetailCubit(
        documentId: id,
        getDocument: GetDocument(docs),
        renameDocument: RenameDocument(docs),
        deleteDocument: DeleteDocument(docs),
        exportDocument: ExportDocument(_NoExport()),
        shareFile: ShareFile(_NoShare()),
      ),
    );
    addTearDown(() => sl.unregister<DocumentDetailCubit>());

    final router = GoRouter(
      initialLocation: '/document/doc-1',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('HOME')),
          routes: [
            GoRoute(
              path: 'document/:id',
              builder: (_, s) => DocumentDetailPage(documentId: s.pathParameters['id']!),
            ),
            GoRoute(
              path: 'scan',
              builder: (_, _) => const Scaffold(body: Text('CAMERA')),
              routes: [GoRoute(path: 'edit', builder: (_, _) => const EditPage())],
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(app(session, router));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Original title'), findsOneWidget);
    expect(find.textContaining('Page 1 of 3'), findsOneWidget);
    expect(_shownFiles(tester), containsAll(oldFiles.take(1)));

    await tester.tap(find.byIcon(AppIcons.editDocument));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.byType(EditPage), findsOneWidget);

    session.setTitle('Edited title');
    session.removePage(0);
    await tester.pump();

    await tester.tap(find.byType(FilledButton).last);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(docs.updates, 1);
    expect(find.byType(EditPage), findsNothing);
    expect(find.text('Edited title'), findsOneWidget, reason: 'the document screen reloads instead of showing the old pages');
    expect(find.textContaining('Page 1 of 2'), findsOneWidget);
    for (final path in _shownFiles(tester).where((p) => p.isNotEmpty)) {
      expect(File(path).existsSync(), isTrue, reason: 'every picture on screen exists: $path');
    }
    expect(tester.takeException(), isNull);
  });
}

class _NoExport implements ExportRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _NoShare implements ShareService {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

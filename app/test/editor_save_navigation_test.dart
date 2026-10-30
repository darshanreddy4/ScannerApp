import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:doculoom/app/di.dart';
import 'package:doculoom/core/error/result.dart';
import 'package:doculoom/features/documents/domain/entities/scanned_document.dart';
import 'package:doculoom/features/documents/domain/repositories/document_repository.dart';
import 'package:doculoom/features/documents/domain/usecases/document_usecases.dart';
import 'package:doculoom/features/importer/domain/importer.dart';
import 'package:doculoom/features/monetization/domain/entities/plan_status.dart';
import 'package:doculoom/features/monetization/domain/repositories/monetization_contracts.dart';
import 'package:doculoom/features/monetization/presentation/plan_cubit.dart';
import 'package:doculoom/features/scanner/domain/entities/filter_settings.dart';
import 'package:doculoom/features/scanner/domain/entities/prepared_image.dart';
import 'package:doculoom/features/scanner/domain/entities/quad.dart';
import 'package:doculoom/features/scanner/domain/repositories/scanner_repository.dart';
import 'package:doculoom/features/scanner/domain/usecases/scanner_usecases.dart';
import 'package:doculoom/features/scanner/presentation/bloc/scan_session_cubit.dart';
import 'package:doculoom/features/scanner/presentation/pages/crop_page.dart';
import 'package:doculoom/features/settings/data/settings_repository.dart';
import 'package:doculoom/features/settings/domain/app_settings.dart';
import 'package:doculoom/features/settings/presentation/settings_cubit.dart';
import 'package:doculoom/features/scanner/presentation/pages/edit_page.dart';

late Directory _dir;
late Uint8List _jpeg;
int _n = 0;

String _imageFile() {
  final f = File('${_dir.path}/img_${_n++}.jpg')..writeAsBytesSync(_jpeg);
  return f.path;
}

class _Scanner implements ScannerRepository {
  @override
  Future<Result<PreparedImage>> prepareImage(String sourcePath) async =>
      Ok(PreparedImage(path: _imageFile(), width: 40, height: 60, detectedQuad: Quad.defaultInset));
  @override
  Future<Result<ImageFileInfo>> cropToQuad({required String imagePath, required Quad quad}) async =>
      Ok(ImageFileInfo(path: _imageFile(), width: 40, height: 60));
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

class _Docs implements DocumentRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();

  int saves = 0;
  @override
  Future<Result<ScannedDocument>> saveDocument({required String title, required List<NewPage> pages, String? folderId}) async {
    saves++;
    return Ok(ScannedDocument(id: 'doc-1', title: title, createdAt: DateTime(2026), updatedAt: DateTime(2026), pages: const []));
  }

  @override
  Future<Result<void>> deleteDocument(String id) => throw UnimplementedError();
  @override
  Future<Result<ScannedDocument>> getDocument(String id) => throw UnimplementedError();
  @override
  Future<Result<List<ScannedDocument>>> listDocuments() => throw UnimplementedError();
  @override
  Future<Result<void>> moveDocument(String id, String? folderId) => throw UnimplementedError();
  @override
  Future<Result<ScannedDocument>> renameDocument(String id, String title) => throw UnimplementedError();
  @override
  Future<Result<ScannedDocument>> updateDocument({required String id, required String title, required List<NewPage> pages}) => throw UnimplementedError();
  @override
  Future<Result<ScannedDocument>> mergeDocuments({required List<String> ids, required String title, String? folderId, required bool deleteOriginals}) =>
      throw UnimplementedError();
}

class _Importer implements DocumentImporter {
  @override
  Future<Result<ImportedDocument>> import({required ImportKind kind, required String path, ImportProgress? onProgress}) async {
    final paths = [for (var i = 0; i < 3; i++) _imageFile()];
    for (var i = 0; i < paths.length; i++) {
      onProgress?.call(i + 1, paths.length);
    }
    return Ok(ImportedDocument(title: 'Second', imagePaths: paths));
  }
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

void main() {
  setUpAll(() {
    _dir = Directory.systemTemp.createTempSync('sv_widget');
    _jpeg = Uint8List.fromList(img.encodeJpg(img.Image(width: 40, height: 60)..clear(img.ColorRgb8(200, 200, 200))));
    if (!sl.isRegistered<AdService>()) sl.registerSingleton<AdService>(_NoAds());
  });
  tearDownAll(() => _dir.deleteSync(recursive: true));

  Widget app(ScanSessionCubit session, GoRouter router) => MultiBlocProvider(
    providers: [
      BlocProvider.value(value: session),
      BlocProvider(create: (_) => PlanCubit(_Plans())),
      BlocProvider(create: (_) => SettingsCubit(_Prefs())),
    ],
    child: MaterialApp.router(routerConfig: router),
  );

  ScanSessionCubit buildSession(_Docs docs) {
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
    )..start(defaultFilter: ScanFilter.magicColor);
  }

  testWidgets('saving navigates exactly once, straight to the saved document', (tester) async {
    tester.view.physicalSize = const Size(400 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final docs = _Docs();
    final session = buildSession(docs);

    await tester.runAsync(() async {
      await session.importMany(['/a.jpg', '/b.jpg']);
      await session.commitAll();
    });

    final visited = <String>[];
    late final GoRouter router;
    router = GoRouter(
      initialLocation: '/scan/edit',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('HOME')),
        ),
        GoRoute(
          path: '/document/:id',
          builder: (_, s) => Scaffold(body: Text('DETAIL ${s.pathParameters['id']}')),
        ),
        GoRoute(
          path: '/scan',
          builder: (_, _) => const Scaffold(body: Text('CAMERA')),
          routes: [GoRoute(path: 'edit', builder: (_, _) => const EditPage())],
        ),
      ],
    );
    router.routerDelegate.addListener(() => visited.add(router.routerDelegate.currentConfiguration.uri.toString()));

    await tester.pumpWidget(app(session, router));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 300));

    final saveButton = find.byType(FilledButton).last;
    await tester.tap(saveButton);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(docs.saves, 1);
    expect(find.text('DETAIL doc-1'), findsOneWidget);
    expect(visited.where((u) => u == '/').length, 0, reason: 'must not bounce through home before the document opens');
    expect(tester.takeException(), isNull);
  });

  testWidgets('importing a second PDF while editing appends its pages and keeps the editor usable', (tester) async {
    tester.view.physicalSize = const Size(400 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final session = buildSession(_Docs());
    await tester.runAsync(() => session.importDocumentFile(ImportKind.pdf, '/first.pdf'));

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
    expect(find.text('1/3'), findsOneWidget);

    await tester.runAsync(() => session.importDocumentFile(ImportKind.pdf, '/second.pdf'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(session.state.pages.length, 6);
    expect(session.state.busy, isFalse);
    expect(find.text('4/6'), findsOneWidget, reason: 'the editor jumps to the first appended page');
    expect(tester.takeException(), isNull);
  });

  testWidgets('renaming the document from the editor title works without framework errors', (tester) async {
    tester.view.physicalSize = const Size(400 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final session = buildSession(_Docs());
    await tester.runAsync(() async {
      await session.importMany(['/a.jpg']);
      await session.commitAll();
    });
    session.setTitle('Old name');

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

    await tester.tap(find.text('Old name'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(TextField), 'New name');
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(session.state.title, 'New name');
    expect(find.text('New name'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in const [Size(1280, 800), Size(800, 1280), Size(360, 780)]) {
    testWidgets('the editor fits a ${size.width.toInt()}x${size.height.toInt()} screen', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final session = buildSession(_Docs());
      await tester.runAsync(() async {
        await session.importMany(['/a.jpg', '/b.jpg']);
        await session.commitAll();
      });

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
            routes: [
              GoRoute(path: 'edit', builder: (_, _) => const EditPage()),
              GoRoute(path: 'crop', builder: (_, _) => const CropPage()),
            ],
          ),
        ],
      );
      await tester.pumpWidget(app(session, router));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Crop'), findsOneWidget);
      expect(tester.getRect(find.text('Crop')).bottom, lessThanOrEqualTo(size.height));
      expect(find.text('Color'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'no overflow in the editor');
    });
  }

  for (final size in const [Size(1280, 800), Size(800, 1280), Size(360, 780)]) {
    testWidgets('the crop screen fits a ${size.width.toInt()}x${size.height.toInt()} screen', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final session = buildSession(_Docs());
      await tester.runAsync(() => session.beginDraft('/c.jpg'));

      final router = GoRouter(
        initialLocation: '/scan/crop',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: Text('HOME')),
          ),
          GoRoute(
            path: '/scan',
            builder: (_, _) => const Scaffold(body: Text('CAMERA')),
            routes: [GoRoute(path: 'crop', builder: (_, _) => const CropPage())],
          ),
        ],
      );
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [BlocProvider.value(value: SettingsCubit(_Prefs()))],
          child: app(session, router),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('CONTINUE'), findsOneWidget);
      expect(tester.getRect(find.text('CONTINUE')).bottom, lessThanOrEqualTo(size.height));
      expect(tester.takeException(), isNull, reason: 'no overflow on the crop screen');
    });
  }
}

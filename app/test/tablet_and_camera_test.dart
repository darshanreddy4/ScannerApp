import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scanvault/app/di.dart';
import 'support/coins_fakes.dart';
import 'package:scanvault/core/error/result.dart';
import 'package:scanvault/core/widgets/responsive.dart';
import 'package:scanvault/features/documents/domain/entities/scanned_document.dart';
import 'package:scanvault/features/documents/domain/repositories/document_repository.dart';
import 'package:scanvault/features/documents/domain/usecases/document_usecases.dart';
import 'package:scanvault/features/documents/presentation/bloc/documents_cubit.dart';
import 'package:scanvault/features/documents/presentation/pages/home_page.dart';
import 'package:scanvault/features/monetization/domain/entities/plan_status.dart';
import 'package:scanvault/features/monetization/domain/repositories/monetization_contracts.dart';
import 'package:scanvault/features/monetization/presentation/plan_cubit.dart';
import 'package:scanvault/features/scanner/domain/entities/quad.dart';
import 'package:scanvault/features/scanner/presentation/bloc/camera_cubit.dart';
import 'package:scanvault/features/settings/data/settings_repository.dart';
import 'package:scanvault/features/settings/domain/app_settings.dart';
import 'package:scanvault/features/settings/presentation/settings_cubit.dart';
import 'package:camera/camera.dart' show CameraLensDirection;

class _Docs implements DocumentRepository, FolderRepository {
  _Docs(this.docs);
  final List<ScannedDocument> docs;

  @override
  Future<Result<List<ScannedDocument>>> listDocuments() async => Ok(docs);
  @override
  Future<Result<List<Folder>>> listFolders() async => Ok([Folder(id: 'f1', name: 'Work', createdAt: DateTime(2026))]);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
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
    if (!sl.isRegistered<AdService>()) sl.registerSingleton<AdService>(_NoAds());
  });

  group('camera orientation maths', () {
    test('back camera held upright turns a sensor-90 frame by 90 degrees', () {
      int rot(DeviceOrientation d, {int sensor = 90, bool android = true}) => frameRotation(sensorOrientation: sensor, held: d, android: android);
      expect(rot(DeviceOrientation.portraitUp), 90);
      expect(rot(DeviceOrientation.landscapeLeft), 0);
      expect(rot(DeviceOrientation.portraitDown), 270);
      expect(rot(DeviceOrientation.landscapeRight), 180);
      expect(rot(DeviceOrientation.landscapeLeft, android: false), 90, reason: 'other platforms keep the sensor angle');
    });

    test('rotating a rectangle keeps its corners in tl, tr, br, bl order', () {
      const q = Quad(NormPoint(.1, .2), NormPoint(.9, .2), NormPoint(.9, .8), NormPoint(.1, .8));
      final r = quadForDisplay(q, 90);
      expect([r.tl.x, r.tl.y], [closeTo(.2, 1e-9), closeTo(.1, 1e-9)]);
      expect([r.tr.x, r.tr.y], [closeTo(.8, 1e-9), closeTo(.1, 1e-9)]);
      expect([r.br.x, r.br.y], [closeTo(.8, 1e-9), closeTo(.9, 1e-9)]);
      expect([r.bl.x, r.bl.y], [closeTo(.2, 1e-9), closeTo(.9, 1e-9)]);
      expect(quadForDisplay(q, 0), q);
    });

    test('camera state tells the front camera apart', () {
      expect(const CameraState().isFront, isFalse);
      expect(const CameraState(lens: CameraLensDirection.front).isFront, isTrue);
      expect(const CameraState().canSwitch, isFalse);
      expect(const CameraState().copyWith(canSwitch: true).canSwitch, isTrue);
    });
  });

  group('orientation policy', () {
    Future<List<DeviceOrientation>> applied(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      List<DeviceOrientation>? result;
      await tester.pumpWidget(
        MaterialApp(
          home: OrientationPolicy(apply: (o) async => result = o, child: const SizedBox()),
        ),
      );
      return result!;
    }

    testWidgets('phones stay in portrait', (tester) async {
      expect(await applied(tester, const Size(390, 844)), [DeviceOrientation.portraitUp]);
    });

    testWidgets('tablets and foldables may rotate', (tester) async {
      expect(await applied(tester, const Size(800, 1280)), DeviceOrientation.values);
    });
  });

  group('library layout', () {
    Future<void> openHome(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo = _Docs([
        for (var i = 0; i < 5; i++)
          ScannedDocument(id: 'd$i', title: 'Contract number $i', createdAt: DateTime(2026, 1, i + 1), updatedAt: DateTime(2026, 1, i + 1), pages: const []),
      ]);
      final plan = PlanCubit(_Plans());
      final settings = SettingsCubit(_Prefs());
      final docs = DocumentsCubit(
        listDocuments: ListDocuments(repo),
        listFolders: ListFolders(repo),
        deleteDocument: DeleteDocument(repo),
        renameDocument: RenameDocument(repo),
        moveDocument: MoveDocument(repo),
        mergeDocuments: MergeDocuments(repo),
        createFolder: CreateFolder(repo),
        renameFolder: RenameFolder(repo),
        updateFolderMeta: UpdateFolderMeta(repo),
        deleteFolder: DeleteFolder(repo),
      );
      await tester.runAsync(docs.load);
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider.value(value: plan),
            BlocProvider.value(value: settings),
            BlocProvider.value(value: docs),
            BlocProvider(create: (_) => coinsCubit()),
          ],
          child: const MaterialApp(home: HomePage()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a phone keeps the bottom navigation bar', (tester) async {
      await openHome(tester, const Size(390, 844));
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      expect(tester.takeException(), isNull);
    });

    for (final size in const [Size(1280, 800), Size(800, 1280)]) {
      testWidgets('a ${size.width.toInt()}x${size.height.toInt()} tablet gets a navigation rail and a multi-column library', (tester) async {
        await openHome(tester, size);
        expect(find.byType(NavigationRail), findsOneWidget);
        expect(find.byType(NavigationBar), findsNothing);
        expect(find.text('Contract number 4'), findsOneWidget);

        // Newest first: the two newest documents sit side by side on the first row.
        final first = tester.getTopLeft(find.text('Contract number 4'));
        final second = tester.getTopLeft(find.text('Contract number 3'));
        expect(second.dy, first.dy);
        expect(second.dx, greaterThan(first.dx));

        await tester.tap(find.text('Settings'));
        await tester.pumpAndSettle();
        expect(find.text('Camera quality'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}

import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:doculoom/app/di.dart';
import 'package:doculoom/app/router_observer.dart';
import 'package:doculoom/core/error/result.dart';
import 'package:doculoom/core/theme/app_theme.dart';
import 'package:doculoom/features/documents/domain/repositories/document_repository.dart';
import 'package:doculoom/features/documents/domain/usecases/document_usecases.dart';
import 'package:doculoom/features/importer/domain/importer.dart';
import 'package:doculoom/features/scanner/data/datasources/camera_access.dart';
import 'package:doculoom/features/scanner/domain/entities/filter_settings.dart';
import 'package:doculoom/features/scanner/domain/entities/scan_mode.dart';
import 'package:doculoom/features/scanner/domain/repositories/scanner_repository.dart';
import 'package:doculoom/features/scanner/domain/usecases/scanner_usecases.dart';
import 'package:doculoom/features/scanner/presentation/bloc/camera_cubit.dart';
import 'package:doculoom/features/scanner/presentation/bloc/scan_session_cubit.dart';
import 'package:doculoom/features/scanner/presentation/pages/camera_page.dart';
import 'package:doculoom/features/settings/data/settings_repository.dart';
import 'package:doculoom/features/settings/domain/app_settings.dart';
import 'package:doculoom/features/settings/presentation/settings_cubit.dart';

/// A phone whose camera permission is answered by the test.
class _Access implements CameraAccess {
  _Access(this.current, {CameraAccessStatus? afterAsk}) : afterAsk = afterAsk ?? current;

  CameraAccessStatus current;

  /// What the person answers when the system question is shown.
  CameraAccessStatus afterAsk;
  Completer<void>? holdQuestion;
  var statusCalls = 0;
  var requests = 0;
  var settingsOpened = 0;

  @override
  Future<CameraAccessStatus> status() async {
    statusCalls++;
    return current;
  }

  @override
  Future<CameraAccessStatus> request() async {
    requests++;
    await holdQuestion?.future;
    current = afterAsk;
    return current;
  }

  @override
  Future<bool> openSettings() async {
    settingsOpened++;
    return true;
  }
}

const _back = CameraDescription(name: '0', lensDirection: CameraLensDirection.back, sensorOrientation: 90);

class _Cameras {
  var opened = 0;

  /// What the camera hardware does when opened: null throws a plain failure, otherwise the given error.
  CameraException? error = CameraException('cameraError', 'broken');

  CameraController create(CameraDescription d, ResolutionPreset p) {
    opened++;
    return _ThrowingController(d, p, error);
  }
}

class _ThrowingController extends CameraController {
  _ThrowingController(super.description, super.resolutionPreset, this.error);
  final CameraException? error;

  @override
  Future<void> initialize() async => throw error ?? CameraException('cameraError', 'broken');

  @override
  // ignore: must_call_super
  Future<void> dispose() async {}
}

CameraCubit _cubit(_Access access, _Cameras cameras, {List<CameraDescription> list = const [_back]}) =>
    CameraCubit(access: access, listCameras: () async => list, createController: cameras.create);

void main() {
  group('camera permission (cubit)', () {
    test('without permission the camera is never opened and the person is told what to do', () async {
      final access = _Access(CameraAccessStatus.denied);
      final cameras = _Cameras();
      final cubit = _cubit(access, cameras);
      await cubit.start();
      expect(cubit.state.status, CameraStatus.permissionDenied);
      expect(cubit.state.settingsNeeded, isFalse);
      expect(cameras.opened, 0);
      expect(access.requests, 0, reason: 'coming back to the screen must not pop the system question again');
      await cubit.close();
    });

    test('the first visit asks once; saying no leaves the "allow camera" screen and the camera closed', () async {
      final access = _Access(CameraAccessStatus.denied);
      final cameras = _Cameras();
      final cubit = _cubit(access, cameras);
      await cubit.start(ask: true);
      expect(access.requests, 1);
      expect(cubit.state.status, CameraStatus.permissionDenied);
      expect(cubit.state.settingsNeeded, isFalse, reason: 'the system may still ask again');
      expect(cameras.opened, 0);
      await cubit.close();
    });

    test('saying yes opens the camera', () async {
      final access = _Access(CameraAccessStatus.denied, afterAsk: CameraAccessStatus.granted);
      final cameras = _Cameras();
      final cubit = _cubit(access, cameras);
      await cubit.start(ask: true);
      expect(cameras.opened, greaterThan(0));
      await cubit.close();
    });

    test('when the system no longer asks, the screen offers Settings and does not ask', () async {
      final access = _Access(CameraAccessStatus.blocked);
      final cameras = _Cameras();
      final cubit = _cubit(access, cameras);
      await cubit.start(ask: true);
      expect(cubit.state.status, CameraStatus.permissionDenied);
      expect(cubit.state.settingsNeeded, isTrue);
      expect(access.requests, 0);
      expect(cameras.opened, 0);

      await cubit.allowAccess();
      expect(access.settingsOpened, 1);
      expect(access.requests, 0);
      await cubit.close();
    });

    test('Allow camera asks again after a first no, and a second no leads to Settings', () async {
      final access = _Access(CameraAccessStatus.denied, afterAsk: CameraAccessStatus.blocked);
      final cameras = _Cameras();
      final cubit = _cubit(access, cameras);
      await cubit.start(ask: true);
      expect(cubit.state.settingsNeeded, isTrue, reason: 'the first answer already was a block');
      access.current = CameraAccessStatus.denied;
      await cubit.start(ask: true);
      await cubit.allowAccess();
      expect(access.settingsOpened, 1);
      expect(cameras.opened, 0);
      await cubit.close();
    });

    test('several starts at once ask only one question', () async {
      final access = _Access(CameraAccessStatus.denied);
      final cameras = _Cameras();
      final cubit = _cubit(access, cameras);
      await Future.wait([cubit.start(ask: true), cubit.start(ask: true), cubit.start(), cubit.resume()]);
      expect(access.requests, 1);
      expect(cameras.opened, 0);
      await cubit.close();
    });

    test('the app looking paused while the question is open changes nothing', () async {
      final access = _Access(CameraAccessStatus.denied)..holdQuestion = Completer<void>();
      final cameras = _Cameras();
      final cubit = _cubit(access, cameras);
      final starting = cubit.start(ask: true);
      await Future<void>.delayed(Duration.zero);
      await cubit.pause();
      await cubit.resume();
      expect(access.requests, 1);
      access.holdQuestion!.complete();
      await starting;
      expect(cubit.state.status, CameraStatus.permissionDenied);
      expect(access.requests, 1, reason: 'no second question after coming back');
      await cubit.close();
    });

    test('pausing and resuming on the "allow camera" screen neither flickers nor asks again', () async {
      final access = _Access(CameraAccessStatus.denied);
      final cameras = _Cameras();
      final cubit = _cubit(access, cameras);
      await cubit.start(ask: true);
      final states = <CameraStatus>[];
      final sub = cubit.stream.listen((s) => states.add(s.status));
      for (var i = 0; i < 5; i++) {
        await cubit.pause();
        await cubit.resume();
      }
      await sub.cancel();
      expect(states, isEmpty);
      expect(cubit.state.status, CameraStatus.permissionDenied);
      expect(access.requests, 1);
      await cubit.close();
    });

    test('after a visit to Settings the camera opens by itself once access was turned on', () async {
      final access = _Access(CameraAccessStatus.blocked);
      final cameras = _Cameras();
      final cubit = _cubit(access, cameras);
      await cubit.start(ask: true);
      await cubit.allowAccess();
      access.current = CameraAccessStatus.granted;
      await cubit.resume();
      expect(cameras.opened, greaterThan(0));
      await cubit.close();
    });

    test('after a visit to Settings where nothing was changed the screen stays and nothing loops', () async {
      final access = _Access(CameraAccessStatus.blocked);
      final cameras = _Cameras();
      final cubit = _cubit(access, cameras);
      await cubit.start(ask: true);
      await cubit.allowAccess();
      await cubit.resume();
      expect(cubit.state.status, CameraStatus.permissionDenied);
      expect(cubit.state.settingsNeeded, isTrue);
      expect(cameras.opened, 0);
      expect(access.requests, 0);
      await cubit.resume();
      expect(access.statusCalls, lessThan(5));
      await cubit.close();
    });

    test('a refusal reported by the camera itself (iOS) leads to Settings', () async {
      final access = _Access(CameraAccessStatus.granted);
      final cameras = _Cameras()..error = CameraException('CameraAccessDenied', 'no');
      final cubit = _cubit(access, cameras);
      await cubit.start(ask: true);
      expect(cubit.state.status, CameraStatus.permissionDenied);
      expect(cubit.state.settingsNeeded, isTrue);
      await cubit.close();
    });

    test('a restricted camera (parental controls) leads to Settings as well', () async {
      final access = _Access(CameraAccessStatus.granted);
      final cameras = _Cameras()..error = CameraException('CameraAccessRestricted', 'no');
      final cubit = _cubit(access, cameras);
      await cubit.start();
      expect(cubit.state.status, CameraStatus.permissionDenied);
      await cubit.close();
    });

    test('access taken away while running (Android) still allows asking again', () async {
      final access = _Access(CameraAccessStatus.denied, afterAsk: CameraAccessStatus.granted);
      final cameras = _Cameras()..error = CameraException('CameraAccessDenied', 'no');
      final cubit = CameraCubit(access: _GrantedOnce(access), listCameras: () async => [_back], createController: cameras.create);
      await cubit.start();
      expect(cubit.state.status, CameraStatus.permissionDenied);
      expect(cubit.state.settingsNeeded, isFalse);
      await cubit.close();
    });

    test('other camera problems are not mistaken for a missing permission', () async {
      final access = _Access(CameraAccessStatus.granted);
      final cameras = _Cameras();
      final cubit = _cubit(access, cameras);
      await cubit.start();
      expect(cubit.state.status, CameraStatus.failed);
      expect(cubit.state.failure?.message, contains('could not be started'));
      await cubit.close();
    });

    test('a phone without a camera says so instead of asking for permission', () async {
      final access = _Access(CameraAccessStatus.granted);
      final cubit = _cubit(access, _Cameras(), list: const []);
      await cubit.start();
      expect(cubit.state.status, CameraStatus.failed);
      expect(cubit.state.failure?.message, contains('No camera'));
      await cubit.close();
    });

    test('leaving the screen while the question is open does not crash when it is answered', () async {
      final access = _Access(CameraAccessStatus.denied, afterAsk: CameraAccessStatus.granted)..holdQuestion = Completer<void>();
      final cameras = _Cameras();
      final cubit = _cubit(access, cameras);
      final starting = cubit.start(ask: true);
      await Future<void>.delayed(Duration.zero);
      final closing = cubit.close();
      access.holdQuestion!.complete();
      await starting;
      await closing;
      expect(cameras.opened, 0, reason: 'the screen is gone, so no camera is opened');
    });

    test('Allow camera does nothing while the camera is working', () async {
      final access = _Access(CameraAccessStatus.granted);
      final cubit = _cubit(access, _Cameras());
      await cubit.allowAccess();
      expect(access.requests, 0);
      expect(access.settingsOpened, 0);
      await cubit.close();
    });
  });

  group('camera screen without permission', () {
    late _Access access;
    late _Cameras cameras;

    ScanSessionCubit session() {
      final scanner = _NoScanner();
      return ScanSessionCubit(
        prepareImage: PrepareImage(scanner),
        inspectImage: InspectImage(scanner),
        cropDocument: CropDocument(scanner),
        rotateImage: RotateImage(scanner),
        previewFilter: PreviewFilter(scanner),
        previewFilterBatch: PreviewFilterBatch(scanner),
        applyFilter: ApplyFilter(scanner),
        saveDocument: SaveDocument(_NoDocs()),
        updateDocument: UpdateDocument(_NoDocs()),
        importDocumentFile: ImportDocumentFile(_NoImporter()),
      )..start(defaultFilter: ScanFilter.original);
    }

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      if (sl.isRegistered<CameraCubit>()) sl.unregister<CameraCubit>();
      sl.registerFactory(() => _cubit(access, cameras));
      final settings = SettingsCubit(_Prefs());
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider.value(value: session()),
            BlocProvider.value(value: settings),
          ],
          child: MaterialApp(theme: AppTheme.light(), navigatorObservers: [routeObserver], home: const CameraPage()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('denying the permission shows a steady "Allow camera access" screen that does not blink or close', (tester) async {
      access = _Access(CameraAccessStatus.denied);
      cameras = _Cameras();
      await open(tester);

      expect(find.byKey(const ValueKey('camera-permission-title')), findsOneWidget);
      expect(find.byKey(const ValueKey('camera-allow')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(cameras.opened, 0);
      expect(access.requests, 1);

      // The system dialog and a return from it make the app look inactive, paused and resumed again.
      for (var i = 0; i < 4; i++) {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byKey(const ValueKey('camera-permission-title')), findsOneWidget, reason: 'no blinking while inactive');
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump(const Duration(milliseconds: 100));
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byKey(const ValueKey('camera-permission-title')), findsOneWidget, reason: 'no blinking after coming back');
        expect(find.byType(CircularProgressIndicator), findsNothing);
      }
      await tester.pump(const Duration(seconds: 6));
      expect(access.requests, 1, reason: 'the system question is not repeated on its own');
      expect(cameras.opened, 0);
      expect(find.byType(CameraPage), findsOneWidget, reason: 'the screen stays');
      expect(tester.takeException(), isNull);
    });

    testWidgets('the capture button, flash and auto mode are not offered without a camera', (tester) async {
      access = _Access(CameraAccessStatus.denied);
      cameras = _Cameras();
      await open(tester);
      expect(find.text('Auto'), findsNothing);
      expect(find.byTooltip('Turn flash on'), findsNothing);
      expect(tester.widget<GestureDetector>(find.byKey(const ValueKey('camera-capture'))).onTapDown, isNull);
      expect(find.text('Gallery'), findsOneWidget, reason: 'pictures can still be added from the gallery');
      expect(find.byTooltip('Close'), findsOneWidget);
    });

    testWidgets('the scan mode bar picks a mode and tells what it does', (tester) async {
      access = _Access(CameraAccessStatus.denied);
      cameras = _Cameras();
      await open(tester);
      final session = tester.element(find.byType(CameraPage)).read<ScanSessionCubit>();
      expect(session.state.mode, ScanMode.document);

      await tester.tap(find.byKey(const ValueKey('scan-mode-receipt')));
      await tester.pump();
      expect(session.state.mode, ScanMode.receipt);
      expect(session.state.currentFilter, ScanFilter.original, reason: 'a mode never adds a filter');
      expect(session.state.title, startsWith('Receipt '));

      await tester.tap(find.byKey(const ValueKey('scan-mode-document')));
      await tester.pump();
      expect(session.state.currentFilter, ScanFilter.original);
      expect(session.state.title, startsWith('Scan '));
    });

    testWidgets('the bottom bar has one capture button, Gallery and no overflow on a narrow phone', (tester) async {
      access = _Access(CameraAccessStatus.denied);
      cameras = _Cameras();
      tester.view.physicalSize = const Size(320 * 3, 640 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await open(tester);
      tester.view.physicalSize = const Size(320 * 3, 640 * 3);
      await tester.pump();
      expect(find.byKey(const ValueKey('camera-capture')), findsOneWidget);
      expect(find.text('Gallery'), findsOneWidget);
      expect(find.text('Phone camera'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Allow camera asks again; a second refusal turns the button into Open Settings', (tester) async {
      access = _Access(CameraAccessStatus.denied);
      cameras = _Cameras();
      await open(tester);
      expect(access.requests, 1);
      expect(find.byKey(const ValueKey('camera-allow')), findsOneWidget);

      access.afterAsk = CameraAccessStatus.blocked;
      await tester.tap(find.byKey(const ValueKey('camera-allow')));
      await tester.pump(const Duration(milliseconds: 50));
      expect(access.requests, 2);
      expect(find.byKey(const ValueKey('camera-open-settings')), findsOneWidget);
      expect(find.textContaining('Open Settings, tap Permissions'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('camera-open-settings')));
      await tester.pump();
      expect(access.settingsOpened, 1);
      expect(access.requests, 2, reason: 'Settings, not another question');
      expect(cameras.opened, 0);
    });

    testWidgets('allowing access in Settings and coming back opens the camera without any tap', (tester) async {
      access = _Access(CameraAccessStatus.blocked);
      cameras = _Cameras();
      await open(tester);
      expect(find.byKey(const ValueKey('camera-open-settings')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('camera-open-settings')));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      access.current = CameraAccessStatus.granted;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(cameras.opened, greaterThan(0));
      expect(find.byKey(const ValueKey('camera-permission-title')), findsNothing);
    });

    testWidgets('allowing the permission on the first question opens the camera', (tester) async {
      access = _Access(CameraAccessStatus.denied, afterAsk: CameraAccessStatus.granted);
      cameras = _Cameras();
      await open(tester);
      expect(cameras.opened, greaterThan(0));
      expect(find.byKey(const ValueKey('camera-permission-title')), findsNothing);
    });
  });
}

class _NoScanner implements ScannerRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _NoDocs implements DocumentRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _NoImporter implements DocumentImporter {
  @override
  Future<Result<ImportedDocument>> import({required ImportKind kind, required String path, ImportProgress? onProgress}) => throw UnimplementedError();
}

class _Prefs implements SettingsRepository {
  @override
  Future<AppSettings> load() async => const AppSettings();
  @override
  Future<void> save(AppSettings settings) async {}
}

/// Granted when the camera is opened but reported as asked-and-denied afterwards, like a permission revoked in between.
class _GrantedOnce implements CameraAccess {
  _GrantedOnce(this._inner);
  final _Access _inner;
  var _first = true;

  @override
  Future<CameraAccessStatus> status() async {
    if (_first) {
      _first = false;
      return CameraAccessStatus.granted;
    }
    return CameraAccessStatus.denied;
  }

  @override
  Future<CameraAccessStatus> request() => _inner.request();

  @override
  Future<bool> openSettings() => _inner.openSettings();
}

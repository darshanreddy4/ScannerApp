import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/error/failures.dart';
import '../../../settings/domain/app_settings.dart';
import '../../data/datasources/camera_access.dart';
import '../../data/datasources/document_edge_detector.dart';
import '../../domain/entities/quad.dart';

enum CameraStatus { initializing, ready, permissionDenied, failed }

class CameraState {
  const CameraState({
    this.status = CameraStatus.initializing,
    this.controller,
    this.quad,
    this.stable = false,
    this.flashOn = false,
    this.autoCapture = true,
    this.capturing = false,
    this.lens = CameraLensDirection.back,
    this.canSwitch = false,
    this.settingsNeeded = false,
    this.zoom = 1,
    this.minZoom = 1,
    this.maxZoom = 1,
    this.failure,
  });

  final CameraStatus status;
  final CameraController? controller;

  /// Detected outline in preview (display) orientation, normalized.
  final Quad? quad;
  final bool stable;
  final bool flashOn;
  final bool autoCapture;
  final bool capturing;

  /// Which camera is open. The front camera has no flash and no live outline (manual capture only).
  final CameraLensDirection lens;

  /// True when the device has both a back and a front camera.
  final bool canSwitch;

  /// With [CameraStatus.permissionDenied]: the system no longer asks, so access must be turned on in Settings.
  final bool settingsNeeded;

  /// Zoom factor and the range the camera offers; below 1 is the ultra-wide lens on phones that have one.
  final double zoom;
  final double minZoom;
  final double maxZoom;
  final Failure? failure;

  bool get isFront => lens == CameraLensDirection.front;

  CameraState copyWith({
    CameraStatus? status,
    CameraController? controller,
    Quad? quad,
    bool clearQuad = false,
    bool? stable,
    bool? flashOn,
    bool? autoCapture,
    bool? capturing,
    CameraLensDirection? lens,
    bool? canSwitch,
    bool? settingsNeeded,
    double? zoom,
    double? minZoom,
    double? maxZoom,
    Failure? failure,
  }) => CameraState(
    status: status ?? this.status,
    controller: controller ?? this.controller,
    quad: clearQuad ? null : (quad ?? this.quad),
    stable: stable ?? this.stable,
    flashOn: flashOn ?? this.flashOn,
    autoCapture: autoCapture ?? this.autoCapture,
    capturing: capturing ?? this.capturing,
    lens: lens ?? this.lens,
    canSwitch: canSwitch ?? this.canSwitch,
    settingsNeeded: settingsNeeded ?? this.settingsNeeded,
    zoom: zoom ?? this.zoom,
    minZoom: minZoom ?? this.minZoom,
    maxZoom: maxZoom ?? this.maxZoom,
    failure: failure ?? this.failure,
  );
}

class CameraCubit extends Cubit<CameraState> {
  CameraCubit({
    DocumentEdgeDetector detector = const DocumentEdgeDetector(),
    CameraAccess access = const SystemCameraAccess(),
    Future<List<CameraDescription>> Function() listCameras = availableCameras,
    CameraController Function(CameraDescription, ResolutionPreset)? createController,
  }) : _detector = detector,
       _access = access,
       _listCameras = listCameras,
       _createController = createController ?? _defaultController,
       super(const CameraState());

  static CameraController _defaultController(CameraDescription description, ResolutionPreset preset) => CameraController(
    description,
    preset,
    enableAudio: false,
    imageFormatGroup: defaultTargetPlatform == TargetPlatform.iOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.yuv420,
  );

  /// Called with the captured file path when auto-capture triggers.
  void Function(String path)? onAutoCaptured;

  static const _gridWidth = 96;
  static const _frameInterval = Duration(milliseconds: 200);
  static const _stableFramesRequired = 7;
  static const _stableDelta = 0.02;

  final DocumentEdgeDetector _detector;
  final CameraAccess _access;
  final Future<List<CameraDescription>> Function() _listCameras;
  final CameraController Function(CameraDescription, ResolutionPreset) _createController;
  CameraController? _controller;
  CameraQuality _quality = CameraQuality.high;
  CameraLensDirection _lens = CameraLensDirection.back;

  ResolutionPreset get _preset => switch (_quality) {
    CameraQuality.standard => ResolutionPreset.veryHigh,
    CameraQuality.high => ResolutionPreset.ultraHigh,
    CameraQuality.maximum => ResolutionPreset.max,
  };

  void setQuality(CameraQuality quality) => _quality = quality;

  bool _detect = true;

  /// Turns the live outline search (and with it auto-capture) on or off; cards are fitted into a frame instead.
  void setDetection(bool on) {
    if (_detect == on) return;
    _detect = on;
    _previous = null;
    _stableCount = 0;
    if (!on) emit(state.copyWith(clearQuad: true, stable: false));
  }

  Future<void> _readZoom(CameraController c) async {
    try {
      final lo = await c.getMinZoomLevel();
      final hi = await c.getMaxZoomLevel();
      if (!isClosed) emit(state.copyWith(minZoom: lo, maxZoom: hi, zoom: 1.0.clamp(lo, hi)));
    } catch (_) {
      // A camera without zoom control simply shows no zoom buttons.
    }
  }

  Future<void> setZoom(double level) async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || state.isFront) return;
    final next = level.clamp(state.minZoom, state.maxZoom);
    try {
      await c.setZoomLevel(next);
      if (!isClosed) emit(state.copyWith(zoom: next));
    } catch (_) {}
  }

  DateTime _lastFrame = DateTime.fromMillisecondsSinceEpoch(0);
  Quad? _previous;
  int _stableCount = 0;
  bool _disposed = false;
  bool _armed = true;

  /// The start in progress. Starts never overlap: the system permission question makes the app look paused and resumed.
  Future<void>? _starting;
  bool _asking = false;
  bool _openedSettings = false;

  /// Opens the camera. With [ask] the system permission question is shown first when it is still allowed; otherwise a
  /// missing permission only shows the "allow camera" screen. The camera is never opened without permission.
  Future<void> start({bool ask = false}) => _starting ??= _start(ask).whenComplete(() => _starting = null);

  Future<CameraAccessStatus> _checkAccess(bool ask) async {
    var access = await _access.status();
    if (access == CameraAccessStatus.denied && ask) {
      _asking = true;
      try {
        access = await _access.request();
      } finally {
        _asking = false;
      }
    }
    return access;
  }

  void _showDenied({required bool settingsNeeded}) {
    if (isClosed) return;
    emit(
      state.copyWith(
        status: CameraStatus.permissionDenied,
        settingsNeeded: settingsNeeded,
        failure: const PermissionFailure('Camera access is turned off. Allow it to scan documents.'),
      ),
    );
  }

  Future<void> _start(bool ask) async {
    await _release();
    if (isClosed) return;
    emit(CameraState(flashOn: state.flashOn, autoCapture: state.autoCapture, lens: _lens, canSwitch: state.canSwitch));
    try {
      final access = await _checkAccess(ask);
      if (isClosed) return;
      if (access != CameraAccessStatus.granted) {
        _showDenied(settingsNeeded: access == CameraAccessStatus.blocked);
        return;
      }
      final cameras = await _listCameras();
      if (isClosed) return;
      if (cameras.isEmpty) {
        emit(state.copyWith(status: CameraStatus.failed, failure: const CameraFailure('No camera was found on this device.')));
        return;
      }
      final canSwitch = cameras.any((c) => c.lensDirection == CameraLensDirection.back) && cameras.any((c) => c.lensDirection == CameraLensDirection.front);
      // A tablet may only have a front camera, so fall back to whatever exists.
      final description = cameras.firstWhere(
        (c) => c.lensDirection == _lens,
        orElse: () => cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cameras.first),
      );
      _lens = description.lensDirection;
      final front = _lens == CameraLensDirection.front;

      var controller = await _open(description, _preset);
      if (controller == null) {
        // Some cameras (often the front one) do not offer the highest preset.
        controller = await _open(description, ResolutionPreset.ultraHigh) ?? await _open(description, ResolutionPreset.high);
        if (controller == null) {
          emit(state.copyWith(status: CameraStatus.failed, failure: const CameraFailure('The camera could not be started.')));
          return;
        }
      }
      if (isClosed) {
        await controller.dispose();
        return;
      }
      _controller = controller;
      final torch = !front && state.flashOn;
      await controller.setFlashMode(torch ? FlashMode.torch : FlashMode.off).catchError((_) {});
      if (_disposed) {
        await controller.dispose();
        return;
      }
      emit(
        state.copyWith(status: CameraStatus.ready, controller: controller, lens: _lens, canSwitch: canSwitch, flashOn: torch, zoom: 1, minZoom: 1, maxZoom: 1),
      );
      if (!front) await _readZoom(controller);
      if (!front) await controller.startImageStream(_onFrame);
    } on CameraException catch (e) {
      if (isClosed) return;
      if (e.code.contains('AccessDenied') || e.code.contains('Restricted')) {
        // Where the system keeps its own record (Android) ask it; elsewhere a refusal can only be undone in Settings.
        _showDenied(settingsNeeded: await _access.status() != CameraAccessStatus.denied);
      } else {
        emit(
          state.copyWith(
            status: CameraStatus.failed,
            failure: CameraFailure('The camera could not be started.', cause: e),
          ),
        );
      }
    } catch (e) {
      if (isClosed) return;
      emit(
        state.copyWith(
          status: CameraStatus.failed,
          failure: CameraFailure('The camera could not be started.', cause: e),
        ),
      );
    }
  }

  /// Opens a controller, or returns null when this preset is not supported (permission errors still throw).
  Future<CameraController?> _open(CameraDescription description, ResolutionPreset preset) async {
    final controller = _createController(description, preset);
    try {
      await controller.initialize();
      return controller;
    } on CameraException catch (e) {
      await controller.dispose();
      if (e.code.contains('AccessDenied') || e.code.contains('Restricted')) rethrow;
      return null;
    }
  }

  /// Switches between the back and front camera.
  Future<void> switchCamera() async {
    if (!state.canSwitch || state.capturing || state.status == CameraStatus.initializing) return;
    _lens = _lens == CameraLensDirection.front ? CameraLensDirection.back : CameraLensDirection.front;
    await start();
  }

  void _onFrame(CameraImage image) {
    if (!_detect) return;
    final now = DateTime.now();
    if (now.difference(_lastFrame) < _frameInterval || state.capturing) return;
    _lastFrame = now;

    try {
      final gh = (_gridWidth * image.height / image.width).round();
      final gray = _grayGrid(image, _gridWidth, gh);
      final raw = _detector.detect(gray, _gridWidth, gh);
      final controller = _controller;
      if (controller == null) return;
      final quad = raw == null
          ? null
          : quadForDisplay(
              raw,
              frameRotation(
                sensorOrientation: controller.description.sensorOrientation,
                held: controller.value.lockedCaptureOrientation ?? controller.value.deviceOrientation,
                android: defaultTargetPlatform == TargetPlatform.android,
              ),
            );

      final previous = _previous;
      if (quad != null && previous != null && quad.maxCornerDelta(previous) < _stableDelta) {
        _stableCount++;
      } else {
        _stableCount = 0;
      }
      _previous = quad;
      // After an auto-capture, wait until the document leaves the frame before capturing again.
      if (quad == null) _armed = true;

      final stable = quad != null && _stableCount >= _stableFramesRequired;
      emit(state.copyWith(quad: quad, clearQuad: quad == null, stable: stable));

      if (stable && state.autoCapture && _armed) {
        _stableCount = 0;
        _armed = false;
        capture().then((path) {
          if (path != null) onAutoCaptured?.call(path);
        });
      }
    } catch (e) {
      debugPrint('Frame analysis skipped: $e');
    }
  }

  Uint8List _grayGrid(CameraImage image, int gw, int gh) {
    final plane = image.planes.first;
    final stride = plane.bytesPerRow;
    final bytes = plane.bytes;
    final bgra = image.format.group == ImageFormatGroup.bgra8888;
    final out = Uint8List(gw * gh);
    for (var y = 0; y < gh; y++) {
      final sy = (y * image.height / gh).floor();
      for (var x = 0; x < gw; x++) {
        final sx = (x * image.width / gw).floor();
        out[y * gw + x] = bgra ? bytes[sy * stride + sx * 4 + 1] : bytes[sy * stride + sx];
      }
    }
    return out;
  }

  Future<void> toggleFlash() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || state.isFront) return;
    final next = !state.flashOn;
    try {
      await c.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      emit(state.copyWith(flashOn: next));
    } catch (_) {}
  }

  void toggleAutoCapture() => emit(state.copyWith(autoCapture: !state.autoCapture));

  void setAutoCapture(bool value) => emit(state.copyWith(autoCapture: value));

  Future<String?> capture() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || state.capturing) return null;
    emit(state.copyWith(capturing: true));
    try {
      if (c.value.isStreamingImages) await c.stopImageStream();
      final file = await c.takePicture();
      return file.path;
    } catch (e) {
      emit(state.copyWith(capturing: false, failure: CameraFailure('The photo could not be captured.', cause: e)));
      await resumeStream();
      return null;
    }
  }

  Future<void> resumeStream() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    _previous = null;
    _stableCount = 0;
    emit(state.copyWith(capturing: false, stable: false, clearQuad: true));
    if (!state.isFront && !c.value.isStreamingImages) {
      try {
        await c.startImageStream(_onFrame);
      } catch (_) {}
    }
  }

  Future<void> _release() async {
    final c = _controller;
    _controller = null;
    if (c != null) {
      try {
        if (c.value.isStreamingImages) await c.stopImageStream();
      } catch (_) {}
      await c.dispose();
    }
  }

  /// Frees the camera while the app is backgrounded.
  Future<void> pause() async {
    // The permission question and the "allow camera" screen must stay as they are while the app looks paused.
    if (_asking || state.status == CameraStatus.permissionDenied) return;
    await _release();
    if (!isClosed) emit(CameraState(flashOn: state.flashOn, autoCapture: state.autoCapture, lens: _lens, canSwitch: state.canSwitch));
  }

  /// The app came back to the front: reopens the camera. A missing permission is only looked at again after a visit to
  /// Settings, so the system question can never loop.
  Future<void> resume() async {
    if (_asking) return;
    if (state.status == CameraStatus.permissionDenied) {
      if (!_openedSettings) return;
      _openedSettings = false;
    }
    await start();
  }

  /// "Allow camera": asks again, or goes to Settings once the system no longer asks.
  Future<void> allowAccess() async {
    if (state.status != CameraStatus.permissionDenied || _starting != null) return;
    if (state.settingsNeeded) {
      _openedSettings = true;
      await _access.openSettings();
    } else {
      await start(ask: true);
    }
  }

  @override
  Future<void> close() async {
    _disposed = true;
    await _release();
    return super.close();
  }
}

/// Clockwise degrees to turn a sensor frame so it is upright for the way the device is held.
@visibleForTesting
int frameRotation({required int sensorOrientation, required DeviceOrientation held, required bool android}) {
  if (!android) return sensorOrientation;
  final heldDegrees = switch (held) {
    DeviceOrientation.portraitUp => 0,
    DeviceOrientation.landscapeLeft => 90,
    DeviceOrientation.portraitDown => 180,
    DeviceOrientation.landscapeRight => 270,
  };
  return (sensorOrientation - heldDegrees + 360) % 360;
}

/// Turns a quad found in sensor orientation by [rotation] degrees clockwise, as corners ordered tl, tr, br, bl.
@visibleForTesting
Quad quadForDisplay(Quad q, int rotation) {
  NormPoint map(NormPoint p) => switch (rotation) {
    90 => NormPoint(1 - p.y, p.x),
    180 => NormPoint(1 - p.x, 1 - p.y),
    270 => NormPoint(p.y, 1 - p.x),
    _ => p,
  };
  final pts = q.points.map(map).toList();
  final bySum = [...pts]..sort((a, b) => (a.x + a.y).compareTo(b.x + b.y));
  final tl = bySum.first, br = bySum.last;
  final rest = pts.where((p) => p != tl && p != br).toList()..sort((a, b) => (b.x - b.y).compareTo(a.x - a.y));
  return Quad(tl, rest.first, br, rest.last);
}

/// Zoom buttons to offer for a camera whose zoom runs from [min] to [max]: the ultra-wide end when there is one, then 1x and the usual steps.
List<double> zoomStops(double min, double max) {
  final stops = <double>[
    if (min < 0.95) (min * 10).ceil() / 10,
    for (final z in const [1.0, 2.0, 3.0, 5.0, 10.0])
      if (z >= min - 0.001 && z <= max + 0.001) z,
  ];
  return stops.length < 2 ? const [] : stops;
}

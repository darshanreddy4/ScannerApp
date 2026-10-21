import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/error/failures.dart';
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
  final Failure? failure;

  CameraState copyWith({
    CameraStatus? status,
    CameraController? controller,
    Quad? quad,
    bool clearQuad = false,
    bool? stable,
    bool? flashOn,
    bool? autoCapture,
    bool? capturing,
    Failure? failure,
  }) =>
      CameraState(
        status: status ?? this.status,
        controller: controller ?? this.controller,
        quad: clearQuad ? null : (quad ?? this.quad),
        stable: stable ?? this.stable,
        flashOn: flashOn ?? this.flashOn,
        autoCapture: autoCapture ?? this.autoCapture,
        capturing: capturing ?? this.capturing,
        failure: failure ?? this.failure,
      );
}

class CameraCubit extends Cubit<CameraState> {
  CameraCubit({DocumentEdgeDetector detector = const DocumentEdgeDetector()})
      : _detector = detector,
        super(const CameraState());

  /// Called with the captured file path when auto-capture triggers.
  void Function(String path)? onAutoCaptured;

  static const _gridWidth = 96;
  static const _frameInterval = Duration(milliseconds: 200);
  static const _stableFramesRequired = 7;
  static const _stableDelta = 0.02;

  final DocumentEdgeDetector _detector;
  CameraController? _controller;
  DateTime _lastFrame = DateTime.fromMillisecondsSinceEpoch(0);
  Quad? _previous;
  int _stableCount = 0;
  bool _disposed = false;

  Future<void> start() async {
    await _release();
    emit(CameraState(flashOn: state.flashOn, autoCapture: state.autoCapture));
    try {
      final cameras = await availableCameras();
      final back = cameras.where((c) => c.lensDirection == CameraLensDirection.back);
      if (back.isEmpty) {
        emit(state.copyWith(status: CameraStatus.failed, failure: const CameraFailure('No camera was found on this device.')));
        return;
      }
      final controller = CameraController(
        back.first,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: defaultTargetPlatform == TargetPlatform.iOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.yuv420,
      );
      _controller = controller;
      await controller.initialize();
      await controller.setFlashMode(state.flashOn ? FlashMode.torch : FlashMode.off);
      if (_disposed) {
        await controller.dispose();
        return;
      }
      emit(state.copyWith(status: CameraStatus.ready, controller: controller));
      await controller.startImageStream(_onFrame);
    } on CameraException catch (e) {
      final denied = e.code.contains('AccessDenied') || e.code.contains('Restricted');
      emit(state.copyWith(
        status: denied ? CameraStatus.permissionDenied : CameraStatus.failed,
        failure: denied
            ? const PermissionFailure('Camera access is turned off. Enable it in Settings to scan documents.')
            : CameraFailure('The camera could not be started.', cause: e),
      ));
    } catch (e) {
      emit(state.copyWith(status: CameraStatus.failed, failure: CameraFailure('The camera could not be started.', cause: e)));
    }
  }

  void _onFrame(CameraImage image) {
    final now = DateTime.now();
    if (now.difference(_lastFrame) < _frameInterval || state.capturing) return;
    _lastFrame = now;

    try {
      final gh = (_gridWidth * image.height / image.width).round();
      final gray = _grayGrid(image, _gridWidth, gh);
      final raw = _detector.detect(gray, _gridWidth, gh);
      final controller = _controller;
      if (controller == null) return;
      final quad = raw == null ? null : _toDisplayOrientation(raw, controller.description.sensorOrientation);

      final previous = _previous;
      if (quad != null && previous != null && quad.maxCornerDelta(previous) < _stableDelta) {
        _stableCount++;
      } else {
        _stableCount = 0;
      }
      _previous = quad;

      final stable = quad != null && _stableCount >= _stableFramesRequired;
      emit(state.copyWith(quad: quad, clearQuad: quad == null, stable: stable));

      if (stable && state.autoCapture) {
        _stableCount = 0;
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

  /// Maps a quad from sensor orientation into the upright preview.
  Quad _toDisplayOrientation(Quad q, int sensorOrientation) {
    NormPoint map(NormPoint p) => switch (sensorOrientation) {
          90 => NormPoint(1 - p.y, p.x),
          180 => NormPoint(1 - p.x, 1 - p.y),
          270 => NormPoint(p.y, 1 - p.x),
          _ => p,
        };
    final pts = q.points.map(map).toList();
    // Re-sort into tl, tr, br, bl after rotation.
    final bySum = [...pts]..sort((a, b) => (a.x + a.y).compareTo(b.x + b.y));
    final tl = bySum.first, br = bySum.last;
    final rest = pts.where((p) => p != tl && p != br).toList()..sort((a, b) => (b.x - b.y).compareTo(a.x - a.y));
    return Quad(tl, rest.first, br, rest.last);
  }

  Future<void> toggleFlash() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final next = !state.flashOn;
    try {
      await c.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      emit(state.copyWith(flashOn: next));
    } catch (_) {}
  }

  void toggleAutoCapture() => emit(state.copyWith(autoCapture: !state.autoCapture));

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
    if (!c.value.isStreamingImages) {
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
    await _release();
    if (!isClosed) emit(const CameraState().copyWith(flashOn: state.flashOn, autoCapture: state.autoCapture));
  }

  @override
  Future<void> close() async {
    _disposed = true;
    await _release();
    return super.close();
  }
}

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../app/di.dart';
import '../../../../app/router_observer.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/widgets/feedback.dart';
import '../bloc/camera_cubit.dart';
import '../bloc/scan_session_cubit.dart';
import '../widgets/quad_overlay.dart';

class CameraPage extends StatelessWidget {
  const CameraPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (_) => sl<CameraCubit>(),
        child: const _CameraView(),
      );
}

class _CameraView extends StatefulWidget {
  const _CameraView();

  @override
  State<_CameraView> createState() => _CameraViewState();
}

class _CameraViewState extends State<_CameraView> with WidgetsBindingObserver, RouteAware {
  final _picker = ImagePicker();
  CameraCubit get _camera => context.read<CameraCubit>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _camera.onAutoCaptured = _handleCaptured;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) routeObserver.subscribe(this, route);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _camera.pause();
    } else if (state == AppLifecycleState.resumed && (ModalRoute.of(context)?.isCurrent ?? false)) {
      _camera.start();
    }
  }

  @override
  void didPush() {
    // Only open the camera if this page is actually visible (not underneath crop).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) _camera.start();
    });
  }

  @override
  void didPushNext() => _camera.pause();

  @override
  void didPopNext() => _camera.start();

  Future<void> _capture() async {
    final path = await _camera.capture();
    if (path != null) await _handleCaptured(path);
  }

  Future<void> _pickFromGallery() async {
    try {
      final file = await _picker.pickImage(source: ImageSource.gallery);
      if (file != null) await _openCrop(file.path);
    } catch (_) {
      if (mounted) showFailure(context, const PermissionFailure('Photo library access is unavailable.'));
    }
  }

  Future<void> _handleCaptured(String path) => _openCrop(path, fromCamera: true);

  Future<void> _openCrop(String path, {bool fromCamera = false}) async {
    final session = context.read<ScanSessionCubit>();
    final ok = await session.beginDraft(path);
    if (!mounted) return;
    if (ok) {
      context.push('/scan/crop');
    } else {
      final error = session.state.error;
      if (error != null) showFailure(context, error);
      if (fromCamera) await _camera.resumeStream();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pageCount = context.select((ScanSessionCubit c) => c.state.pages.length);
    final busy = context.select((ScanSessionCubit c) => c.state.busy);

    return Scaffold(
      backgroundColor: AppColors.scannerBackdrop,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _TopBar(pageCount: pageCount),
                const Expanded(child: _Viewfinder()),
                _BottomBar(onCapture: _capture, onGallery: _pickFromGallery),
              ],
            ),
            BusyOverlay(visible: busy, label: 'Preparing image'),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.pageCount});
  final int pageCount;

  @override
  Widget build(BuildContext context) {
    final flashOn = context.select((CameraCubit c) => c.state.flashOn);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Close',
            color: Colors.white,
            icon: const Icon(AppIcons.close),
            onPressed: () => context.go('/'),
          ),
          const Spacer(),
          IconButton(
            tooltip: flashOn ? 'Turn flash off' : 'Turn flash on',
            color: Colors.white,
            icon: Icon(flashOn ? AppIcons.flash : AppIcons.flashOff),
            onPressed: () => context.read<CameraCubit>().toggleFlash(),
          ),
          if (pageCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 12)),
                onPressed: () => context.go('/scan/review'),
                icon: const Icon(AppIcons.document, size: 18),
                label: Text('$pageCount'),
              ),
            ),
        ],
      ),
    );
  }
}

class _Viewfinder extends StatelessWidget {
  const _Viewfinder();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CameraCubit, CameraState>(
      builder: (context, state) {
        switch (state.status) {
          case CameraStatus.initializing:
            return const Center(child: CircularProgressIndicator(color: Colors.white));
          case CameraStatus.permissionDenied:
          case CameraStatus.failed:
            return _CameraMessage(
              message: state.failure?.message ?? 'The camera is unavailable.',
              showRetry: state.status == CameraStatus.failed,
            );
          case CameraStatus.ready:
            final controller = state.controller!;
            return Center(
              child: AspectRatio(
                aspectRatio: 1 / controller.value.aspectRatio,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(borderRadius: BorderRadius.circular(AppSpacing.sm), child: CameraPreview(controller)),
                    CustomPaint(painter: QuadOverlayPainter(quad: state.quad, locked: state.stable)),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: AppSpacing.md,
                      child: Center(child: _StatusPill(detected: state.quad != null, stable: state.stable)),
                    ),
                  ],
                ),
              ),
            );
        }
      },
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.detected, required this.stable});
  final bool detected;
  final bool stable;

  @override
  Widget build(BuildContext context) {
    final (icon, text, color) = stable
        ? (AppIcons.check, 'Hold steady', AppColors.success)
        : detected
            ? (AppIcons.autoDetect, 'Document detected', AppColors.primary)
            : (AppIcons.scan, 'Align document in frame', Colors.black87);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: Colors.white),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
      ]),
    );
  }
}

class _CameraMessage extends StatelessWidget {
  const _CameraMessage({required this.message, required this.showRetry});
  final String message;
  final bool showRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(AppIcons.camera, size: 48, color: Colors.white54),
              const SizedBox(height: AppSpacing.md),
              Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 15)),
              if (showRetry) ...[
                const SizedBox(height: AppSpacing.md),
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(140, 44)),
                  onPressed: () => context.read<CameraCubit>().start(),
                  child: const Text('Try again'),
                ),
              ],
            ],
          ),
        ),
      );
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.onCapture, required this.onGallery});
  final VoidCallback onCapture;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context) {
    final auto = context.select((CameraCubit c) => c.state.autoCapture);
    final capturing = context.select((CameraCubit c) => c.state.capturing);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _RoundAction(icon: AppIcons.gallery, label: 'Import', onTap: onGallery),
          GestureDetector(
            onTap: capturing ? null : onCapture,
            child: Container(
              width: 72,
              height: 72,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3)),
              child: DecoratedBox(
                decoration: BoxDecoration(shape: BoxShape.circle, color: capturing ? Colors.white54 : Colors.white),
              ),
            ),
          ),
          _RoundAction(
            icon: AppIcons.autoCapture,
            label: auto ? 'Auto on' : 'Auto off',
            active: auto,
            onTap: () => context.read<CameraCubit>().toggleAutoCapture(),
          ),
        ],
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({required this.icon, required this.label, required this.onTap, this.active = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) => InkResponse(
        onTap: onTap,
        child: SizedBox(
          width: 64,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: active ? AppColors.scannerOverlay : Colors.white, size: 26),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(color: active ? AppColors.scannerOverlay : Colors.white70, fontSize: 11)),
            ],
          ),
        ),
      );
}

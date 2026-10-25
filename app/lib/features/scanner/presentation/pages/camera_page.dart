import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../app/di.dart';
import '../../../../app/router_observer.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/widgets/feedback.dart';
import '../../../settings/presentation/settings_cubit.dart';
import '../bloc/camera_cubit.dart';
import '../bloc/scan_session_cubit.dart';
import '../widgets/quad_overlay.dart';

class CameraPage extends StatelessWidget {
  const CameraPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(create: (_) => sl<CameraCubit>(), child: const _CameraView());
}

class _CameraView extends StatefulWidget {
  const _CameraView();

  @override
  State<_CameraView> createState() => _CameraViewState();
}

class _CameraViewState extends State<_CameraView> with WidgetsBindingObserver, RouteAware {
  final _picker = ImagePicker();
  CameraCubit get _camera => context.read<CameraCubit>();
  ScanSessionCubit get _session => context.read<ScanSessionCubit>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _camera
      ..onAutoCaptured = _handleCaptured
      ..setQuality(context.read<SettingsCubit>().state.cameraQuality)
      ..setAutoCapture(context.read<SettingsCubit>().state.autoCapture);
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
      _camera.resume();
    }
  }

  @override
  void didPush() {
    // Only open the camera if this page is actually visible.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) _camera.start(ask: true);
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

  /// Captured photo: open the crop screen, or add the page directly when it is turned off.
  Future<void> _handleCaptured(String path) async {
    final showCrop = context.read<SettingsCubit>().state.showCropAfterCapture;
    final ok = await _session.beginDraft(path);
    if (!mounted) return;
    if (!ok) {
      if (_session.state.error != null) showFailure(context, _session.state.error!);
      await _camera.resumeStream();
      return;
    }
    if (showCrop) {
      context.push('/scan/crop');
      return;
    }
    final added = await _session.commitAll();
    if (!mounted) return;
    if (added) {
      HapticFeedback.mediumImpact();
    } else if (_session.state.error != null) {
      showFailure(context, _session.state.error!);
    }
    await _camera.resumeStream();
  }

  Future<void> _pickFromGallery() async {
    final showCrop = context.read<SettingsCubit>().state.showCropAfterCapture;
    try {
      final files = await _picker.pickMultiImage();
      if (files.isEmpty || !mounted) return;
      final ok = await _session.importMany([for (final f in files) f.path]);
      if (!mounted) return;
      if (!ok) {
        if (_session.state.error != null) showFailure(context, _session.state.error!);
        return;
      }
      if (showCrop) {
        context.push('/scan/crop');
      } else {
        final done = await _session.commitAll();
        if (!mounted) return;
        if (done && _session.state.pages.isNotEmpty) {
          context.go('/scan/edit');
        } else if (_session.state.error != null) {
          showFailure(context, _session.state.error!);
        }
      }
    } catch (_) {
      if (mounted) showFailure(context, const PermissionFailure('Photo library access is unavailable.'));
    }
  }

  Future<void> _close() async {
    if (_session.state.pages.isEmpty) {
      context.go('/');
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard scan?'),
        content: const Text('The pages you captured will be deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final pages = context.select((ScanSessionCubit c) => c.state.pages);
    final busy = context.select((ScanSessionCubit c) => c.state.busy);
    final busyLabel = context.select((ScanSessionCubit c) => c.state.busyLabel);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: AppColors.scannerBackdrop,
        body: SafeArea(
          child: Stack(
            children: [
              OrientationBuilder(
                builder: (context, orientation) {
                  final bottom = _BottomBar(
                    axis: orientation == Orientation.landscape ? Axis.vertical : Axis.horizontal,
                    pages: pages.length,
                    lastPagePath: pages.isEmpty ? null : pages.last.croppedPath,
                    onCapture: _capture,
                    onGallery: _pickFromGallery,
                    onDone: () => context.go('/scan/edit'),
                  );
                  // Held sideways (tablets, foldables) the controls move to the right edge so the preview keeps its height.
                  if (orientation == Orientation.landscape) {
                    return Row(
                      children: [
                        const Expanded(child: _Viewfinder()),
                        SizedBox(
                          width: 128,
                          child: Column(
                            children: [
                              _TopBar(onClose: _close, axis: Axis.vertical),
                              Expanded(child: Center(child: bottom)),
                            ],
                          ),
                        ),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      _TopBar(onClose: _close),
                      const Expanded(child: _Viewfinder()),
                      bottom,
                    ],
                  );
                },
              ),
              BusyOverlay(visible: busy, label: busyLabel),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onClose, this.axis = Axis.horizontal});
  final VoidCallback onClose;
  final Axis axis;

  @override
  Widget build(BuildContext context) {
    final flashOn = context.select((CameraCubit c) => c.state.flashOn);
    final auto = context.select((CameraCubit c) => c.state.autoCapture);
    final front = context.select((CameraCubit c) => c.state.isFront);
    final canSwitch = context.select((CameraCubit c) => c.state.canSwitch);
    final ready = context.select((CameraCubit c) => c.state.status == CameraStatus.ready);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Flex(
        direction: axis,
        mainAxisSize: axis == Axis.vertical ? MainAxisSize.min : MainAxisSize.max,
        children: [
          IconButton(tooltip: 'Close', color: Colors.white, icon: const Icon(AppIcons.close), onPressed: onClose),
          if (axis == Axis.horizontal) const Spacer(),
          // The front camera has no outline detection or flash, so these only apply to the back camera.
          if (ready && !front)
            TextButton.icon(
              onPressed: () {
                context.read<CameraCubit>().toggleAutoCapture();
                context.read<SettingsCubit>().update((s) => s.copyWith(autoCapture: !auto));
              },
              style: TextButton.styleFrom(foregroundColor: auto ? AppColors.scannerOverlay : Colors.white70),
              icon: const Icon(AppIcons.autoCapture, size: 18),
              label: Text(auto ? 'Auto' : 'Manual'),
            ),
          if (ready && !front)
            IconButton(
              tooltip: flashOn ? 'Turn flash off' : 'Turn flash on',
              color: Colors.white,
              icon: Icon(flashOn ? AppIcons.flash : AppIcons.flashOff),
              onPressed: () => context.read<CameraCubit>().toggleFlash(),
            ),
          if (ready && canSwitch)
            IconButton(
              tooltip: front ? 'Use back camera' : 'Use front camera',
              color: Colors.white,
              icon: const Icon(AppIcons.flipCamera),
              onPressed: () => context.read<CameraCubit>().switchCamera(),
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
            return _PermissionNeeded(settingsNeeded: state.settingsNeeded);
          case CameraStatus.failed:
            return _CameraMessage(message: state.failure?.message ?? 'The camera is unavailable.', showRetry: true);
          case CameraStatus.ready:
            final controller = state.controller!;
            // CameraPreview sizes itself for the way the device is held, so this also works rotated on tablets.
            return Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppSpacing.sm),
                child: CameraPreview(
                  controller,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (!state.isFront)
                        CustomPaint(
                          painter: QuadOverlayPainter(quad: state.quad, locked: state.stable),
                        ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: AppSpacing.md,
                        child: Center(
                          child: _StatusPill(detected: state.quad != null, stable: state.stable, auto: state.autoCapture, front: state.isFront),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
        }
      },
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.detected, required this.stable, required this.auto, this.front = false});
  final bool detected;
  final bool stable;
  final bool auto;
  final bool front;

  @override
  Widget build(BuildContext context) {
    final (icon, text, color) = front
        ? (AppIcons.camera, 'Front camera: tap to capture', Colors.black87)
        : stable
        ? (AppIcons.check, auto ? 'Hold steady' : 'Ready to capture', AppColors.success)
        : detected
        ? (AppIcons.autoDetect, 'Document detected', AppColors.primary)
        : (AppIcons.scan, 'Align document in frame', Colors.black87);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

/// Shown instead of the camera until access is allowed; the camera itself is not opened before that.
class _PermissionNeeded extends StatelessWidget {
  const _PermissionNeeded({required this.settingsNeeded});
  final bool settingsNeeded;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(AppIcons.camera, size: 48, color: Colors.white54),
            const SizedBox(height: AppSpacing.md),
            const Text(
              'Allow camera access',
              key: ValueKey('camera-permission-title'),
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              settingsNeeded
                  ? 'Camera access is turned off for ScanVault. Open Settings, tap Permissions, then Camera, and choose Allow.'
                  : 'ScanVault needs the camera to photograph your documents. Pictures stay on your phone.',
              key: const ValueKey('camera-permission-text'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 15),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              key: ValueKey(settingsNeeded ? 'camera-open-settings' : 'camera-allow'),
              onPressed: () => context.read<CameraCubit>().allowAccess(),
              child: Text(settingsNeeded ? 'Open Settings' : 'Allow camera'),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'You can still add pictures with Gallery.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );
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
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 15),
          ),
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
  const _BottomBar({
    required this.axis,
    required this.pages,
    required this.lastPagePath,
    required this.onCapture,
    required this.onGallery,
    required this.onDone,
  });

  final Axis axis;
  final int pages;
  final String? lastPagePath;
  final VoidCallback onCapture;
  final VoidCallback onGallery;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final capturing = context.select((CameraCubit c) => c.state.capturing);
    final ready = context.select((CameraCubit c) => c.state.status == CameraStatus.ready);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      child: Flex(
        direction: axis,
        mainAxisSize: axis == Axis.vertical ? MainAxisSize.min : MainAxisSize.max,
        mainAxisAlignment: axis == Axis.vertical ? MainAxisAlignment.center : MainAxisAlignment.spaceBetween,
        children: [
          _RoundAction(icon: AppIcons.gallery, label: 'Gallery', onTap: onGallery),
          if (axis == Axis.vertical) const SizedBox(height: AppSpacing.md),
          GestureDetector(
            key: const ValueKey('camera-capture'),
            onTap: capturing || !ready ? null : onCapture,
            child: Opacity(
              opacity: ready ? 1 : 0.35,
              child: Container(
                width: 72,
                height: 72,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(shape: BoxShape.circle, color: capturing ? Colors.white54 : Colors.white),
                ),
              ),
            ),
          ),
          if (axis == Axis.vertical) const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: 64,
            child: pages == 0 || lastPagePath == null
                ? const SizedBox.shrink()
                : InkResponse(
                    onTap: onDone,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              width: 44,
                              height: 52,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Image.file(File(lastPagePath!), fit: BoxFit.cover, cacheWidth: 140, gaplessPlayback: true),
                              ),
                            ),
                            Positioned(
                              top: -8,
                              right: -8,
                              child: CircleAvatar(
                                radius: 11,
                                backgroundColor: AppColors.primary,
                                child: Text(
                                  '$pages',
                                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Done',
                          style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkResponse(
    onTap: onTap,
    child: SizedBox(
      width: 64,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 26),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    ),
  );
}

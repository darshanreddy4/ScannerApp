import 'package:flutter/material.dart' hide Text;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../app/di.dart';
import '../../../core/i18n/tr.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/text.dart';
import '../../documents/presentation/widgets/document_widgets.dart' show confirmDestructive;
import '../../scanner/data/datasources/camera_access.dart';
import '../data/system_scan_services.dart' show detectedFrom;
import '../domain/scan_services.dart';
import 'code_result_card.dart';
import 'qr_scan_cubits.dart';

/// Builds the live camera view and calls `onDetect` with the codes it sees.
typedef CodeCameraBuilder = Widget Function(BuildContext context, void Function(List<DetectedCode> codes) onDetect);

Widget defaultCameraBuilder(BuildContext context, void Function(List<DetectedCode>) onDetect) => _CameraScanView(onDetect: onDetect);

Future<String?> _pickPicture() async => (await ImagePicker().pickImage(source: ImageSource.gallery))?.path;

/// Reads QR codes and barcodes with the camera or from a picture. Nothing is sent anywhere.
class QrScanPage extends StatelessWidget {
  const QrScanPage({super.key, this.cameraBuilder = defaultCameraBuilder, this.pickPicture = _pickPicture});
  final CodeCameraBuilder cameraBuilder;
  final Future<String?> Function() pickPicture;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => QrScanCubit(history: sl<ScanHistory>(), reader: sl<CodeImageReader>()),
    child: _ScanView(cameraBuilder: cameraBuilder, pickPicture: pickPicture),
  );
}

class _ScanView extends StatefulWidget {
  const _ScanView({required this.cameraBuilder, required this.pickPicture});
  final CodeCameraBuilder cameraBuilder;
  final Future<String?> Function() pickPicture;

  @override
  State<_ScanView> createState() => _ScanViewState();
}

class _ScanViewState extends State<_ScanView> {
  CameraAccessStatus? _access;

  @override
  void initState() {
    super.initState();
    _ask();
  }

  Future<void> _ask() async {
    final s = await sl<CameraAccess>().request();
    if (mounted) setState(() => _access = s);
  }

  Future<void> _fromPicture() async {
    final cubit = context.read<QrScanCubit>();
    final path = await widget.pickPicture();
    if (path != null) await cubit.scanImage(path);
  }

  Future<void> _open(QrScanState s) async {
    final cubit = context.read<QrScanCubit>();
    await showCodeSheet(context, s.current!);
    cubit.dismiss();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<QrScanCubit>();
    return BlocListener<QrScanCubit, QrScanState>(
      listenWhen: (a, b) => (b.current != null && a.current?.raw != b.current!.raw) || (b.notice != null && a.notice != b.notice),
      listener: (context, s) {
        if (s.current != null) {
          _open(s);
        } else if (s.notice != null) {
          showMessage(context, s.notice!);
          cubit.dismiss();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Scan QR code'),
          actions: [
            IconButton(tooltip: tr('Read from a picture'), icon: const Icon(AppIcons.images), onPressed: _fromPicture),
            IconButton(tooltip: tr('Scan history'), icon: const Icon(AppIcons.history), onPressed: () => context.push('/qr-history')),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(child: _camera(context)),
              BlocBuilder<QrScanCubit, QrScanState>(
                builder: (context, s) => Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.md),
                  child: s.busy
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                            SizedBox(width: 10),
                            Text('Reading the picture...'),
                          ],
                        )
                      : const Text(
                          'Point the camera at a QR code or barcode. Everything is read on this phone and nothing is uploaded.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted, height: 1.4),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _camera(BuildContext context) {
    final access = _access;
    if (access == null) return const Center(child: CircularProgressIndicator());
    if (access != CameraAccessStatus.granted) {
      final blocked = access == CameraAccessStatus.blocked;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(AppIcons.camera, size: 40, color: AppColors.inkMuted),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'The camera is needed to read codes.',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                blocked
                    ? 'Allow the camera for Doculoom in your phone\'s Settings. You can still read a code from a picture.'
                    : 'Allow the camera when your phone asks. You can still read a code from a picture.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: AppColors.inkMuted, height: 1.4),
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                onPressed: () async {
                  if (blocked) {
                    await sl<CameraAccess>().openSettings();
                  } else {
                    await _ask();
                  }
                },
                child: Text(blocked ? 'Open Settings' : 'Allow camera'),
              ),
              if (blocked) TextButton(onPressed: _ask, child: const Text('Check again')),
            ],
          ),
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.cameraBuilder(context, (codes) => context.read<QrScanCubit>().onDetected(codes)),
        const IgnorePointer(child: Center(child: _Frame())),
      ],
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame();

  @override
  Widget build(BuildContext context) {
    final side = (MediaQuery.sizeOf(context).shortestSide * 0.62).clamp(160.0, 320.0);
    return Container(
      width: side,
      height: side,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white, width: 3),
      ),
    );
  }
}

class _CameraScanView extends StatefulWidget {
  const _CameraScanView({required this.onDetect});
  final void Function(List<DetectedCode>) onDetect;

  @override
  State<_CameraScanView> createState() => _CameraScanViewState();
}

class _CameraScanViewState extends State<_CameraScanView> {
  final _controller = MobileScannerController();
  bool _torch = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      MobileScanner(
        controller: _controller,
        onDetect: (capture) {
          final codes = detectedFrom(capture);
          if (codes.isNotEmpty) widget.onDetect(codes);
        },
        errorBuilder: (context, error) => ColoredBox(
          color: Colors.black,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text(
                error.errorCode == MobileScannerErrorCode.permissionDenied
                    ? 'The camera is not allowed. Allow it in your phone\'s Settings.'
                    : 'The camera could not be started.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ),
      ),
      Positioned(
        right: 12,
        bottom: 12,
        child: Row(
          children: [
            IconButton.filledTonal(
              tooltip: tr(_torch ? 'Turn the light off' : 'Turn the light on'),
              icon: Icon(_torch ? AppIcons.torchOff : AppIcons.torchOn),
              onPressed: () async {
                await _controller.toggleTorch();
                if (mounted) setState(() => _torch = !_torch);
              },
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(tooltip: tr('Switch camera'), icon: const Icon(AppIcons.switchCamera), onPressed: _controller.switchCamera),
          ],
        ),
      ),
    ],
  );
}

// region history

/// Codes scanned earlier, kept on this phone only.
class QrHistoryPage extends StatelessWidget {
  const QrHistoryPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(create: (_) => QrHistoryCubit(sl<ScanHistory>())..load(), child: const _HistoryView());
}

class _HistoryView extends StatelessWidget {
  const _HistoryView();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<QrHistoryCubit, QrHistoryState>(
      builder: (context, state) {
        final cubit = context.read<QrHistoryCubit>();
        return Scaffold(
          appBar: AppBar(
            title: const Text('Scan history'),
            actions: [
              if (state.items.isNotEmpty)
                IconButton(
                  tooltip: tr('Clear history'),
                  icon: const Icon(AppIcons.delete),
                  onPressed: () async {
                    final ok = await confirmDestructive(
                      context,
                      title: 'Clear the scan history?',
                      message: 'The list of scanned codes is removed from this phone.',
                      action: 'Clear',
                    );
                    if (ok) await cubit.clear();
                  },
                ),
            ],
          ),
          body: SafeArea(
            child: ListView(
              padding: contentPadding(context, base: AppSpacing.md, maxWidth: 640),
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Keep a history of scans'),
                  subtitle: const Text('Stored only on this phone.'),
                  value: state.enabled,
                  onChanged: cubit.setEnabled,
                ),
                const SizedBox(height: AppSpacing.sm),
                if (state.loaded && state.items.isEmpty)
                  const Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacing.md),
                      child: Text('No scans yet. Codes you scan appear here.', style: TextStyle(height: 1.4)),
                    ),
                  ),
                for (final r in state.items)
                  Card(
                    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: ListTile(
                      key: ValueKey('scan-${r.raw.hashCode}'),
                      leading: Icon(codeKindIcon(r.code.kind), color: AppColors.primary),
                      title: Text(r.code.summary, maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${tr(codeKindLabel(r.code.kind))} \u00B7 ${formatDateTime(r.at)}'),
                      onTap: () => showCodeSheet(context, r.code),
                      trailing: IconButton(
                        tooltip: tr('Delete'),
                        icon: const Icon(AppIcons.delete, size: 20, color: AppColors.danger),
                        onPressed: () => cubit.delete(r.raw),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// endregion

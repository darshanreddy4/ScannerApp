import 'package:flutter/material.dart' hide Text;
import 'package:image_picker/image_picker.dart';

import '../../../app/di.dart';
import '../../../core/i18n/tr.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/text.dart';
import '../../qr/domain/scan_services.dart';
import '../../qr/presentation/qr_scan_page.dart' show CodeCameraBuilder, defaultCameraBuilder;
import '../../scanner/data/datasources/camera_access.dart';

Future<String?> _pickPicture() async => (await ImagePicker().pickImage(source: ImageSource.gallery))?.path;

/// Reads the code on a card, with the camera or from a picture, and hands it back. Nothing leaves the phone.
class CardScanPage extends StatefulWidget {
  const CardScanPage({super.key, this.cameraBuilder = defaultCameraBuilder, this.pickPicture = _pickPicture});
  final CodeCameraBuilder cameraBuilder;
  final Future<String?> Function() pickPicture;

  @override
  State<CardScanPage> createState() => _CardScanPageState();
}

class _CardScanPageState extends State<CardScanPage> {
  CameraAccessStatus? _access;
  bool _busy = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _ask();
  }

  Future<void> _ask() async {
    final s = await sl<CameraAccess>().request();
    if (mounted) setState(() => _access = s);
  }

  void _found(List<DetectedCode> codes) {
    if (_done) return;
    final first = codes.where((c) => c.raw.trim().isNotEmpty).firstOrNull;
    if (first == null) return;
    _done = true;
    Navigator.of(context).pop(first);
  }

  Future<void> _fromPicture() async {
    final path = await widget.pickPicture();
    if (path == null || !mounted) return;
    setState(() => _busy = true);
    final found = await sl<CodeImageReader>().read(path);
    if (!mounted) return;
    setState(() => _busy = false);
    if (found.where((c) => c.raw.trim().isNotEmpty).isEmpty) {
      showMessage(context, 'No QR code or barcode was found in that picture.');
    } else {
      _found(found);
    }
  }

  @override
  Widget build(BuildContext context) {
    final access = _access;
    final Widget body;
    if (access == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (access != CameraAccessStatus.granted) {
      final blocked = access == CameraAccessStatus.blocked;
      body = Center(
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
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                onPressed: () async => blocked ? await sl<CameraAccess>().openSettings() : await _ask(),
                child: Text(blocked ? 'Open Settings' : 'Allow camera'),
              ),
              TextButton(onPressed: _fromPicture, child: const Text('Read from a picture')),
            ],
          ),
        ),
      );
    } else {
      body = Stack(
        fit: StackFit.expand,
        children: [
          widget.cameraBuilder(context, _found),
          const IgnorePointer(child: Center(child: _Frame())),
          if (_busy)
            const ColoredBox(
              color: Colors.black45,
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan the card'),
        actions: [IconButton(tooltip: tr('Read from a picture'), icon: const Icon(AppIcons.images), onPressed: _fromPicture)],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: body),
            const Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: Text(
                'Hold the barcode or QR code of your card inside the frame. It is read on this phone and not uploaded.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame();

  @override
  Widget build(BuildContext context) {
    final w = (MediaQuery.sizeOf(context).shortestSide * 0.8).clamp(200.0, 420.0);
    return Container(
      width: w,
      height: w * 0.55,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white, width: 3),
      ),
    );
  }
}

import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../app/di.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/feedback.dart';
import '../../export/domain/repositories/export_repository.dart';
import '../domain/qr_payloads.dart';

enum _QrKind { text, wifi }

/// Creates QR codes from text, links or Wi-Fi details entirely on the device.
class QrGeneratorPage extends StatefulWidget {
  const QrGeneratorPage({super.key});

  @override
  State<QrGeneratorPage> createState() => _QrGeneratorPageState();
}

class _QrGeneratorPageState extends State<QrGeneratorPage> {
  _QrKind _kind = _QrKind.text;
  final _text = TextEditingController();
  final _ssid = TextEditingController();
  final _password = TextEditingController();
  WifiSecurity _security = WifiSecurity.wpa;
  bool _hidden = false;
  bool _showPassword = false;

  @override
  void dispose() {
    _text.dispose();
    _ssid.dispose();
    _password.dispose();
    super.dispose();
  }

  String? get _payload {
    switch (_kind) {
      case _QrKind.text:
        final t = _text.text.trim();
        return t.isEmpty ? null : t;
      case _QrKind.wifi:
        final s = _ssid.text.trim();
        return s.isEmpty ? null : QrPayloads.wifi(ssid: s, password: _password.text, security: _security, hidden: _hidden);
    }
  }

  Future<void> _share(String data) async {
    final painter = QrPainter(
      data: data,
      version: QrVersions.auto,
      errorCorrectionLevel: QrErrorCorrectLevel.M,
      gapless: false,
      eyeStyle: const QrEyeStyle(color: Colors.black),
      dataModuleStyle: const QrDataModuleStyle(color: Colors.black),
    );
    final bytes = await painter.toImageData(1024, format: ImageByteFormat.png);
    if (bytes == null) return;
    final dir = await getTemporaryDirectory();
    final file = await File(p.join(dir.path, 'qr_code.png')).writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    final result = await sl<ShareService>().shareFile(path: file.path, mimeType: 'image/png', subject: 'QR code');
    if (mounted && result.failureOrNull != null) showFailure(context, result.failureOrNull!);
  }

  @override
  Widget build(BuildContext context) {
    final payload = _payload;
    final tooLong = payload != null && payload.length > QrPayloads.maxChars;

    return Scaffold(
      appBar: AppBar(title: const Text('QR code generator')),
      body: ListView(
        padding: contentPadding(context),
        children: [
          SegmentedButton<_QrKind>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: _QrKind.text, icon: Icon(AppIcons.link), label: Text('Text / link')),
              ButtonSegment(value: _QrKind.wifi, icon: Icon(AppIcons.wifi), label: Text('Wi-Fi')),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() => _kind = s.first),
          ),
          const SizedBox(height: AppSpacing.md),
          if (_kind == _QrKind.text)
            TextField(
              controller: _text,
              minLines: 3,
              maxLines: 6,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Text or link',
                helperText: '${_text.text.length}/${QrPayloads.maxChars} characters',
                alignLabelWithHint: true,
              ),
            )
          else ...[
            TextField(
              controller: _ssid,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Network name (SSID)'),
            ),
            const SizedBox(height: AppSpacing.sm + 4),
            DropdownButtonFormField<WifiSecurity>(
              initialValue: _security,
              decoration: const InputDecoration(labelText: 'Security'),
              items: [for (final s in WifiSecurity.values) DropdownMenuItem(value: s, child: Text(s.label))],
              onChanged: (s) => setState(() => _security = s ?? _security),
            ),
            if (_security != WifiSecurity.open) ...[
              const SizedBox(height: AppSpacing.sm + 4),
              TextField(
                controller: _password,
                obscureText: !_showPassword,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Password',
                  suffixIcon: IconButton(
                    icon: Icon(_showPassword ? AppIcons.eyeOff : AppIcons.eye, size: 18),
                    tooltip: _showPassword ? 'Hide password' : 'Show password',
                    onPressed: () => setState(() => _showPassword = !_showPassword),
                  ),
                ),
              ),
            ],
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Hidden network'), value: _hidden, onChanged: (v) => setState(() => _hidden = v)),
          ],
          const SizedBox(height: AppSpacing.lg),
          if (payload == null)
            const Center(
              child: Text('Enter details to create a QR code', style: TextStyle(color: AppColors.inkMuted)),
            )
          else if (tooLong)
            const Center(
              child: Text('Too long for a QR code. Shorten it or use a link instead.', style: TextStyle(color: AppColors.danger)),
            )
          else ...[
            Center(
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppSpacing.radius),
                  border: Border.all(color: AppColors.border),
                ),
                child: QrImageView(data: payload, size: 240, backgroundColor: Colors.white, errorCorrectionLevel: QrErrorCorrectLevel.M),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(onPressed: () => _share(payload), icon: const Icon(AppIcons.share, size: 20), label: const Text('Share QR image')),
          ],
        ],
      ),
    );
  }
}

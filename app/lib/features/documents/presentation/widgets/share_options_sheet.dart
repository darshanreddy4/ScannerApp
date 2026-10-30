import 'package:flutter/material.dart' hide Text;

import '../../../../core/i18n/tr.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/widgets/text.dart';
import '../../../export/data/share_packager.dart';
import '../../../export/domain/entities/export_options.dart';

enum ShareSize {
  original('Original', 'Same quality as the document.', null),
  smaller('Compress', 'Sharp text, a smaller file.', ExportQuality.medium),
  smallest('Compress more', 'Smallest file, slightly softer.', ExportQuality.low);

  const ShareSize(this.label, this.description, this.quality);
  final String label;
  final String description;
  final ExportQuality? quality;

  /// The smaller of this choice and the quality chosen in Settings, so a choice here never makes the file larger than usual.
  ExportQuality effective(ExportQuality fromSettings) {
    final own = quality;
    if (own == null) return fromSettings;
    return own.index > fromSettings.index ? own : fromSettings;
  }
}

/// What the user picked for this one share. It changes the file that is sent, never the saved document.
class ShareOptions {
  const ShareOptions({this.size = ShareSize.original, this.password, this.zip = false});
  final ShareSize size;
  final String? password;
  final bool zip;
}

Future<ShareOptions?> showShareOptions(BuildContext context, {required String title}) => showModalBottomSheet<ShareOptions>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => _ShareOptionsSheet(title: title),
);

class _ShareOptionsSheet extends StatefulWidget {
  const _ShareOptionsSheet({required this.title});
  final String title;

  @override
  State<_ShareOptionsSheet> createState() => _ShareOptionsSheetState();
}

class _ShareOptionsSheetState extends State<_ShareOptionsSheet> {
  var _size = ShareSize.original;
  var _zip = false;
  var _protect = false;
  var _show = false;
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String? get _problem {
    if (!_protect) return null;
    if (_password.text.length < SharePackager.minPasswordLength) return trf('Use at least {n} characters.', {'n': SharePackager.minPasswordLength});
    if (_password.text != _confirm.text) return 'The two passwords are not the same.';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final problem = _problem;
    final muted = const TextStyle(color: AppColors.inkMuted, fontSize: 13, height: 1.4);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Share PDF', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
            const SizedBox(height: 16),
            const Text('Size', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            SegmentedButton<ShareSize>(
              key: const ValueKey('share-size'),
              showSelectedIcon: false,
              segments: [
                for (final s in ShareSize.values)
                  ButtonSegment(
                    value: s,
                    label: Text(s.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
              ],
              selected: {_size},
              onSelectionChanged: (v) => setState(() => _size = v.first),
            ),
            const SizedBox(height: 6),
            Text(_size.description, style: muted),
            const Divider(height: 28),
            SwitchListTile(
              key: const ValueKey('share-password'),
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(AppIcons.lock),
              title: const Text('Add a password'),
              subtitle: const Text('The receiver needs it to open the PDF.'),
              value: _protect,
              onChanged: (v) => setState(() => _protect = v),
            ),
            if (_protect) ...[
              const SizedBox(height: 4),
              TextField(
                key: const ValueKey('share-pw'),
                controller: _password,
                obscureText: !_show,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: tr('Password'),
                  suffixIcon: IconButton(
                    tooltip: tr(_show ? 'Hide password' : 'Show password'),
                    icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    onPressed: () => setState(() => _show = !_show),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('share-pw2'),
                controller: _confirm,
                obscureText: !_show,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: tr('Repeat the password'),
                  errorText: _confirm.text.isNotEmpty && _confirm.text != _password.text ? tr('The two passwords are not the same.') : null,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 6),
              Text('If the password is lost, nobody can recover the file, not even this app.', style: muted),
              const SizedBox(height: 6),
            ],
            SwitchListTile(
              key: const ValueKey('share-zip'),
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(AppIcons.pdfCompress),
              title: const Text('Put in a ZIP file'),
              subtitle: const Text('Sent as one .zip file.'),
              value: _zip,
              onChanged: (v) => setState(() => _zip = v),
            ),
            const Divider(height: 28),
            Text('Only the copy you share changes. The document in this app stays as it is.', style: muted),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('share-go'),
                    onPressed: problem != null
                        ? null
                        : () => Navigator.pop(context, ShareOptions(size: _size, password: _protect ? _password.text : null, zip: _zip)),
                    child: const Text('Share'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

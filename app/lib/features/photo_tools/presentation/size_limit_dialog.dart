import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/text.dart';
import '../../../core/i18n/tr.dart';

/// Asks for a size limit in kB or MB and pops the value in bytes.
class SizeLimitDialog extends StatefulWidget {
  const SizeLimitDialog();

  @override
  State<SizeLimitDialog> createState() => SizeLimitDialogState();
}

class SizeLimitDialogState extends State<SizeLimitDialog> {
  final _controller = TextEditingController();
  bool _mb = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final value = double.tryParse(_controller.text.trim().replaceAll(',', '.'));
    if (value == null || value <= 0) {
      setState(() => _error = 'Enter a number above 0.');
      return;
    }
    final bytes = (value * (_mb ? 1024 * 1024 : 1024)).round();
    if (bytes < 2 * 1024) {
      setState(() => _error = 'Use at least 2 kB.');
      return;
    }
    Navigator.pop(context, bytes);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Custom size limit'),
    content: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            decoration: InputDecoration(hintText: tr('For example 45'), errorText: _error),
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _save(),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        DropdownButton<bool>(
          value: _mb,
          items: const [
            DropdownMenuItem(value: false, child: Text('kB')),
            DropdownMenuItem(value: true, child: Text('MB')),
          ],
          onChanged: (v) => setState(() => _mb = v ?? false),
        ),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      TextButton(onPressed: _save, child: const Text('Use')),
    ],
  );
}

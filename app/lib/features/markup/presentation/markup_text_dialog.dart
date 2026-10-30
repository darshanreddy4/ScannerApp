import 'package:flutter/material.dart' hide Text;
import '../../../core/widgets/text.dart';
import '../../../core/i18n/tr.dart';

/// Asks for the words to put on the page. Returns null when cancelled; [initial] is filled in when editing.
Future<String?> showMarkupTextDialog(BuildContext context, {String initial = ''}) => showDialog<String>(
  context: context,
  builder: (_) => _TextDialog(initial: initial),
);

class _TextDialog extends StatefulWidget {
  const _TextDialog({required this.initial});
  final String initial;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final TextEditingController _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.initial.isEmpty ? 'Add text' : 'Edit text'),
    content: TextField(
      key: const ValueKey('markup-text-field'),
      controller: _controller,
      autofocus: true,
      minLines: 1,
      maxLines: 5,
      keyboardType: TextInputType.multiline,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(hintText: tr('Type here')),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      TextButton(
        key: const ValueKey('markup-text-save'),
        onPressed: () => Navigator.pop(context, _controller.text),
        child: Text(widget.initial.isEmpty ? 'Add' : 'Save'),
      ),
    ],
  );
}

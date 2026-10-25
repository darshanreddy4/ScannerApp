import 'package:flutter/material.dart';

/// Asks for a line of text. Returns the trimmed text, or null if cancelled (or left empty unless [allowEmpty]).
/// The text controller lives inside the dialog, so it is disposed only after the dialog has fully closed.
Future<String?> promptText(BuildContext context, {required String title, String initial = '', String hint = '', bool allowEmpty = false}) async {
  final result = await showDialog<String>(
    context: context,
    builder: (_) => _TextPromptDialog(title: title, initial: initial, hint: hint),
  );
  final trimmed = result?.trim();
  if (trimmed == null) return null;
  return (trimmed.isEmpty && !allowEmpty) ? null : trimmed;
}

class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({required this.title, required this.initial, required this.hint});
  final String title;
  final String initial;
  final String hint;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  late final TextEditingController _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _controller,
      autofocus: true,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(hintText: widget.hint),
      onSubmitted: (v) => Navigator.pop(context, v),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      TextButton(onPressed: () => Navigator.pop(context, _controller.text), child: const Text('Save')),
    ],
  );
}

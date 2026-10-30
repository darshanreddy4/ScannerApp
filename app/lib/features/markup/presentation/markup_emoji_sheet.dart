import 'package:flutter/material.dart' hide Text;

import '../../../core/theme/app_icons.dart';
import 'markup_color_sheet.dart';
import '../../../core/widgets/text.dart';
import '../../../core/i18n/tr.dart';

const markupEmojiGroups = <(String, List<String>)>[
  ('Marks', ['✅', '❌', '✔️', '✖️', '⭕', '❗', '❓', '⚠️', '⛔', '🚫', '💯', '🆗']),
  ('Faces', ['😀', '😂', '😍', '😎', '🤔', '😮', '😢', '😡', '🥳', '😴', '🤝', '🙏']),
  ('Hands', ['👍', '👎', '👏', '👌', '✌️', '💪', '👆', '👇', '👉', '👈', '✍️', '🙌']),
  ('Symbols', ['⭐', '🌟', '❤️', '💙', '🔥', '🎉', '💡', '📌', '📎', '🔒', '🔔', '🏆']),
  ('Arrows', ['➡️', '⬅️', '⬆️', '⬇️', '↗️', '↘️', '↩️', '🔁', '▶️', '⏩', '🔼', '🔽']),
  ('Shapes', ['🔴', '🟠', '🟡', '🟢', '🔵', '🟣', '⚫', '⚪', '🟥', '🟩', '🟦', '🔶']),
  ('Office', ['📞', '📧', '📅', '📍', '🏠', '💰', '📝', '📄', '🖊️', '🔍', '📷', '🕒']),
];

/// Lets the person pick an emoji, or type any emoji or short text of their own.
Future<String?> showMarkupEmojiSheet(BuildContext context) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  backgroundColor: MarkupColors.raised,
  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
  builder: (_) => const _EmojiSheet(),
);

class _EmojiSheet extends StatefulWidget {
  const _EmojiSheet();

  @override
  State<_EmojiSheet> createState() => _EmojiSheetState();
}

class _EmojiSheetState extends State<_EmojiSheet> {
  final _custom = TextEditingController();

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  void _useCustom() {
    final text = _custom.text.trim();
    if (text.isNotEmpty) Navigator.pop(context, text.characters.take(4).toString());
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Choose an emoji',
                  style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('custom-emoji'),
                        controller: _custom,
                        style: const TextStyle(color: Colors.white, fontSize: 18),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: tr('Type or paste your own'),
                          hintStyle: const TextStyle(color: Colors.white54, fontSize: 14),
                          filled: true,
                          fillColor: Colors.white12,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        ),
                        onSubmitted: (_) => _useCustom(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(tooltip: tr('Use'), onPressed: _useCustom, icon: const Icon(AppIcons.check, size: 20)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 16),
                  children: [
                    for (final group in markupEmojiGroups) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 12, bottom: 6),
                        child: Text(
                          group.$1,
                          style: const TextStyle(color: Colors.white60, fontSize: 12.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          for (final e in group.$2)
                            InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => Navigator.pop(context, e),
                              child: SizedBox(
                                width: 48,
                                height: 48,
                                child: Center(child: Text(e, style: const TextStyle(fontSize: 28))),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

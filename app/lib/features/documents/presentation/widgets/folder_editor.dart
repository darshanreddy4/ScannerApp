import 'package:flutter/material.dart' hide Text;

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../domain/entities/scanned_document.dart';
import 'folder_style.dart';
import '../../../../core/widgets/text.dart';
import '../../../../core/i18n/tr.dart';

typedef FolderEdit = ({String name, FolderStyle style});

/// Asks for a folder's name, icon and colour. Returns null when cancelled.
Future<FolderEdit?> showFolderEditor(BuildContext context, {required String title, Folder? folder}) => showDialog<FolderEdit>(
  context: context,
  builder: (_) => _FolderEditor(title: title, folder: folder),
);

class _FolderEditor extends StatefulWidget {
  const _FolderEditor({required this.title, this.folder});
  final String title;
  final Folder? folder;

  @override
  State<_FolderEditor> createState() => _FolderEditorState();
}

class _FolderEditorState extends State<_FolderEditor> {
  late final TextEditingController _name = TextEditingController(text: widget.folder?.name ?? '');
  late String? _icon = widget.folder?.icon;
  late int? _color = widget.folder?.color;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(context, (name: name, style: FolderStyle(icon: _icon, color: _color)));
  }

  @override
  Widget build(BuildContext context) {
    final accent = folderAccent(_color);
    return AlertDialog(
      title: Text(widget.title),
      scrollable: true,
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ListenableBuilder(
                  listenable: _name,
                  builder: (_, _) => FolderBadge(name: _name.text, icon: _icon, color: _color, size: 52),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: TextField(
                    key: const ValueKey('folder-name'),
                    controller: _name,
                    autofocus: widget.folder == null,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(hintText: tr('Folder name')),
                    onSubmitted: (_) => _save(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            const Text('Icon', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                _Choice(
                  key: const ValueKey('icon-text'),
                  selected: _icon == FolderStyle.textOnly,
                  accent: accent,
                  onTap: () => setState(() => _icon = FolderStyle.textOnly),
                  child: Text(
                    'Aa',
                    style: TextStyle(fontWeight: FontWeight.w800, color: _icon == FolderStyle.textOnly ? accent : AppColors.inkMuted),
                  ),
                ),
                for (final e in folderIcons.entries)
                  _Choice(
                    key: ValueKey('icon-${e.key}'),
                    selected: (_icon ?? 'folder') == e.key,
                    accent: accent,
                    onTap: () => setState(() => _icon = e.key == 'folder' ? null : e.key),
                    child: Icon(e.value, size: 20, color: (_icon ?? 'folder') == e.key ? accent : AppColors.inkMuted),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            const Text('Colour', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final c in folderColors)
                  GestureDetector(
                    key: ValueKey('color-${c.toRadixString(16)}'),
                    onTap: () => setState(() => _color = c == folderColors.first ? null : c),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: Border.all(color: (_color ?? folderColors.first) == c ? AppColors.ink : Colors.transparent, width: 2.5),
                      ),
                      child: (_color ?? folderColors.first) == c ? const Icon(AppIcons.check, size: 16, color: Colors.white) : null,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({super.key, required this.selected, required this.accent, required this.onTap, required this.child});
  final bool selected;
  final Color accent;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(12),
    onTap: onTap,
    child: Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? accent.withValues(alpha: 0.12) : AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: selected ? accent : AppColors.border, width: selected ? 2 : 1),
      ),
      child: child,
    ),
  );
}

import 'dart:io';

import 'package:flutter/material.dart' hide Text;
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/i18n/tr.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/widgets/feedback.dart';
import '../../../../core/widgets/text.dart';
import '../../../documents/presentation/widgets/document_widgets.dart';
import '../../../text_edit/docx/doc_template_store.dart';
import '../domain/slide_presets.dart';
import '../domain/slide_themes.dart';

/// Folder (inside the temporary one) for presentations started from one the person saved.
const newDecksFolder = 'new_decks';

class _DeckPick {
  const _DeckPick({this.preset, this.mine, this.blank = false});
  final DeckPreset? preset;
  final File? mine;
  final bool blank;
}

/// Asks what to start from and opens the new presentation in the editor.
Future<void> startNewPresentation(
  BuildContext context, {
  Future<Directory> Function() tempDir = getTemporaryDirectory,
  DocTemplateStore store = const DocTemplateStore.decks(),
}) async {
  final pick = await showModalBottomSheet<_DeckPick>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _NewPresentationSheet(store: store),
  );
  if (pick == null || !context.mounted) return;
  if (pick.blank) {
    context.push('/slides', extra: null);
  } else if (pick.preset != null) {
    context.push('/slides', extra: pick.preset);
  } else if (pick.mine != null) {
    try {
      final dir = await Directory(p.join((await tempDir()).path, newDecksFolder)).create(recursive: true);
      final out = p.join(dir.path, p.basename(pick.mine!.path));
      await pick.mine!.copy(out);
      if (context.mounted) context.push('/slides', extra: out);
    } catch (e) {
      if (context.mounted) showFailure(context, ExportFailure('The presentation could not be created.', cause: e));
    }
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch(this.theme);
  final DeckTheme theme;

  @override
  Widget build(BuildContext context) {
    Color c(String hex) => Color(0xFF000000 | int.parse(hex, radix: 16));
    return Container(
      width: 44,
      height: 32,
      decoration: BoxDecoration(color: c(theme.background), borderRadius: BorderRadius.circular(6), border: Border.all(color: AppColors.border)),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(top: 0, left: 0, right: 0, height: 4, child: ColoredBox(color: c(theme.accents.first))),
          Positioned(left: 6, top: 11, width: 22, height: 4, child: ColoredBox(color: c(theme.title))),
          Positioned(left: 6, top: 19, width: 30, height: 3, child: ColoredBox(color: c(theme.text).withValues(alpha: 0.5))),
        ],
      ),
    );
  }
}

class _NewPresentationSheet extends StatefulWidget {
  const _NewPresentationSheet({required this.store});
  final DocTemplateStore store;

  @override
  State<_NewPresentationSheet> createState() => _NewPresentationSheetState();
}

class _NewPresentationSheetState extends State<_NewPresentationSheet> {
  late Future<List<File>> _mine = widget.store.list();

  Future<void> _remove(File file) async {
    final name = p.basenameWithoutExtension(file.path);
    final ok = await confirmDestructive(context, title: 'Delete template?', message: '"$name" is removed from My templates. Presentations made from it are kept.');
    if (!ok || !mounted) return;
    await widget.store.delete(file);
    if (mounted) setState(() => _mine = widget.store.list());
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 2),
    child: Text(
      text,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.inkMuted, letterSpacing: 0.4),
    ),
  );

  Widget _tile(DeckPreset d) => ListTile(
    key: ValueKey('deck-${d.id}'),
    leading: _Swatch(deckThemeById(d.themeId)),
    title: Text(d.title),
    subtitle: Text('${d.hint} (${d.slides.length} slides)'),
    onTap: () => Navigator.pop(context, _DeckPick(preset: d)),
  );

  @override
  Widget build(BuildContext context) {
    final study = [for (final d in deckPresets) if (d.group == 'study') d];
    final work = [for (final d in deckPresets) if (d.group == 'work') d];
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsetsDirectional.fromSTEB(AppSpacing.md, 0, AppSpacing.md, 4),
                child: Text('New presentation', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              ),
              ListTile(
                key: const ValueKey('deck-blank'),
                leading: const Icon(AppIcons.newDocument, color: AppColors.primary),
                title: const Text('Blank presentation'),
                subtitle: const Text('One empty slide'),
                onTap: () => Navigator.pop(context, const _DeckPick(blank: true)),
              ),
              _label(tr('SCHOOL AND COLLEGE')),
              for (final d in study) _tile(d),
              _label(tr('WORK AND OFFICE')),
              for (final d in work) _tile(d),
              FutureBuilder<List<File>>(
                future: _mine,
                builder: (context, snapshot) {
                  final files = snapshot.data ?? const <File>[];
                  if (files.isEmpty) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _label(tr('MY TEMPLATES')),
                      for (final f in files)
                        ListTile(
                          key: ValueKey('mine-${p.basenameWithoutExtension(f.path)}'),
                          leading: const Icon(AppIcons.slides, color: AppColors.primary),
                          title: Text(p.basenameWithoutExtension(f.path), maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: IconButton(
                            tooltip: tr('Delete'),
                            icon: const Icon(AppIcons.delete, size: 20),
                            onPressed: () => _remove(f),
                          ),
                          onTap: () => Navigator.pop(context, _DeckPick(mine: f)),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ),
        ),
      ),
    );
  }
}

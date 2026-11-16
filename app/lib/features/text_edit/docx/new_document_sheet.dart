import 'dart:io';

import 'package:flutter/material.dart' hide Text;
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/error/failures.dart';
import '../../../core/i18n/tr.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/utils/region.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/text.dart';
import '../../documents/presentation/widgets/document_widgets.dart';
import 'doc_template_store.dart';
import 'doc_templates.dart';
import 'docx_builder.dart';
import 'docx_edit_cubit.dart';

class _Pick {
  const _Pick({this.template, this.mine});
  final DocTemplate? template;
  final File? mine;
}

/// Asks what to start from, writes the new Word file and opens it in the editor.
Future<void> startNewDocument(
  BuildContext context, {
  Future<Directory> Function() tempDir = getTemporaryDirectory,
  DocTemplateStore store = const DocTemplateStore(),
}) async {
  final pick = await showModalBottomSheet<_Pick>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _NewDocumentSheet(store: store),
  );
  if (pick == null || !context.mounted) return;
  try {
    final dir = await Directory(p.join((await tempDir()).path, newDocsFolder)).create(recursive: true);
    final template = pick.template;
    final name = template == null ? p.basenameWithoutExtension(pick.mine!.path) : (template.id == 'blank' ? 'Document' : template.title);
    final out = p.join(dir.path, '${DocTemplateStore.cleanName(name)}.docx');
    if (template != null) {
      await File(out).writeAsBytes(buildDocx(template.build(), letter: Region.toolRegion == ToolRegion.usa), flush: true);
    } else {
      await pick.mine!.copy(out);
    }
    if (context.mounted) context.push('/docx-edit', extra: out);
  } catch (e) {
    if (context.mounted) showFailure(context, ExportFailure('The document could not be created.', cause: e));
  }
}

IconData _iconFor(DocTemplate t) => t.id == 'blank' ? AppIcons.newDocument : (t.group == 'study' ? AppIcons.study : AppIcons.work);

class _NewDocumentSheet extends StatefulWidget {
  const _NewDocumentSheet({required this.store});
  final DocTemplateStore store;

  @override
  State<_NewDocumentSheet> createState() => _NewDocumentSheetState();
}

class _NewDocumentSheetState extends State<_NewDocumentSheet> {
  late Future<List<File>> _mine = widget.store.list();

  Future<void> _remove(File file) async {
    final name = p.basenameWithoutExtension(file.path);
    final ok = await confirmDestructive(context, title: 'Delete template?', message: '"$name" is removed from My templates. Documents made from it are kept.');
    if (!ok || !mounted) return;
    await widget.store.delete(file);
    if (mounted) setState(() => _mine = widget.store.list());
  }

  Widget _tile(DocTemplate t) => ListTile(
    key: ValueKey('template-${t.id}'),
    leading: Icon(_iconFor(t), color: AppColors.primary),
    title: Text(t.title),
    subtitle: Text(t.hint),
    onTap: () => Navigator.pop(context, _Pick(template: t)),
  );

  Widget _label(String text) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 2),
    child: Text(
      text,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.inkMuted, letterSpacing: 0.4),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final study = [for (final t in docTemplates) if (t.group == 'study' && t.id != 'blank') t];
    final work = [for (final t in docTemplates) if (t.group == 'work') t];
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
                child: Text('New Word document', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              ),
              _tile(docTemplates.first),
              _label(tr('SCHOOL AND COLLEGE')),
              for (final t in study) _tile(t),
              _label(tr('WORK AND OFFICE')),
              for (final t in work) _tile(t),
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
                          leading: const Icon(AppIcons.docx, color: AppColors.primary),
                          title: Text(p.basenameWithoutExtension(f.path), maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: IconButton(
                            tooltip: tr('Delete'),
                            icon: const Icon(AppIcons.delete, size: 20),
                            onPressed: () => _remove(f),
                          ),
                          onTap: () => Navigator.pop(context, _Pick(mine: f)),
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

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
import '../data/sheet_templates.dart';
import 'sheet_page.dart';

/// Folder (inside the temporary one) for spreadsheets started from one the person saved.
const newSheetsFolder = 'new_sheets';

class _SheetPick {
  const _SheetPick({this.template, this.mine});
  final SheetTemplate? template;
  final File? mine;
}

/// Asks what to start from and opens the new spreadsheet in the editor.
Future<void> startNewSpreadsheet(
  BuildContext context, {
  Future<Directory> Function() tempDir = getTemporaryDirectory,
  DocTemplateStore store = const DocTemplateStore.sheets(),
}) async {
  final pick = await showModalBottomSheet<_SheetPick>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _NewSpreadsheetSheet(store: store),
  );
  if (pick == null || !context.mounted) return;
  if (pick.template != null) {
    context.push('/sheet', extra: SheetArgs(template: pick.template));
  } else if (pick.mine != null) {
    try {
      final dir = await Directory(p.join((await tempDir()).path, newSheetsFolder)).create(recursive: true);
      final out = p.join(dir.path, p.basename(pick.mine!.path));
      await pick.mine!.copy(out);
      if (context.mounted) context.push('/sheet', extra: SheetArgs(path: out));
    } catch (e) {
      if (context.mounted) showFailure(context, ExportFailure('The spreadsheet could not be created.', cause: e));
    }
  }
}

IconData _iconFor(SheetTemplate t) => t.id == 'blank'
    ? AppIcons.newDocument
    : switch (t.group) {
        'study' => AppIcons.study,
        'money' => AppIcons.receipt,
        _ => AppIcons.work,
      };

class _NewSpreadsheetSheet extends StatefulWidget {
  const _NewSpreadsheetSheet({required this.store});
  final DocTemplateStore store;

  @override
  State<_NewSpreadsheetSheet> createState() => _NewSpreadsheetSheetState();
}

class _NewSpreadsheetSheetState extends State<_NewSpreadsheetSheet> {
  late Future<List<File>> _mine = widget.store.list();

  Future<void> _remove(File file) async {
    final name = p.basenameWithoutExtension(file.path);
    final ok = await confirmDestructive(context, title: 'Delete template?', message: '"$name" is removed from My templates. Spreadsheets made from it are kept.');
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

  Widget _tile(SheetTemplate t) => ListTile(
    key: ValueKey('sheet-${t.id}'),
    leading: Icon(_iconFor(t), color: AppColors.primary),
    title: Text(t.title),
    subtitle: Text(t.hint),
    onTap: () => Navigator.pop(context, _SheetPick(template: t)),
  );

  @override
  Widget build(BuildContext context) {
    List<SheetTemplate> group(String g) => [for (final t in sheetTemplates) if (t.group == g && t.id != 'blank') t];
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
                child: Text('New spreadsheet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              ),
              _tile(sheetTemplates.first),
              _label(tr('SCHOOL AND COLLEGE')),
              for (final t in group('study')) _tile(t),
              _label(tr('MONEY')),
              for (final t in group('money')) _tile(t),
              _label(tr('WORK AND OFFICE')),
              for (final t in group('work')) _tile(t),
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
                          leading: const Icon(AppIcons.sheet, color: AppColors.primary),
                          title: Text(p.basenameWithoutExtension(f.path), maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: IconButton(
                            tooltip: tr('Delete'),
                            icon: const Icon(AppIcons.delete, size: 20),
                            onPressed: () => _remove(f),
                          ),
                          onTap: () => Navigator.pop(context, _SheetPick(mine: f)),
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

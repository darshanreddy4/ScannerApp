import 'package:flutter/material.dart' hide Text;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../app/di.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/responsive.dart';
import '../../export/domain/repositories/export_repository.dart';
import '../../ocr/domain/ocr_engine.dart';
import '../../office/sheets/presentation/sheet_page.dart';
import '../../pdf_tools/presentation/pdf_form_page.dart' show askFormText;
import '../../settings/presentation/settings_cubit.dart';
import '../domain/table_reader.dart';
import 'table_cubit.dart';
import '../../../core/widgets/text.dart';

const _xlsxMime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

/// What the table screen reads: the pictures of the pages (one table across them) and the name to give the files.
class TableArgs {
  const TableArgs({required this.title, required this.imagePaths});
  final String title;
  final List<String> imagePaths;
}

/// Turns the photo of a printed table into a spreadsheet: reads it on the phone, shows the cells to correct, and shares Excel or CSV.
class TablePage extends StatelessWidget {
  const TablePage({super.key, required this.args, this.engine});
  final TableArgs args;
  final OcrEngine? engine;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) => TableCubit(
      engine: engine ?? sl<OcrEngine>(),
      images: args.imagePaths,
      script: context.read<SettingsCubit>().state.ocrScript,
      outputDir: getTemporaryDirectory,
      title: args.title,
    )..start(),
    child: _TableView(title: args.title),
  );
}

class _TableView extends StatelessWidget {
  const _TableView({required this.title});
  final String title;

  Future<void> _open(BuildContext context) async {
    final path = await context.read<TableCubit>().writeXlsx();
    if (path != null && context.mounted) await context.push('/sheet', extra: SheetArgs(path: path));
  }

  Future<void> _share(BuildContext context, {required bool excel}) async {
    final cubit = context.read<TableCubit>();
    final path = excel ? await cubit.writeXlsx() : await cubit.writeCsv();
    if (path == null || !context.mounted) return;
    final failure = (await sl<ShareService>().shareFile(path: path, mimeType: excel ? _xlsxMime : 'text/csv', subject: title)).failureOrNull;
    if (failure != null && context.mounted) showFailure(context, failure);
  }

  Future<void> _save(BuildContext context) async {
    final path = await context.read<TableCubit>().writeXlsx();
    if (path == null || !context.mounted) return;
    final result = await sl<SaveService>().saveToFiles(
      sourcePath: path,
      fileName: p.basename(path).replaceAll(RegExp(r'_\d{10,}(?=\.xlsx$)'), ''),
      mimeType: _xlsxMime,
    );
    if (!context.mounted) return;
    final failure = result.failureOrNull;
    if (failure != null) {
      showFailure(context, failure);
    } else if (result.valueOrNull == true) {
      showMessage(context, 'Saved');
    }
  }

  Future<void> _setSpacing(BuildContext context, TableSpacing spacing) async {
    final cubit = context.read<TableCubit>();
    if (cubit.state.edited) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Change the columns?'),
          content: const Text('The table is read again, so the corrections you made by hand are lost.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
            TextButton(key: const ValueKey('table-spacing-confirm'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Change')),
          ],
        ),
      );
      if (ok != true) return;
    }
    cubit.setSpacing(spacing);
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<TableCubit, TableState>(
      listenWhen: (a, b) => b.failure != null && a.failure != b.failure && b.status == TableStatus.ready,
      listener: (context, s) {
        showFailure(context, s.failure!);
        context.read<TableCubit>().clearFailure();
      },
      builder: (context, state) {
        final cubit = context.read<TableCubit>();
        return Scaffold(
          appBar: AppBar(title: const Text('Table to Excel')),
          body: SafeArea(
            child: switch (state.status) {
              TableStatus.reading => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      state.total > 1 ? 'Reading page ${(state.done + 1).clamp(1, state.total)} of ${state.total}' : 'Reading the table',
                      key: const ValueKey('table-progress'),
                    ),
                  ],
                ),
              ),
              TableStatus.failed => ListView(
                padding: contentPadding(context, base: AppSpacing.md, maxWidth: 560),
                children: [
                  Text(
                    state.failure?.message ?? 'The table could not be read.',
                    key: const ValueKey('table-failure'),
                    style: const TextStyle(color: AppColors.danger, height: 1.4),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  FilledButton(key: const ValueKey('table-retry'), onPressed: cubit.start, child: const Text('Try again')),
                ],
              ),
              TableStatus.ready => Column(
                children: [
                  _Spacing(state: state, onPick: (s) => _setSpacing(context, s)),
                  if (!state.hasTable)
                    Expanded(
                      child: ListView(
                        padding: contentPadding(context, base: AppSpacing.md, maxWidth: 560),
                        children: const [
                          Text(
                            'No table was found.',
                            key: ValueKey('table-empty'),
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          SizedBox(height: AppSpacing.sm),
                          Text(
                            'Hold the phone straight above the table with good light so every line is sharp, fit only the table in the frame, and try again. Printed text reads best.',
                            style: TextStyle(height: 1.4),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.xs),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          '${state.rows.length} ${state.rows.length == 1 ? 'row' : 'rows'}, ${state.columnCount} ${state.columnCount == 1 ? 'column' : 'columns'}. Tap a cell to correct it; press and hold for more.',
                          key: const ValueKey('table-summary'),
                          style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
                        ),
                      ),
                    ),
                    const Expanded(child: _Grid()),
                    _Actions(
                      onOpen: () => _open(context),
                      onExcel: () => _share(context, excel: true),
                      onCsv: () => _share(context, excel: false),
                      onSave: () => _save(context),
                    ),
                  ],
                ],
              ),
            },
          ),
        );
      },
    );
  }
}

class _Spacing extends StatelessWidget {
  const _Spacing({required this.state, required this.onPick});
  final TableState state;
  final ValueChanged<TableSpacing> onPick;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xs),
    child: Wrap(
      spacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text('Columns apart:', style: TextStyle(fontSize: 13)),
        for (final s in TableSpacing.values)
          ChoiceChip(key: ValueKey('table-spacing-${s.name}'), label: Text(s.label), selected: state.spacing == s, onSelected: (_) => onPick(s)),
      ],
    ),
  );
}

class _Grid extends StatelessWidget {
  const _Grid();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TableCubit>().state;
    final cubit = context.read<TableCubit>();
    final widths = <int, TableColumnWidth>{
      for (var c = 0; c < state.columnCount; c++)
        c: FixedColumnWidth((state.rows.map((r) => r[c].length).fold<int>(0, (a, b) => a > b ? a : b) * 8.0 + 28).clamp(72.0, 260.0)),
    };
    return Scrollbar(
      child: SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Table(
            key: const ValueKey('table-grid'),
            columnWidths: widths,
            border: TableBorder.all(color: AppColors.inkMuted.withValues(alpha: 0.35)),
            children: [
              TableRow(
                decoration: BoxDecoration(color: AppColors.primarySoft),
                children: [
                  for (var c = 0; c < state.columnCount; c++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        columnLabel(c),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.inkMuted),
                      ),
                    ),
                ],
              ),
              for (var r = 0; r < state.rows.length; r++)
                TableRow(
                  children: [
                    for (var c = 0; c < state.columnCount; c++)
                      _Cell(
                        key: ValueKey('table-cell-$r-$c'),
                        text: state.rows[r][c],
                        onTap: () async {
                          final text = await askFormText(context, title: 'Row ${r + 1}, column ${columnLabel(c)}', initial: state.rows[r][c], multiline: false);
                          if (text != null) cubit.editCell(r, c, text);
                        },
                        onMore: () => _more(context, r, c),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _more(BuildContext context, int row, int column) async {
    final cubit = context.read<TableCubit>();
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const ValueKey('table-delete-row'),
              leading: const Icon(AppIcons.delete),
              title: Text('Delete row ${row + 1}'),
              onTap: () => Navigator.pop(ctx, 'row'),
            ),
            ListTile(
              key: const ValueKey('table-delete-column'),
              leading: const Icon(AppIcons.delete),
              title: Text('Delete column ${columnLabel(column)}'),
              onTap: () => Navigator.pop(ctx, 'column'),
            ),
          ],
        ),
      ),
    );
    if (choice == 'row') cubit.deleteRow(row);
    if (choice == 'column') cubit.deleteColumn(column);
  }
}

class _Cell extends StatelessWidget {
  const _Cell({super.key, required this.text, required this.onTap, required this.onMore});
  final String text;
  final VoidCallback onTap;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    onLongPress: onMore,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
      child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
    ),
  );
}

class _Actions extends StatelessWidget {
  const _Actions({required this.onOpen, required this.onExcel, required this.onCsv, required this.onSave});
  final VoidCallback onOpen;
  final VoidCallback onExcel;
  final VoidCallback onCsv;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) => Material(
    elevation: 6,
    color: Theme.of(context).colorScheme.surface,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.3),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            FilledButton.icon(
              key: const ValueKey('table-share-xlsx'),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: onExcel,
              icon: const Icon(AppIcons.sheet, size: 18),
              label: const Text('Share Excel'),
            ),
            OutlinedButton.icon(
              key: const ValueKey('table-open'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: onOpen,
              icon: const Icon(AppIcons.edit, size: 18),
              label: const Text('Open to edit'),
            ),
            OutlinedButton.icon(
              key: const ValueKey('table-share-csv'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: onCsv,
              icon: const Icon(AppIcons.share, size: 18),
              label: const Text('Share CSV'),
            ),
            OutlinedButton.icon(
              key: const ValueKey('table-save'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: onSave,
              icon: const Icon(AppIcons.storage, size: 18),
              label: const Text('Save to Files'),
            ),
          ],
        ),
      ),
    ),
  );
}

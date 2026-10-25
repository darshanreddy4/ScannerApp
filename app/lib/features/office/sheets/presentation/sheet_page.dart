import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../app/di.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/widgets/feedback.dart';
import '../../../export/domain/repositories/export_repository.dart';
import '../domain/sheet_model.dart';
import 'sheet_cubit.dart';
import 'sheet_dialogs.dart';
import 'sheet_grid.dart';

/// Which file the spreadsheet screen opens; a null [path] starts an empty workbook.
class SheetArgs {
  const SheetArgs({this.path});
  final String? path;
}

class SheetPage extends StatelessWidget {
  const SheetPage({super.key, required this.args});

  final SheetArgs args;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) {
      final cubit = SheetCubit(workDir: getTemporaryDirectory);
      if (args.path == null) {
        cubit.startBlank();
      } else {
        cubit.open(args.path!);
      }
      return cubit;
    },
    child: const _SheetView(),
  );
}

class _SheetView extends StatefulWidget {
  const _SheetView();

  @override
  State<_SheetView> createState() => _SheetViewState();
}

class _SheetViewState extends State<_SheetView> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _findController = TextEditingController();
  final _findFocus = FocusNode();
  var _original = '';
  var _finding = false;

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    _findController.dispose();
    _findFocus.dispose();
    super.dispose();
  }

  SheetCubit get cubit => context.read<SheetCubit>();

  bool get _pending => _input.text != _original;

  void _syncInput() {
    final c = cubit;
    if (c.state.loading || !_ready) return;
    final text = c.inputTextOf(c.state.row, c.state.col);
    _original = text;
    _input.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  bool get _ready => cubit.hasWorkbook;

  static bool _wantsReference(String text) => text.startsWith('=') && text.isNotEmpty && '=+-*/^&(,:<>;'.contains(text[text.length - 1]);

  void _tapCell(int r, int c) {
    final s = cubit.state;
    if (_focus.hasFocus && _wantsReference(_input.text)) {
      final text = '${_input.text}${CellRef.a1(r, c)}';
      _input.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      return;
    }
    if (_pending) cubit.commitInput(_input.text, moveDown: false);
    if (r == s.row && c == s.col && s.kind == SelectionKind.cells && !s.rangeMode && s.anchorRow == null) {
      _focus.requestFocus();
      return;
    }
    _focus.unfocus();
    cubit.selectCell(r, c);
  }

  void _commit() {
    cubit.commitInput(_input.text);
    _focus.unfocus();
  }

  Future<void> _export(SaveChoice choice) async {
    if (_pending) cubit.commitInput(_input.text, moveDown: false);
    final path = await cubit.export(choice.format);
    if (path == null || !mounted) return;
    final name = cubit.exportName(choice.format);
    if (choice.action == SaveAction.share) {
      final failure = (await sl<ShareService>().shareFiles(paths: [path], mimeType: choice.format.mimeType)).failureOrNull;
      if (!mounted) return;
      if (failure != null) {
        showFailure(context, failure);
        return;
      }
      if (choice.format == SheetExportFormat.xlsx) cubit.markSaved();
    } else {
      final result = await sl<SaveService>().saveToFiles(sourcePath: path, fileName: name, mimeType: choice.format.mimeType);
      if (!mounted) return;
      final failure = result.failureOrNull;
      if (failure != null) {
        showFailure(context, failure);
      } else if (result.valueOrNull == true) {
        showMessage(context, 'Saved');
        if (choice.format == SheetExportFormat.xlsx) cubit.markSaved();
      }
    }
  }

  Future<void> _saveSheet() async {
    final choice = await askSave(context);
    if (choice != null && mounted) await _export(choice);
  }

  Future<void> _leave() async {
    final state = cubit.state;
    if (!state.modified) {
      context.pop();
      return;
    }
    final choice = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Leave without saving?'),
        content: const Text('Your changes to this spreadsheet have not been saved or shared. If you leave now they are lost.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, 'keep'), child: const Text('Keep editing')),
          TextButton(
            onPressed: () => Navigator.pop(context, 'leave'),
            child: const Text('Leave', style: TextStyle(color: AppColors.danger)),
          ),
          FilledButton(onPressed: () => Navigator.pop(context, 'save'), child: const Text('Save')),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'leave') {
      context.pop();
    } else if (choice == 'save') {
      await _saveSheet();
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<SheetCubit, SheetState>(
      listenWhen: (a, b) => a.row != b.row || a.col != b.col || a.sheetIndex != b.sheetIndex || a.version != b.version || a.loading != b.loading,
      listener: (context, state) => _syncInput(),
      builder: (context, state) {
        return BlocListener<SheetCubit, SheetState>(
          listenWhen: (a, b) => (a.failure != b.failure && b.failure != null) || (a.notice != b.notice && b.notice != null),
          listener: (context, s) {
            final f = s.failure;
            if (f != null) showFailure(context, f);
            if (s.notice != null) showMessage(context, s.notice!);
            cubit.clearMessages();
          },
          child: PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) _leave();
            },
            child: Scaffold(
              appBar: _appBar(state),
              body: SafeArea(
                child: Stack(
                  children: [
                    if (state.loading)
                      const Center(child: CircularProgressIndicator())
                    else if (!_ready)
                      _Unreadable(message: state.failure?.message ?? 'This spreadsheet could not be opened.', onBack: () => context.pop())
                    else
                      Column(
                        children: [
                          if (_finding) _findBar(state),
                          _formulaBar(state),
                          Expanded(
                            child: SheetGrid(
                              workbook: cubit.workbook,
                              sheet: cubit.sheet,
                              state: state,
                              onTapCell: _tapCell,
                              onTapRow: (r) {
                                if (_pending) cubit.commitInput(_input.text, moveDown: false);
                                cubit.selectRow(r);
                              },
                              onTapCol: (c) {
                                if (_pending) cubit.commitInput(_input.text, moveDown: false);
                                cubit.selectCol(c);
                              },
                              onTapCorner: cubit.selectAll,
                            ),
                          ),
                          _toolbar(state),
                          _SheetTabs(state: state),
                        ],
                      ),
                    BusyOverlay(visible: state.busy != null, label: state.busy),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  PreferredSizeWidget _appBar(SheetState state) {
    final ready = !state.loading && _ready;
    return AppBar(
      leading: IconButton(key: const ValueKey('sheet_back'), icon: const Icon(AppIcons.back), onPressed: _leave),
      title: Text(
        ready ? '${cubit.name}${state.modified ? ' *' : ''}' : 'Spreadsheet',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 17),
      ),
      actions: [
        if (ready) ...[
          IconButton(
            key: const ValueKey('sheet_undo'),
            tooltip: 'Undo',
            onPressed: state.canUndo ? cubit.undo : null,
            icon: const Icon(AppIcons.markUndo, size: 20),
          ),
          IconButton(
            key: const ValueKey('sheet_redo'),
            tooltip: 'Redo',
            onPressed: state.canRedo ? cubit.redo : null,
            icon: const Icon(AppIcons.markRedo, size: 20),
          ),
          IconButton(
            key: const ValueKey('sheet_find'),
            tooltip: 'Find',
            onPressed: () => setState(() {
              _finding = !_finding;
              if (_finding) {
                _findFocus.requestFocus();
              } else {
                cubit.endFind();
              }
            }),
            icon: const Icon(AppIcons.search, size: 20),
          ),
          IconButton(key: const ValueKey('sheet_save'), tooltip: 'Save or share', onPressed: _saveSheet, icon: const Icon(AppIcons.export, size: 20)),
          PopupMenuButton<String>(
            key: const ValueKey('sheet_menu'),
            icon: const Icon(AppIcons.more),
            onSelected: _menu,
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'zoom_in', child: Text('Zoom in')),
              const PopupMenuItem(value: 'zoom_out', child: Text('Zoom out')),
              const PopupMenuItem(value: 'zoom_reset', child: Text('Reset zoom')),
              PopupMenuItem(value: 'freeze', child: Text(cubit.isFrozen ? 'Unfreeze panes' : 'Freeze rows and columns above and left of the selected cell')),
              const PopupMenuItem(value: 'width', child: Text('Column width')),
              const PopupMenuItem(value: 'height', child: Text('Row height')),
              const PopupMenuItem(value: 'hide_rows', child: Text('Hide selected rows')),
              const PopupMenuItem(value: 'hide_cols', child: Text('Hide selected columns')),
              if (cubit.hasHidden) const PopupMenuItem(value: 'show_all', child: Text('Show hidden rows and columns')),
              const PopupMenuItem(value: 'fill_down', child: Text('Fill down')),
              const PopupMenuItem(value: 'fill_right', child: Text('Fill right')),
              const PopupMenuItem(value: 'clear_format', child: Text('Clear formatting')),
              const PopupMenuItem(value: 'share_text', child: Text('Copy selection as text')),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _menu(String value) async {
    final c = cubit;
    switch (value) {
      case 'zoom_in':
        c.setZoom(c.state.zoom + 0.15);
      case 'zoom_out':
        c.setZoom(c.state.zoom - 0.15);
      case 'zoom_reset':
        c.setZoom(1);
      case 'freeze':
        c.toggleFreeze();
      case 'width':
        final w = await askNumber(context, title: 'Column width', initial: c.sheet.widthOf(c.state.col), label: 'Width in characters (1 to 255)');
        if (w != null) c.setColumnWidth(w);
      case 'height':
        final h = await askNumber(context, title: 'Row height', initial: c.sheet.heightOf(c.state.row), label: 'Height in points (4 to 409)', min: 4, max: 409);
        if (h != null) c.setRowHeight(h);
      case 'hide_rows':
        c.setHidden(rows: true, hide: true);
      case 'hide_cols':
        c.setHidden(rows: false, hide: true);
      case 'show_all':
        c.showAllHidden();
      case 'fill_down':
        c.fillDown();
      case 'fill_right':
        c.fillRight();
      case 'clear_format':
        c.clearFormatting();
      case 'share_text':
        c.copySelection();
        final text = c.clipText;
        if (text != null) {
          await Clipboard.setData(ClipboardData(text: text));
          if (mounted) showMessage(context, 'Copied as text');
        }
    }
  }

  Widget _findBar(SheetState state) {
    return Container(
      color: AppColors.primarySoft,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const ValueKey('find_field'),
              controller: _findController,
              focusNode: _findFocus,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(hintText: 'Find in this sheet', isDense: true, border: InputBorder.none),
              onSubmitted: cubit.find,
            ),
          ),
          Text(
            state.matches.isEmpty ? '' : '${state.matchIndex + 1} of ${state.matches.length}',
            style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
          ),
          IconButton(
            key: const ValueKey('find_prev'),
            visualDensity: VisualDensity.compact,
            onPressed: state.matches.isEmpty ? null : () => cubit.findNext(back: true),
            icon: const Icon(AppIcons.expandLess),
          ),
          IconButton(
            key: const ValueKey('find_next'),
            visualDensity: VisualDensity.compact,
            onPressed: state.matches.isEmpty ? null : cubit.findNext,
            icon: const Icon(AppIcons.expandMore),
          ),
        ],
      ),
    );
  }

  Widget _formulaBar(SheetState state) {
    final sel = state.selection;
    final ref = sel.isSingle ? CellRef.a1(state.row, state.col) : sel.toString();
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Container(
            key: const ValueKey('ref_label'),
            constraints: const BoxConstraints(minWidth: 48, maxWidth: 110),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(8)),
            child: Text(
              ref,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.primary),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              key: const ValueKey('formula_field'),
              controller: _input,
              focusNode: _focus,
              textInputAction: TextInputAction.done,
              keyboardType: TextInputType.text,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(hintText: 'Tap a cell, then type here', isDense: true, border: InputBorder.none, filled: false),
              onSubmitted: (_) => _commit(),
            ),
          ),
          ListenableBuilder(
            listenable: _input,
            builder: (context, _) => _pending
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        key: const ValueKey('formula_cancel'),
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Cancel',
                        icon: const Icon(AppIcons.close, size: 20),
                        onPressed: () {
                          _input.text = _original;
                          _focus.unfocus();
                        },
                      ),
                      IconButton(
                        key: const ValueKey('formula_ok'),
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Done',
                        icon: const Icon(AppIcons.check, size: 22, color: AppColors.primary),
                        onPressed: _commit,
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _toolbar(SheetState state) {
    final style = cubit.activeStyle;
    final c = cubit;
    Widget tool(String key, IconData icon, String label, VoidCallback? onTap, {bool on = false}) =>
        _Tool(key: ValueKey('tool_$key'), icon: icon, label: label, onTap: onTap, selected: on);
    const gap = SizedBox(width: 6);
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      height: 62,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        children: [
          tool('range', AppIcons.table, 'Select\nrange', c.toggleRangeMode, on: state.rangeMode),
          gap,
          tool('bold', AppIcons.bold, 'Bold', c.toggleBold, on: style.bold),
          tool('italic', AppIcons.italic, 'Italic', c.toggleItalic, on: style.italic),
          tool('underline', AppIcons.underline, 'Underline', c.toggleUnderline, on: style.underline),
          tool('size', AppIcons.fontSize, 'Size', () async {
            final s = await pickFontSize(context, style.fontSize);
            if (s != null) c.setFontSize(s);
          }),
          tool('fill', AppIcons.fillColor, 'Fill', () async {
            final choice = await pickColor(context, title: 'Cell colour', noneLabel: 'No fill');
            if (choice != null) c.setFill(choice.color);
          }),
          tool('textcolor', AppIcons.textColor, 'Text\ncolour', () async {
            final choice = await pickColor(context, title: 'Text colour', noneLabel: 'Automatic');
            if (choice != null) c.setFontColor(choice.color);
          }),
          gap,
          tool('left', AppIcons.alignLeft, 'Left', () => c.setAlign(HAlign.left), on: style.align == HAlign.left),
          tool('center', AppIcons.alignCenter, 'Centre', () => c.setAlign(HAlign.center), on: style.align == HAlign.center),
          tool('right', AppIcons.alignRight, 'Right', () => c.setAlign(HAlign.right), on: style.align == HAlign.right),
          tool('wrap', AppIcons.wrap, 'Wrap', c.toggleWrap, on: style.wrap),
          tool('merge', c.selectionIsMerged ? AppIcons.splitCells : AppIcons.mergeCells, c.selectionIsMerged ? 'Unmerge' : 'Merge', c.toggleMerge),
          tool('format', AppIcons.sheet, 'Format', () async {
            final f = await pickNumberFormat(context, style.numFmt);
            if (f != null) c.setNumberFormat(f);
          }),
          gap,
          tool('copy', AppIcons.copy, 'Copy', c.copySelection),
          tool('cut', AppIcons.cut, 'Cut', () => c.copySelection(cut: true)),
          tool('paste', AppIcons.paste, 'Paste', state.hasClip ? c.paste : null),
          tool('clear', AppIcons.clear, 'Clear', c.clearContents),
          gap,
          tool('sum', AppIcons.sum, 'AutoSum', c.autoSum),
          tool('sort', AppIcons.sort, 'Sort', () async {
            final choice = await askSort(context, columnName: CellRef.columnName(state.col));
            if (choice != null) c.sortSelection(ascending: choice.ascending, hasHeader: choice.hasHeader);
          }),
          gap,
          tool('row_add', AppIcons.addRow, 'Insert\nrow', c.insertRows),
          tool('row_del', AppIcons.delete, 'Delete\nrow', c.deleteRows),
          tool('col_add', AppIcons.addColumn, 'Insert\ncolumn', c.insertCols),
          tool('col_del', AppIcons.delete, 'Delete\ncolumn', c.deleteCols),
        ],
      ),
    );
  }
}

class _Tool extends StatelessWidget {
  const _Tool({super.key, required this.icon, required this.label, required this.onTap, this.selected = false});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final color = !enabled ? AppColors.border : (selected ? AppColors.primary : AppColors.ink);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        width: 56,
        decoration: BoxDecoration(color: selected ? AppColors.primarySoft : null, borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 19, color: color),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 2,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 9.5, height: 1.05, color: color, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetTabs extends StatelessWidget {
  const _SheetTabs({required this.state});
  final SheetState state;

  Future<void> _menu(BuildContext context, int index) async {
    final cubit = context.read<SheetCubit>();
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(cubit.workbook.sheets[index].name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            ListTile(
              key: const ValueKey('tab_rename'),
              leading: const Icon(AppIcons.edit),
              title: const Text('Rename'),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            ListTile(
              key: const ValueKey('tab_duplicate'),
              leading: const Icon(AppIcons.duplicate),
              title: const Text('Duplicate'),
              onTap: () => Navigator.pop(context, 'duplicate'),
            ),
            if (index > 0)
              ListTile(
                key: const ValueKey('tab_left'),
                leading: const Icon(AppIcons.back),
                title: const Text('Move left'),
                onTap: () => Navigator.pop(context, 'left'),
              ),
            if (index < cubit.workbook.sheets.length - 1)
              ListTile(
                key: const ValueKey('tab_right'),
                leading: const Icon(AppIcons.next),
                title: const Text('Move right'),
                onTap: () => Navigator.pop(context, 'right'),
              ),
            ListTile(
              key: const ValueKey('tab_hide'),
              leading: const Icon(AppIcons.eyeOff),
              title: const Text('Hide'),
              onTap: () => Navigator.pop(context, 'hide'),
            ),
            ListTile(
              key: const ValueKey('tab_delete'),
              leading: const Icon(AppIcons.delete, color: AppColors.danger),
              title: const Text('Delete', style: TextStyle(color: AppColors.danger)),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    switch (choice) {
      case 'rename':
        final name = await askText(context, title: 'Rename sheet', initial: cubit.workbook.sheets[index].name, maxLength: 31);
        if (name != null) cubit.renameSheet(index, name);
      case 'duplicate':
        cubit.duplicateSheet(index);
      case 'left':
        cubit.moveSheet(index, -1);
      case 'right':
        cubit.moveSheet(index, 1);
      case 'hide':
        cubit.setSheetHidden(index, true);
      case 'delete':
        final ok = await confirmDialog(
          context,
          title: 'Delete this sheet?',
          message: 'The sheet "${cubit.workbook.sheets[index].name}" and everything on it will be deleted. You can undo this.',
          confirm: 'Delete',
          danger: true,
        );
        if (ok) cubit.deleteSheet(index);
    }
  }

  Future<void> _hidden(BuildContext context) async {
    final cubit = context.read<SheetCubit>();
    final hidden = [
      for (var i = 0; i < cubit.workbook.sheets.length; i++)
        if (cubit.workbook.sheets[i].hidden) i,
    ];
    final pick = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('Show a hidden sheet', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            for (final i in hidden) ListTile(title: Text(cubit.workbook.sheets[i].name), onTap: () => Navigator.pop(context, i)),
          ],
        ),
      ),
    );
    if (pick != null) {
      cubit.setSheetHidden(pick, false);
      cubit.selectSheet(pick);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SheetCubit>();
    final sheets = cubit.workbook.sheets;
    final hasHidden = sheets.any((s) => s.hidden);
    return Container(
      height: 46,
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          IconButton(key: const ValueKey('tab_add'), tooltip: 'Add a sheet', onPressed: cubit.addSheet, icon: const Icon(AppIcons.add, size: 20)),
          if (hasHidden)
            IconButton(
              key: const ValueKey('tab_hidden'),
              tooltip: 'Hidden sheets',
              onPressed: () => _hidden(context),
              icon: const Icon(AppIcons.eyeOff, size: 18),
            ),
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (var i = 0; i < sheets.length; i++)
                  if (!sheets[i].hidden)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
                      child: GestureDetector(
                        key: ValueKey('tab_$i'),
                        onTap: () => cubit.selectSheet(i),
                        onLongPress: () => _menu(context, i),
                        child: Container(
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: state.sheetIndex == i ? AppColors.primary : Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: state.sheetIndex == i ? AppColors.primary : AppColors.border),
                          ),
                          child: Text(
                            sheets[i].name,
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: state.sheetIndex == i ? Colors.white : AppColors.ink),
                          ),
                        ),
                      ),
                    ),
              ],
            ),
          ),
          IconButton(
            key: const ValueKey('tab_options'),
            tooltip: 'Sheet options',
            onPressed: () => _menu(context, state.sheetIndex),
            icon: const Icon(AppIcons.more, size: 20),
          ),
        ],
      ),
    );
  }
}

class _Unreadable extends StatelessWidget {
  const _Unreadable({required this.message, required this.onBack});
  final String message;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(AppIcons.warning, size: 40, color: AppColors.danger),
          const SizedBox(height: AppSpacing.md),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(height: 1.4)),
          const SizedBox(height: AppSpacing.md),
          FilledButton(onPressed: onBack, child: const Text('Go back')),
        ],
      ),
    ),
  );
}

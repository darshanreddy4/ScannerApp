import 'dart:io';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../app/di.dart';
import '../../../core/error/failures.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/feedback.dart';
import '../../export/domain/repositories/export_repository.dart';
import '../../documents/presentation/library_actions.dart';
import '../../documents/presentation/library_picker.dart';
import 'doc_template_store.dart';
import 'docx_builder.dart';
import 'docx_document.dart';
import 'docx_edit_cubit.dart';
import '../../../core/widgets/text.dart';
import '../../../core/i18n/tr.dart';

const _docxMime = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';

/// Shows a Word file as pages of text and lets the words, their look and the paragraphs be changed. Everything else in the file stays as it is.
class DocxEditPage extends StatelessWidget {
  const DocxEditPage({super.key, required this.path, this.libraryId, this.workDir = getTemporaryDirectory});
  final String path;

  /// Set when the file is one kept in the library; saving then puts the new version in its place.
  final String? libraryId;
  final Future<Directory> Function() workDir;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => DocxEditCubit(workDir: workDir)..open(path),
    child: _EditView(path: path, libraryId: libraryId),
  );
}

const _ptToPx = 1.3;
const _headingSizes = {0: 26.0, 1: 20.0, 2: 16.0, 3: 14.0};

class _EditView extends StatefulWidget {
  const _EditView({required this.path, this.libraryId});
  final String path;
  final String? libraryId;

  @override
  State<_EditView> createState() => _EditViewState();
}

class _EditViewState extends State<_EditView> {
  final _keys = <int, GlobalKey>{};
  final _findField = TextEditingController();
  final _replaceField = TextEditingController();
  final _findFocus = FocusNode();
  var _finding = false;
  var _replacing = false;
  late String? _libraryId = widget.libraryId;

  @override
  void dispose() {
    _findField.dispose();
    _replaceField.dispose();
    _findFocus.dispose();
    super.dispose();
  }

  GlobalKey _keyFor(int index) => _keys.putIfAbsent(index, GlobalKey.new);

  void _scrollTo(int paragraph) {
    final ctx = _keys[paragraph]?.currentContext;
    if (ctx != null) Scrollable.ensureVisible(ctx, alignment: 0.3, duration: const Duration(milliseconds: 250));
  }

  Future<void> _edit(int index) async {
    final cubit = context.read<DocxEditCubit>();
    int? target = index;
    while (target != null && mounted) {
      final text = ValueNotifier<String>(cubit.paragraphText(target));
      final result = await showModalBottomSheet<_SheetResult>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => BlocProvider.value(
          value: cubit,
          child: _ParagraphSheet(index: target!, text: text),
        ),
      );
      if (mounted && !(result?.skipCommit ?? false)) cubit.commitText(target, text.value);
      text.dispose();
      target = result?.openNext;
    }
  }

  Future<void> _save() async {
    final cubit = context.read<DocxEditCubit>();
    final path = await cubit.export();
    if (path == null || !mounted) return;
    final name = cubit.fileName;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const Text('Your changes are in this copy'),
            ),
            ListTile(
              key: const ValueKey('save-library'),
              leading: const Icon(AppIcons.library),
              title: const Text('Save in Doculoom'),
              subtitle: const Text('Keep it with your documents to open or use again'),
              onTap: () => Navigator.pop(context, 'library'),
            ),
            ListTile(
              key: const ValueKey('save-share'),
              leading: const Icon(AppIcons.share),
              title: const Text('Share'),
              onTap: () => Navigator.pop(context, 'share'),
            ),
            ListTile(
              key: const ValueKey('save-files'),
              leading: const Icon(AppIcons.storage),
              title: const Text('Save to Files'),
              onTap: () => Navigator.pop(context, 'save'),
            ),
            ListTile(
              key: const ValueKey('save-template'),
              leading: const Icon(AppIcons.tplBlank),
              title: const Text('Save as my template'),
              subtitle: const Text('Start new documents from this one'),
              onTap: () => Navigator.pop(context, 'template'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'template') {
      try {
        await const DocTemplateStore().save(path, cubit.name);
        if (mounted) showMessage(context, 'Saved. Find it under My templates when you start a new document.');
      } catch (_) {
        if (mounted) showFailure(context, const ExportFailure('The template could not be saved.'));
      }
      return;
    }
    if (choice == 'library') {
      _libraryId = await saveToLibrary(context, path: path, title: cubit.name, existingId: _libraryId) ?? _libraryId;
      return;
    }
    _libraryId = await saveToLibrary(context, path: path, title: cubit.name, existingId: _libraryId, announce: false) ?? _libraryId;
    if (!mounted) return;
    if (choice == 'share') {
      final failure = (await sl<ShareService>().shareFile(path: path, mimeType: _docxMime, subject: name)).failureOrNull;
      if (failure != null && mounted) showFailure(context, failure);
    } else {
      final result = await sl<SaveService>().saveToFiles(sourcePath: path, fileName: name, mimeType: _docxMime);
      if (!mounted) return;
      final failure = result.failureOrNull;
      if (failure != null) {
        showFailure(context, failure);
      } else if (result.valueOrNull == true) {
        showMessage(context, 'Saved');
      }
    }
  }

  Future<void> _headerFooter() async {
    final cubit = context.read<DocxEditCubit>();
    final result = await showDialog<({String header, String footer, bool numbers})>(
      context: context,
      builder: (_) => _HeaderFooterDialog(initial: cubit.headerFooter),
    );
    if (result != null && mounted) {
      cubit.setHeaderFooter(header: result.header, footer: result.footer, pageNumbers: result.numbers, pageWord: tr('Page'), ofWord: tr('of'));
    }
  }

  void _openFind() {
    setState(() => _finding = true);
    _findFocus.requestFocus();
  }

  void _closeFind() {
    _findField.clear();
    context.read<DocxEditCubit>().endFind();
    _findFocus.unfocus();
    setState(() {
      _finding = false;
      _replacing = false;
    });
  }

  Future<bool> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave without saving?'),
        content: const Text('Your changes to this document have not been saved.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep editing')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    return leave == true;
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<DocxEditCubit, DocxEditState>(
      listenWhen: (a, b) => a.failure != b.failure || a.notice != b.notice || a.current != b.current || a.query != b.query,
      listener: (context, state) {
        if (state.failure != null) showFailure(context, state.failure!);
        if (state.notice != null) showMessage(context, state.notice!);
        if (state.current >= 0 && state.current < state.matches.length) _scrollTo(state.matches[state.current].paragraph);
      },
      builder: (context, state) {
        final cubit = context.read<DocxEditCubit>();
        return PopScope(
          canPop: !state.modified,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            if (await _confirmLeave() && context.mounted) context.pop();
          },
          child: Scaffold(
            backgroundColor: const Color(0xFFE9EDF3),
            appBar: AppBar(
              title: Text(p.basename(widget.path), overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16)),
              actions: [
                IconButton(
                  key: const ValueKey('docx-undo'),
                  tooltip: tr('Undo'),
                  icon: const Icon(AppIcons.markUndo),
                  onPressed: state.canUndo ? cubit.undo : null,
                ),
                IconButton(
                  key: const ValueKey('docx-redo'),
                  tooltip: tr('Redo'),
                  icon: const Icon(AppIcons.markRedo),
                  onPressed: state.canRedo ? cubit.redo : null,
                ),
                IconButton(
                  key: const ValueKey('docx-find-button'),
                  tooltip: tr('Find and replace'),
                  icon: const Icon(AppIcons.search),
                  onPressed: state.loading ? null : (_finding ? _closeFind : _openFind),
                ),
                IconButton(
                  key: const ValueKey('docx-header-footer'),
                  tooltip: tr('Header and footer'),
                  icon: const Icon(Icons.vertical_split_outlined),
                  onPressed: state.loading ? null : _headerFooter,
                ),
                TextButton(
                  key: const ValueKey('docx-save'),
                  onPressed: state.loading || state.busy ? null : _save,
                  child: const Text('Save', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            body: Stack(
              children: [
                Column(
                  children: [
                    if (_finding) _findBar(state, cubit),
                    Expanded(child: _content(state)),
                  ],
                ),
                BusyOverlay(visible: state.busy, label: 'Saving'),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _findBar(DocxEditState state, DocxEditCubit cubit) {
    final status = state.query.isEmpty ? '' : (state.matches.isEmpty ? 'None' : '${state.current + 1} of ${state.matches.length}');
    return Material(
      color: Colors.white,
      elevation: 1,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md, 6, AppSpacing.xs, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('docx-find-field'),
                    controller: _findField,
                    focusNode: _findFocus,
                    textInputAction: TextInputAction.search,
                    onChanged: (v) => cubit.find(v),
                    onSubmitted: (_) {
                      cubit.step(1);
                      _findFocus.requestFocus();
                    },
                    decoration: InputDecoration(hintText: tr('Find'), isDense: true, prefixIcon: Icon(AppIcons.search, size: 18)),
                  ),
                ),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 40),
                  child: Center(
                    child: Text(
                      status,
                      key: const ValueKey('docx-find-count'),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.inkMuted),
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('docx-find-prev'),
                  visualDensity: VisualDensity.compact,
                  tooltip: tr('Previous'),
                  onPressed: state.matches.isEmpty ? null : () => cubit.step(-1),
                  icon: const Icon(AppIcons.expandLess),
                ),
                IconButton(
                  key: const ValueKey('docx-find-next'),
                  visualDensity: VisualDensity.compact,
                  tooltip: tr('Next'),
                  onPressed: state.matches.isEmpty ? null : () => cubit.step(1),
                  icon: const Icon(AppIcons.expandMore),
                ),
                IconButton(
                  key: const ValueKey('docx-find-options'),
                  visualDensity: VisualDensity.compact,
                  tooltip: tr('Replace'),
                  onPressed: () => setState(() => _replacing = !_replacing),
                  icon: Icon(AppIcons.edit, color: _replacing ? AppColors.primary : null),
                ),
                IconButton(
                  key: const ValueKey('docx-find-close'),
                  visualDensity: VisualDensity.compact,
                  tooltip: tr('Close'),
                  onPressed: _closeFind,
                  icon: const Icon(AppIcons.close),
                ),
              ],
            ),
            if (_replacing)
              Padding(
                padding: const EdgeInsetsDirectional.only(top: 6, end: AppSpacing.sm),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('docx-replace-field'),
                        controller: _replaceField,
                        decoration: InputDecoration(hintText: tr('Replace with'), isDense: true),
                      ),
                    ),
                    const SizedBox(width: 6),
                    FilterChip(
                      key: const ValueKey('docx-match-case'),
                      label: const Text('Aa'),
                      selected: state.matchCase,
                      onSelected: (v) => cubit.find(_findField.text, matchCase: v),
                      visualDensity: VisualDensity.compact,
                    ),
                    TextButton(
                      key: const ValueKey('docx-replace-one'),
                      onPressed: state.matches.isEmpty ? null : () => cubit.replaceCurrent(_replaceField.text),
                      child: const Text('Replace'),
                    ),
                    FilledButton(
                      key: const ValueKey('docx-replace-all'),
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                      onPressed: state.matches.isEmpty
                          ? null
                          : () {
                              final n = cubit.replaceAll(_replaceField.text);
                              showMessage(context, n == 1 ? 'Replaced 1 match' : 'Replaced $n matches');
                            },
                      child: const Text('All'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _content(DocxEditState state) {
    if (state.loading) return const Center(child: CircularProgressIndicator());
    if (state.blocks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Text(
            state.failure?.message ?? 'This document has no text.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.inkMuted),
          ),
        ),
      );
    }
    final cubit = context.read<DocxEditCubit>();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Container(
            key: const ValueKey('docx-paper'),
            width: double.infinity,
            padding: const EdgeInsetsDirectional.fromSTEB(20, 24, 20, 40),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8)],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [..._blocks(state.blocks, state, cubit)]),
          ),
        ),
      ),
    );
  }

  Iterable<Widget> _blocks(List<DocBlock> blocks, DocxEditState state, DocxEditCubit cubit) sync* {
    for (final b in blocks) {
      switch (b) {
        case ParaBlock():
          yield _paragraph(b, state, cubit);
        case TableBlock():
          final columns = b.rows.fold<int>(1, (m, r) => r.length > m ? r.length : m);
          yield Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Table(
              border: TableBorder.all(color: const Color(0xFFB8C0CC)),
              defaultVerticalAlignment: TableCellVerticalAlignment.top,
              children: [
                for (final row in b.rows)
                  TableRow(
                    children: [
                      for (var c = 0; c < columns; c++)
                        c < row.length
                            ? Padding(
                                padding: const EdgeInsets.all(4),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [..._blocks(row[c], state, cubit)]),
                              )
                            : const SizedBox.shrink(),
                    ],
                  ),
              ],
            ),
          );
      }
    }
  }

  Widget _paragraph(ParaBlock b, DocxEditState state, DocxEditCubit cubit) {
    final ranges = <(int, int, bool)>[];
    for (var i = 0; i < state.matches.length; i++) {
      final m = state.matches[i];
      if (m.paragraph == b.index) ranges.add((m.start, m.end, i == state.current));
    }
    final defaultSize = _headingSizes[b.headingLevel] ?? 11.0;
    final children = <InlineSpan>[];
    var at = 0;
    for (final span in b.spans) {
      final style = TextStyle(
        fontSize: (span.sizePt ?? defaultSize) * _ptToPx,
        fontWeight: span.bold || (b.headingLevel != null && span.sizePt == null) ? FontWeight.w700 : FontWeight.w400,
        fontStyle: span.italic ? FontStyle.italic : FontStyle.normal,
        color: span.color == null ? const Color(0xFF111111) : Color(span.color!),
        decoration: TextDecoration.combine([if (span.underline) TextDecoration.underline, if (span.strike) TextDecoration.lineThrough]),
        fontFamily: docxPreviewFamily(span.font),
        height: 1.35,
      );
      // Split the stretch where a search match starts or ends.
      final cuts = <int>{0, span.text.length};
      for (final r in ranges) {
        if (r.$1 > at && r.$1 < at + span.text.length) cuts.add(r.$1 - at);
        if (r.$2 > at && r.$2 < at + span.text.length) cuts.add(r.$2 - at);
      }
      final sorted = cuts.toList()..sort();
      for (var i = 0; i + 1 < sorted.length; i++) {
        final from = sorted[i], to = sorted[i + 1];
        final pos = at + from;
        final hit = ranges.where((r) => pos >= r.$1 && pos < r.$2).firstOrNull;
        children.add(
          TextSpan(
            text: span.text.substring(from, to).replaceAll('\t', '    '),
            style: hit == null ? style : style.copyWith(backgroundColor: hit.$3 ? const Color(0x99FF6D00) : const Color(0x66FFC107)),
          ),
        );
      }
      at += span.text.length;
    }
    final align = switch (b.align) {
      'center' => TextAlign.center,
      'right' => TextAlign.end,
      'both' => TextAlign.justify,
      _ => TextAlign.start,
    };
    return KeyedSubtree(
      key: _keyFor(b.index),
      child: InkWell(
        key: ValueKey('docx-para-${b.index}'),
        onTap: () => _edit(b.index),
        child: Padding(
          padding: EdgeInsetsDirectional.only(start: (b.indentPt * _ptToPx).clamp(0, 140), top: 3, bottom: 3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 22),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (b.listLabel != null)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 8),
                        child: Text(b.listLabel!, style: TextStyle(fontSize: 11 * _ptToPx, height: 1.35)),
                      ),
                    Expanded(
                      child: Text.rich(TextSpan(children: children), textAlign: align),
                    ),
                  ],
                ),
              ),
              for (final part in b.images)
                if (cubit.document.imageBytes(part) case final bytes?)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Image.memory(bytes, height: 140, fit: BoxFit.contain, errorBuilder: (_, _, _) => const SizedBox.shrink()),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

const _textColors = <int>[
  0xFF000000,
  0xFF424242,
  0xFFC62828,
  0xFFEF6C00,
  0xFFF9A825,
  0xFF2E7D32,
  0xFF00838F,
  0xFF1565C0,
  0xFF4527A0,
  0xFFAD1457,
  0xFF6D4C41,
  0xFF757575,
];

const _sizes = [8.0, 9.0, 10.0, 11.0, 12.0, 14.0, 16.0, 18.0, 20.0, 24.0, 28.0, 36.0];

/// Fonts offered in the picker; Word and other readers show them as named.
const docxFonts = ['Calibri', 'Arial', 'Times New Roman', 'Cambria', 'Georgia', 'Verdana', 'Tahoma', 'Trebuchet MS', 'Courier New', 'Consolas'];

/// The closest family this device has, so serif and typewriter text look different while editing.
String? docxPreviewFamily(String? font) {
  final f = (font ?? '').toLowerCase();
  if (f.contains('courier') || f.contains('consolas') || f.contains('mono')) return 'monospace';
  if (f.contains('times') || f.contains('cambria') || f.contains('georgia') || f.contains('garamond')) return 'serif';
  return null;
}

/// How the paragraph sheet was left: [skipCommit] when the paragraph was deleted, [openNext] to go on with a new paragraph.
class _SheetResult {
  const _SheetResult({this.skipCommit = false, this.openNext});
  final bool skipCommit;
  final int? openNext;
}

/// The place where one paragraph is typed and its look is chosen.
class _ParagraphSheet extends StatefulWidget {
  const _ParagraphSheet({required this.index, required this.text});
  final int index;
  final ValueNotifier<String> text;

  @override
  State<_ParagraphSheet> createState() => _ParagraphSheetState();
}

class _ParagraphSheetState extends State<_ParagraphSheet> {
  late final TextEditingController _controller = TextEditingController(text: widget.text.value)..addListener(_changed);

  void _changed() {
    widget.text.value = _controller.text;
    setState(() {});
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Types what is in the box into the document first, so the look is applied to the text that is shown.
  void _apply(FormatChange change) {
    final cubit = context.read<DocxEditCubit>();
    final sel = _controller.selection;
    cubit.commitText(widget.index, _controller.text);
    final start = sel.isValid ? sel.start : 0, end = sel.isValid ? sel.end : 0;
    cubit.format(widget.index, start, end, change);
  }

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<DocxEditCubit, DocxEditState>(buildWhen: (a, b) => a.version != b.version, builder: (context, _) => _sheet(context));

  /// Asks for a picture (from the phone or from Doculoom) and puts it in a paragraph below this one.
  Future<void> _addPicture() async {
    final cubit = context.read<DocxEditCubit>();
    cubit.commitText(widget.index, _controller.text);
    try {
      final paths = await pickFilePaths(context, allowedExtensions: const ['jpg', 'jpeg', 'png']);
      if (paths.isEmpty || !mounted) return;
      final bytes = await File(paths.first).readAsBytes();
      final info = img.findDecoderForData(bytes)?.startDecode(bytes);
      if (info == null || !mounted) {
        if (mounted) showMessage(context, 'That picture could not be added.');
        return;
      }
      cubit.addPicture(widget.index, bytes, extension: p.extension(paths.first), pixelWidth: info.width, pixelHeight: info.height);
      Navigator.pop(context, const _SheetResult(skipCommit: true));
    } catch (_) {
      if (mounted) showMessage(context, 'That picture could not be added.');
    }
  }

  Widget _sheet(BuildContext context) {
    final cubit = context.read<DocxEditCubit>();
    final sel = _controller.selection;
    final start = sel.isValid ? sel.start : 0, end = sel.isValid ? sel.end : 0;
    // The look shown is that of the text in the document, which matches the box once the typing is committed.
    final modelLength = cubit.paragraphText(widget.index).length;
    final fmt = cubit.formatOf(widget.index, start.clamp(0, modelLength), end.clamp(0, modelLength));
    Widget toggle(Key key, IconData icon, String tip, bool? on, FormatChange Function(bool) change) => IconButton(
      key: key,
      tooltip: tip,
      isSelected: on == true,
      style: IconButton.styleFrom(backgroundColor: on == true ? AppColors.primarySoft : null, foregroundColor: on == true ? AppColors.primary : AppColors.ink),
      icon: Icon(icon, size: 20),
      onPressed: () => _apply(change(on != true)),
    );
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final s in const [
                      (DocStyle.normal, 'Normal'),
                      (DocStyle.title, 'Title'),
                      (DocStyle.heading1, 'Heading 1'),
                      (DocStyle.heading2, 'Heading 2'),
                      (DocStyle.heading3, 'Heading 3'),
                    ])
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 6),
                        child: ChoiceChip(
                          key: ValueKey('style-${s.$1.id}'),
                          label: Text(s.$2),
                          selected: cubit.styleOf(widget.index) == s.$1,
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) {
                            cubit.commitText(widget.index, _controller.text);
                            cubit.setStyle(widget.index, s.$1);
                          },
                        ),
                      ),
                    IconButton(
                      key: const ValueKey('list-bullet'),
                      tooltip: tr('Bullet list'),
                      style: IconButton.styleFrom(
                        backgroundColor: cubit.listOf(widget.index) == DocList.bullet ? AppColors.primarySoft : null,
                        foregroundColor: cubit.listOf(widget.index) == DocList.bullet ? AppColors.primary : AppColors.ink,
                      ),
                      icon: const Icon(AppIcons.listBullet, size: 20),
                      onPressed: () {
                        cubit.commitText(widget.index, _controller.text);
                        cubit.setList(widget.index, cubit.listOf(widget.index) == DocList.bullet ? DocList.none : DocList.bullet);
                      },
                    ),
                    IconButton(
                      key: const ValueKey('list-number'),
                      tooltip: tr('Numbered list'),
                      style: IconButton.styleFrom(
                        backgroundColor: cubit.listOf(widget.index) == DocList.number ? AppColors.primarySoft : null,
                        foregroundColor: cubit.listOf(widget.index) == DocList.number ? AppColors.primary : AppColors.ink,
                      ),
                      icon: const Icon(AppIcons.listNumbered, size: 20),
                      onPressed: () {
                        cubit.commitText(widget.index, _controller.text);
                        cubit.setList(widget.index, cubit.listOf(widget.index) == DocList.number ? DocList.none : DocList.number);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              TextField(
                key: const ValueKey('docx-paragraph-field'),
                controller: _controller,
                autofocus: true,
                minLines: 2,
                maxLines: 6,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(hintText: tr('Type here')),
              ),
              const SizedBox(height: AppSpacing.sm),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    toggle(const ValueKey('fmt-bold'), AppIcons.bold, 'Bold', fmt.bold, (on) => FormatChange(bold: on)),
                    toggle(const ValueKey('fmt-italic'), AppIcons.italic, 'Italic', fmt.italic, (on) => FormatChange(italic: on)),
                    toggle(const ValueKey('fmt-underline'), AppIcons.underline, 'Underline', fmt.underline, (on) => FormatChange(underline: on)),
                    PopupMenuButton<String>(
                      key: const ValueKey('fmt-font'),
                      tooltip: tr('Font'),
                      onSelected: (v) => _apply(FormatChange(font: v)),
                      itemBuilder: (_) => [
                        for (final f in docxFonts)
                          PopupMenuItem(
                            value: f,
                            child: Text(f, style: TextStyle(fontFamily: docxPreviewFamily(f), fontWeight: fmt.font == f ? FontWeight.w800 : FontWeight.w400)),
                          ),
                      ],
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                        child: Row(
                          children: [
                            const Icon(Icons.font_download_outlined, size: 20),
                            const SizedBox(width: 4),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 90),
                              child: Text(fmt.font ?? '-', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                            ),
                          ],
                        ),
                      ),
                    ),
                    PopupMenuButton<double>(
                      key: const ValueKey('fmt-size'),
                      tooltip: tr('Text size'),
                      onSelected: (v) => _apply(FormatChange(sizePt: v)),
                      itemBuilder: (_) => [for (final s in _sizes) PopupMenuItem(value: s, child: Text('${s.round()}'))],
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                        child: Row(
                          children: [
                            const Icon(AppIcons.fontSize, size: 20),
                            const SizedBox(width: 4),
                            Text(fmt.sizePt == null ? '-' : '${fmt.sizePt!.round()}'),
                          ],
                        ),
                      ),
                    ),
                    PopupMenuButton<int>(
                      key: const ValueKey('fmt-color'),
                      tooltip: tr('Text colour'),
                      onSelected: (v) => _apply(v == -1 ? const FormatChange(clearColor: true) : FormatChange(color: v)),
                      itemBuilder: (_) => [
                        const PopupMenuItem<int>(value: -1, child: Text('Automatic')),
                        for (final c in _textColors)
                          PopupMenuItem<int>(
                            value: c,
                            child: Row(
                              children: [
                                Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(color: Color(c), shape: BoxShape.circle),
                                ),
                              ],
                            ),
                          ),
                      ],
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                        child: Icon(AppIcons.textColor, size: 20, color: fmt.color == null ? AppColors.ink : Color(fmt.color!)),
                      ),
                    ),
                    for (final a in const [('left', AppIcons.alignLeft), ('center', AppIcons.alignCenter), ('right', AppIcons.alignRight)])
                      IconButton(
                        key: ValueKey('align-${a.$1}'),
                        tooltip: 'Align ${a.$1}',
                        style: IconButton.styleFrom(
                          backgroundColor: fmt.align == a.$1 ? AppColors.primarySoft : null,
                          foregroundColor: fmt.align == a.$1 ? AppColors.primary : AppColors.ink,
                        ),
                        icon: Icon(a.$2, size: 20),
                        onPressed: () {
                          cubit.commitText(widget.index, _controller.text);
                          cubit.setAlign(widget.index, a.$1);
                        },
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      children: [
                        TextButton.icon(
                          key: const ValueKey('para-add'),
                          onPressed: () {
                            cubit.commitText(widget.index, _controller.text);
                            final created = cubit.addAfter(widget.index);
                            Navigator.pop(context, _SheetResult(skipCommit: true, openNext: created));
                          },
                          icon: const Icon(AppIcons.add, size: 18),
                          label: const Text('Add below'),
                        ),
                        TextButton.icon(
                          key: const ValueKey('para-picture'),
                          onPressed: _addPicture,
                          icon: const Icon(AppIcons.gallery, size: 18),
                          label: const Text('Picture below'),
                        ),
                        TextButton.icon(
                          key: const ValueKey('para-delete'),
                          onPressed: () {
                            cubit.delete(widget.index);
                            Navigator.pop(context, const _SheetResult(skipCommit: true));
                          },
                          style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                          icon: const Icon(AppIcons.delete, size: 18),
                          label: const Text('Delete'),
                        ),
                      ],
                    ),
                  ),
                  FilledButton(
                    key: const ValueKey('para-done'),
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks for the text at the top and bottom of every page and whether pages are numbered.
class _HeaderFooterDialog extends StatefulWidget {
  const _HeaderFooterDialog({required this.initial});
  final ({String header, String footer, bool pageNumbers}) initial;

  @override
  State<_HeaderFooterDialog> createState() => _HeaderFooterDialogState();
}

class _HeaderFooterDialogState extends State<_HeaderFooterDialog> {
  late final _header = TextEditingController(text: widget.initial.header);
  late final _footer = TextEditingController(text: widget.initial.footer);
  late var _numbers = widget.initial.pageNumbers;

  @override
  void dispose() {
    _header.dispose();
    _footer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Header and footer'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const ValueKey('hf-header'),
            controller: _header,
            minLines: 1,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: tr('Top of every page')),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('hf-footer'),
            controller: _footer,
            minLines: 1,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: tr('Bottom of every page')),
          ),
          CheckboxListTile(
            key: const ValueKey('hf-numbers'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _numbers,
            onChanged: (v) => setState(() => _numbers = v ?? false),
            title: const Text('Page numbers at the bottom'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(
        key: const ValueKey('hf-apply'),
        onPressed: () => Navigator.pop(context, (header: _header.text, footer: _footer.text, numbers: _numbers)),
        child: const Text('Apply'),
      ),
    ],
  );
}

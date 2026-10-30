import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../app/di.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/feedback.dart';
import '../../export/domain/repositories/export_repository.dart';
import '../../reader/data/pdf_text_edit.dart';
import 'pdf_edit_cubit.dart';
import 'pdf_page_renderer.dart';
import '../../../core/widgets/text.dart';
import '../../../core/i18n/tr.dart';

const _pdfMime = 'application/pdf';
const _renderWidth = 1300;

/// Shows a PDF page by page and lets its lines of text be retyped or removed and new text be added. Nothing leaves the phone.
class PdfEditPage extends StatelessWidget {
  const PdfEditPage({super.key, required this.path, this.workDir = getTemporaryDirectory, this.openRenderer = PdfxPageRenderer.open});
  final String path;
  final Future<Directory> Function() workDir;
  final Future<PdfPageRenderer> Function(String path) openRenderer;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => PdfEditCubit(workDir: workDir)..open(path),
    child: _EditView(path: path, openRenderer: openRenderer),
  );
}

enum _Mode { edit, add }

class _EditView extends StatefulWidget {
  const _EditView({required this.path, required this.openRenderer});
  final String path;
  final Future<PdfPageRenderer> Function(String path) openRenderer;

  @override
  State<_EditView> createState() => _EditViewState();
}

class _EditViewState extends State<_EditView> {
  PdfPageRenderer? _renderer;
  Object? _rendererError;
  final _images = <int, Future<Uint8List>>{};
  final _pages = PageController();
  var _page = 0;
  var _mode = _Mode.edit;
  AddedText? _lastStyle;

  @override
  void initState() {
    super.initState();
    _openRenderer();
  }

  Future<void> _openRenderer() async {
    try {
      final r = await widget.openRenderer(widget.path);
      if (!mounted) {
        await r.dispose();
        return;
      }
      setState(() => _renderer = r);
    } catch (e) {
      if (mounted) setState(() => _rendererError = e);
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    _renderer?.dispose();
    super.dispose();
  }

  Future<Uint8List> _image(int page) => _images.putIfAbsent(page, () => _renderer!.render(page, width: _renderWidth));

  Future<void> _editLine(int page, int line) async {
    final cubit = context.read<PdfEditCubit>();
    final original = cubit.state.pages[page].lines[line].text;
    final current = cubit.state.edits.textOf(page, line);
    final result = await showModalBottomSheet<_LineResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _LineSheet(original: original, current: current),
    );
    if (result == null || !mounted) return;
    switch (result.action) {
      case _LineAction.apply:
        cubit.editLine(page, line, result.text);
      case _LineAction.delete:
        cubit.deleteLine(page, line);
      case _LineAction.restore:
        cubit.restoreLine(page, line);
    }
  }

  Future<void> _addText(int page, double x, double y) async {
    final cubit = context.read<PdfEditCubit>();
    final info = cubit.state.pages[page];
    final seed = _lastStyle ?? AddedText(page: page, x: 0, y: 0, text: '', sizePt: _typicalSize(info));
    final result = await showModalBottomSheet<_AddResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AddSheet(initial: seed),
    );
    if (result == null || result.text == null || !mounted) return;
    final t = result.text!;
    _lastStyle = AddedText(page: page, x: 0, y: 0, text: '', sizePt: t.sizePt, rgb: t.rgb, bold: t.bold, italic: t.italic, family: t.family);
    final heightPt = info.widthPt / info.aspect;
    cubit.addText(
      AddedText(
        page: page,
        x: x.clamp(0.0, 0.97),
        y: (y + 0.3 * t.sizePt / heightPt).clamp(0.02, 0.99),
        text: t.text,
        sizePt: t.sizePt,
        rgb: t.rgb,
        bold: t.bold,
        italic: t.italic,
        family: t.family,
      ),
    );
  }

  Future<void> _editAdded(int index) async {
    final cubit = context.read<PdfEditCubit>();
    final current = cubit.state.edits.added[index];
    final result = await showModalBottomSheet<_AddResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AddSheet(initial: current, canDelete: true),
    );
    if (result == null || !mounted) return;
    if (result.text == null) {
      cubit.removeAdded(index);
    } else {
      final t = result.text!;
      cubit.replaceAdded(
        index,
        AddedText(page: current.page, x: current.x, y: current.y, text: t.text, sizePt: t.sizePt, rgb: t.rgb, bold: t.bold, italic: t.italic, family: t.family),
      );
    }
  }

  double _typicalSize(PdfPageEditInfo info) {
    if (info.lines.isEmpty) return 14;
    final sizes = info.lines.map((l) => l.fontSize).toList()..sort();
    return sizes[sizes.length ~/ 2].clamp(8.0, 48.0).roundToDouble();
  }

  Future<void> _save() async {
    final cubit = context.read<PdfEditCubit>();
    final path = await cubit.export();
    if (path == null || !mounted) return;
    final name = p.basename(path);
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
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'share') {
      final failure = (await sl<ShareService>().shareFile(path: path, mimeType: _pdfMime, subject: name)).failureOrNull;
      if (failure != null && mounted) showFailure(context, failure);
    } else {
      final result = await sl<SaveService>().saveToFiles(sourcePath: path, fileName: name, mimeType: _pdfMime);
      if (!mounted) return;
      final failure = result.failureOrNull;
      if (failure != null) {
        showFailure(context, failure);
      } else if (result.valueOrNull == true) {
        showMessage(context, 'Saved');
      }
    }
  }

  Future<bool> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave without saving?'),
        content: const Text('Your changes to this PDF have not been saved.'),
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
    return BlocConsumer<PdfEditCubit, PdfEditState>(
      listenWhen: (a, b) => a.failure != b.failure && b.failure != null && !b.loading,
      listener: (context, state) => showFailure(context, state.failure!),
      builder: (context, state) {
        final cubit = context.read<PdfEditCubit>();
        final ready = !state.loading && state.pages.isNotEmpty && _renderer != null;
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
                  key: const ValueKey('pdf-undo'),
                  tooltip: tr('Undo'),
                  icon: const Icon(AppIcons.markUndo),
                  onPressed: state.canUndo ? cubit.undo : null,
                ),
                IconButton(
                  key: const ValueKey('pdf-redo'),
                  tooltip: tr('Redo'),
                  icon: const Icon(AppIcons.markRedo),
                  onPressed: state.canRedo ? cubit.redo : null,
                ),
                TextButton(
                  key: const ValueKey('pdf-save'),
                  onPressed: !ready || state.busy ? null : _save,
                  child: const Text('Save', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            body: Stack(
              children: [
                _body(state, ready),
                BusyOverlay(visible: state.busy, label: 'Saving'),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _body(PdfEditState state, bool ready) {
    if (_rendererError != null || (!state.loading && state.pages.isEmpty)) {
      return _Message(icon: AppIcons.info, text: state.failure?.message ?? 'This PDF could not be shown.');
    }
    if (!ready) return const Center(child: CircularProgressIndicator());
    final info = state.pages[_page.clamp(0, state.pages.length - 1)];
    final note = !info.editable
        ? 'The text on this page cannot be changed here. You can still add text.'
        : info.lines.isEmpty
        ? 'No text to change on this page (it may be a scan). Use Add text to write on it.'
        : null;
    return Column(
      children: [
        if (note != null)
          Material(
            key: const ValueKey('pdf-page-note'),
            color: const Color(0xFFFFF7E0),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 8),
              child: Row(
                children: [
                  const Icon(AppIcons.info, size: 18, color: Color(0xFF8A6100)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(note, style: const TextStyle(fontSize: 13, color: Color(0xFF5C4300))),
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: PageView.builder(
            key: const ValueKey('pdf-pages'),
            controller: _pages,
            itemCount: state.pages.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (context, i) => _PageCanvas(
              index: i,
              info: state.pages[i],
              edits: state.edits,
              mode: _mode,
              image: _image(i),
              onLine: (line) => _editLine(i, line),
              onAdded: _editAdded,
              onEmptyTap: (x, y) => _addText(i, x, y),
            ),
          ),
        ),
        _bottomBar(state),
      ],
    );
  }

  Widget _bottomBar(PdfEditState state) {
    return Material(
      color: Colors.white,
      elevation: 6,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md, 8, AppSpacing.md, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: SegmentedButton<_Mode>(
                      key: const ValueKey('pdf-mode'),
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: _Mode.edit,
                          icon: Icon(AppIcons.edit, size: 18),
                          label: Text('Edit text', key: ValueKey('pdf-mode-edit')),
                        ),
                        ButtonSegment(
                          value: _Mode.add,
                          icon: Icon(AppIcons.add, size: 18),
                          label: Text('Add text', key: ValueKey('pdf-mode-add')),
                        ),
                      ],
                      selected: {_mode},
                      onSelectionChanged: (s) => setState(() => _mode = s.first),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${_page + 1} / ${state.pages.length}',
                    key: const ValueKey('pdf-page-label'),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.inkMuted),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _mode == _Mode.edit ? 'Tap a line to change or remove it. Pinch to zoom.' : 'Tap the page where the new text should go.',
                key: const ValueKey('pdf-hint'),
                style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: AppColors.inkMuted),
          const SizedBox(height: 12),
          Text(text, key: const ValueKey('pdf-message'), textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

Color _colorOf(int rgb) => Color(0xFF000000 | (rgb & 0xFFFFFF));

String? _familyName(String family) => switch (family) {
  'serif' => 'serif',
  'mono' => 'monospace',
  _ => null,
};

TextStyle _previewStyle({required double px, required int rgb, required bool bold, required bool italic, required String family}) => TextStyle(
  fontSize: px,
  height: 1.0,
  color: _colorOf(rgb),
  fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
  fontStyle: italic ? FontStyle.italic : FontStyle.normal,
  fontFamily: _familyName(family),
);

/// One page: its picture, with every line and every added text laid over it at the right place.
class _PageCanvas extends StatelessWidget {
  const _PageCanvas({
    required this.index,
    required this.info,
    required this.edits,
    required this.mode,
    required this.image,
    required this.onLine,
    required this.onAdded,
    required this.onEmptyTap,
  });

  final int index;
  final PdfPageEditInfo info;
  final PdfEdits edits;
  final _Mode mode;
  final Future<Uint8List> image;
  final void Function(int line) onLine;
  final void Function(int index) onAdded;
  final void Function(double x, double y) onEmptyTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final maxW = c.maxWidth - 16, maxH = c.maxHeight - 16;
        final w = (maxH * info.aspect < maxW ? maxH * info.aspect : maxW).clamp(1.0, 100000.0);
        final h = w / info.aspect;
        final pxPerPt = w / info.widthPt;
        return InteractiveViewer(
          maxScale: 5,
          child: Center(
            child: Container(
              key: ValueKey('pdf-page-$index'),
              width: w,
              height: h,
              decoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 2))],
              ),
              child: ClipRect(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: FutureBuilder<Uint8List>(
                        future: image,
                        builder: (context, snap) {
                          if (snap.hasData) return Image.memory(snap.data!, fit: BoxFit.fill, gaplessPlayback: true);
                          if (snap.hasError) return const Center(child: Icon(AppIcons.info, color: AppColors.inkMuted));
                          return const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)));
                        },
                      ),
                    ),
                    if (mode == _Mode.add)
                      Positioned.fill(
                        child: GestureDetector(
                          key: const ValueKey('pdf-add-surface'),
                          behavior: HitTestBehavior.opaque,
                          onTapUp: (d) => onEmptyTap(d.localPosition.dx / w, d.localPosition.dy / h),
                        ),
                      ),
                    if (mode == _Mode.edit)
                      for (var i = 0; i < info.lines.length; i++) _line(i, w, h, pxPerPt),
                    for (var i = 0; i < edits.added.length; i++)
                      if (edits.added[i].page == index) _added(i, edits.added[i], w, h, pxPerPt),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _line(int i, double w, double h, double pxPerPt) {
    final line = info.lines[i];
    final b = line.box;
    final edited = edits.textOf(index, i);
    final left = b.left * w, top = b.top * h, width = b.width * w, height = b.height * h;
    Widget content;
    if (edited == null) {
      content = DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.10),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.35), width: 0.8),
          borderRadius: BorderRadius.circular(2),
        ),
      );
    } else {
      content = DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: edited.isEmpty ? AppColors.danger : AppColors.success, width: 1),
          borderRadius: BorderRadius.circular(2),
        ),
        child: edited.isEmpty
            ? null
            : OverflowBox(
                alignment: AlignmentDirectional.centerStart,
                minWidth: 0,
                maxWidth: double.infinity,
                child: Text(
                  edited,
                  maxLines: 1,
                  softWrap: false,
                  style: _previewStyle(px: line.fontSize * pxPerPt, rgb: line.rgb, bold: line.bold, italic: line.italic, family: line.family),
                ),
              ),
      );
    }
    return Positioned(
      left: left - 2,
      top: top - 2,
      width: width + 4,
      height: height + 4,
      child: GestureDetector(
        key: ValueKey('pdf-line-$index-$i'),
        behavior: HitTestBehavior.opaque,
        onTap: () => onLine(i),
        child: Padding(padding: const EdgeInsets.all(2), child: content),
      ),
    );
  }

  Widget _added(int i, AddedText a, double w, double h, double pxPerPt) {
    final px = a.sizePt * pxPerPt;
    return Positioned(
      left: a.x * w,
      top: a.y * h - px * 0.85,
      child: GestureDetector(
        key: ValueKey('pdf-added-$i'),
        onTap: () => onAdded(i),
        child: DecoratedBox(
          decoration: BoxDecoration(border: Border.all(color: AppColors.success.withValues(alpha: 0.7), width: 0.8)),
          child: Text(
            a.text,
            style: _previewStyle(px: px, rgb: a.rgb, bold: a.bold, italic: a.italic, family: a.family).copyWith(height: 1.2),
          ),
        ),
      ),
    );
  }
}

enum _LineAction { apply, delete, restore }

class _LineResult {
  const _LineResult(this.action, [this.text = '']);
  final _LineAction action;
  final String text;
}

class _LineSheet extends StatefulWidget {
  const _LineSheet({required this.original, required this.current});
  final String original;

  /// The new text when the line was already changed (empty when removed), otherwise null.
  final String? current;

  @override
  State<_LineSheet> createState() => _LineSheetState();
}

class _LineSheetState extends State<_LineSheet> {
  late final _controller = TextEditingController(text: widget.current ?? widget.original);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _bad => unsupportedCharacters(_controller.text);

  @override
  Widget build(BuildContext context) {
    final bad = _bad;
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(AppSpacing.md, 0, AppSpacing.md, MediaQuery.viewInsetsOf(context).bottom + AppSpacing.md),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Change this line', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('The new text is written in a standard font with the same size and colour.', style: TextStyle(fontSize: 12, color: AppColors.inkMuted)),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('pdf-line-field'),
              controller: _controller,
              autofocus: true,
              minLines: 1,
              maxLines: 3,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(errorText: bad.isEmpty ? null : 'These characters cannot be used: $bad'),
            ),
            if (widget.current != null) ...[
              const SizedBox(height: 6),
              Text(
                'In the file: ${widget.original}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 4,
              children: [
                TextButton.icon(
                  key: const ValueKey('pdf-line-delete'),
                  style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                  onPressed: () => Navigator.pop(context, const _LineResult(_LineAction.delete)),
                  icon: const Icon(AppIcons.delete, size: 18),
                  label: const Text('Remove line'),
                ),
                if (widget.current != null)
                  TextButton(
                    key: const ValueKey('pdf-line-restore'),
                    onPressed: () => Navigator.pop(context, const _LineResult(_LineAction.restore)),
                    child: const Text('Restore'),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                const SizedBox(width: 8),
                FilledButton(
                  key: const ValueKey('pdf-line-apply'),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: bad.isEmpty ? () => Navigator.pop(context, _LineResult(_LineAction.apply, _controller.text)) : null,
                  child: const Text('Apply'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The text and look chosen in the Add text sheet; [text] is null when the text should be removed.
class _AddResult {
  const _AddResult(this.text);
  final AddedText? text;
}

const _addColors = [0x000000, 0xC62828, 0x1565C0, 0x2E7D32, 0xEF6C00, 0x6B7280];

class _AddSheet extends StatefulWidget {
  const _AddSheet({required this.initial, this.canDelete = false});
  final AddedText initial;
  final bool canDelete;

  @override
  State<_AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends State<_AddSheet> {
  late final _controller = TextEditingController(text: widget.initial.text);
  late double _size = widget.initial.sizePt.clamp(8.0, 48.0);
  late int _rgb = widget.initial.rgb;
  late bool _bold = widget.initial.bold;
  late bool _italic = widget.initial.italic;
  late String _family = widget.initial.family;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bad = unsupportedCharacters(_controller.text);
    final empty = _controller.text.trim().isEmpty;
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(AppSpacing.md, 0, AppSpacing.md, MediaQuery.viewInsetsOf(context).bottom + AppSpacing.md),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.canDelete ? 'Change added text' : 'Add text', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('pdf-add-field'),
              controller: _controller,
              autofocus: true,
              minLines: 1,
              maxLines: 4,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(hintText: tr('Type here'), errorText: bad.isEmpty ? null : 'These characters cannot be used: $bad'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Size', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                Expanded(
                  child: Slider(
                    key: const ValueKey('pdf-add-size'),
                    min: 8,
                    max: 48,
                    divisions: 40,
                    value: _size,
                    label: '${_size.round()} pt',
                    onChanged: (v) => setState(() => _size = v),
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: Text('${_size.round()} pt', key: const ValueKey('pdf-add-size-label'), style: const TextStyle(fontSize: 13)),
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final c in _addColors)
                  GestureDetector(
                    key: ValueKey('pdf-add-color-${c.toRadixString(16).padLeft(6, '0')}'),
                    onTap: () => setState(() => _rgb = c),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: _colorOf(c),
                        shape: BoxShape.circle,
                        border: Border.all(color: _rgb == c ? AppColors.primary : Colors.black12, width: _rgb == c ? 3 : 1),
                      ),
                    ),
                  ),
                FilterChip(
                  key: const ValueKey('pdf-add-bold'),
                  label: const Icon(AppIcons.bold, size: 16),
                  selected: _bold,
                  onSelected: (v) => setState(() => _bold = v),
                ),
                FilterChip(
                  key: const ValueKey('pdf-add-italic'),
                  label: const Icon(AppIcons.italic, size: 16),
                  selected: _italic,
                  onSelected: (v) => setState(() => _italic = v),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              key: const ValueKey('pdf-add-family'),
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'sans', label: Text('Sans')),
                ButtonSegment(value: 'serif', label: Text('Serif')),
                ButtonSegment(value: 'mono', label: Text('Mono')),
              ],
              selected: {_family},
              onSelectionChanged: (s) => setState(() => _family = s.first),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (widget.canDelete)
                  IconButton(
                    key: const ValueKey('pdf-add-delete'),
                    tooltip: tr('Remove'),
                    color: AppColors.danger,
                    onPressed: () => Navigator.pop(context, const _AddResult(null)),
                    icon: const Icon(AppIcons.delete),
                  ),
                const Spacer(),
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                const SizedBox(width: 8),
                FilledButton(
                  key: const ValueKey('pdf-add-apply'),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: bad.isNotEmpty || empty
                      ? null
                      : () => Navigator.pop(
                          context,
                          _AddResult(
                            AddedText(
                              page: widget.initial.page,
                              x: widget.initial.x,
                              y: widget.initial.y,
                              text: _controller.text,
                              sizePt: _size.roundToDouble(),
                              rgb: _rgb,
                              bold: _bold,
                              italic: _italic,
                              family: _family,
                            ),
                          ),
                        ),
                  child: Text(widget.canDelete ? 'Apply' : 'Add'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
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
import '../../documents/presentation/library_actions.dart';
import '../../documents/presentation/library_picker.dart';
import '../../ocr/domain/ocr_engine.dart';
import '../../ocr/domain/ocr_models.dart';
import '../../reader/data/pdf_text_edit.dart';
import 'pdf_edit_cubit.dart';
import 'pdf_page_renderer.dart';
import 'scan_text.dart';
import 'text_picture.dart';
import '../../../core/widgets/text.dart';
import '../../../core/i18n/tr.dart';

const _pdfMime = 'application/pdf';
const _renderWidth = 1300;

/// Shows a PDF page by page and lets its lines of text be retyped or removed and new text be added. Nothing leaves the phone.
class PdfEditPage extends StatelessWidget {
  const PdfEditPage({super.key, required this.path, this.libraryId, this.workDir = getTemporaryDirectory, this.openRenderer = PdfxPageRenderer.open, this.scanReader});
  final String path;

  /// Finds the lines of text in the picture of a scanned page; by default the on-device text recognition.
  final ScanReader? scanReader;

  /// Set when the file is one kept in the library; saving then puts the new version in its place.
  final String? libraryId;
  final Future<Directory> Function() workDir;
  final Future<PdfPageRenderer> Function(String path) openRenderer;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => PdfEditCubit(workDir: workDir)..open(path),
    child: _EditView(path: path, libraryId: libraryId, openRenderer: openRenderer, workDir: workDir, scanReader: scanReader),
  );
}

enum _Mode { edit, add, mark, picture }

/// Colours offered for drawings.
const _markColors = [0xFFEB3B, 0xFFFFFF, 0x000000, 0xC62828, 0x1565C0, 0x2E7D32];

int _defaultMarkColor(String kind) => switch (kind) {
  'highlight' => 0xFFEB3B,
  'cover' => 0xFFFFFF,
  _ => 0xC62828,
};

class _EditView extends StatefulWidget {
  const _EditView({required this.path, required this.openRenderer, required this.workDir, this.scanReader, this.libraryId});
  final String path;
  final String? libraryId;
  final Future<Directory> Function() workDir;
  final ScanReader? scanReader;
  final Future<PdfPageRenderer> Function(String path) openRenderer;

  @override
  State<_EditView> createState() => _EditViewState();
}

class _EditViewState extends State<_EditView> {
  PdfPageRenderer? _renderer;
  Object? _rendererError;
  final _images = <int, Future<Uint8List>>{};
  final _pages = PageController();
  final _hold = ValueNotifier<bool>(false);
  var _page = 0;
  var _mode = _Mode.edit;
  AddedText? _lastStyle;
  var _markKind = 'highlight';
  var _markRgb = 0xFFEB3B;
  final _scans = <int, List<ScanLine>>{};
  var _scanning = false;
  late String? _libraryId = widget.libraryId;

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
    _hold.dispose();
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
        if (unsupportedCharacters(result.text).isNotEmpty) {
          await _replaceLineWithPicture(page, line, result.text);
        } else {
          cubit.editLine(page, line, result.text);
        }
      case _LineAction.delete:
        cubit.deleteLine(page, line);
      case _LineAction.restore:
        cubit.restoreLine(page, line);
    }
  }

  ScanReader get _reader => widget.scanReader ?? (png, script) async => readScanWithEngine(sl<OcrEngine>(), await widget.workDir(), png, script);

  /// Finds the lines of text on a scanned page with the on-device text recognition, so they can be retyped.
  Future<void> _findScanText(int page) async {
    final script = await showModalBottomSheet<OcrScript>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsetsDirectional.fromSTEB(20, 0, 20, 4),
              child: Text('Find text in this scan', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            for (final sc in OcrScript.values)
              ListTile(
                key: ValueKey('pdf-scan-${sc.name}'),
                title: Text(sc == OcrScript.latin ? 'English and other Latin letters' : 'Hindi, Marathi (Devanagari)'),
                onTap: () => Navigator.pop(context, sc),
              ),
          ],
        ),
      ),
    );
    if (script == null || !mounted) return;
    setState(() => _scanning = true);
    try {
      final png = await _image(page);
      final lines = await _reader(png, script);
      if (!mounted) return;
      setState(() => _scans[page] = lines);
      if (lines.isEmpty) showMessage(context, 'No text was found on this page.');
    } catch (e) {
      if (mounted) showFailure(context, scanFailure(e));
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  /// The cover-up that hides a scanned line, a little larger than the line.
  static AddedMark _coverFor(int page, ScanLine l) => AddedMark(
    page: page,
    kind: 'cover',
    x0: (l.left - 0.004).clamp(0.0, 1.0),
    y0: (l.top - 0.0025).clamp(0.0, 1.0),
    x1: (l.right + 0.004).clamp(0.0, 1.0),
    y1: (l.bottom + 0.0025).clamp(0.0, 1.0),
    rgb: l.background,
  );

  /// Which lines of a scanned page were already retyped, because their cover-up is on the page.
  Set<int> _doneScans(int page, PdfEdits edits) {
    final lines = _scans[page];
    if (lines == null) return const {};
    final done = <int>{};
    for (var j = 0; j < lines.length; j++) {
      final c = _coverFor(page, lines[j]);
      if (edits.marks.any((m) => m.page == page && m.kind == 'cover' && (m.x0 - c.x0).abs() < 1e-6 && (m.y0 - c.y0).abs() < 1e-6 && (m.x1 - c.x1).abs() < 1e-6 && (m.y1 - c.y1).abs() < 1e-6)) {
        done.add(j);
      }
    }
    return done;
  }

  /// Retypes (or removes) a line found in a scan: the old writing is covered with the colour of the paper and the new words go over it.
  Future<void> _retypeScan(int page, int j) async {
    final cubit = context.read<PdfEditCubit>();
    final line = _scans[page]![j];
    final result = await showModalBottomSheet<_LineResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _LineSheet(original: line.text, current: null),
    );
    if (result == null || !mounted || result.action == _LineAction.restore) return;
    final cover = _coverFor(page, line);
    final text = result.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (result.action == _LineAction.delete || text.isEmpty) {
      cubit.addScanEdit(cover);
      return;
    }
    final info = cubit.state.pages[page];
    final heightPt = info.widthPt / info.aspect;
    final sizePt = (line.height * heightPt * 0.72).clamp(6.0, 72.0);
    if (unsupportedCharacters(text).isNotEmpty) {
      final pic = await renderTextPicture(text, sizePt: sizePt, rgb: line.ink);
      if (!mounted) return;
      final w = (pic.widthPt / info.widthPt).clamp(0.02, 1.0);
      final h = pic.heightPt / heightPt;
      cubit.addScanEdit(
        cover,
        picture: AddedPicture(page: page, x: line.left.clamp(0.0, 1 - w), y: (line.top + (line.height - h) / 2).clamp(0.0, (1 - h).clamp(0.0, 1.0)), w: w, bytes: pic.bytes, aspect: pic.aspect),
      );
    } else {
      cubit.addScanEdit(cover, text: AddedText(page: page, x: line.left, y: (line.bottom - 0.2 * line.height).clamp(0.02, 0.99), text: text, sizePt: sizePt.roundToDouble(), rgb: line.ink));
    }
  }

  /// Draws [text] as a picture where the line [line] was, in the size and colour of that line.
  Future<void> _replaceLineWithPicture(int page, int line, String text) async {
    final cubit = context.read<PdfEditCubit>();
    final info = cubit.state.pages[page];
    final l = info.lines[line];
    final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final pic = await renderTextPicture(clean, sizePt: l.fontSize, rgb: l.rgb, bold: l.bold, italic: l.italic, family: l.family);
    if (!mounted) return;
    final heightPt = info.widthPt / info.aspect;
    final w = (pic.widthPt / info.widthPt).clamp(0.02, 1.0);
    final h = pic.heightPt / heightPt;
    final top = l.box.top + (l.box.height - h) / 2;
    cubit.replaceLineWithPicture(page, line, AddedPicture(page: page, x: l.box.left.clamp(0.0, 1 - w), y: top.clamp(0.0, (1 - h).clamp(0.0, 1.0)), w: w, bytes: pic.bytes, aspect: pic.aspect));
  }

  /// Draws added text as a picture when the built-in fonts cannot show it.
  Future<void> _addTextAsPicture(int page, double x, double y, AddedText t) async {
    final cubit = context.read<PdfEditCubit>();
    final info = cubit.state.pages[page];
    final pic = await renderTextPicture(t.text, sizePt: t.sizePt, rgb: t.rgb, bold: t.bold, italic: t.italic, family: t.family);
    if (!mounted) return;
    final heightPt = info.widthPt / info.aspect;
    final w = (pic.widthPt / info.widthPt).clamp(0.02, 1.0);
    final h = pic.heightPt / heightPt;
    cubit.addPicture(AddedPicture(page: page, x: x.clamp(0.0, 1 - w), y: (y - h / 2).clamp(0.0, (1 - h).clamp(0.0, 1.0)), w: w, bytes: pic.bytes, aspect: pic.aspect));
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
    if (unsupportedCharacters(t.text).isNotEmpty) {
      await _addTextAsPicture(page, x, y, t);
      return;
    }
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
    } else if (unsupportedCharacters(result.text!.text).isNotEmpty) {
      final t = result.text!;
      cubit.removeAdded(index);
      await _addTextAsPicture(current.page, current.x, current.y, t);
    } else {
      final t = result.text!;
      cubit.replaceAdded(
        index,
        AddedText(page: current.page, x: current.x, y: current.y, text: t.text, sizePt: t.sizePt, rgb: t.rgb, bold: t.bold, italic: t.italic, family: t.family),
      );
    }
  }

  void _drawMark(int page, double x0, double y0, double x1, double y1) {
    context.read<PdfEditCubit>().addMark(
      AddedMark(page: page, kind: _markKind, x0: x0.clamp(0.0, 1.0), y0: y0.clamp(0.0, 1.0), x1: x1.clamp(0.0, 1.0), y1: y1.clamp(0.0, 1.0), rgb: _markRgb, widthPt: _markKind == 'line' ? 3 : 2),
    );
  }

  Future<void> _editMark(int index) async {
    final cubit = context.read<PdfEditCubit>();
    final current = cubit.state.edits.marks[index];
    final result = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (_) => _MarkSheet(rgb: current.rgb),
    );
    if (result == null || !mounted) return;
    if (result < 0) {
      cubit.removeMark(index);
    } else {
      cubit.replaceMark(
        index,
        AddedMark(page: current.page, kind: current.kind, x0: current.x0, y0: current.y0, x1: current.x1, y1: current.y1, rgb: result, widthPt: current.widthPt),
      );
    }
  }

  Future<void> _addPicture(int page, double x, double y) async {
    final cubit = context.read<PdfEditCubit>();
    try {
      final picked = await pickFilePaths(context, type: FileType.image);
      final path = picked.isEmpty ? null : picked.first;
      if (path == null || !mounted) return;
      final bytes = await File(path).readAsBytes();
      final size = await _pictureSize(bytes);
      if (size == null || !mounted) {
        if (mounted) showMessage(context, 'That picture could not be added.');
        return;
      }
      final info = cubit.state.pages[page];
      const w = 0.3;
      final h = w * info.aspect / (size.width / size.height);
      cubit.addPicture(AddedPicture(page: page, x: (x - w / 2).clamp(0.0, 1 - w), y: (y - h / 2).clamp(0.0, (1 - h).clamp(0.0, 1.0)), w: w, bytes: bytes, aspect: size.width / size.height));
    } catch (_) {
      if (mounted) showMessage(context, 'That picture could not be added.');
    }
  }

  Future<Size?> _pictureSize(Uint8List bytes) async {
    try {
      final image = await decodeImageFromList(bytes);
      final size = Size(image.width.toDouble(), image.height.toDouble());
      image.dispose();
      return size.isEmpty ? null : size;
    } catch (_) {
      return null;
    }
  }

  Future<void> _editPicture(int index) async {
    final cubit = context.read<PdfEditCubit>();
    final current = cubit.state.edits.pictures[index];
    final result = await showModalBottomSheet<double>(
      context: context,
      showDragHandle: true,
      builder: (_) => _PictureSheet(width: current.w),
    );
    if (result == null || !mounted) return;
    if (result < 0) {
      cubit.removePicture(index);
    } else {
      final info = cubit.state.pages[current.page];
      final h = result * info.aspect / current.aspect;
      cubit.replacePicture(index, current.copyWith(w: result, x: current.x.clamp(0.0, 1 - result), y: current.y.clamp(0.0, (1 - h).clamp(0.0, 1.0))));
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
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'library') {
      _libraryId = await saveToLibrary(context, path: path, title: cubit.name, existingId: _libraryId) ?? _libraryId;
      return;
    }
    _libraryId = await saveToLibrary(context, path: path, title: cubit.name, existingId: _libraryId, announce: false) ?? _libraryId;
    if (!mounted) return;
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
    final scanned = _scans[_page.clamp(0, state.pages.length - 1)];
    final noText = !info.editable || info.lines.isEmpty;
    final note = scanned != null && scanned.isNotEmpty
        ? 'Tap a framed line to retype it. The old writing is covered with the colour of the paper.'
        : !info.editable
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(AppIcons.info, size: 18, color: Color(0xFF8A6100)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(note, style: const TextStyle(fontSize: 13, color: Color(0xFF5C4300))),
                      ),
                    ],
                  ),
                  if (_scanning)
                    const Padding(padding: EdgeInsets.only(top: 6), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                  else if (noText && (scanned == null || scanned.isEmpty))
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: OutlinedButton(
                        key: const ValueKey('pdf-scan-find'),
                        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 38), padding: const EdgeInsets.symmetric(horizontal: 12)),
                        onPressed: () => _findScanText(_page.clamp(0, state.pages.length - 1)),
                        child: const Text('Find text in this scan'),
                      ),
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
              markKind: _markKind,
              markRgb: _markRgb,
              hold: _hold,
              scan: _scans[i],
              scanDone: _doneScans(i, state.edits),
              onScan: (j) => _retypeScan(i, j),
              image: _image(i),
              onLine: (line) => _editLine(i, line),
              onAdded: _editAdded,
              onMoveAdded: (index, x, y) => context.read<PdfEditCubit>().moveAdded(index, x, y),
              onEmptyTap: (x, y) => _mode == _Mode.picture ? _addPicture(i, x, y) : _addText(i, x, y),
              onDraw: (x0, y0, x1, y1) => _drawMark(i, x0, y0, x1, y1),
              onMark: _editMark,
              onPicture: _editPicture,
              onMovePicture: (index, x, y) {
                final cubit = context.read<PdfEditCubit>();
                final pic = cubit.state.edits.pictures[index];
                final h = pic.w * cubit.state.pages[pic.page].aspect / pic.aspect;
                cubit.replacePicture(index, pic.copyWith(x: x.clamp(0.0, 1 - pic.w), y: y.clamp(0.0, (1 - h).clamp(0.0, 1.0))));
              },
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
              if (_mode == _Mode.mark) _markTools(),
              SegmentedButton<_Mode>(
                key: const ValueKey('pdf-mode'),
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact, padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 4))),
                segments: const [
                  ButtonSegment(
                    value: _Mode.edit,
                    icon: Icon(AppIcons.edit, size: 16),
                    label: Text('Edit text', key: ValueKey('pdf-mode-edit'), maxLines: 1, style: TextStyle(fontSize: 12)),
                  ),
                  ButtonSegment(
                    value: _Mode.add,
                    icon: Icon(AppIcons.add, size: 16),
                    label: Text('Add text', key: ValueKey('pdf-mode-add'), maxLines: 1, style: TextStyle(fontSize: 12)),
                  ),
                  ButtonSegment(
                    value: _Mode.mark,
                    icon: Icon(Icons.draw_outlined, size: 16),
                    label: Text('Mark', key: ValueKey('pdf-mode-mark'), maxLines: 1, style: TextStyle(fontSize: 12)),
                  ),
                  ButtonSegment(
                    value: _Mode.picture,
                    icon: Icon(AppIcons.gallery, size: 16),
                    label: Text('Picture', key: ValueKey('pdf-mode-picture'), maxLines: 1, style: TextStyle(fontSize: 12)),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => setState(() => _mode = s.first),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      switch (_mode) {
                        _Mode.edit => 'Tap a line to change or remove it. Pinch to zoom.',
                        _Mode.add => 'Tap the page where the new text should go.',
                        _Mode.mark => 'Drag on the page to draw. Tap a drawing to change or remove it.',
                        _Mode.picture => 'Tap the page where the picture should go. Drag a picture to move it.',
                      },
                      key: const ValueKey('pdf-hint'),
                      style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _markTools() {
    const kinds = [('highlight', 'Highlight'), ('cover', 'Cover up'), ('box', 'Box'), ('line', 'Line')];
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final k in kinds)
            ChoiceChip(
              key: ValueKey('pdf-mark-${k.$1}'),
              label: Text(k.$2),
              selected: _markKind == k.$1,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => setState(() {
                _markKind = k.$1;
                _markRgb = _defaultMarkColor(k.$1);
              }),
            ),
          for (final c in _markColors)
            GestureDetector(
              key: ValueKey('pdf-mark-color-${c.toRadixString(16).padLeft(6, '0')}'),
              onTap: () => setState(() => _markRgb = c),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: _colorOf(c),
                  shape: BoxShape.circle,
                  border: Border.all(color: _markRgb == c ? AppColors.primary : Colors.black26, width: _markRgb == c ? 3 : 1),
                ),
              ),
            ),
        ],
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
    required this.onMoveAdded,
    required this.onEmptyTap,
    required this.onDraw,
    required this.onMark,
    required this.onPicture,
    required this.onMovePicture,
    required this.markKind,
    required this.markRgb,
    required this.hold,
    required this.scan,
    required this.scanDone,
    required this.onScan,
  });

  /// Lines found in a scan of this page, which can be retyped; null when the page was not read.
  final List<ScanLine>? scan;
  final Set<int> scanDone;
  final void Function(int line) onScan;

  /// True while a finger is dragging something on the page, so the page itself does not pan.
  final ValueNotifier<bool> hold;
  final String markKind;
  final int markRgb;
  final int index;
  final PdfPageEditInfo info;
  final PdfEdits edits;
  final _Mode mode;
  final Future<Uint8List> image;
  final void Function(int line) onLine;
  final void Function(int index) onAdded;
  final void Function(int index, double x, double y) onMoveAdded;
  final void Function(double x, double y) onEmptyTap;
  final void Function(double x0, double y0, double x1, double y1) onDraw;
  final void Function(int index) onMark;
  final void Function(int index) onPicture;
  final void Function(int index, double x, double y) onMovePicture;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final maxW = c.maxWidth - 16, maxH = c.maxHeight - 16;
        final w = (maxH * info.aspect < maxW ? maxH * info.aspect : maxW).clamp(1.0, 100000.0);
        final h = w / info.aspect;
        final pxPerPt = w / info.widthPt;
        return ValueListenableBuilder<bool>(
          valueListenable: hold,
          builder: (context, holding, child) => InteractiveViewer(maxScale: 5, panEnabled: mode != _Mode.mark && !holding, child: child!),
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
                    for (var i = 0; i < edits.marks.length; i++)
                      if (edits.marks[i].page == index) Positioned.fill(child: IgnorePointer(child: CustomPaint(key: ValueKey('pdf-mark-$i'), painter: _MarkPainter(edits.marks[i], pxPerPt)))),
                    if (mode == _Mode.add || mode == _Mode.picture)
                      Positioned.fill(
                        child: GestureDetector(
                          key: const ValueKey('pdf-add-surface'),
                          behavior: HitTestBehavior.opaque,
                          onTapUp: (d) => onEmptyTap(d.localPosition.dx / w, d.localPosition.dy / h),
                        ),
                      ),
                    for (var i = 0; i < edits.pictures.length; i++)
                      if (edits.pictures[i].page == index) _picture(i, edits.pictures[i], w, h),
                    if (mode == _Mode.mark)
                      Positioned.fill(
                        child: _MarkLayer(
                          key: const ValueKey('pdf-mark-surface'),
                          width: w,
                          height: h,
                          pxPerPt: pxPerPt,
                          page: index,
                          kind: markKind,
                          rgb: markRgb,
                          onDraw: onDraw,
                          onTapAt: (x, y) {
                            for (var i = edits.marks.length - 1; i >= 0; i--) {
                              final m = edits.marks[i];
                              if (m.page != index) continue;
                              final pad = m.kind == 'line' ? 0.02 : 0.0;
                              final l = (m.x0 < m.x1 ? m.x0 : m.x1) - pad, r = (m.x0 < m.x1 ? m.x1 : m.x0) + pad;
                              final t = (m.y0 < m.y1 ? m.y0 : m.y1) - pad, b = (m.y0 < m.y1 ? m.y1 : m.y0) + pad;
                              if (x >= l && x <= r && y >= t && y <= b) {
                                onMark(i);
                                return;
                              }
                            }
                          },
                        ),
                      ),
                    if (mode == _Mode.edit && scan != null)
                      for (var j = 0; j < scan!.length; j++)
                        if (!scanDone.contains(j)) _scanBox(j, scan![j], w, h),
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

  Widget _picture(int i, AddedPicture pic, double w, double h) {
    final pw = pic.w * w, ph = pw / pic.aspect;
    final interactive = mode == _Mode.picture;
    final child = DecoratedBox(
      decoration: BoxDecoration(border: interactive ? Border.all(color: AppColors.success.withValues(alpha: 0.8), width: 1) : null),
      child: Image.memory(pic.bytes, key: ValueKey('pdf-picture-image-$i'), width: pw, height: ph, fit: BoxFit.fill, cacheWidth: 700, gaplessPlayback: true),
    );
    return Positioned(
      left: pic.x * w,
      top: pic.y * h,
      width: pw,
      height: ph,
      child: interactive
          ? _Draggable(key: ValueKey('pdf-picture-$i'), onHold: (v) => hold.value = v, onTap: () => onPicture(i), onMoved: (dx, dy) => onMovePicture(i, pic.x + dx / w, pic.y + dy / h), child: child)
          : IgnorePointer(child: child),
    );
  }

  Widget _scanBox(int j, ScanLine l, double w, double h) => Positioned(
    left: l.left * w - 2,
    top: l.top * h - 2,
    width: l.width * w + 4,
    height: l.height * h + 4,
    child: GestureDetector(
      key: ValueKey('pdf-scan-$index-$j'),
      behavior: HitTestBehavior.opaque,
      onTap: () => onScan(j),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFFFFB300).withValues(alpha: 0.12),
            border: Border.all(color: const Color(0xFFFFB300).withValues(alpha: 0.8), width: 0.8),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    ),
  );

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
      child: _Draggable(
        key: ValueKey('pdf-added-$i'),
        onHold: (v) => hold.value = v,
        onTap: () => onAdded(i),
        onMoved: (dx, dy) => onMoveAdded(i, a.x + dx / w, a.y + dy / h),
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

/// How far a finger may move and still count as a tap.
const _tapSlop = 12.0;

/// Follows a finger while it drags and reports how far it went in pixels; a touch that stays put is a tap. Reads the touches directly so that
/// the zoom and pan of the page do not take the drag, and tells the page to hold still while a finger is on it.
class _Draggable extends StatefulWidget {
  const _Draggable({super.key, required this.child, required this.onTap, required this.onMoved, this.onHold});
  final Widget child;
  final VoidCallback onTap;
  final void Function(double dx, double dy) onMoved;
  final void Function(bool holding)? onHold;

  @override
  State<_Draggable> createState() => _DraggableState();
}

class _DraggableState extends State<_Draggable> {
  final _pointers = <int>{};
  Offset _offset = Offset.zero;
  var _dragging = false;

  void _end({required bool cancel}) {
    final moved = _offset;
    final dragged = _dragging;
    _pointers.clear();
    setState(() {
      _offset = Offset.zero;
      _dragging = false;
    });
    widget.onHold?.call(false);
    if (cancel) return;
    if (dragged) {
      widget.onMoved(moved.dx, moved.dy);
    } else {
      widget.onTap();
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.opaque,
    onPointerDown: (e) {
      _pointers.add(e.pointer);
      if (_pointers.length == 1) {
        _offset = Offset.zero;
        _dragging = false;
        widget.onHold?.call(true);
      } else {
        // A second finger means zooming, not moving.
        setState(() {
          _offset = Offset.zero;
          _dragging = false;
        });
      }
    },
    onPointerMove: (e) {
      if (_pointers.length != 1 || !_pointers.contains(e.pointer)) return;
      final next = _offset + e.delta;
      setState(() {
        _offset = next;
        if (next.distance > _tapSlop) _dragging = true;
      });
    },
    onPointerUp: (e) {
      if (!_pointers.remove(e.pointer)) return;
      if (_pointers.isEmpty) _end(cancel: false);
    },
    onPointerCancel: (e) {
      _pointers.remove(e.pointer);
      if (_pointers.isEmpty) _end(cancel: true);
    },
    child: Transform.translate(offset: _dragging ? _offset : Offset.zero, child: widget.child),
  );
}

/// Takes the drag that draws a highlight, cover-up, box or line, and shows it while it is drawn. A tap on a drawing is passed on.
class _MarkLayer extends StatefulWidget {
  const _MarkLayer({
    super.key,
    required this.width,
    required this.height,
    required this.pxPerPt,
    required this.page,
    required this.kind,
    required this.rgb,
    required this.onDraw,
    required this.onTapAt,
  });
  final double width;
  final double height;
  final double pxPerPt;
  final int page;
  final String kind;
  final int rgb;
  final void Function(double x0, double y0, double x1, double y1) onDraw;
  final void Function(double x, double y) onTapAt;

  @override
  State<_MarkLayer> createState() => _MarkLayerState();
}

class _MarkLayerState extends State<_MarkLayer> {
  final _pointers = <int>{};
  Offset? _start;
  Offset? _from;
  Offset? _to;
  var _drawing = false;

  Offset _share(Offset o) => Offset((o.dx / widget.width).clamp(0.0, 1.0), (o.dy / widget.height).clamp(0.0, 1.0));

  void _reset() => setState(() {
    _start = null;
    _from = _to = null;
    _drawing = false;
  });

  @override
  Widget build(BuildContext context) {
    final a = _from, b = _to;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) {
        _pointers.add(e.pointer);
        if (_pointers.length == 1) {
          _start = e.localPosition;
          _from = _share(e.localPosition);
        } else {
          _reset();
        }
      },
      onPointerMove: (e) {
        final start = _start;
        if (_pointers.length != 1 || start == null) return;
        if (!_drawing && (e.localPosition - start).distance <= _tapSlop) return;
        setState(() {
          _drawing = true;
          _to = _share(e.localPosition);
        });
      },
      onPointerUp: (e) {
        if (!_pointers.remove(e.pointer)) return;
        final start = _start;
        if (start != null && _pointers.isEmpty) {
          final from = _from, to = _to;
          if (_drawing && from != null && to != null) {
            widget.onDraw(from.dx, from.dy, to.dx, to.dy);
          } else if (!_drawing) {
            widget.onTapAt(start.dx / widget.width, start.dy / widget.height);
          }
        }
        if (_pointers.isEmpty) _reset();
      },
      onPointerCancel: (e) {
        _pointers.remove(e.pointer);
        if (_pointers.isEmpty) _reset();
      },
      child: !_drawing || a == null || b == null
          ? const SizedBox.expand()
          : CustomPaint(
              painter: _MarkPainter(
                AddedMark(page: widget.page, kind: widget.kind, x0: a.dx, y0: a.dy, x1: b.dx, y1: b.dy, rgb: widget.rgb, widthPt: widget.kind == 'line' ? 3 : 2),
                widget.pxPerPt,
              ),
              child: const SizedBox.expand(),
            ),
    );
  }
}

/// Draws one drawing the way it will look in the file.
class _MarkPainter extends CustomPainter {
  _MarkPainter(this.mark, this.pxPerPt);
  final AddedMark mark;
  final double pxPerPt;

  @override
  void paint(Canvas canvas, Size size) {
    final m = mark;
    final a = Offset(m.x0 * size.width, m.y0 * size.height), b = Offset(m.x1 * size.width, m.y1 * size.height);
    final rect = Rect.fromPoints(a, b);
    final color = _colorOf(m.rgb);
    switch (m.kind) {
      case 'highlight':
        canvas.drawRect(rect, Paint()..color = color.withValues(alpha: 0.5));
      case 'cover':
        canvas.drawRect(rect, Paint()..color = color);
      case 'box':
        canvas.drawRect(rect, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = m.widthPt * pxPerPt);
      case 'line':
        canvas.drawLine(a, b, Paint()..color = color..strokeWidth = m.widthPt * pxPerPt..strokeCap = StrokeCap.round);
    }
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.mark != mark || old.pxPerPt != pxPerPt;
}

/// Choose a colour for a drawing, or remove it.
class _MarkSheet extends StatelessWidget {
  const _MarkSheet({required this.rgb});
  final int rgb;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Drawing', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              for (final c in _markColors)
                GestureDetector(
                  key: ValueKey('pdf-marksheet-color-${c.toRadixString(16).padLeft(6, '0')}'),
                  onTap: () => Navigator.pop(context, c),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _colorOf(c),
                      shape: BoxShape.circle,
                      border: Border.all(color: rgb == c ? AppColors.primary : Colors.black26, width: rgb == c ? 3 : 1),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            key: const ValueKey('pdf-mark-delete'),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, -1),
            icon: const Icon(AppIcons.delete, size: 18),
            label: const Text('Remove'),
          ),
        ],
      ),
    ),
  );
}

/// Change the width of a picture on the page, or remove it.
class _PictureSheet extends StatefulWidget {
  const _PictureSheet({required this.width});
  final double width;

  @override
  State<_PictureSheet> createState() => _PictureSheetState();
}

class _PictureSheetState extends State<_PictureSheet> {
  late double _w = widget.width.clamp(0.05, 1.0);

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Picture', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          Row(
            children: [
              const Text('Size', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              Expanded(
                child: Slider(key: const ValueKey('pdf-picture-size'), min: 0.05, max: 1, value: _w, onChanged: (v) => setState(() => _w = v)),
              ),
              SizedBox(width: 44, child: Text('${(_w * 100).round()}%', style: const TextStyle(fontSize: 13))),
            ],
          ),
          Row(
            children: [
              TextButton.icon(
                key: const ValueKey('pdf-picture-delete'),
                style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                onPressed: () => Navigator.pop(context, -1.0),
                icon: const Icon(AppIcons.delete, size: 18),
                label: const Text('Remove'),
              ),
              const Spacer(),
              FilledButton(
                key: const ValueKey('pdf-picture-apply'),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: () => Navigator.pop(context, _w),
                child: const Text('Apply'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
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
              decoration: InputDecoration(helperMaxLines: 3, helperText: bad.isEmpty ? null : tr(_pictureNote)),
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
                  onPressed: () => Navigator.pop(context, _LineResult(_LineAction.apply, _controller.text)),
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

const _pictureNote = 'These letters are not in the built-in fonts, so the text is placed as a picture. It looks the same but cannot be selected or searched.';

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
              decoration: InputDecoration(hintText: tr('Type here'), helperMaxLines: 3, helperText: bad.isEmpty ? null : tr(_pictureNote)),
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
                  onPressed: empty
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

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../../app/di.dart';
import '../../../core/error/failures.dart';
import '../../../core/i18n/tr.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/utils/region.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/text.dart';
import '../../documents/presentation/widgets/document_widgets.dart' show confirmDestructive;
import '../../export/domain/repositories/export_repository.dart';
import '../../ocr/domain/ocr_engine.dart';
import '../../ocr/domain/ocr_models.dart';
import '../../photo_tools/domain/watermark_service.dart';
import '../data/safe_id_processor.dart';
import '../domain/safe_id.dart';

enum SafeIdSource { camera, gallery, files }

Future<String?> _pickPicture(SafeIdSource source) async {
  try {
    if (source == SafeIdSource.files) {
      final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['jpg', 'jpeg', 'png']);
      return picked.isEmpty ? null : picked.first.path;
    }
    final file = await ImagePicker().pickImage(source: source == SafeIdSource.camera ? ImageSource.camera : ImageSource.gallery);
    return file?.path;
  } on Object {
    throw const PermissionFailure('The camera or the photo library is unavailable.');
  }
}

enum _From { found, line, manual }

class _Cover {
  _Cover(this.box, this.label, this.from, {required this.covered});
  final CoverBox box;
  final String label;
  final _From from;
  bool covered;
}

IdKind _defaultKind() => switch (Region.toolRegion) {
  ToolRegion.india => IdKind.aadhaar,
  ToolRegion.usa => IdKind.usSsn,
  ToolRegion.gulf => IdKind.saudiId,
  _ => IdKind.other,
};

/// A copy of an ID that is safe to hand over: what the other side does not need is covered with solid black, and a repeated mark says
/// what the copy is for and when it was made. The picture is read on this phone and the original is not changed.
class SafeIdPage extends StatefulWidget {
  const SafeIdPage({super.key, this.pick = _pickPicture, this.service, this.ocr, this.workDir = getTemporaryDirectory, this.initialPath});
  final Future<String?> Function(SafeIdSource source) pick;
  final SafeIdService? service;
  final OcrEngine? ocr;
  final Future<Directory> Function() workDir;

  /// A picture to start from, such as a scan that was just saved.
  final String? initialPath;

  @override
  State<SafeIdPage> createState() => _SafeIdPageState();
}

class _SafeIdPageState extends State<SafeIdPage> {
  late final SafeIdService _service = widget.service ?? SafeIdProcessor(watermark: sl<WatermarkService>());
  late final OcrEngine _ocr = widget.ocr ?? sl<OcrEngine>();
  final _purpose = TextEditingController(text: safeIdPurposes.first);
  PreparedId? _work;
  OcrPageResult? _page;
  IdKind _kind = _defaultKind();
  final _covers = <_Cover>[];
  bool _draw = false;
  bool _mark = true;
  bool _pdf = false;
  bool _reading = false;
  bool _busy = false;
  bool _readFailed = false;
  WatermarkOutput? _output;
  Offset? _dragStart;
  Offset? _dragNow;

  @override
  void initState() {
    super.initState();
    if (widget.initialPath != null) WidgetsBinding.instance.addPostFrameCallback((_) => _open(widget.initialPath!));
  }

  @override
  void dispose() {
    _purpose.dispose();
    _deleteWork();
    super.dispose();
  }

  /// The working copy shows the whole ID, so it is not kept.
  void _deleteWork() {
    final w = _work;
    _work = null;
    if (w != null) {
      try {
        File(w.path).deleteSync();
      } on Object {
        // Already gone.
      }
    }
  }

  Future<void> _choose(SafeIdSource source) async {
    String? path;
    try {
      path = await widget.pick(source);
    } on Failure catch (f) {
      if (mounted) showFailure(context, f);
      return;
    }
    if (path != null && mounted) await _open(path);
  }

  Future<void> _open(String path) async {
    setState(() {
      _reading = true;
      _output = null;
    });
    final dir = (await widget.workDir()).path;
    final prepared = await _service.prepare(sourcePath: path, outputDir: dir);
    if (!mounted) return;
    final failure = prepared.failureOrNull;
    if (failure != null) {
      setState(() => _reading = false);
      showFailure(context, failure);
      return;
    }
    _deleteWork();
    final work = prepared.valueOrNull!;
    final read = await _ocr.recognize(work.path, OcrScript.latin);
    if (!mounted) return;
    setState(() {
      _work = work;
      _page = read.valueOrNull;
      _readFailed = read.failureOrNull != null;
      _covers.clear();
      _rebuild();
      _reading = false;
    });
  }

  /// The lines and the numbers worth covering for the chosen kind of ID; boxes the person drew are kept.
  void _rebuild() {
    final page = _page;
    final manual = _covers.where((c) => c.from == _From.manual).toList();
    final lines = {for (final c in _covers.where((c) => c.from == _From.line)) c.box: c.covered};
    _covers.clear();
    if (page != null && page.width > 0 && page.height > 0) {
      CoverBox share(double l, double t, double r, double b) => CoverBox.fromCorners(l / page.width, t / page.height, r / page.width, b / page.height);
      for (final block in page.blocks) {
        for (final line in block.lines) {
          final box = share(line.left, line.top, line.right, line.bottom);
          _covers.add(_Cover(box, 'Text', _From.line, covered: lines[box] ?? false));
        }
      }
      for (final f in findSensitive(page, _kind)) {
        _covers.add(_Cover(share(f.left, f.top, f.right, f.bottom), f.label, _From.found, covered: f.covered));
      }
    }
    _covers.addAll(manual);
  }

  _Cover? _hit(double x, double y) {
    _Cover? best;
    for (final c in _covers) {
      if (!c.box.contains(x, y)) continue;
      final rank = (c.from == _From.manual ? 0 : (c.from == _From.found ? 1 : 2));
      final bestRank = best == null ? 9 : (best.from == _From.manual ? 0 : (best.from == _From.found ? 1 : 2));
      if (best == null || rank < bestRank || (rank == bestRank && c.box.width * c.box.height < best.box.width * best.box.height)) best = c;
    }
    return best;
  }

  void _tap(Offset p, Size size) {
    final hit = _hit(p.dx / size.width, p.dy / size.height);
    if (hit == null) return;
    setState(() {
      _output = null;
      if (hit.from == _From.manual) {
        _covers.remove(hit);
      } else {
        hit.covered = !hit.covered;
      }
    });
  }

  void _endDrag(Size size) {
    final a = _dragStart, b = _dragNow;
    setState(() {
      _dragStart = null;
      _dragNow = null;
    });
    if (a == null || b == null) return;
    final box = CoverBox.fromCorners(a.dx / size.width, a.dy / size.height, b.dx / size.width, b.dy / size.height);
    if (box.width < 0.01 || box.height < 0.01) return;
    setState(() {
      _output = null;
      _covers.add(_Cover(box, 'Box', _From.manual, covered: true));
    });
  }

  int get _count => _covers.where((c) => c.covered).length;

  Future<void> _create() async {
    final work = _work;
    if (work == null) return;
    if (_count == 0) {
      final go = await confirmDestructive(
        context,
        title: 'Nothing is covered',
        message: 'The copy will show everything on the ID. Make it anyway?',
        action: 'Make it',
      );
      if (!go || !mounted) return;
    }
    setState(() => _busy = true);
    final dir = (await widget.workDir()).path;
    final result = await _service.make(
      workPath: work.path,
      boxes: [
        for (final c in _covers)
          if (c.covered) c.box,
      ],
      markText: _mark ? safeIdMarkText(_purpose.text) : null,
      pdf: _pdf,
      name: 'SafeID_${_kind.name}',
      outputDir: dir,
    );
    if (!mounted) return;
    final failure = result.failureOrNull;
    setState(() {
      _busy = false;
      if (failure == null) _output = result.valueOrNull;
    });
    if (failure != null) {
      showFailure(context, failure);
    } else {
      // The copy is made, so the working picture, which still shows everything, is not needed.
      _deleteWork();
      setState(() {
        _work = null;
        _page = null;
        _covers.clear();
      });
    }
  }

  Future<void> _share(WatermarkOutput o) async {
    final failure = (await sl<ShareService>().shareFiles(paths: [o.path], mimeType: o.mimeType)).failureOrNull;
    if (failure != null && mounted) showFailure(context, failure);
  }

  Future<void> _gallery(WatermarkOutput o) async {
    final failure = (await sl<SaveService>().saveImagesToGallery([o.path])).failureOrNull;
    if (!mounted) return;
    failure != null ? showFailure(context, failure) : showMessage(context, 'Saved to your gallery');
  }

  Future<void> _files(WatermarkOutput o) async {
    final result = await sl<SaveService>().saveToFiles(sourcePath: o.path, fileName: o.name, mimeType: o.mimeType);
    if (!mounted) return;
    final failure = result.failureOrNull;
    if (failure != null) {
      showFailure(context, failure);
    } else if (result.valueOrNull == true) {
      showMessage(context, 'Saved');
    }
  }

  Widget _preview(PreparedId work) => LayoutBuilder(
    builder: (context, box) {
      final aspect = work.width / work.height;
      final w = (box.maxWidth).clamp(0.0, 520.0 * aspect < box.maxWidth ? 520.0 * aspect : box.maxWidth);
      final size = Size(w, w / aspect);
      return Center(
        child: SizedBox(
          key: const ValueKey('safeid-preview'),
          width: size.width,
          height: size.height,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => _tap(d.localPosition, size),
            onPanStart: _draw ? (d) => setState(() => _dragStart = _dragNow = d.localPosition) : null,
            onPanUpdate: _draw ? (d) => setState(() => _dragNow = d.localPosition) : null,
            onPanEnd: _draw ? (_) => _endDrag(size) : null,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.file(
                  File(work.path),
                  fit: BoxFit.fill,
                  errorBuilder: (_, _, _) => const ColoredBox(color: AppColors.border),
                ),
                CustomPaint(painter: _CoverPainter(_covers, _dragStart, _dragNow, size)),
              ],
            ),
          ),
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final work = _work;
    final out = _output;
    return Scaffold(
      appBar: AppBar(title: const Text('Safe ID copy')),
      body: ListView(
        padding: contentPadding(context).copyWith(bottom: AppSpacing.xl),
        children: [
          const Text(
            'Make a copy of an ID that is safe to hand over. What the other side does not need is covered with solid black, and a repeated mark says what the copy is for. It is made on this phone and your original is not changed.',
            style: TextStyle(fontSize: 13, color: AppColors.inkMuted, height: 1.4),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              FilledButton.icon(
                key: const ValueKey('safeid-pick-camera'),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: _reading || _busy ? null : () => _choose(SafeIdSource.camera),
                icon: const Icon(AppIcons.camera, size: 18),
                label: const Text('Take a photo'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('safeid-pick-gallery'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: _reading || _busy ? null : () => _choose(SafeIdSource.gallery),
                icon: const Icon(AppIcons.gallery, size: 18),
                label: const Text('Gallery'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('safeid-pick-files'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: _reading || _busy ? null : () => _choose(SafeIdSource.files),
                icon: const Icon(AppIcons.importFile, size: 18),
                label: const Text('Files'),
              ),
            ],
          ),
          if (_reading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Center(child: CircularProgressIndicator(key: ValueKey('safeid-reading'))),
            ),
          if (work != null) ...[
            const SizedBox(height: AppSpacing.lg),
            const Text('What is it?', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final k in IdKind.values)
                  ChoiceChip(
                    key: ValueKey('safeid-kind-${k.name}'),
                    label: Text(k.label),
                    selected: _kind == k,
                    onSelected: (_) => setState(() {
                      _kind = k;
                      _output = null;
                      _rebuild();
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _kind.hint,
              key: const ValueKey('safeid-hint'),
              style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted, height: 1.4),
            ),
            if (_readFailed)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'The text on the picture could not be read, so nothing is found for you. Draw boxes over what must be hidden.',
                  key: ValueKey('safeid-read-failed'),
                  style: TextStyle(fontSize: 12.5, color: AppColors.danger, height: 1.4),
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            SegmentedButton<bool>(
              key: const ValueKey('safeid-mode'),
              segments: const [
                ButtonSegment(value: false, label: Text('Tap text'), icon: Icon(AppIcons.markRedact, size: 16)),
                ButtonSegment(value: true, label: Text('Draw a box'), icon: Icon(AppIcons.edit, size: 16)),
              ],
              selected: {_draw},
              onSelectionChanged: (s) => setState(() => _draw = s.first),
            ),
            const SizedBox(height: 6),
            Text(
              _draw
                  ? 'Drag over anything to cover it. Tap a box you drew to remove it.'
                  : 'Tap a line to cover it, and tap again to show it. Black is covered.',
              style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
            ),
            const SizedBox(height: AppSpacing.sm),
            _preview(work),
            const SizedBox(height: 6),
            Text(
              _count == 1 ? tr('1 area covered') : trf('{n} areas covered', {'n': _count}),
              key: const ValueKey('safeid-summary'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.md),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      key: const ValueKey('safeid-mark'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Add a repeated mark'),
                      subtitle: const Text('Says what the copy is for and the date, all over it'),
                      value: _mark,
                      onChanged: (v) => setState(() {
                        _mark = v;
                        _output = null;
                      }),
                    ),
                    if (_mark) ...[
                      TextField(
                        key: const ValueKey('safeid-purpose'),
                        controller: _purpose,
                        maxLength: 60,
                        onChanged: (_) => setState(() => _output = null),
                        decoration: InputDecoration(labelText: tr('What is the copy for?'), counterText: ''),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final (i, s) in safeIdPurposes.indexed)
                            ActionChip(
                              key: ValueKey('safeid-preset-$i'),
                              label: Text(s),
                              onPressed: () => setState(() {
                                _purpose.text = s;
                                _output = null;
                              }),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        trf('The mark will read: {text}', {'text': safeIdMarkText(_purpose.text).replaceAll('{date}', 'the date')}),
                        key: const ValueKey('safeid-mark-text'),
                        style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    SegmentedButton<bool>(
                      key: const ValueKey('safeid-format'),
                      segments: const [
                        ButtonSegment(value: false, label: Text('Picture')),
                        ButtonSegment(value: true, label: Text('PDF')),
                      ],
                      selected: {_pdf},
                      onSelectionChanged: (s) => setState(() {
                        _pdf = s.first;
                        _output = null;
                      }),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            FilledButton.icon(
              key: const ValueKey('safeid-create'),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
              onPressed: _busy ? null : _create,
              icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(AppIcons.shield, size: 20),
              label: const Text('Make the safe copy'),
            ),
          ],
          if (out != null) ...[
            const SizedBox(height: AppSpacing.lg),
            Card(
              key: const ValueKey('safeid-result'),
              margin: EdgeInsets.zero,
              color: AppColors.primarySoft,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Your safe copy is ready', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    const Text(
                      'The picture that showed everything has been deleted from this phone\'s working space. Your original is untouched.',
                      style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted, height: 1.4),
                    ),
                    if (!out.isPdf) ...[
                      const SizedBox(height: AppSpacing.sm),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppSpacing.radius),
                        child: Image.file(File(out.path), height: 160, fit: BoxFit.contain, errorBuilder: (_, _, _) => const SizedBox.shrink()),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        FilledButton.icon(
                          key: const ValueKey('safeid-share'),
                          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                          onPressed: () => _share(out),
                          icon: const Icon(AppIcons.share, size: 18),
                          label: const Text('Share'),
                        ),
                        if (!out.isPdf)
                          OutlinedButton.icon(
                            key: const ValueKey('safeid-gallery'),
                            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                            onPressed: () => _gallery(out),
                            icon: const Icon(AppIcons.download, size: 18),
                            label: const Text('Save to gallery'),
                          ),
                        OutlinedButton.icon(
                          key: const ValueKey('safeid-files'),
                          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                          onPressed: () => _files(out),
                          icon: const Icon(AppIcons.storage, size: 18),
                          label: const Text('Save to Files'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CoverPainter extends CustomPainter {
  _CoverPainter(this.covers, this.dragStart, this.dragNow, this.size);
  final List<_Cover> covers;
  final Offset? dragStart;
  final Offset? dragNow;
  final Size size;

  Rect _rect(CoverBox b) => Rect.fromLTRB(b.left * size.width, b.top * size.height, b.right * size.width, b.bottom * size.height);

  @override
  void paint(Canvas canvas, Size _) {
    final fill = Paint()..color = const Color(0xFF000000);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x552563EB);
    final found = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFFF59E0B);
    for (final c in covers) {
      final r = _rect(c.box);
      if (c.covered) {
        canvas.drawRect(r, fill);
      } else {
        canvas.drawRect(r, c.from == _From.found ? found : line);
      }
    }
    if (dragStart != null && dragNow != null) {
      canvas.drawRect(
        Rect.fromPoints(dragStart!, dragNow!),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xFFDC2626),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CoverPainter old) => true;
}

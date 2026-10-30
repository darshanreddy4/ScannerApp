import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../../app/di.dart';
import '../../../core/error/failures.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/feedback.dart';
import '../../export/domain/repositories/export_repository.dart' show ShareService;
import '../../../core/widgets/responsive.dart';
import '../../documents/presentation/widgets/document_widgets.dart' show confirmDestructive;
import '../data/signature_processor.dart' show smoothPath;
import '../domain/signature.dart';
import 'signature_cubits.dart';
import '../../../core/widgets/text.dart';
import '../../../core/i18n/tr.dart';

/// Shows a signature on white paper, the way it will look on a page.
class SignatureThumb extends StatelessWidget {
  const SignatureThumb({super.key, required this.path, this.height = 90});
  final String path;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    width: double.infinity,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppColors.border),
    ),
    padding: const EdgeInsets.all(8),
    child: Image.file(File(path), fit: BoxFit.contain, errorBuilder: (_, _, _) => const Icon(AppIcons.edit)),
  );
}

// region hub

/// Saved signatures, with ways to make a new one and to sign a document.
class SignatureHubPage extends StatelessWidget {
  const SignatureHubPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(create: (_) => SignatureHubCubit(sl<SignatureStore>())..load(), child: const _HubView());
}

class _HubView extends StatelessWidget {
  const _HubView();

  Future<void> _go(BuildContext context, String route, {SignatureKind? kind}) async {
    await context.push<bool>(route, extra: kind);
    if (context.mounted) await context.read<SignatureHubCubit>().load();
  }

  Future<void> _onAction(BuildContext context, _SigAction action, SavedSignature s) async {
    final cubit = context.read<SignatureHubCubit>();
    switch (action) {
      case _SigAction.rename:
        final name = await promptText(
          context,
          title: tr('Name this signature'),
          initial: s.name,
          hint: tr('For example: Work, or My initials'),
          allowEmpty: true,
        );
        if (name != null) await cubit.rename(s.id, name);
      case _SigAction.makeDefault:
        await cubit.makeDefault(s.id);
      case _SigAction.switchKind:
        await cubit.setKind(s.id, s.kind == SignatureKind.signature ? SignatureKind.initials : SignatureKind.signature);
      case _SigAction.recolor:
        final ink = await showModalBottomSheet<InkColor>(
          context: context,
          showDragHandle: true,
          builder: (sheet) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final c in InkColor.values)
                  ListTile(
                    leading: CircleAvatar(radius: 10, backgroundColor: Color(c.argb)),
                    title: Text(c.label),
                    onTap: () => Navigator.pop(sheet, c),
                  ),
              ],
            ),
          ),
        );
        if (ink != null) await cubit.recolor(s.id, ink);
      case _SigAction.duplicate:
        await cubit.duplicate(s.id);
      case _SigAction.share:
        final r = await sl<ShareService>().shareFile(path: s.path, mimeType: 'image/png');
        if (context.mounted && r.failureOrNull != null) showFailure(context, r.failureOrNull!);
      case _SigAction.moveUp:
        await cubit.shift(s.id, -1);
      case _SigAction.moveDown:
        await cubit.shift(s.id, 1);
      case _SigAction.delete:
        final ok = await confirmDestructive(
          context,
          title: 'Delete this signature?',
          message: 'It will be removed from this phone. Documents you already signed are not changed.',
          action: 'Delete',
        );
        if (ok) await cubit.delete(s.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<SignatureHubCubit, SignatureHubState>(
      listenWhen: (a, b) => b.failure != null && a.failure != b.failure,
      listener: (context, state) => showFailure(context, state.failure!),
      builder: (context, state) {
        final cubit = context.read<SignatureHubCubit>();
        final full = state.signatures.length >= SignatureStore.maxSaved;
        final newKind = state.filter ?? SignatureKind.signature;
        final initials = newKind == SignatureKind.initials;
        final shown = state.visible;
        return Scaffold(
          appBar: AppBar(title: const Text('Signature')),
          body: SafeArea(
            child: ListView(
              padding: contentPadding(context, base: AppSpacing.md, maxWidth: 640),
              children: [
                const Text(
                  'Make a signature once, then put it on any PDF or photo. Your signatures stay on this phone.',
                  style: TextStyle(fontSize: 13, color: AppColors.inkMuted, height: 1.4),
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    FilledButton.icon(
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                      onPressed: full ? null : () => _go(context, '/signature-draw', kind: newKind),
                      icon: const Icon(AppIcons.edit, size: 18),
                      label: Text(initials ? 'Draw initials' : 'Draw'),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                      onPressed: full ? null : () => _go(context, '/signature-photo', kind: newKind),
                      icon: const Icon(AppIcons.camera, size: 18),
                      label: Text(initials ? 'Initials from a photo' : 'From a photo'),
                    ),
                  ],
                ),
                if (full)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Text(
                      trf('You have {n} signatures. Delete one to add another.', {'n': SignatureStore.maxSaved}),
                      style: const TextStyle(fontSize: 12.5, color: AppColors.warning),
                    ),
                  ),
                if (state.signatures.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    children: [
                      ChoiceChip(label: const Text('All'), selected: state.filter == null, onSelected: (_) => cubit.setFilter(null)),
                      for (final k in SignatureKind.values)
                        ChoiceChip(
                          label: Text(k == SignatureKind.signature ? 'Signatures' : 'Initials'),
                          selected: state.filter == k,
                          onSelected: (_) => cubit.setFilter(k),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                if (state.loaded && state.signatures.isEmpty)
                  const Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacing.md),
                      child: Text('No signature yet. Draw one with your finger, or photograph one written on white paper.', style: TextStyle(height: 1.4)),
                    ),
                  ),
                if (state.signatures.isNotEmpty && shown.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Text('Nothing of this kind yet.', style: TextStyle(color: AppColors.inkMuted)),
                  ),
                for (final s in shown)
                  Card(
                    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md, AppSpacing.sm, AppSpacing.xs, AppSpacing.sm),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (s.isDefault)
                                const Padding(
                                  padding: EdgeInsetsDirectional.only(end: 6),
                                  child: Icon(AppIcons.star, size: 16, color: AppColors.warning),
                                ),
                              Expanded(
                                child: Text(
                                  s.isDefault ? '${state.labelOf(s)} (${tr('default')})' : state.labelOf(s),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                              PopupMenuButton<_SigAction>(
                                key: ValueKey('sig-menu-${s.id}'),
                                tooltip: tr('More'),
                                icon: const Icon(AppIcons.more),
                                onSelected: (a) => _onAction(context, a, s),
                                itemBuilder: (_) => [
                                  const PopupMenuItem(value: _SigAction.rename, child: _MenuRow(AppIcons.edit, 'Rename')),
                                  if (!s.isDefault)
                                    PopupMenuItem(
                                      value: _SigAction.makeDefault,
                                      child: _MenuRow(
                                        AppIcons.star,
                                        s.kind == SignatureKind.initials ? 'Use these initials first' : 'Use this signature first',
                                      ),
                                    ),
                                  PopupMenuItem(
                                    value: _SigAction.switchKind,
                                    child: _MenuRow(AppIcons.edit, s.kind == SignatureKind.signature ? 'Keep as initials' : 'Keep as a signature'),
                                  ),
                                  const PopupMenuItem(value: _SigAction.recolor, child: _MenuRow(AppIcons.palette, 'Change ink colour')),
                                  const PopupMenuItem(value: _SigAction.duplicate, child: _MenuRow(AppIcons.copy, 'Make a copy')),
                                  const PopupMenuItem(value: _SigAction.share, child: _MenuRow(AppIcons.share, 'Share picture')),
                                  if (state.signatures.first.id != s.id)
                                    const PopupMenuItem(value: _SigAction.moveUp, child: _MenuRow(AppIcons.moveUp, 'Move up')),
                                  if (state.signatures.last.id != s.id)
                                    const PopupMenuItem(value: _SigAction.moveDown, child: _MenuRow(AppIcons.moveDown, 'Move down')),
                                  const PopupMenuItem(value: _SigAction.delete, child: _MenuRow(AppIcons.delete, 'Delete', danger: true)),
                                ],
                              ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsetsDirectional.only(end: AppSpacing.md),
                            child: SignatureThumb(path: s.path),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: AppSpacing.sm),
                FilledButton.icon(
                  onPressed: state.signatures.isEmpty ? null : () => _go(context, '/sign-document'),
                  icon: const Icon(AppIcons.pdf, size: 18),
                  label: const Text('Sign a PDF or photo'),
                ),
                const SizedBox(height: AppSpacing.md),
                const Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.md),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(AppIcons.info, size: 20, color: AppColors.primary),
                        SizedBox(width: AppSpacing.sm + 4),
                        Expanded(
                          child: Text(
                            'This puts a picture of your signature on the page. It is not a certified digital signature, so it does not prove who signed or detect later changes. Many forms and offices accept it; some legal documents require a certified one.',
                            style: TextStyle(fontSize: 13, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// endregion

enum _SigAction { rename, makeDefault, switchKind, recolor, duplicate, share, moveUp, moveDown, delete }

class _MenuRow extends StatelessWidget {
  const _MenuRow(this.icon, this.label, {this.danger = false});
  final IconData icon;
  final String label;
  final bool danger;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 18, color: danger ? AppColors.danger : null),
      const SizedBox(width: 12),
      Flexible(
        child: Text(label, style: danger ? const TextStyle(color: AppColors.danger) : null),
      ),
    ],
  );
}

// region draw

class SignatureDrawPage extends StatelessWidget {
  const SignatureDrawPage({super.key, this.kind = SignatureKind.signature});
  final SignatureKind kind;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => SignatureDrawCubit(maker: sl<SignatureMaker>(), store: sl<SignatureStore>(), workDir: getTemporaryDirectory, kind: kind),
    child: const _DrawView(),
  );
}

class _DrawView extends StatefulWidget {
  const _DrawView();

  @override
  State<_DrawView> createState() => _DrawViewState();
}

class _DrawViewState extends State<_DrawView> {
  bool _holding = false;
  Size _pad = Size.zero;

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<SignatureDrawCubit, SignatureDrawState>(
      listenWhen: (a, b) => a.saved?.id != b.saved?.id || (b.failure != null && a.failure != b.failure),
      listener: (context, s) {
        if (s.saved != null) {
          Navigator.pop(context, true);
        } else if (s.failure != null) {
          showFailure(context, s.failure!);
          context.read<SignatureDrawCubit>().clearFailure();
        }
      },
      builder: (context, state) {
        final cubit = context.read<SignatureDrawCubit>();
        return Scaffold(
          appBar: AppBar(title: const Text('Draw your signature')),
          body: SafeArea(
            child: Stack(
              children: [
                ListView(
                  physics: _holding ? const NeverScrollableScrollPhysics() : null,
                  padding: contentPadding(context, base: AppSpacing.md, maxWidth: 640),
                  children: [
                    const Text('Sign inside the box with your finger.', style: TextStyle(fontSize: 13, color: AppColors.inkMuted)),
                    const SizedBox(height: AppSpacing.sm),
                    LayoutBuilder(
                      builder: (context, box) {
                        _pad = Size(box.maxWidth, 220);
                        return Listener(
                          onPointerDown: (e) {
                            setState(() => _holding = true);
                            cubit.begin(e.localPosition.dx, e.localPosition.dy);
                          },
                          onPointerMove: (e) => cubit.extend(e.localPosition.dx, e.localPosition.dy),
                          onPointerUp: (_) => setState(() => _holding = false),
                          onPointerCancel: (_) => setState(() => _holding = false),
                          child: Container(
                            key: const ValueKey('signature-pad'),
                            height: 220,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: CustomPaint(
                                painter: _PadPainter(strokes: state.strokes, pen: state.pen, ink: Color(state.ink.argb), version: state.version),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      children: [
                        TextButton.icon(onPressed: state.isEmpty ? null : cubit.undo, icon: const Icon(AppIcons.reset, size: 18), label: const Text('Undo')),
                        TextButton.icon(onPressed: state.isEmpty ? null : cubit.clear, icon: const Icon(AppIcons.delete, size: 18), label: const Text('Clear')),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    const Text('Pen', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: AppSpacing.xs),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      children: [
                        for (final p in SignatureDrawCubit.pens)
                          ChoiceChip(label: Text(p.$1), selected: state.pen == p.$2, onSelected: (_) => cubit.setPen(p.$2)),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    const Text('Ink', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: AppSpacing.xs),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      children: [
                        for (final c in InkColor.values)
                          ChoiceChip(
                            avatar: CircleAvatar(backgroundColor: Color(c.argb), radius: 8),
                            label: Text(c.label),
                            selected: state.ink == c,
                            onSelected: (_) => cubit.setInk(c),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    FilledButton.icon(
                      onPressed: state.isEmpty || state.busy ? null : () => cubit.save(padWidth: _pad.width, padHeight: _pad.height),
                      icon: const Icon(AppIcons.check, size: 18),
                      label: const Text('Save signature'),
                    ),
                  ],
                ),
                BusyOverlay(visible: state.busy, label: 'Saving...'),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PadPainter extends CustomPainter {
  const _PadPainter({required this.strokes, required this.pen, required this.ink, required this.version});
  final List<Stroke> strokes;
  final double pen;
  final Color ink;
  final int version;

  @override
  void paint(Canvas canvas, Size size) {
    // A faint line to sign on.
    final guide = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    canvas.drawLine(Offset(16, size.height * 0.72), Offset(size.width - 16, size.height * 0.72), guide);
    final line = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = pen
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    final dot = Paint()..color = ink;
    for (final s in strokes) {
      if (s.points.length == 1) {
        canvas.drawCircle(Offset(s.points.first.x, s.points.first.y), pen / 2, dot);
      } else if (s.points.length > 1) {
        canvas.drawPath(smoothPath(s.points, 1), line);
      }
    }
  }

  @override
  bool shouldRepaint(_PadPainter old) => old.version != version || old.pen != pen || old.ink != ink || old.strokes.length != strokes.length;
}

// endregion

// region photo

class SignaturePhotoPage extends StatelessWidget {
  const SignaturePhotoPage({super.key, this.kind = SignatureKind.signature});
  final SignatureKind kind;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => SignaturePhotoCubit(maker: sl<SignatureMaker>(), store: sl<SignatureStore>(), workDir: getTemporaryDirectory, kind: kind),
    child: const _PhotoView(),
  );
}

class _PhotoView extends StatefulWidget {
  const _PhotoView();

  @override
  State<_PhotoView> createState() => _PhotoViewState();
}

class _PhotoViewState extends State<_PhotoView> {
  double? _dragging;

  Future<void> _pick(BuildContext context) async {
    final source = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(AppIcons.camera), title: const Text('Take a photo'), onTap: () => Navigator.pop(context, 'camera')),
            ListTile(leading: const Icon(AppIcons.gallery), title: const Text('Choose from gallery'), onTap: () => Navigator.pop(context, 'gallery')),
            ListTile(leading: const Icon(AppIcons.importFile), title: const Text('Choose from Files'), onTap: () => Navigator.pop(context, 'files')),
          ],
        ),
      ),
    );
    if (source == null || !context.mounted) return;
    try {
      final String? path;
      if (source == 'camera') {
        path = (await ImagePicker().pickImage(source: ImageSource.camera, preferredCameraDevice: CameraDevice.rear))?.path;
      } else if (source == 'gallery') {
        path = (await ImagePicker().pickImage(source: ImageSource.gallery))?.path;
      } else {
        final picked = await FilePicker.pickFiles(type: FileType.image);
        path = picked.isEmpty ? null : picked.first.path;
      }
      if (path == null || !context.mounted) return;
      await context.read<SignaturePhotoCubit>().pick(path);
    } catch (_) {
      if (context.mounted) showFailure(context, const PermissionFailure('The camera or photo library is unavailable.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<SignaturePhotoCubit, SignaturePhotoState>(
      listenWhen: (a, b) => a.saved?.id != b.saved?.id || (b.failure != null && a.failure != b.failure),
      listener: (context, s) {
        if (s.saved != null) {
          Navigator.pop(context, true);
        } else if (s.failure != null) {
          showFailure(context, s.failure!);
          context.read<SignaturePhotoCubit>().clearFailure();
        }
      },
      builder: (context, state) {
        final cubit = context.read<SignaturePhotoCubit>();
        final value = _dragging ?? state.sensitivity;
        return Scaffold(
          appBar: AppBar(title: const Text('Signature from a photo')),
          body: SafeArea(
            child: Stack(
              children: [
                ListView(
                  padding: contentPadding(context, base: AppSpacing.md, maxWidth: 640),
                  children: [
                    const Text(
                      'Sign on plain white paper with a dark pen, then photograph it in good, even light. The paper becomes transparent.',
                      style: TextStyle(fontSize: 13, color: AppColors.inkMuted, height: 1.4),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    OutlinedButton.icon(
                      onPressed: state.busy ? null : () => _pick(context),
                      icon: const Icon(AppIcons.camera, size: 18),
                      label: Text(state.sourcePath == null ? 'Add a photo' : 'Use another photo'),
                    ),
                    if (state.sourcePath != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      if (state.preview != null)
                        SignatureThumb(path: state.preview!.path, height: 140)
                      else
                        Container(
                          height: 140,
                          alignment: Alignment.center,
                          child: state.busy ? const CircularProgressIndicator() : const Text('No signature found'),
                        ),
                      const SizedBox(height: AppSpacing.md),
                      const Text('Ink colour', style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: AppSpacing.xs),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.xs,
                        children: [
                          ChoiceChip(label: const Text('Keep pen colour'), selected: state.ink == null, onSelected: (_) => cubit.setInk(null)),
                          for (final c in InkColor.values)
                            ChoiceChip(
                              avatar: CircleAvatar(backgroundColor: Color(c.argb), radius: 8),
                              label: Text(c.label),
                              selected: state.ink == c,
                              onSelected: (_) => cubit.setInk(c),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      const Text('Faint lines', style: TextStyle(fontWeight: FontWeight.w700)),
                      Row(
                        children: [
                          const Text('Less', style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
                          Expanded(
                            child: Slider(
                              value: value,
                              onChanged: (v) => setState(() => _dragging = v),
                              onChangeEnd: (v) {
                                setState(() => _dragging = null);
                                cubit.setSensitivity(v);
                              },
                            ),
                          ),
                          const Text('More', style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
                        ],
                      ),
                      const Text(
                        'Raise it if thin parts are missing. Lower it if specks of paper show.',
                        style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted, height: 1.4),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      FilledButton.icon(
                        onPressed: state.preview == null || state.busy ? null : cubit.save,
                        icon: const Icon(AppIcons.check, size: 18),
                        label: const Text('Save signature'),
                      ),
                    ],
                  ],
                ),
                BusyOverlay(visible: state.busy && state.preview != null, label: 'Working...'),
              ],
            ),
          ),
        );
      },
    );
  }
}

// endregion

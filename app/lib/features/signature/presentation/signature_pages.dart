import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../../app/di.dart';
import '../../../core/error/failures.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/responsive.dart';
import '../../documents/presentation/widgets/document_widgets.dart' show confirmDestructive;
import '../data/signature_processor.dart' show smoothPath;
import '../domain/signature.dart';
import 'signature_cubits.dart';

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

  Future<void> _go(BuildContext context, String route) async {
    await context.push<bool>(route);
    if (context.mounted) await context.read<SignatureHubCubit>().load();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SignatureHubCubit, SignatureHubState>(
      builder: (context, state) {
        final cubit = context.read<SignatureHubCubit>();
        final full = state.signatures.length >= SignatureStore.maxSaved;
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
                      onPressed: full ? null : () => _go(context, '/signature-draw'),
                      icon: const Icon(AppIcons.edit, size: 18),
                      label: const Text('Draw'),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                      onPressed: full ? null : () => _go(context, '/signature-photo'),
                      icon: const Icon(AppIcons.camera, size: 18),
                      label: const Text('From a photo'),
                    ),
                  ],
                ),
                if (full)
                  const Padding(
                    padding: EdgeInsets.only(top: AppSpacing.sm),
                    child: Text('You have 5 signatures. Delete one to add another.', style: TextStyle(fontSize: 12.5, color: AppColors.warning)),
                  ),
                const SizedBox(height: AppSpacing.md),
                if (state.loaded && state.signatures.isEmpty)
                  const Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacing.md),
                      child: Text('No signature yet. Draw one with your finger, or photograph one written on white paper.', style: TextStyle(height: 1.4)),
                    ),
                  ),
                for (final s in state.signatures)
                  Card(
                    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      child: Row(
                        children: [
                          Expanded(child: SignatureThumb(path: s.path)),
                          IconButton(
                            tooltip: 'Delete signature',
                            icon: const Icon(AppIcons.delete, size: 20, color: AppColors.danger),
                            onPressed: () async {
                              final ok = await confirmDestructive(
                                context,
                                title: 'Delete this signature?',
                                message: 'It will be removed from this phone. Documents you already signed are not changed.',
                                action: 'Delete',
                              );
                              if (ok) await cubit.delete(s.id);
                            },
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

// region draw

class SignatureDrawPage extends StatelessWidget {
  const SignatureDrawPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => SignatureDrawCubit(maker: sl<SignatureMaker>(), store: sl<SignatureStore>(), workDir: getTemporaryDirectory),
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
  const SignaturePhotoPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => SignaturePhotoCubit(maker: sl<SignatureMaker>(), store: sl<SignatureStore>(), workDir: getTemporaryDirectory),
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

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path_provider/path_provider.dart';

import '../../../app/di.dart';
import '../../../core/error/failures.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/responsive.dart';
import '../data/pdf_picture_pages.dart';
import '../domain/pdf_redact.dart';
import 'pdf_redact_cubit.dart';
import 'pdf_result_card.dart';
import '../../../core/widgets/text.dart';
import '../../../core/i18n/tr.dart';

/// Covers parts of a PDF in solid black and writes a copy in which what was underneath is gone from the file.
class PdfRedactPage extends StatelessWidget {
  const PdfRedactPage({super.key, this.pages});
  final PdfPicturePages Function()? pages;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => PdfRedactCubit(service: sl<PdfRedactService>(), outputDir: getTemporaryDirectory, pages: pages),
    child: const _RedactView(),
  );
}

class _RedactView extends StatelessWidget {
  const _RedactView();

  Future<void> _pick(BuildContext context) async {
    try {
      final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['pdf']);
      final path = picked.isEmpty ? null : picked.first.path;
      if (path == null || !context.mounted) return;
      await context.read<PdfRedactCubit>().pick(path);
    } catch (_) {
      if (context.mounted) showFailure(context, const PermissionFailure('The file picker is unavailable.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<PdfRedactCubit, PdfRedactState>(
      listenWhen: (a, b) => b.failure != null && a.failure != b.failure && b.open,
      listener: (context, s) => showFailure(context, s.failure!),
      builder: (context, state) {
        final cubit = context.read<PdfRedactCubit>();
        return Scaffold(
          appBar: AppBar(
            title: const Text('Hide text in a PDF'),
            actions: [
              if (state.open && state.boxes.isNotEmpty && !state.busy)
                IconButton(key: const ValueKey('redact-undo'), tooltip: tr('Undo the last box'), icon: const Icon(AppIcons.undo), onPressed: cubit.undo),
              if (state.path != null && !state.busy) TextButton(onPressed: cubit.clear, child: const Text('Close')),
            ],
          ),
          body: SafeArea(
            child: Stack(
              children: [
                if (!state.open)
                  ListView(
                    padding: contentPadding(context, base: AppSpacing.md, maxWidth: 640),
                    children: [
                      FilledButton.icon(
                        key: const ValueKey('redact-pick'),
                        onPressed: state.busy ? null : () => _pick(context),
                        icon: const Icon(AppIcons.importFile, size: 18),
                        label: const Text('Choose a PDF'),
                      ),
                      if (state.failure != null)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.md),
                          child: Text(
                            state.failure!.message,
                            key: const ValueKey('redact-failure'),
                            style: const TextStyle(color: AppColors.danger, height: 1.4),
                          ),
                        ),
                      const SizedBox(height: AppSpacing.md),
                      const Card(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: EdgeInsets.all(AppSpacing.md),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(AppIcons.shield, size: 20, color: AppColors.success),
                              SizedBox(width: AppSpacing.sm + 4),
                              Expanded(
                                child: Text(
                                  'Draw over names, numbers or anything private. The areas are painted black before the new PDF is made, so the text under them is not in the file at all and cannot be copied out. The pages become pictures, so no text on them can be selected. Your original file is not changed.',
                                  style: TextStyle(fontSize: 13, height: 1.4),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                else
                  const _Editor(),
                BusyOverlay(visible: state.busy, label: state.status == RedactStatus.saving ? 'Hiding and saving' : 'Opening'),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Editor extends StatelessWidget {
  const _Editor();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PdfRedactCubit>().state;
    final cubit = context.read<PdfRedactCubit>();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  ChoiceChip(
                    key: const ValueKey('redact-scroll'),
                    avatar: const Icon(AppIcons.pointer, size: 16),
                    label: const Text('Scroll'),
                    selected: !state.drawing,
                    onSelected: (_) => cubit.setDrawing(false),
                  ),
                  ChoiceChip(
                    key: const ValueKey('redact-draw'),
                    avatar: const Icon(AppIcons.markRedact, size: 16),
                    label: const Text('Hide'),
                    selected: state.drawing,
                    onSelected: (_) => cubit.setDrawing(true),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: AppSpacing.xs),
                child: Text(
                  state.drawing
                      ? 'Drag on a page over what to hide. Tap a black box to remove it.'
                      : 'Scroll through the pages, then switch to Hide to cover things.',
                  key: const ValueKey('redact-hint'),
                  style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            key: const ValueKey('redact-pages'),
            physics: state.drawing ? const NeverScrollableScrollPhysics() : null,
            padding: contentPadding(context, base: AppSpacing.sm, maxWidth: 720),
            itemCount: state.pageCount,
            itemBuilder: (context, i) => _PageView(index: i),
          ),
        ),
        Material(
          elevation: 6,
          color: Theme.of(context).colorScheme.surface,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (state.result != null) ...[
                  PdfResultCard(
                    title: 'Your PDF is ready',
                    message: 'The hidden areas are black in the file and what was under them is gone. Share this copy, not the original.',
                    path: state.result!.path,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                SwitchListTile(
                  key: const ValueKey('redact-high'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('High detail'),
                  subtitle: const Text('Sharper pages, larger file.'),
                  value: state.high,
                  onChanged: state.busy ? null : cubit.setHigh,
                ),
                FilledButton.icon(
                  key: const ValueKey('redact-save'),
                  onPressed: state.busy ? null : cubit.save,
                  icon: const Icon(AppIcons.markRedact, size: 18),
                  label: Text(state.boxes.isEmpty ? 'Hide and save' : 'Hide ${state.boxes.length} ${state.boxes.length == 1 ? 'area' : 'areas'} and save'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PageView extends StatefulWidget {
  const _PageView({required this.index});
  final int index;

  @override
  State<_PageView> createState() => _PageViewState();
}

class _PageViewState extends State<_PageView> {
  Offset? _start;
  Offset? _now;

  Future<void> _remove(RedactBox box) async {
    final cubit = context.read<PdfRedactCubit>();
    final remove = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove this black box?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          TextButton(key: const ValueKey('redact-remove'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (remove == true) cubit.removeBox(box);
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<PdfRedactCubit>();
    final state = context.watch<PdfRedactCubit>().state;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: FutureBuilder(
          future: cubit.preview(widget.index),
          builder: (context, snap) {
            final data = snap.data;
            if (data == null) {
              return SizedBox(
                height: 240,
                child: Center(child: snap.hasError ? const Icon(AppIcons.info, color: AppColors.inkMuted) : const CircularProgressIndicator(strokeWidth: 2)),
              );
            }
            return AspectRatio(
              aspectRatio: data.aspect,
              child: LayoutBuilder(
                builder: (context, box) {
                  final w = box.maxWidth, h = box.maxHeight;
                  Rect shares(Offset a, Offset b) => Rect.fromPoints(Offset(a.dx / w, a.dy / h), Offset(b.dx / w, b.dy / h));
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.memory(data.bytes, fit: BoxFit.fill, gaplessPlayback: true),
                      for (final b in state.boxes.where((b) => b.page == widget.index))
                        Positioned(
                          left: b.left * w,
                          top: b.top * h,
                          width: b.width * w,
                          height: b.height * h,
                          child: GestureDetector(
                            key: ValueKey('box-${b.page}-${b.left.toStringAsFixed(3)}-${b.top.toStringAsFixed(3)}'),
                            onTap: () => _remove(b),
                            child: const ColoredBox(color: Colors.black),
                          ),
                        ),
                      if (_start != null && _now != null)
                        Positioned.fromRect(
                          rect: Rect.fromPoints(_start!, _now!),
                          child: IgnorePointer(child: ColoredBox(color: Colors.black.withValues(alpha: 0.6))),
                        ),
                      if (state.drawing)
                        Positioned.fill(
                          child: GestureDetector(
                            key: ValueKey('draw-${widget.index}'),
                            behavior: HitTestBehavior.translucent,
                            onPanStart: (d) => setState(() {
                              _start = d.localPosition;
                              _now = d.localPosition;
                            }),
                            onPanUpdate: (d) => setState(() => _now = d.localPosition),
                            onPanEnd: (_) {
                              final a = _start, b = _now;
                              setState(() {
                                _start = null;
                                _now = null;
                              });
                              if (a != null && b != null) {
                                final r = shares(a, b);
                                cubit.addBox(widget.index, r.left, r.top, r.right, r.bottom);
                              }
                            },
                            onPanCancel: () => setState(() {
                              _start = null;
                              _now = null;
                            }),
                          ),
                        ),
                    ],
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

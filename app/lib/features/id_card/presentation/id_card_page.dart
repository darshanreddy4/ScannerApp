import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';

import '../../../app/di.dart';
import '../../../core/error/failures.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/responsive.dart';
import '../../export/domain/repositories/export_repository.dart';
import '../../photo_tools/domain/crop_math.dart';
import '../../photo_tools/domain/passport_maker.dart';
import '../domain/id_card.dart';
import 'id_card_cubit.dart';
import '../../../core/widgets/text.dart';

/// Puts the front and back of an ID card on one page at its real size, ready to print or send.
class IdCardPage extends StatelessWidget {
  const IdCardPage({super.key, this.photos = const []});

  /// Front and back photos to start from, e.g. a scan that was just saved.
  final List<String> photos;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) {
      final cubit = IdCardCubit(maker: sl<IdCardMaker>(), workDir: getTemporaryDirectory);
      if (photos.isNotEmpty) cubit.prefill(photos);
      return cubit;
    },
    child: const _IdCardView(),
  );
}

class _IdCardView extends StatelessWidget {
  const _IdCardView();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<IdCardCubit, IdCardState>(
      listenWhen: (a, b) => b.failure != null && a.failure != b.failure,
      listener: (context, s) {
        showFailure(context, s.failure!);
        context.read<IdCardCubit>().clearFailure();
      },
      builder: (context, state) {
        final cubit = context.read<IdCardCubit>();
        final editing = state.editing;
        return PopScope(
          canPop: editing == null,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) cubit.done();
          },
          child: Scaffold(
            appBar: AppBar(title: Text(editing == null ? 'Copy of ID card' : 'Adjust the ${editing.label.toLowerCase()}')),
            body: SafeArea(
              child: Stack(
                children: [
                  editing == null ? const _Overview() : _EditSide(side: editing),
                  BusyOverlay(visible: state.busy, label: 'Working...'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

Future<void> _choose(BuildContext context, CardSideId side) async {
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
    await context.read<IdCardCubit>().setPhoto(side, path);
  } catch (_) {
    if (context.mounted) showFailure(context, const PermissionFailure('The camera or photo library is unavailable.'));
  }
}

class _Overview extends StatelessWidget {
  const _Overview();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<IdCardCubit>().state;
    return ListView(
      padding: contentPadding(context, base: AppSpacing.md, maxWidth: 640),
      children: [
        const Text(
          'Add a photo of each side. Both sides are printed on one page at the size of the real card.',
          style: TextStyle(fontSize: 13, color: AppColors.inkMuted, height: 1.4),
        ),
        const SizedBox(height: AppSpacing.md),
        _SideSlot(id: CardSideId.front, state: state),
        const SizedBox(height: AppSpacing.md),
        _SideSlot(id: CardSideId.back, state: state),
        const SizedBox(height: AppSpacing.lg),
        _Options(state: state),
        const SizedBox(height: AppSpacing.md),
        FilledButton.icon(
          onPressed: state.busy || !state.front.has ? null : context.read<IdCardCubit>().create,
          icon: const Icon(AppIcons.check, size: 18),
          label: const Text('Create page'),
        ),
        if (state.result != null) ...[const SizedBox(height: AppSpacing.md), _Result(state: state)],
        const SizedBox(height: AppSpacing.md),
        const _Note(),
      ],
    );
  }
}

class _SideSlot extends StatelessWidget {
  const _SideSlot({required this.id, required this.state});
  final CardSideId id;
  final IdCardState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<IdCardCubit>();
    final side = state.side(id);
    final size = state.options.size;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(id == CardSideId.back ? 'Back (optional)' : 'Front', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: AppSpacing.sm),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: AspectRatio(
                  aspectRatio: size.aspect,
                  child: side.has
                      ? LayoutBuilder(
                          builder: (_, box) => CardCropFrame(
                            photo: side.photo!,
                            view: side.view!,
                            frameAspect: size.aspect,
                            width: box.maxWidth,
                            height: box.maxHeight,
                            cardW: size.widthMm,
                            cardH: size.heightMm,
                          ),
                        )
                      : InkWell(
                          key: ValueKey('add-${id.name}'),
                          onTap: state.busy ? null : () => _choose(context, id),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: AppColors.border),
                              borderRadius: BorderRadius.circular(8),
                              color: Colors.black12,
                            ),
                            child: const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(AppIcons.add, size: 28, color: AppColors.primary),
                                  SizedBox(height: 4),
                                  Text('Add photo'),
                                ],
                              ),
                            ),
                          ),
                        ),
                ),
              ),
            ),
            if (side.has) ...[
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  TextButton.icon(onPressed: state.busy ? null : () => cubit.edit(id), icon: const Icon(AppIcons.crop, size: 18), label: const Text('Adjust')),
                  TextButton.icon(
                    onPressed: state.busy ? null : () => _choose(context, id),
                    icon: const Icon(AppIcons.retake, size: 18),
                    label: const Text('Replace'),
                  ),
                  TextButton.icon(
                    onPressed: state.busy ? null : () => cubit.remove(id),
                    icon: const Icon(AppIcons.delete, size: 18),
                    label: const Text('Remove'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Options extends StatelessWidget {
  const _Options({required this.state});
  final IdCardState state;

  Future<void> _custom(BuildContext context) async {
    final size = await showDialog<CardSize>(context: context, builder: (_) => const _CustomCardDialog());
    if (size != null && context.mounted) context.read<IdCardCubit>().setOptions(state.options.copyWith(size: size));
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<IdCardCubit>();
    final o = state.options;
    final custom = o.size.id == 'custom';
    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        label('Card size'),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            for (final s in CardSize.presets)
              ChoiceChip(
                label: Text(s.label),
                selected: o.size == s,
                onSelected: (_) => cubit.setOptions(o.copyWith(size: s)),
              ),
            ChoiceChip(label: Text(custom ? o.size.sizeLabel : 'Custom'), selected: custom, onSelected: (_) => _custom(context)),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: Text(o.size.sizeLabel, style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
        ),
        const SizedBox(height: AppSpacing.md),
        label('Paper'),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            for (final p in CardPaper.values)
              ChoiceChip(
                label: Text(p.label),
                selected: o.paper == p,
                onSelected: (_) => cubit.setOptions(o.copyWith(paper: p)),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        label('Size on paper'),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            for (final s in CardScale.values)
              ChoiceChip(
                label: Text(s.label),
                selected: o.scale == s,
                onSelected: (_) => cubit.setOptions(o.copyWith(scale: s)),
              ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Black and white'),
          subtitle: const Text('Saves colour ink.'),
          value: o.blackAndWhite,
          onChanged: (v) => cubit.setOptions(o.copyWith(blackAndWhite: v)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Line around each card'),
          subtitle: const Text('Helps you cut along the edge.'),
          value: o.border,
          onChanged: (v) => cubit.setOptions(o.copyWith(border: v)),
        ),
      ],
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({required this.state});
  final IdCardState state;

  Future<void> _share(BuildContext context, String path, String mime) async {
    final failure = (await sl<ShareService>().shareFiles(paths: [path], mimeType: mime)).failureOrNull;
    if (failure != null && context.mounted) showFailure(context, failure);
  }

  Future<void> _save(BuildContext context, String path, String name, String mime) async {
    final result = await sl<SaveService>().saveToFiles(sourcePath: path, fileName: name, mimeType: mime);
    if (!context.mounted) return;
    final failure = result.failureOrNull;
    if (failure != null) {
      showFailure(context, failure);
    } else if (result.valueOrNull == true) {
      showMessage(context, 'Saved');
    }
  }

  Future<void> _gallery(BuildContext context, String path) async {
    final result = await sl<SaveService>().saveImagesToGallery([path]);
    if (!context.mounted) return;
    final failure = result.failureOrNull;
    failure != null ? showFailure(context, failure) : showMessage(context, 'Saved to your gallery');
  }

  Future<void> _print(BuildContext context, String pdfPath) async {
    try {
      final bytes = await File(pdfPath).readAsBytes();
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'ID card copy');
    } catch (_) {
      if (context.mounted) showFailure(context, const ExportFailure('Printing is not available on this device. Share the PDF instead.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = state.result!;
    final o = state.options;
    ButtonStyle style() => OutlinedButton.styleFrom(minimumSize: const Size(0, 44));
    return Card(
      margin: EdgeInsets.zero,
      color: AppColors.primarySoft,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(r.cards == 1 ? 'Your page is ready' : 'Your page with both sides is ready', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: AppSpacing.sm),
            Center(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 320),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  color: Colors.white,
                ),
                child: AspectRatio(
                  aspectRatio: o.paper.widthMm / o.paper.heightMm,
                  child: Image.file(File(r.jpgPath), fit: BoxFit.contain, errorBuilder: (_, _, _) => const Icon(AppIcons.print)),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              r.shrunk
                  ? 'This card is too big for the paper at real size, so it was made smaller (${(r.scale * 100).round()}%).'
                  : (o.scale == CardScale.actual
                        ? 'Printed at the real size of the card on ${o.paper.label}.'
                        : 'Enlarged to ${(r.scale * 100).round()}% on ${o.paper.label}.'),
              style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted, height: 1.4),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: () => _print(context, r.pdfPath),
                  icon: const Icon(AppIcons.print, size: 18),
                  label: const Text('Print'),
                ),
                OutlinedButton.icon(
                  style: style(),
                  onPressed: () => _share(context, r.pdfPath, 'application/pdf'),
                  icon: const Icon(AppIcons.pdf, size: 18),
                  label: const Text('Share PDF'),
                ),
                OutlinedButton.icon(
                  style: style(),
                  onPressed: () => _share(context, r.jpgPath, 'image/jpeg'),
                  icon: const Icon(AppIcons.gallery, size: 18),
                  label: const Text('Share JPG'),
                ),
                OutlinedButton.icon(
                  style: style(),
                  onPressed: () => _save(context, r.pdfPath, 'ID_card_copy.pdf', 'application/pdf'),
                  icon: const Icon(AppIcons.storage, size: 18),
                  label: const Text('Save PDF'),
                ),
                OutlinedButton.icon(
                  style: style(),
                  onPressed: () => _gallery(context, r.jpgPath),
                  icon: const Icon(AppIcons.download, size: 18),
                  label: const Text('Gallery'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note();

  @override
  Widget build(BuildContext context) => const Card(
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
              'Everything stays on your phone. A copy of an ID is sensitive: share it only with the person who needs it, and consider adding a watermark that says what it is for.',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    ),
  );
}

// region crop

class _EditSide extends StatefulWidget {
  const _EditSide({required this.side});
  final CardSideId side;

  @override
  State<_EditSide> createState() => _EditSideState();
}

class _EditSideState extends State<_EditSide> {
  /// While a finger is on the photo the list must not scroll, or dragging the photo would scroll the screen.
  bool _holding = false;
  double _startZoom = 1;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<IdCardCubit>();
    final state = context.watch<IdCardCubit>().state;
    final side = state.side(widget.side);
    if (!side.has) return const SizedBox.shrink();
    final size = state.options.size;
    return LayoutBuilder(
      builder: (context, box) {
        final maxW = (box.maxWidth - 2 * AppSpacing.md).clamp(120.0, 560.0);
        final maxH = (box.maxHeight * 0.5).clamp(140.0, 420.0);
        final frameW = (maxH * size.aspect).clamp(0.0, maxW);
        final frameH = frameW / size.aspect;
        return ListView(
          physics: _holding ? const NeverScrollableScrollPhysics() : null,
          padding: contentPadding(context, base: AppSpacing.md, maxWidth: 640),
          children: [
            Center(
              child: Listener(
                onPointerDown: (_) => setState(() => _holding = true),
                onPointerUp: (_) => setState(() => _holding = false),
                onPointerCancel: (_) => setState(() => _holding = false),
                child: GestureDetector(
                  onScaleStart: (_) => _startZoom = cubit.state.side(widget.side).view?.zoom ?? 1,
                  onScaleUpdate: (d) {
                    cubit.pan(d.focalPointDelta.dx / frameW, d.focalPointDelta.dy / frameH);
                    if (d.pointerCount > 1) cubit.setZoom(_startZoom * d.scale);
                  },
                  child: CardCropFrame(
                    photo: side.photo!,
                    view: side.view!,
                    frameAspect: size.aspect,
                    width: frameW,
                    height: frameH,
                    cardW: size.widthMm,
                    cardH: size.heightMm,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Drag to move and pinch to zoom until the card fills the frame. Keep all four corners inside.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted, height: 1.4),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                const Icon(AppIcons.fullFrame, size: 16, color: AppColors.inkMuted),
                Expanded(
                  child: Slider(value: side.view!.zoom, min: 1, max: CropView.maxZoom, onChanged: cubit.setZoom),
                ),
                Text('${side.view!.zoom.toStringAsFixed(1)}x', style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
              ],
            ),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: AppSpacing.sm,
              children: [
                TextButton.icon(onPressed: state.busy ? null : cubit.rotate, icon: const Icon(AppIcons.rotate, size: 18), label: const Text('Rotate')),
                TextButton.icon(onPressed: cubit.resetView, icon: const Icon(AppIcons.reset, size: 18), label: const Text('Reset')),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            FilledButton.icon(onPressed: cubit.done, icon: const Icon(AppIcons.check, size: 18), label: const Text('Done')),
          ],
        );
      },
    );
  }
}

/// The photo behind a fixed frame in the shape of the card.
class CardCropFrame extends StatelessWidget {
  const CardCropFrame({
    super.key,
    required this.photo,
    required this.view,
    required this.frameAspect,
    required this.width,
    required this.height,
    required this.cardW,
    required this.cardH,
  });

  final WorkingPhoto photo;
  final CropView view;
  final double frameAspect;
  final double width;
  final double height;
  final double cardW;
  final double cardH;

  @override
  Widget build(BuildContext context) {
    final rect = view.rect(photo.width, photo.height, cardW, cardH);
    final scale = width / rect.width;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        color: Colors.black12,
      ),
      child: ClipRect(
        key: const ValueKey('card-crop'),
        child: Stack(
          children: [
            Positioned(
              left: -rect.left * scale,
              top: -rect.top * scale,
              width: photo.width * scale,
              height: photo.height * scale,
              child: Image.file(
                File(photo.path),
                fit: BoxFit.fill,
                filterQuality: FilterQuality.medium,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black26),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// endregion

class _CustomCardDialog extends StatefulWidget {
  const _CustomCardDialog();

  @override
  State<_CustomCardDialog> createState() => _CustomCardDialogState();
}

class _CustomCardDialogState extends State<_CustomCardDialog> {
  final _w = TextEditingController();
  final _h = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _w.dispose();
    _h.dispose();
    super.dispose();
  }

  void _save() {
    final w = double.tryParse(_w.text.trim().replaceAll(',', '.'));
    final h = double.tryParse(_h.text.trim().replaceAll(',', '.'));
    final size = w == null || h == null ? null : CardSize.custom(w, h);
    if (size == null) {
      setState(() => _error = 'Enter the width and height between ${CardSize.minMm.round()} and ${CardSize.maxMm.round()} mm.');
      return;
    }
    Navigator.pop(context, size);
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration deco(String label) => InputDecoration(labelText: label, suffixText: 'mm');
    final filter = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];
    return AlertDialog(
      title: const Text('Custom card size'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _w,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: filter,
            decoration: deco('Width'),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _h,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: filter,
            decoration: deco('Height').copyWith(errorText: _error, errorMaxLines: 3),
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _save(),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: _save, child: const Text('Use')),
      ],
    );
  }
}

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
import '../../text_edit/pdf/pdf_page_renderer.dart';
import '../domain/pdf_forms.dart';
import 'pdf_crop_cubit.dart';
import 'pdf_result_card.dart';
import '../../../core/widgets/text.dart';
import '../../../core/i18n/tr.dart';

/// Shows less of each page of a PDF by cutting margins, one page at a time or the same cut on every page.
class PdfCropPage extends StatelessWidget {
  const PdfCropPage({super.key, this.openRenderer = PdfxPageRenderer.open});
  final Future<PdfPageRenderer> Function(String path) openRenderer;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => PdfCropCubit(service: sl<PdfPageToolsService>(), outputDir: getTemporaryDirectory, openRenderer: openRenderer),
    child: const _CropView(),
  );
}

class _CropView extends StatelessWidget {
  const _CropView();

  Future<void> _pick(BuildContext context) async {
    try {
      final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['pdf']);
      final path = picked.isEmpty ? null : picked.first.path;
      if (path == null || !context.mounted) return;
      await context.read<PdfCropCubit>().pick(path);
    } catch (_) {
      if (context.mounted) showFailure(context, const PermissionFailure('The file picker is unavailable.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<PdfCropCubit, PdfCropState>(
      listenWhen: (a, b) => b.failure != null && a.failure != b.failure && b.pageCount > 0,
      listener: (context, s) => showFailure(context, s.failure!),
      builder: (context, state) {
        final cubit = context.read<PdfCropCubit>();
        final open = state.pageCount > 0;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Crop PDF pages'),
            actions: [if (state.path != null && !state.busy) TextButton(onPressed: cubit.clear, child: const Text('Close'))],
          ),
          body: SafeArea(
            child: Stack(
              children: [
                if (!open)
                  ListView(
                    padding: contentPadding(context, base: AppSpacing.md, maxWidth: 640),
                    children: [
                      FilledButton.icon(
                        key: const ValueKey('crop-pick'),
                        onPressed: state.busy ? null : () => _pick(context),
                        icon: const Icon(AppIcons.importFile, size: 18),
                        label: const Text('Choose a PDF'),
                      ),
                      if (state.failure != null)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.md),
                          child: Text(
                            state.failure!.message,
                            key: const ValueKey('crop-failure'),
                            style: const TextStyle(color: AppColors.danger, height: 1.4),
                          ),
                        ),
                      const SizedBox(height: AppSpacing.md),
                      const Card(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: EdgeInsets.all(AppSpacing.md),
                          child: Text(
                            'Cut the margins off the pages, for example the edge of a scan or a wide border. Text stays selectable. The cut part is hidden, not erased: to remove something for good, use Hide text in a PDF.',
                            style: TextStyle(fontSize: 13, height: 1.4),
                          ),
                        ),
                      ),
                    ],
                  )
                else
                  const _Editor(),
                BusyOverlay(visible: state.busy, label: state.status == CropStatus.saving ? 'Saving' : 'Opening'),
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
    final state = context.watch<PdfCropCubit>().state;
    final cubit = context.read<PdfCropCubit>();
    final cut = state.insetsOf(state.page);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                key: const ValueKey('crop-prev'),
                tooltip: tr('Previous page'),
                onPressed: state.page > 0 ? () => cubit.goTo(state.page - 1) : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Flexible(
                child: Text(
                  'Page ${state.page + 1} of ${state.pageCount}',
                  key: const ValueKey('crop-page-label'),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                key: const ValueKey('crop-next'),
                tooltip: tr('Next page'),
                onPressed: state.page < state.pageCount - 1 ? () => cubit.goTo(state.page + 1) : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: FutureBuilder(
                key: ValueKey('crop-picture-${state.page}'),
                future: cubit.picture(state.page),
                builder: (context, snap) {
                  final data = snap.data;
                  if (data == null)
                    return snap.hasError ? const Icon(AppIcons.info, color: AppColors.inkMuted) : const CircularProgressIndicator(strokeWidth: 2);
                  return AspectRatio(
                    aspectRatio: data.aspect,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.memory(data.bytes, fit: BoxFit.fill, gaplessPlayback: true),
                        CustomPaint(key: const ValueKey('crop-shade'), painter: _CropShade(cut)),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        Material(
          elevation: 6,
          color: Theme.of(context).colorScheme.surface,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.sm),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (state.result != null) ...[
                  PdfResultCard(
                    title: 'Your PDF is cropped',
                    message: 'The pages show less. The cut parts are hidden, not erased from the file. The original file is unchanged.',
                    path: state.result!.path,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                for (final side in CropSide.values)
                  Row(
                    children: [
                      SizedBox(
                        width: MediaQuery.textScalerOf(context).scale(56),
                        child: Text(_label(side), style: const TextStyle(fontSize: 13)),
                      ),
                      Expanded(
                        child: Slider(
                          key: ValueKey('crop-slider-${side.name}'),
                          value: _of(cut, side),
                          max: 0.45,
                          onChanged: state.busy ? null : (v) => cubit.setSide(side, v),
                        ),
                      ),
                      SizedBox(
                        width: MediaQuery.textScalerOf(context).scale(38),
                        child: Text(
                          '${(_of(cut, side) * 100).round()}%',
                          textAlign: TextAlign.end,
                          style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
                        ),
                      ),
                    ],
                  ),
                SwitchListTile(
                  key: const ValueKey('crop-all'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Same cut for every page'),
                  value: state.all,
                  onChanged: state.busy ? null : cubit.setAll,
                ),
                Row(
                  children: [
                    TextButton(key: const ValueKey('crop-reset'), onPressed: state.busy ? null : cubit.reset, child: const Text('Reset')),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: FilledButton.icon(
                        key: const ValueKey('crop-save'),
                        onPressed: state.busy ? null : cubit.save,
                        icon: const Icon(AppIcons.crop, size: 18),
                        label: const Text('Crop PDF'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String _label(CropSide s) => switch (s) {
    CropSide.left => 'Left',
    CropSide.top => 'Top',
    CropSide.right => 'Right',
    CropSide.bottom => 'Bottom',
  };

  static double _of(CropInsets c, CropSide s) => switch (s) {
    CropSide.left => c.left,
    CropSide.top => c.top,
    CropSide.right => c.right,
    CropSide.bottom => c.bottom,
  };
}

/// Darkens what will be cut off and outlines what stays.
class _CropShade extends CustomPainter {
  const _CropShade(this.cut);
  final CropInsets cut;

  @override
  void paint(Canvas canvas, Size size) {
    final keep = Rect.fromLTRB(cut.left * size.width, cut.top * size.height, size.width - cut.right * size.width, size.height - cut.bottom * size.height);
    final shade = Paint()..color = Colors.black.withValues(alpha: 0.55);
    canvas.drawPath(Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), Path()..addRect(keep)), shade);
    canvas.drawRect(
      keep,
      Paint()
        ..color = AppColors.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_CropShade old) => old.cut != cut;
}

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/widgets/dialogs.dart';
import '../../../../core/widgets/feedback.dart';
import '../../../../core/widgets/responsive.dart';
import '../../../settings/presentation/settings_cubit.dart';
import '../../domain/entities/filter_settings.dart';
import '../bloc/scan_session_cubit.dart';
import '../widgets/filter_labels.dart';
import '../widgets/polygon_cropper.dart';

/// Crop step shown after each capture/import: adjust corners, pick a filter, retake or continue.
class CropPage extends StatelessWidget {
  const CropPage({super.key});

  Future<void> _continue(BuildContext context) async {
    final session = context.read<ScanSessionCubit>();
    final flow = session.state.flow;
    final outcome = await session.commitDraft();
    if (!context.mounted) return;
    switch (outcome) {
      case CropOutcome.failed:
        if (session.state.error != null) showFailure(context, session.state.error!);
      case CropOutcome.nextImage:
        break;
      case CropOutcome.finished:
        _leave(context, flow);
    }
  }

  Future<void> _retake(BuildContext context) async {
    final session = context.read<ScanSessionCubit>();
    final flow = session.state.flow;
    final outcome = await session.discardDraft();
    if (!context.mounted) return;
    if (outcome == CropOutcome.finished) _leave(context, flow);
  }

  void _leave(BuildContext context, ScanFlow flow) {
    final hasPages = context.read<ScanSessionCubit>().state.pages.isNotEmpty;
    switch (flow) {
      case ScanFlow.camera:
      case ScanFlow.recrop:
        context.pop();
      case ScanFlow.import:
        context.go(hasPages ? '/scan/edit' : '/');
    }
  }

  Future<void> _renameDialog(BuildContext context) async {
    final session = context.read<ScanSessionCubit>();
    final title = await promptText(context, title: 'Document name', initial: session.state.title);
    if (title != null) session.setTitle(title);
  }

  @override
  Widget build(BuildContext context) {
    final draft = context.select((ScanSessionCubit c) => c.state.draft);
    final draftPreview = context.select((ScanSessionCubit c) => c.state.draftPreview);
    final busy = context.select((ScanSessionCubit c) => c.state.busy);
    final busyLabel = context.select((ScanSessionCubit c) => c.state.busyLabel);
    final flow = context.select((ScanSessionCubit c) => c.state.flow);
    final remaining = context.select((ScanSessionCubit c) => c.state.pending.length);
    final showCrop = context.select((SettingsCubit c) => c.state.showCropAfterCapture);
    if (draft == null) return const Scaffold(backgroundColor: AppColors.scannerBackdrop);

    final session = context.read<ScanSessionCubit>();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !busy) _retake(context);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              Builder(
                builder: (context) {
                  final size = MediaQuery.sizeOf(context);
                  final sideBySide = size.width >= Breakpoints.expanded && size.width > size.height;
                  final cropper = Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
                    child: PolygonCropper(
                      imagePath: draft.rawPath,
                      imageWidth: draft.rawWidth,
                      imageHeight: draft.rawHeight,
                      quad: draft.quad,
                      previewBytes: draftPreview,
                      onChanged: session.updateQuad,
                    ),
                  );
                  final queued = remaining > 0
                      ? Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.sm),
                          child: Text('$remaining more image${remaining == 1 ? '' : 's'} queued', style: const TextStyle(color: Colors.white60, fontSize: 12)),
                        )
                      : null;
                  final controls = _Controls(
                    filter: draft.settings.filter,
                    busy: busy,
                    canRename: flow != ScanFlow.recrop,
                    showCrop: showCrop,
                    onFilter: session.setCurrentFilter,
                    onRotate: session.rotateDraft,
                    onFull: session.useFullFrame,
                    onAuto: session.resetToDetected,
                    onRename: () => _renameDialog(context),
                    onToggleCrop: (v) => context.read<SettingsCubit>().update((s) => s.copyWith(showCropAfterCapture: v)),
                    onRetake: () => _retake(context),
                    onContinue: () => _continue(context),
                  );
                  // Wide landscape: controls sit beside the image instead of squeezing it from below.
                  if (sideBySide) {
                    return Row(
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              ?queued,
                              Expanded(child: cropper),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: 400,
                          child: Center(child: SingleChildScrollView(child: controls)),
                        ),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      ?queued,
                      Expanded(child: cropper),
                      controls,
                    ],
                  );
                },
              ),
              BusyOverlay(visible: busy, label: busyLabel),
            ],
          ),
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.filter,
    required this.busy,
    required this.canRename,
    required this.showCrop,
    required this.onFilter,
    required this.onRotate,
    required this.onFull,
    required this.onAuto,
    required this.onRename,
    required this.onToggleCrop,
    required this.onRetake,
    required this.onContinue,
  });

  final ScanFilter filter;
  final bool busy;
  final bool canRename;
  final bool showCrop;
  final ValueChanged<ScanFilter> onFilter;
  final VoidCallback onRotate;
  final VoidCallback onFull;
  final VoidCallback onAuto;
  final VoidCallback onRename;
  final ValueChanged<bool> onToggleCrop;
  final VoidCallback onRetake;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Row(
            children: [
              Icon(AppIcons.info, size: 16, color: Colors.white70),
              SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text('Drag the points to adjust the borders.', style: TextStyle(color: Colors.white70, fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              const Text(
                'FILTER',
                style: TextStyle(color: Colors.white60, fontSize: 12, letterSpacing: 0.8, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: PopupMenuButton<ScanFilter>(
                  initialValue: filter,
                  onSelected: onFilter,
                  itemBuilder: (_) => [
                    for (final f in ScanFilter.values)
                      PopupMenuItem(
                        value: f,
                        child: Row(children: [Icon(f.icon, size: 18), const SizedBox(width: 10), Text(f.label)]),
                      ),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white38),
                      borderRadius: BorderRadius.circular(AppSpacing.radius),
                    ),
                    child: Row(
                      children: [
                        Icon(filter.icon, size: 18, color: Colors.white),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            filter.label,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                          ),
                        ),
                        const Icon(AppIcons.next, size: 16, color: Colors.white54),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            alignment: WrapAlignment.spaceAround,
            children: [
              _Tool(icon: AppIcons.rotate, label: 'Rotate', onTap: busy ? null : onRotate),
              _Tool(icon: AppIcons.fullFrame, label: 'Full page', onTap: onFull),
              _Tool(icon: AppIcons.autoDetect, label: 'Auto', onTap: onAuto),
              if (canRename) _Tool(icon: AppIcons.edit, label: 'Doc name', onTap: onRename),
            ],
          ),
          Row(
            children: [
              const Expanded(
                child: Text('Show crop screen after every capture', style: TextStyle(color: Colors.white70, fontSize: 13)),
              ),
              Switch(value: showCrop, onChanged: onToggleCrop),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : onRetake,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                  ),
                  child: const Text('RETAKE'),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: FilledButton(onPressed: busy ? null : onContinue, child: const Text('CONTINUE')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Tool extends StatelessWidget {
  const _Tool({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = onTap == null ? Colors.white30 : Colors.white;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: color, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

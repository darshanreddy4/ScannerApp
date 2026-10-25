import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../../app/di.dart';
import '../../../core/error/failures.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/responsive.dart';
import '../../export/domain/repositories/export_repository.dart';
import '../domain/photo_compressor.dart';
import 'compress_cubit.dart';
import 'size_limit_dialog.dart';

/// Shrinks photos to a file-size limit (for example "under 100 kB" on a job or government portal).
class CompressPhotoPage extends StatelessWidget {
  const CompressPhotoPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => CompressCubit(compressor: sl<PhotoCompressor>(), outputDir: getTemporaryDirectory),
    child: const _CompressView(),
  );
}

class _CompressView extends StatelessWidget {
  const _CompressView();

  static const _targets = <(String, int?)>[
    ('20 kB', 20 * 1024),
    ('50 kB', 50 * 1024),
    ('100 kB', 100 * 1024),
    ('200 kB', 200 * 1024),
    ('500 kB', 500 * 1024),
    ('1 MB', 1024 * 1024),
    ('No limit', null),
  ];
  static const _sides = <(String, int?)>[('Original', null), ('3000 px', 3000), ('2000 px', 2000), ('1280 px', 1280), ('1024 px', 1024), ('800 px', 800)];

  Future<void> _pickGallery(BuildContext context) async {
    try {
      final files = await ImagePicker().pickMultiImage();
      if (files.isEmpty || !context.mounted) return;
      await context.read<CompressCubit>().add([for (final f in files) f.path]);
    } catch (_) {
      if (context.mounted) showFailure(context, const PermissionFailure('Photo library access is unavailable.'));
    }
  }

  Future<void> _pickFiles(BuildContext context) async {
    try {
      final picked = await FilePicker.pickFiles(type: FileType.image);
      final paths = [
        for (final f in picked)
          if (f.path != null) f.path!,
      ];
      if (paths.isEmpty || !context.mounted) return;
      await context.read<CompressCubit>().add(paths);
    } catch (_) {
      if (context.mounted) showFailure(context, const PermissionFailure('The file picker is unavailable.'));
    }
  }

  Future<void> _customSize(BuildContext context) async {
    final bytes = await showDialog<int>(context: context, builder: (_) => const SizeLimitDialog());
    if (bytes != null && context.mounted) context.read<CompressCubit>().setTarget(bytes);
  }

  Future<void> _share(BuildContext context, List<CompressedPhoto> results) async {
    final failure = (await sl<ShareService>().shareFiles(
      paths: [for (final r in results) r.path],
      mimeType: results.first.path.endsWith('.png') ? 'image/png' : 'image/jpeg',
    )).failureOrNull;
    if (failure != null && context.mounted) showFailure(context, failure);
  }

  Future<void> _gallery(BuildContext context, List<CompressedPhoto> results) async {
    final result = await sl<SaveService>().saveImagesToGallery([for (final r in results) r.path]);
    if (!context.mounted) return;
    final failure = result.failureOrNull;
    if (failure != null) {
      showFailure(context, failure);
    } else {
      showMessage(context, 'Saved to your gallery');
    }
  }

  Future<void> _files(BuildContext context, CompressedPhoto r) async {
    final name = r.path.split(Platform.pathSeparator).last;
    final result = await sl<SaveService>().saveToFiles(sourcePath: r.path, fileName: name, mimeType: r.path.endsWith('.png') ? 'image/png' : 'image/jpeg');
    if (!context.mounted) return;
    final failure = result.failureOrNull;
    if (failure != null) {
      showFailure(context, failure);
    } else if (result.valueOrNull == true) {
      showMessage(context, 'Saved');
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CompressCubit, CompressState>(
      builder: (context, state) {
        final cubit = context.read<CompressCubit>();
        final running = state.status == CompressStatus.running;
        final results = state.results;
        final customTarget = state.targetBytes != null && !_targets.any((t) => t.$2 == state.targetBytes);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Compress photos'),
            actions: [if (state.items.isNotEmpty && !running) TextButton(onPressed: cubit.clear, child: const Text('Clear'))],
          ),
          body: SafeArea(
            child: ListView(
              padding: contentPadding(context, base: AppSpacing.md, maxWidth: 640),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: running ? null : () => _pickGallery(context),
                        icon: const Icon(AppIcons.gallery, size: 18),
                        label: const Text('Gallery'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: running ? null : () => _pickFiles(context),
                        icon: const Icon(AppIcons.importFile, size: 18),
                        label: const Text('Files'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                if (state.items.isEmpty)
                  const _Hint(text: 'Add one or more photos, choose a size limit, then tap Compress. Everything happens on this phone.')
                else
                  for (final item in state.items) _PhotoRow(item: item, running: running, onRemove: () => cubit.remove(item.path)),
                const SizedBox(height: AppSpacing.md),
                const _Label('Make each photo smaller than'),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final t in _targets)
                      ChoiceChip(label: Text(t.$1), selected: state.targetBytes == t.$2, onSelected: running ? null : (_) => cubit.setTarget(t.$2)),
                    ChoiceChip(
                      label: Text(customTarget ? formatBytes(state.targetBytes!) : 'Custom'),
                      selected: customTarget,
                      onSelected: running ? null : (_) => _customSize(context),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                const _Label('Longest side'),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final s in _sides)
                      ChoiceChip(label: Text(s.$1), selected: state.maxSide == s.$2, onSelected: running ? null : (_) => cubit.setMaxSide(s.$2)),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                const _Label('Save as'),
                SegmentedButton<PhotoFormat>(
                  showSelectedIcon: false,
                  segments: [for (final f in PhotoFormat.values) ButtonSegment(value: f, label: Text(f.label))],
                  selected: {state.format},
                  onSelectionChanged: running ? null : (s) => cubit.setFormat(s.first),
                ),
                if (state.format == PhotoFormat.png)
                  const Padding(
                    padding: EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      'PNG keeps every detail but cannot be squeezed like JPG, so a size limit makes the picture smaller. Use JPG for photos.',
                      style: TextStyle(fontSize: 12, color: AppColors.inkMuted, height: 1.4),
                    ),
                  ),
                const SizedBox(height: AppSpacing.lg),
                FilledButton.icon(
                  onPressed: state.items.isEmpty || running ? null : cubit.run,
                  icon: running
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(AppIcons.quality, size: 18),
                  label: Text(running ? 'Compressing ${state.progress} of ${state.items.length}' : 'Compress'),
                ),
                if (results.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      OutlinedButton.icon(onPressed: () => _share(context, results), icon: const Icon(AppIcons.share, size: 18), label: const Text('Share')),
                      OutlinedButton.icon(
                        onPressed: () => _gallery(context, results),
                        icon: const Icon(AppIcons.download, size: 18),
                        label: const Text('Save to gallery'),
                      ),
                      if (results.length == 1)
                        OutlinedButton.icon(
                          onPressed: () => _files(context, results.first),
                          icon: const Icon(AppIcons.storage, size: 18),
                          label: const Text('Save to Files'),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Text(
      text,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.inkMuted),
    ),
  );
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(AppIcons.info, size: 20, color: AppColors.primary),
          const SizedBox(width: AppSpacing.sm + 4),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13, height: 1.4))),
        ],
      ),
    ),
  );
}

class _PhotoRow extends StatelessWidget {
  const _PhotoRow({required this.item, required this.running, required this.onRemove});
  final CompressItem item;
  final bool running;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final r = item.result;
    final failed = item.failure != null;
    final String detail;
    Color color = AppColors.inkMuted;
    if (failed) {
      detail = item.failure!.message;
      color = AppColors.danger;
    } else if (r != null) {
      final saved = item.bytes == 0 ? 0 : (100 - r.bytes * 100 / item.bytes).round();
      detail =
          '${formatBytes(item.bytes)} to ${formatBytes(r.bytes)}${saved > 0 ? ' ($saved% smaller)' : ''} · ${r.width}x${r.height}'
          '${r.metTarget ? '' : '\nThe limit is too small for this photo. This is the smallest readable result.'}';
      color = r.metTarget ? AppColors.success : AppColors.warning;
    } else {
      detail = formatBytes(item.bytes);
    }
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 48,
            height: 48,
            child: Image.file(File(r?.path ?? item.path), fit: BoxFit.cover, cacheWidth: 120, errorBuilder: (_, _, _) => const Icon(AppIcons.gallery)),
          ),
        ),
        title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(detail, style: TextStyle(color: color, fontSize: 12.5)),
        trailing: running ? null : IconButton(tooltip: 'Remove', icon: const Icon(AppIcons.close, size: 18), onPressed: onRemove),
      ),
    );
  }
}

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide Text;
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
import '../domain/metadata_cleaner.dart';
import 'privacy_clean_cubit.dart';
import '../../../core/widgets/text.dart';
import '../../../core/i18n/tr.dart';

/// Shows what hidden data photos carry (location, camera, date) and removes it before sharing.
class PrivacyCleanPage extends StatelessWidget {
  const PrivacyCleanPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => PrivacyCleanCubit(cleaner: sl<MetadataCleaner>(), outputDir: getTemporaryDirectory),
    child: const _CleanView(),
  );
}

class _CleanView extends StatelessWidget {
  const _CleanView();

  Future<void> _gallery(BuildContext context) async {
    try {
      final files = await ImagePicker().pickMultiImage(requestFullMetadata: true);
      if (files.isEmpty || !context.mounted) return;
      await context.read<PrivacyCleanCubit>().add([for (final f in files) f.path]);
    } catch (_) {
      if (context.mounted) showFailure(context, const PermissionFailure('Photo library access is unavailable.'));
    }
  }

  Future<void> _files(BuildContext context) async {
    try {
      final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['jpg', 'jpeg', 'png']);
      final paths = [
        for (final f in picked)
          if (f.path != null) f.path!,
      ];
      if (paths.isEmpty || !context.mounted) return;
      await context.read<PrivacyCleanCubit>().add(paths);
    } catch (_) {
      if (context.mounted) showFailure(context, const PermissionFailure('The file picker is unavailable.'));
    }
  }

  Future<void> _share(BuildContext context, List<CleanedPhoto> results) async {
    final failure = (await sl<ShareService>().shareFiles(paths: [for (final r in results) r.path], mimeType: 'image/*')).failureOrNull;
    if (failure != null && context.mounted) showFailure(context, failure);
  }

  Future<void> _toGallery(BuildContext context, List<CleanedPhoto> results) async {
    final result = await sl<SaveService>().saveImagesToGallery([for (final r in results) r.path]);
    if (!context.mounted) return;
    final failure = result.failureOrNull;
    failure != null ? showFailure(context, failure) : showMessage(context, 'Saved to your gallery');
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PrivacyCleanCubit, PrivacyCleanState>(
      builder: (context, state) {
        final cubit = context.read<PrivacyCleanCubit>();
        final running = state.status == CleanStatus.running;
        final results = state.results;
        final totalHidden = state.cleanable.fold<int>(0, (sum, i) => sum + i.metadata!.hiddenBytes);
        return Scaffold(
          appBar: AppBar(
            title: const Text('Remove photo data'),
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
                        onPressed: running ? null : () => _gallery(context),
                        icon: const Icon(AppIcons.gallery, size: 18),
                        label: const Text('Photos'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: running ? null : () => _files(context),
                        icon: const Icon(AppIcons.importFile, size: 18),
                        label: const Text('Files'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                if (state.items.isEmpty)
                  const _Hint(
                    text:
                        'Photos often carry the place and time they were taken and the phone model. Add photos to see what they carry, then remove it before you share them.',
                  ),
                if (state.checking)
                  const Padding(
                    padding: EdgeInsets.all(AppSpacing.md),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                for (final item in state.items) _PhotoRow(item: item, running: running, onRemove: () => cubit.remove(item.path)),
                const SizedBox(height: AppSpacing.sm),
                FilledButton.icon(
                  onPressed: state.cleanable.isEmpty || running ? null : cubit.run,
                  icon: running
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(AppIcons.shield, size: 18),
                  label: Text(
                    running
                        ? 'Cleaning ${state.progress} of ${state.cleanable.length}'
                        : (totalHidden > 0 ? 'Remove hidden data (${formatBytes(totalHidden)})' : 'Remove hidden data'),
                  ),
                ),
                if (results.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Card(
                    margin: EdgeInsets.zero,
                    color: AppColors.primarySoft,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            results.length == 1 ? 'Your clean photo is ready' : '${results.length} clean photos are ready',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          const Text(
                            'The pictures look exactly the same. Send these copies instead of the originals.',
                            style: TextStyle(fontSize: 12.5, height: 1.4),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.sm,
                            children: [
                              FilledButton.icon(
                                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                                onPressed: () => _share(context, results),
                                icon: const Icon(AppIcons.share, size: 18),
                                label: const Text('Share'),
                              ),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                                onPressed: () => _toGallery(context, results),
                                icon: const Icon(AppIcons.download, size: 18),
                                label: const Text('Save to gallery'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                const _Hint(
                  text:
                      'Chat apps usually remove the location when a photo is sent as a picture, but email, cloud links and "send as file" keep it. Only JPG and PNG photos can be cleaned.',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
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
  final CleanItem item;
  final bool running;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final meta = item.metadata;
    final r = item.result;
    final lines = <String>[];
    Color color = AppColors.inkMuted;
    if (item.failure != null) {
      lines.add(item.failure!.message);
      color = AppColors.danger;
    } else if (r != null) {
      lines.add('Clean. Removed ${formatBytes(r.removedBytes)} of hidden data.');
      color = AppColors.success;
    } else if (meta != null) {
      if (meta.isClean) {
        lines.add('Nothing hidden found');
        color = AppColors.success;
      } else {
        if (meta.hasLocation) lines.add('Location where it was taken');
        if (meta.camera != null) lines.add('Phone or camera: ${meta.camera}');
        if (meta.takenAt != null) lines.add('Date and time: ${meta.takenAt}');
        if (meta.software != null) lines.add('Edited with: ${meta.software}');
        if (meta.hasOtherData) lines.add('Other embedded data (${formatBytes(meta.hiddenBytes)})');
        color = meta.hasLocation ? AppColors.danger : AppColors.warning;
      }
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
        subtitle: Text(lines.join('\n'), style: TextStyle(color: color, fontSize: 12.5, height: 1.35)),
        isThreeLine: lines.length > 1,
        trailing: running ? null : IconButton(tooltip: tr('Remove'), icon: const Icon(AppIcons.close, size: 18), onPressed: onRemove),
      ),
    );
  }
}

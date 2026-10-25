import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path_provider/path_provider.dart';

import '../../../app/di.dart';
import '../../../core/error/failures.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/responsive.dart';
import '../../export/domain/repositories/export_repository.dart';
import '../../photo_tools/presentation/size_limit_dialog.dart';
import '../domain/pdf_compressor.dart';
import 'pdf_compress_cubit.dart';

/// Shrinks a PDF to fit an email or upload limit.
class PdfCompressPage extends StatelessWidget {
  const PdfCompressPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => PdfCompressCubit(compressor: sl<PdfCompressor>(), outputDir: getTemporaryDirectory),
    child: const _CompressView(),
  );
}

const _targets = <(String, int?)>[
  ('200 kB', 200 * 1024),
  ('500 kB', 500 * 1024),
  ('1 MB', 1024 * 1024),
  ('2 MB', 2 * 1024 * 1024),
  ('5 MB', 5 * 1024 * 1024),
  ('Just smaller', null),
];

class _CompressView extends StatelessWidget {
  const _CompressView();

  Future<void> _pick(BuildContext context) async {
    try {
      final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['pdf']);
      final path = picked.isEmpty ? null : picked.first.path;
      if (path == null || !context.mounted) return;
      await context.read<PdfCompressCubit>().pick(path);
    } catch (_) {
      if (context.mounted) showFailure(context, const PermissionFailure('The file picker is unavailable.'));
    }
  }

  Future<void> _custom(BuildContext context) async {
    final bytes = await showDialog<int>(context: context, builder: (_) => const SizeLimitDialog());
    if (bytes != null && context.mounted) context.read<PdfCompressCubit>().setTarget(bytes);
  }

  Future<void> _share(BuildContext context, CompressedPdf r) async {
    final failure = (await sl<ShareService>().shareFiles(paths: [r.path], mimeType: 'application/pdf')).failureOrNull;
    if (failure != null && context.mounted) showFailure(context, failure);
  }

  Future<void> _save(BuildContext context, CompressedPdf r, String name) async {
    final result = await sl<SaveService>().saveToFiles(
      sourcePath: r.path,
      fileName: '${name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '').replaceAll(' ', '_')}_small.pdf',
      mimeType: 'application/pdf',
    );
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
    return BlocBuilder<PdfCompressCubit, PdfCompressState>(
      builder: (context, state) {
        final cubit = context.read<PdfCompressCubit>();
        final running = state.status == PdfCompressStatus.running;
        final result = state.result;
        final customTarget = state.targetBytes != null && !_targets.any((t) => t.$2 == state.targetBytes);
        return Scaffold(
          appBar: AppBar(
            title: const Text('Compress PDF'),
            actions: [if (state.path != null && !running) TextButton(onPressed: cubit.clear, child: const Text('Clear'))],
          ),
          body: SafeArea(
            child: ListView(
              padding: contentPadding(context, base: AppSpacing.md, maxWidth: 640),
              children: [
                if (state.path == null)
                  FilledButton.icon(onPressed: () => _pick(context), icon: const Icon(AppIcons.importFile, size: 18), label: const Text('Choose a PDF'))
                else
                  Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      leading: const Icon(AppIcons.pdf, color: AppColors.primary),
                      title: Text(state.name!, maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text(formatBytes(state.bytes)),
                      trailing: running ? null : TextButton(onPressed: () => _pick(context), child: const Text('Change')),
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),
                const Text('Make it smaller than', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final t in _targets)
                      ChoiceChip(label: Text(t.$1), selected: state.targetBytes == t.$2, onSelected: running ? null : (_) => cubit.setTarget(t.$2)),
                    ChoiceChip(
                      label: Text(customTarget ? formatBytes(state.targetBytes!) : 'Custom'),
                      selected: customTarget,
                      onSelected: running ? null : (_) => _custom(context),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                FilledButton.icon(
                  onPressed: state.path == null || running ? null : cubit.run,
                  icon: running
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(AppIcons.pdfCompress, size: 18),
                  label: Text(running ? (state.attempts > 1 ? 'Trying setting ${state.attempt} of ${state.attempts}' : 'Working') : 'Compress PDF'),
                ),
                if (state.failure != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.md),
                    child: Text(state.failure!.message, style: const TextStyle(color: AppColors.danger, height: 1.4)),
                  ),
                if (result != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  _ResultCard(
                    result: result,
                    target: state.targetBytes,
                    name: state.name!,
                    onShare: () => _share(context, result),
                    onSave: () => _save(context, result, state.name!),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                const _Note(),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result, required this.target, required this.name, required this.onShare, required this.onSave});
  final CompressedPdf result;
  final int? target;
  final String name;
  final VoidCallback onShare;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final String headline;
    final String detail;
    if (result.unchanged && result.metTarget && target != null && result.pages == 0) {
      headline = 'Already small enough';
      detail = 'This PDF is ${formatBytes(result.bytes)}, which is under your limit. Nothing was changed.';
    } else if (result.unchanged) {
      headline = 'Could not make it smaller';
      detail = 'This PDF is already compact, so redrawing it would make it bigger. Your original is unchanged.';
    } else {
      headline = result.metTarget ? 'Done: ${formatBytes(result.originalBytes)} to ${formatBytes(result.bytes)}' : 'Smaller, but still above your limit';
      detail = result.metTarget
          ? 'Saved ${formatBytes(result.savedBytes)} across ${result.pages} ${result.pages == 1 ? 'page' : 'pages'}.'
          : 'This is the smallest the pages can be while staying readable: ${formatBytes(result.bytes)}. Try a higher limit, or split the PDF into parts.';
    }
    return Card(
      margin: EdgeInsets.zero,
      color: result.metTarget ? AppColors.primarySoft : null,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(headline, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: AppSpacing.xs),
            Text(detail, style: const TextStyle(fontSize: 12.5, height: 1.4)),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: onShare,
                  icon: const Icon(AppIcons.share, size: 18),
                  label: const Text('Share'),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: onSave,
                  icon: const Icon(AppIcons.storage, size: 18),
                  label: const Text('Save to Files'),
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
          Icon(AppIcons.info, size: 20, color: AppColors.primary),
          SizedBox(width: AppSpacing.sm + 4),
          Expanded(
            child: Text(
              'Every page is redrawn as a picture at lower quality until the file fits. Text stays readable but can no longer be selected or searched, and links and form fields are removed. '
              'Password-protected PDFs cannot be opened.',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    ),
  );
}

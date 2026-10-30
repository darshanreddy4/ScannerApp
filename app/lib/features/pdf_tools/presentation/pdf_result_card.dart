import 'package:flutter/material.dart' hide Text;
import 'package:path/path.dart' as p;

import '../../../app/di.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/feedback.dart';
import '../../export/domain/repositories/export_repository.dart';
import '../../../core/widgets/text.dart';

/// Shown when a tool has made a PDF: what it is, and buttons to send it on or keep it.
class PdfResultCard extends StatelessWidget {
  const PdfResultCard({super.key, required this.title, required this.message, required this.path});
  final String title;
  final String message;
  final String path;

  Future<void> _share(BuildContext context) async {
    final failure = (await sl<ShareService>().shareFiles(paths: [path], mimeType: 'application/pdf')).failureOrNull;
    if (failure != null && context.mounted) showFailure(context, failure);
  }

  Future<void> _save(BuildContext context) async {
    final result = await sl<SaveService>().saveToFiles(
      sourcePath: path,
      fileName: p.basename(path).replaceAll(RegExp(r'_\d{10,}(?=\.pdf$)'), ''),
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
  Widget build(BuildContext context) => Card(
    key: const ValueKey('pdf-result'),
    margin: EdgeInsets.zero,
    color: AppColors.primarySoft,
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: AppSpacing.xs),
          Text(message, style: const TextStyle(fontSize: 12.5, height: 1.4)),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              FilledButton.icon(
                key: const ValueKey('pdf-result-share'),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: () => _share(context),
                icon: const Icon(AppIcons.share, size: 18),
                label: const Text('Share'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('pdf-result-save'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: () => _save(context),
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

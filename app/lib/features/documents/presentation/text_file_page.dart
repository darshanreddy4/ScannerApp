import 'dart:io';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../../app/di.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/text.dart';
import '../../../core/i18n/tr.dart';
import '../../export/domain/repositories/export_repository.dart';

/// Shows a text file from the library, with copy and share.
class TextFilePage extends StatelessWidget {
  const TextFilePage({super.key, required this.path});
  final String path;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(p.basename(path), overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16)),
      actions: [
        IconButton(
          key: const ValueKey('text-file-copy'),
          tooltip: tr('Copy'),
          icon: const Icon(AppIcons.copy),
          onPressed: () async {
            final text = await File(path).readAsString();
            await Clipboard.setData(ClipboardData(text: text));
            if (context.mounted) showMessage(context, 'Copied');
          },
        ),
        IconButton(
          key: const ValueKey('text-file-share'),
          tooltip: tr('Share'),
          icon: const Icon(AppIcons.share),
          onPressed: () => sl<ShareService>().shareFile(path: path, mimeType: 'text/plain'),
        ),
      ],
    ),
    body: FutureBuilder<String>(
      future: File(path).readAsString(),
      builder: (context, snap) {
        if (snap.hasError) return const Center(child: Text('The file could not be opened.', style: TextStyle(color: AppColors.inkMuted)));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: SelectableText(snap.data!, style: const TextStyle(fontSize: 15, height: 1.45)),
        );
      },
    ),
  );
}

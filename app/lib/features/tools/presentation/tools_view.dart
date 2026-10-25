import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/failures.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/feedback.dart';
import '../../importer/domain/importer.dart';
import '../../reader/presentation/reader_page.dart';
import '../../scanner/presentation/add_content.dart';

/// Hub for everything that works on files, beyond scanning.
class ToolsView extends StatelessWidget {
  const ToolsView({super.key});

  Future<void> _openReader(BuildContext context) async {
    try {
      final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['pdf', 'docx']);
      final path = picked.isEmpty ? null : picked.first.path;
      if (path == null || !context.mounted) return;
      final kind = path.toLowerCase().endsWith('.pdf') ? ImportKind.pdf : ImportKind.docx;
      context.push(
        '/reader',
        extra: ReaderArgs(path: path, kind: kind),
      );
    } catch (_) {
      if (context.mounted) showFailure(context, const PermissionFailure('The file picker is unavailable.'));
    }
  }

  Future<void> _editText(BuildContext context, {required String extension, required String route}) async {
    try {
      final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: [extension]);
      final path = picked.isEmpty ? null : picked.first.path;
      if (path == null || !context.mounted) return;
      context.push(route, extra: path);
    } catch (_) {
      if (context.mounted) showFailure(context, const PermissionFailure('The file picker is unavailable.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: contentPadding(context),
      children: [
        const _SectionLabel('PDF and documents'),
        _ToolGrid([
          _Tool(icon: AppIcons.reader, color: 0xFF2563EB, title: 'Read PDF or Word', hint: 'Open, zoom and read', onTap: () => _openReader(context)),
          _Tool(
            icon: AppIcons.edit,
            color: 0xFFE5322D,
            title: 'Edit a PDF',
            hint: 'Draw, reorder, crop, filter',
            onTap: () => startImportFile(context, ImportKind.pdf),
          ),
          _Tool(
            icon: AppIcons.editDocument,
            color: 0xFFD6336C,
            title: 'Edit text in a PDF',
            hint: 'Retype lines, add text',
            onTap: () => _editText(context, extension: 'pdf', route: '/pdf-edit'),
          ),
          _Tool(
            icon: AppIcons.markup,
            color: 0xFF2B579A,
            title: 'Edit a Word file',
            hint: 'Mark up Word pages',
            onTap: () => startImportFile(context, ImportKind.docx),
          ),
          _Tool(
            icon: AppIcons.docx,
            color: 0xFF1C7ED6,
            title: 'Edit text in a Word file',
            hint: 'Change words, keep the layout',
            onTap: () => _editText(context, extension: 'docx', route: '/docx-edit'),
          ),
          _Tool(icon: AppIcons.combine, color: 0xFFF97316, title: 'Combine files', hint: 'Merge PDF and Word files', onTap: () => startCombineFiles(context)),
          _Tool(
            icon: AppIcons.pdfCompress,
            color: 0xFF16A34A,
            title: 'Compress PDF',
            hint: 'Shrink below any size',
            onTap: () => context.push('/compress-pdf'),
          ),
          _Tool(
            icon: AppIcons.lock,
            color: 0xFF4F46E5,
            title: 'Lock or unlock PDF',
            hint: 'Add or remove a password',
            onTap: () => context.push('/pdf-password'),
          ),
          _Tool(
            icon: AppIcons.pdfPages,
            color: 0xFF9333EA,
            title: 'Split and number PDF',
            hint: 'Split, rotate, page numbers',
            onTap: () => context.push('/pdf-pages'),
          ),
          _Tool(icon: AppIcons.signature, color: 0xFF0D9488, title: 'Signature', hint: 'Draw once, sign anywhere', onTap: () => context.push('/signature')),
        ]),
        const _SectionLabel('Office files'),
        _ToolGrid([
          _Tool(
            icon: AppIcons.sheet,
            color: 0xFF107C41,
            title: 'Spreadsheets (Excel and CSV)',
            hint: 'Open, edit, convert',
            onTap: () => context.push('/office-sheets'),
          ),
          _Tool(
            icon: AppIcons.slides,
            color: 0xFFD24726,
            title: 'Presentations (PowerPoint)',
            hint: 'Open, edit, convert',
            onTap: () => context.push('/office-slides'),
          ),
        ]),
        const _SectionLabel('Photo tools'),
        _ToolGrid([
          _Tool(
            icon: AppIcons.idPhoto,
            color: 0xFF0284C7,
            title: 'Passport and ID photos',
            hint: 'Right size, clean background',
            onTap: () => context.push('/passport-photo'),
          ),
          _Tool(icon: AppIcons.idCopy, color: 0xFFD97706, title: 'ID card copy', hint: 'Both sides on one page', onTap: () => context.push('/id-card')),
          _Tool(
            icon: AppIcons.photoCompress,
            color: 0xFF059669,
            title: 'Compress photos',
            hint: 'Under 20, 50 or 100 kB',
            onTap: () => context.push('/compress-photo'),
          ),
          _Tool(icon: AppIcons.watermark, color: 0xFF0891B2, title: 'Add watermark', hint: 'Name or logo on photos', onTap: () => context.push('/watermark')),
          _Tool(
            icon: AppIcons.shield,
            color: 0xFFE11D48,
            title: 'Remove photo data',
            hint: 'Strip location and phone',
            onTap: () => context.push('/privacy-clean'),
          ),
        ]),
        const _SectionLabel('More tools'),
        _ToolGrid([_Tool(icon: AppIcons.qr, color: 0xFF334155, title: 'QR code generator', hint: 'Links, text and Wi-Fi', onTap: () => context.push('/qr'))]),
        const SizedBox(height: AppSpacing.md),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(AppIcons.shield, size: 20, color: AppColors.success),
                SizedBox(width: AppSpacing.sm + 4),
                Expanded(
                  child: Text(
                    'To send a saved document by QR code, open it and tap the QR button. The file goes straight to the other phone over Wi-Fi and is never uploaded.',
                    style: TextStyle(fontSize: 13, height: 1.4, color: AppColors.inkMuted),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(AppSpacing.xs, AppSpacing.md, 0, AppSpacing.sm + 2),
    child: Row(
      children: [
        Container(
          width: 4,
          height: 16,
          decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          text,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink, letterSpacing: 0.2),
        ),
      ],
    ),
  );
}

class _Tool {
  const _Tool({required this.icon, required this.color, required this.title, required this.hint, required this.onTap});
  final IconData icon;
  final int color;
  final String title;
  final String hint;
  final VoidCallback onTap;
}

/// Tiles in rows of two (three on wide screens); each row is as tall as its tallest tile.
class _ToolGrid extends StatelessWidget {
  const _ToolGrid(this.tools);
  final List<_Tool> tools;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final columns = box.maxWidth >= 760 ? 4 : (box.maxWidth >= 520 ? 3 : 2);
      const gap = AppSpacing.sm + 4;
      final rows = <Widget>[];
      for (var i = 0; i < tools.length; i += columns) {
        final chunk = tools.skip(i).take(columns).toList();
        rows.add(
          Padding(
            padding: const EdgeInsets.only(bottom: gap),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var c = 0; c < columns; c++) ...[
                    if (c > 0) const SizedBox(width: gap),
                    Expanded(child: c < chunk.length ? _ToolTile(chunk[c]) : const SizedBox.shrink()),
                  ],
                ],
              ),
            ),
          ),
        );
      }
      return Column(children: rows);
    },
  );
}

class _ToolTile extends StatelessWidget {
  const _ToolTile(this.tool);
  final _Tool tool;

  @override
  Widget build(BuildContext context) {
    final accent = Color(tool.color);
    final light = Color.lerp(accent, Colors.white, 0.28)!;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: tool.onTap,
        child: Stack(
          children: [
            Positioned(
              right: -22,
              top: -22,
              child: Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(shape: BoxShape.circle, color: accent.withValues(alpha: 0.08)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md - 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [light, accent]),
                      boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.32), blurRadius: 10, offset: const Offset(0, 4))],
                    ),
                    child: Icon(tool.icon, color: Colors.white, size: 24),
                  ),
                  const SizedBox(height: AppSpacing.sm + 4),
                  Text(tool.title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, height: 1.2)),
                  const SizedBox(height: 3),
                  Text(tool.hint, style: const TextStyle(fontSize: 12, color: AppColors.inkMuted, height: 1.25)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

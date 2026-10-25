import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/failures.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/responsive.dart';
import '../convert/office_converter.dart';
import '../sheets/presentation/sheet_page.dart';

enum OfficeHub { sheets, slides }

/// The start page of the spreadsheet tools or the presentation tools: open, create and convert.
class OfficeHubPage extends StatelessWidget {
  const OfficeHubPage({super.key, required this.hub});

  final OfficeHub hub;

  Future<void> _open(BuildContext context) async {
    final sheets = hub == OfficeHub.sheets;
    try {
      final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: sheets ? const ['xlsx', 'csv', 'tsv'] : const ['pptx']);
      final path = picked.isEmpty ? null : picked.first.path;
      if (path == null || !context.mounted) return;
      if (sheets) {
        await context.push('/sheet', extra: SheetArgs(path: path));
      } else {
        await context.push('/slides', extra: path);
      }
    } catch (_) {
      if (context.mounted) showFailure(context, const PermissionFailure('The file picker is unavailable.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final sheets = hub == OfficeHub.sheets;
    final conversions = [
      for (final c in OfficeConversion.values)
        if (c.isSlides != sheets) c,
    ];
    return Scaffold(
      appBar: AppBar(title: Text(sheets ? 'Spreadsheets' : 'Presentations')),
      body: SafeArea(
        child: ListView(
          padding: contentPadding(context, base: AppSpacing.md, maxWidth: 640),
          children: [
            _Tile(
              key: const ValueKey('hub_open'),
              icon: sheets ? AppIcons.sheet : AppIcons.slides,
              title: sheets ? 'Open an Excel or CSV file' : 'Open a PowerPoint file',
              subtitle: sheets
                  ? 'View it, change cells and formulas, format, add sheets, then save or share.'
                  : 'View it, edit text and pictures, add or reorder slides, then save or share.',
              onTap: () => _open(context),
            ),
            _Tile(
              key: const ValueKey('hub_new'),
              icon: AppIcons.add,
              title: sheets ? 'New spreadsheet' : 'New presentation',
              subtitle: sheets ? 'Start with an empty workbook.' : 'Start with a blank slide.',
              onTap: () => sheets ? context.push('/sheet', extra: const SheetArgs()) : context.push('/slides', extra: null),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(4, AppSpacing.md, 4, AppSpacing.sm),
              child: Text('Convert', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
            for (final c in conversions)
              _Tile(
                key: ValueKey('hub_${c.name}'),
                icon: AppIcons.convert,
                title: c.title,
                subtitle: c.description,
                onTap: () => context.push('/office-convert', extra: c),
              ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({super.key, required this.icon, required this.title, required this.subtitle, required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: InkWell(
      borderRadius: BorderRadius.circular(AppSpacing.radius),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: AppColors.primary, size: 22),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted, height: 1.35)),
                ],
              ),
            ),
            const Icon(AppIcons.next, size: 18, color: AppColors.inkMuted),
          ],
        ),
      ),
    ),
  );
}

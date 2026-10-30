import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:go_router/go_router.dart';

import '../../../core/error/failures.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/i18n/tr.dart';
import '../../../core/utils/region.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/feedback.dart';
import '../../importer/domain/importer.dart';
import '../../rewards/domain/coin_rules.dart';
import '../../monetization/presentation/inline_ad.dart';
import '../../rewards/presentation/unlock.dart';
import '../../reader/presentation/reader_page.dart';
import '../../scanner/domain/entities/scan_mode.dart';
import '../../scanner/presentation/add_content.dart';
import '../../../core/widgets/text.dart';

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

  Future<void> _tablePhoto(BuildContext context) async {
    final camera = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const ValueKey('table-camera'),
              leading: const Icon(AppIcons.camera),
              title: const Text('Scan a table with the camera'),
              onTap: () => Navigator.pop(ctx, true),
            ),
            ListTile(
              key: const ValueKey('table-gallery'),
              leading: const Icon(AppIcons.gallery),
              title: const Text('Choose a photo of a table'),
              onTap: () => Navigator.pop(ctx, false),
            ),
          ],
        ),
      ),
    );
    if (camera == null || !context.mounted) return;
    if (camera) {
      startScan(context, mode: ScanMode.table);
    } else {
      await startImport(context, mode: ScanMode.table);
    }
  }

  /// Tools made for one country or region; the person's own group comes first, the others wait in a folded list.
  Map<ToolRegion, List<_Tool>> _regionTools(BuildContext context) => {
    ToolRegion.india: <_Tool>[
      _Tool(
        icon: AppIcons.qr,
        color: 0xFF16A34A,
        title: 'UPI payment QR',
        tier: CoinTier.light,
        hint: 'Make a code to get paid; scanner reads it',
        onTap: () => context.push('/qr-upi'),
      ),
      _Tool(
        icon: AppIcons.receipt,
        color: 0xFF0F766E,
        title: 'GST invoice',
        hint: 'CGST, SGST, IGST, HSN and UPI code',
        onTap: () => context.push('/gst-invoice'),
      ),
    ],
    ToolRegion.usa: <_Tool>[
      _Tool(
        icon: AppIcons.receipt,
        color: 0xFF1D4ED8,
        title: 'US invoice',
        hint: 'Sales tax, discount, shipping, balance due',
        onTap: () => context.push('/us-invoice'),
      ),
    ],
    ToolRegion.gulf: <_Tool>[
      _Tool(
        icon: AppIcons.receipt,
        color: 0xFF047857,
        title: 'Saudi VAT invoice',
        hint: 'Arabic and English, 15% VAT, QR code',
        onTap: () => context.push('/zatca-invoice'),
      ),
    ],
    ToolRegion.europe: <_Tool>[
      _Tool(
        icon: AppIcons.qr,
        color: 0xFF1D4ED8,
        title: 'Payment QR (SEPA)',
        tier: CoinTier.light,
        hint: 'Make a Girocode; scanner reads it',
        onTap: () => context.push('/qr-payment'),
      ),
      _Tool(
        icon: AppIcons.receipt,
        color: 0xFF0F766E,
        title: 'E-invoice viewer',
        hint: 'Factur-X, ZUGFeRD, XRechnung, FatturaPA',
        onTap: () => context.push('/einvoice'),
      ),
      _Tool(icon: AppIcons.sheet, color: 0xFF7C3AED, title: 'Invoice maker', hint: 'VAT, IBAN, DIN 5008 layout', onTap: () => context.push('/invoice')),
      _Tool(icon: AppIcons.user, color: 0xFF0284C7, title: 'CV maker', hint: 'European style, as a PDF', onTap: () => context.push('/cv')),
      _Tool(
        icon: AppIcons.receipt,
        color: 0xFFB45309,
        title: 'VAT refund receipts',
        hint: 'Tax-free shopping and deadlines',
        onTap: () => context.push('/vat-refund'),
      ),
      _Tool(
        icon: AppIcons.signature,
        color: 0xFF4338CA,
        title: 'Sign with certificate',
        hint: 'Your .p12/.pfx; check PDF signatures',
        onTap: () => context.push('/pdf-certificate'),
      ),
      // EUROPE-TOOLS
    ],
  };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(listenable: Region.toolsChanged, builder: _build);
  }

  Widget _build(BuildContext context, Widget? _) {
    final byRegion = _regionTools(context);
    final mine = Region.toolRegion;
    final own = byRegion[mine] ?? const <_Tool>[];
    final others = [
      for (final e in byRegion.entries)
        if (e.key != mine && e.value.isNotEmpty) e,
    ];
    return ListView(
      padding: contentPadding(context),
      children: [
        const _FeaturedTool(),
        if (own.isNotEmpty) ...[
          _SectionLabel(trf('For {region}', {'region': tr(mine.label)})),
          _ToolGrid(own),
        ],
        const _SectionLabel('PDF and documents'),
        _ToolGrid([
          _Tool(
            icon: AppIcons.reader,
            color: 0xFF2563EB,
            title: 'Read PDF or Word',
            tier: CoinTier.free,
            hint: 'Open, zoom and read',
            onTap: () => _openReader(context),
          ),
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
          _Tool(
            icon: AppIcons.signature,
            color: 0xFF0D9488,
            title: 'Signature',
            tier: CoinTier.light,
            hint: 'Draw once, sign anywhere',
            onTap: () => context.push('/signature'),
          ),
          _Tool(icon: AppIcons.formFill, color: 0xFF2563EB, title: 'Fill a PDF form', hint: 'Boxes, text, date, ticks', onTap: () => context.push('/pdf-form')),
          _Tool(
            icon: AppIcons.markRedact,
            color: 0xFF111827,
            title: 'Hide text in a PDF',
            hint: 'Black out for good',
            onTap: () => context.push('/pdf-redact'),
          ),
          _Tool(icon: AppIcons.crop, color: 0xFFDB2777, title: 'Crop PDF pages', hint: 'Cut margins', onTap: () => context.push('/pdf-crop')),
          _Tool(icon: AppIcons.pdfImage, color: 0xFF0EA5E9, title: 'PDF to pictures', hint: 'Pages or inner images', onTap: () => context.push('/pdf-images')),
          _Tool(icon: AppIcons.flatten, color: 0xFF64748B, title: 'Flatten PDF', hint: 'Make notes permanent', onTap: () => context.push('/pdf-flatten')),
          _Tool(icon: AppIcons.fileDiff, color: 0xFF7C3AED, title: 'Compare two PDFs', hint: 'See what changed', onTap: () => context.push('/compare-pdf')),
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
          _Tool(icon: AppIcons.table, color: 0xFF16A34A, title: 'Table to Excel', hint: 'Photo of a table to a sheet', onTap: () => _tablePhoto(context)),
          _Tool(
            icon: AppIcons.receipt,
            color: 0xFFD97706,
            title: 'Receipts to Excel',
            hint: 'Bills, totals and months',
            onTap: () => context.push('/expenses'),
          ),
          _Tool(
            icon: AppIcons.slides,
            color: 0xFFD24726,
            title: 'Presentations (PowerPoint)',
            hint: 'Open, edit, convert',
            onTap: () => context.push('/office-slides'),
          ),
        ]),
        // Between two groups of tools, with space around it, never next to a tool that could be tapped by mistake.
        const InlineAd(),
        const _SectionLabel('Photo tools'),
        _ToolGrid([
          _Tool(
            icon: AppIcons.idPhoto,
            color: 0xFF0284C7,
            title: 'Passport and ID photos',
            hint: 'Right size, clean background',
            onTap: () => context.push('/passport-photo'),
          ),
          _Tool(
            icon: AppIcons.idCopy,
            color: 0xFFD97706,
            title: 'ID card copy',
            tier: CoinTier.light,
            hint: 'Both sides on one page',
            onTap: () => context.push('/id-card'),
          ),
          _Tool(
            icon: AppIcons.shield,
            color: 0xFF0F766E,
            title: 'Safe ID copy',
            hint: 'Cover numbers, mark what it is for',
            onTap: () => context.push('/safe-id'),
          ),
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
        _ToolGrid([
          _Tool(
            icon: AppIcons.scanQr,
            color: 0xFF0F766E,
            title: 'Scan QR or barcode',
            tier: CoinTier.light,
            hint: 'Open, save or join',
            onTap: () => context.push('/qr-scan'),
          ),
          _Tool(
            icon: AppIcons.qr,
            color: 0xFF334155,
            title: 'QR code generator',
            tier: CoinTier.light,
            hint: 'Links, text and Wi-Fi',
            onTap: () => context.push('/qr'),
          ),
          _Tool(
            icon: AppIcons.receipt,
            color: 0xFFB45309,
            title: 'Amount in words',
            tier: CoinTier.light,
            hint: 'For cheques and invoices',
            onTap: () => context.push('/amount-words'),
          ),
          _Tool(
            icon: AppIcons.cards,
            color: 0xFF7C3AED,
            title: 'Loyalty cards',
            tier: CoinTier.light,
            hint: 'Show card codes at the till',
            onTap: () => context.push('/cards'),
          ),
          _Tool(
            icon: AppIcons.checklist,
            color: 0xFF0EA5E9,
            title: 'Checklists',
            tier: CoinTier.light,
            hint: 'Papers for life events',
            onTap: () => context.push('/checklists'),
          ),
          _Tool(
            icon: AppIcons.packet,
            color: 0xFF4F46E5,
            title: 'Application packet',
            hint: 'Papers in one PDF, within a size limit',
            onTap: () => context.push('/packet'),
          ),
          _Tool(
            icon: AppIcons.calendar,
            color: 0xFF047857,
            title: 'Hijri calendar',
            tier: CoinTier.light,
            hint: 'Convert dates, Ramadan and Eid reminders',
            onTap: () => context.push('/hijri'),
          ),
        ]),
        if (others.isNotEmpty) _OtherCountries(groups: others),
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

/// Tools made for other countries: folded away unless the person asked to see every country's tools.
class _OtherCountries extends StatefulWidget {
  const _OtherCountries({required this.groups});
  final List<MapEntry<ToolRegion, List<_Tool>>> groups;

  @override
  State<_OtherCountries> createState() => _OtherCountriesState();
}

class _OtherCountriesState extends State<_OtherCountries> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final open = _open || Region.showAllTools;
    final count = widget.groups.fold<int>(0, (n, g) => n + g.value.length);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.md),
        Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            key: const ValueKey('other-countries'),
            title: const Text('Tools for other countries'),
            subtitle: Text(trf('{n} tools, kept out of the way', {'n': count})),
            trailing: Icon(open ? Icons.expand_less : Icons.expand_more),
            onTap: Region.showAllTools ? null : () => setState(() => _open = !_open),
          ),
        ),
        if (open)
          for (final g in widget.groups) ...[_SectionLabel(tr(g.key.label)), _ToolGrid(g.value)],
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.xs, AppSpacing.md, 0, AppSpacing.sm + 2),
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

/// The OCR tool, first on the page: pictures and PDFs to text, with translation and a voice.
class _FeaturedTool extends StatelessWidget {
  const _FeaturedTool();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
    child: Card(
      key: const ValueKey('tool-ocr'),
      margin: EdgeInsets.zero,
      color: AppColors.primarySoft,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          if (await requestToolAccess(context, CoinFeature.readText) && context.mounted) context.push('/ocr-tool');
        },
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(12)),
                child: const Icon(AppIcons.ocr, color: Colors.white),
              ),
              const SizedBox(width: AppSpacing.md),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('OCR and translate', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    SizedBox(height: 2),
                    Text(
                      'Read text from pictures and PDFs, translate it and listen to it',
                      style: TextStyle(fontSize: 13, height: 1.35, color: AppColors.inkMuted),
                    ),
                  ],
                ),
              ),
              const Icon(AppIcons.translate, color: AppColors.primary),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Tool {
  const _Tool({required this.icon, required this.color, required this.title, required this.hint, required this.onTap, this.tier = CoinTier.heavy});
  final IconData icon;
  final int color;
  final String title;
  final String hint;
  final VoidCallback onTap;

  /// What the tool costs a Free user each use.
  final CoinTier tier;
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
        onTap: () async {
          if (await requestToolAccess(context, CoinFeature.tool(tool.title, tool.tier)) && context.mounted) tool.onTap();
        },
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
                      gradient: LinearGradient(begin: AlignmentDirectional.topStart, end: AlignmentDirectional.bottomEnd, colors: [light, accent]),
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

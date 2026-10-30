import 'dart:io';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../../../app/app_config.dart';
import '../../../../app/di.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/widgets/responsive.dart';
import '../../../../core/widgets/feedback.dart';
import '../../../export/domain/entities/export_options.dart';
import '../../../qr/presentation/qr_share_page.dart';
import '../../../monetization/domain/repositories/monetization_contracts.dart';
import '../../../monetization/presentation/plan_cubit.dart';
import '../../../scanner/presentation/bloc/scan_session_cubit.dart';
import '../../../settings/domain/feature_access.dart';
import '../../../settings/presentation/settings_cubit.dart';
import '../../domain/entities/scanned_document.dart';
import '../../../rewards/domain/coin_rules.dart';
import '../../../rewards/presentation/unlock.dart';
import '../bloc/document_detail_cubit.dart';
import '../widgets/document_actions.dart';
import '../../../../core/widgets/text.dart';
import '../../../../core/i18n/tr.dart';

class DocumentDetailPage extends StatelessWidget {
  const DocumentDetailPage({super.key, required this.documentId});
  final String documentId;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => sl<DocumentDetailCubit>(param1: documentId)..load(),
    child: const _DetailView(),
  );
}

class _DetailView extends StatefulWidget {
  const _DetailView();

  @override
  State<_DetailView> createState() => _DetailViewState();
}

class _DetailViewState extends State<_DetailView> {
  final _pageController = PageController();
  int _current = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    final choice = await showModalBottomSheet<(ExportFormat, ExportQuality)>(context: context, isScrollControlled: true, builder: (_) => const _ExportSheet());
    if (choice == null || !mounted) return;
    await _runExport(choice.$1, choice.$2);
  }

  Future<void> _quickExport(ExportFormat format) => _runExport(format, context.read<SettingsCubit>().state.exportQuality);

  /// Builds the PDF, then shows a QR code others on the same Wi-Fi can scan to download it.
  Future<void> _shareByQr() async {
    final path = await context.read<DocumentDetailCubit>().exportFile(ExportFormat.pdf, context.read<SettingsCubit>().state.exportQuality);
    if (path == null || !mounted) return;
    context.push(
      '/qr-share',
      extra: QrShareArgs(filePath: path, fileName: p.basename(path), mimeType: ExportFormat.pdf.mimeType),
    );
  }

  Future<void> _runExport(ExportFormat format, ExportQuality quality) async {
    final cubit = context.read<DocumentDetailCubit>();
    final plan = context.read<PlanCubit>().state;
    final produced = await cubit.exportAndShare(format, quality);
    if (produced) await sl<AdService>().showInterstitialIfEligible(plan);
  }

  /// Opens the saved document in the page editor, or the paywall when the plan does not include it.
  Future<void> _edit(ScannedDocument doc, FeatureState access) async {
    if (access == FeatureState.locked) {
      if (AppConfig.rewardsEnabled) {
        if (!await requestUnlock(context, CoinFeature.editSavedDocument)) return;
      } else {
        showMessage(context, 'Editing saved documents is a Premium feature');
        return;
      }
      if (!mounted) return;
    }
    final detail = context.read<DocumentDetailCubit>();
    context.read<ScanSessionCubit>().loadDocument(doc, defaultFilter: context.read<SettingsCubit>().state.defaultFilter);
    await context.push('/scan/edit');
    if (mounted) await detail.load();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<DocumentDetailCubit, DocumentDetailState>(
      listenWhen: (a, b) => b.failure != null && a.failure != b.failure,
      listener: (context, s) => showFailure(context, s.failure!),
      builder: (context, state) {
        final doc = state.document;
        final access = FeatureAccess.editSavedDocuments(
          billingEnabled: AppConfig.billingEnabled,
          coinsEnabled: AppConfig.rewardsEnabled,
          plan: context.watch<PlanCubit>().state,
          enabled: context.watch<SettingsCubit>().state.editSavedDocuments,
        );
        return Scaffold(
          appBar: AppBar(
            title: Text(doc?.title ?? 'Document', overflow: TextOverflow.ellipsis),
            actions: [
              if (doc != null && access != FeatureState.hidden)
                IconButton(
                  tooltip: access == FeatureState.locked
                      ? (AppConfig.rewardsEnabled ? 'Edit pages (${CoinFeature.editSavedDocument.cost} coins)' : 'Edit pages (Premium)')
                      : 'Edit pages',
                  icon: Badge(
                    isLabelVisible: access == FeatureState.locked,
                    label: const Icon(AppIcons.lock, size: 9, color: Colors.white),
                    backgroundColor: AppColors.warning,
                    child: const Icon(AppIcons.editDocument),
                  ),
                  onPressed: () => _edit(doc, access),
                ),
              if (doc != null)
                IconButton(
                  tooltip: tr('More'),
                  icon: const Icon(AppIcons.more),
                  onPressed: () => showDocumentActions(context, doc, refresh: context.read<DocumentDetailCubit>().load, onDeleted: () => context.pop()),
                ),
            ],
          ),
          body: Stack(
            children: [
              if (state.loading)
                const Center(child: CircularProgressIndicator())
              else if (doc == null)
                const Center(child: Text('This document could not be opened.'))
              else
                Column(
                  children: [
                    Expanded(
                      child: PageView.builder(
                        controller: _pageController,
                        itemCount: doc.pages.length,
                        onPageChanged: (i) => setState(() => _current = i),
                        itemBuilder: (_, i) => Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: InteractiveViewer(maxScale: 5, child: Image.file(File(doc.pages[i].imagePath), fit: BoxFit.contain)),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                      child: Text(
                        'Page ${_current + 1} of ${doc.pageCount}  ·  ${formatDateTime(doc.createdAt)}',
                        style: const TextStyle(color: AppColors.inkMuted, fontSize: 13),
                      ),
                    ),
                    SizedBox(
                      height: 64,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                        itemCount: doc.pages.length,
                        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
                        itemBuilder: (_, i) => GestureDetector(
                          onTap: () => _pageController.animateToPage(i, duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
                          child: Container(
                            width: 46,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: i == _current ? AppColors.primary : AppColors.border, width: i == _current ? 2 : 1),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: Image.file(File(doc.pages[i].imagePath), fit: BoxFit.cover, cacheWidth: 140),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SafeArea(
                      top: false,
                      child: ContentWidth(
                        maxWidth: 560,
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Row(
                            children: [
                              Expanded(
                                child: _BarButton(
                                  icon: AppIcons.pdf,
                                  label: 'PDF',
                                  primary: true,
                                  onTap: state.exporting ? null : () => _quickExport(ExportFormat.pdf),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: _BarButton(icon: AppIcons.docx, label: 'Word', onTap: state.exporting ? null : () => _quickExport(ExportFormat.docx)),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: _BarButton(
                                  icon: AppIcons.print,
                                  label: 'Print',
                                  onTap: () => context.push('/print', extra: doc),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: _BarButton(icon: AppIcons.qr, label: 'QR', onTap: state.exporting ? null : _shareByQr),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: _BarButton(icon: AppIcons.quality, label: 'Options', onTap: state.exporting ? null : _export),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              BusyOverlay(visible: state.exporting, label: 'Preparing file'),
            ],
          ),
        );
      },
    );
  }
}

/// Compact icon-over-label button for the bottom action bar.
class _BarButton extends StatelessWidget {
  const _BarButton({required this.icon, required this.label, required this.onTap, this.primary = false});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final fg = primary ? Colors.white : (enabled ? AppColors.primary : AppColors.inkMuted);
    return Material(
      color: primary ? (enabled ? AppColors.primary : AppColors.inkMuted) : AppColors.primarySoft,
      borderRadius: BorderRadius.circular(AppSpacing.radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: fg),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExportSheet extends StatefulWidget {
  const _ExportSheet();

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  ExportFormat _format = ExportFormat.pdf;
  ExportQuality _quality = ExportQuality.high;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Export as', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: AppSpacing.md),
            SegmentedButton<ExportFormat>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: ExportFormat.pdf, icon: Icon(AppIcons.pdf), label: Text('PDF')),
                ButtonSegment(value: ExportFormat.docx, icon: Icon(AppIcons.docx), label: Text('DOCX')),
              ],
              selected: {_format},
              onSelectionChanged: (s) => setState(() => _format = s.first),
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<ExportQuality>(
              initialValue: _quality,
              decoration: InputDecoration(labelText: tr('Quality'), prefixIcon: Icon(AppIcons.quality, size: 20)),
              items: [for (final q in ExportQuality.values) DropdownMenuItem(value: q, child: Text(q.label))],
              onChanged: (q) => setState(() => _quality = q ?? _quality),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, (_format, _quality)),
              icon: const Icon(AppIcons.export, size: 20),
              label: const Text('Export & share'),
            ),
          ],
        ),
      ),
    );
  }
}

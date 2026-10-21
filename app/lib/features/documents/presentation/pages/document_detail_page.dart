import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/di.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/widgets/feedback.dart';
import '../../../export/domain/entities/export_options.dart';
import '../../../monetization/domain/repositories/monetization_contracts.dart';
import '../../../monetization/presentation/plan_cubit.dart';
import '../bloc/document_detail_cubit.dart';

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
    final cubit = context.read<DocumentDetailCubit>();
    final choice = await showModalBottomSheet<(ExportFormat, ExportQuality)>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _ExportSheet(),
    );
    if (choice == null || !mounted) return;

    final plan = context.read<PlanCubit>().state;
    final produced = await cubit.exportAndShare(choice.$1, choice.$2);
    if (produced) await sl<AdService>().showInterstitialIfEligible(plan);
  }

  Future<void> _rename(String current) async {
    final controller = TextEditingController(text: current);
    final cubit = context.read<DocumentDetailCubit>();
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename document'),
        content: TextField(controller: controller, autofocus: true, textCapitalization: TextCapitalization.sentences),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (title != null) await cubit.rename(title);
  }

  Future<void> _delete() async {
    final cubit = context.read<DocumentDetailCubit>();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete document?'),
        content: const Text('This permanently removes the document and its pages from this device.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final ok = await cubit.delete();
    if (ok && mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<DocumentDetailCubit, DocumentDetailState>(
      listenWhen: (a, b) => b.failure != null && a.failure != b.failure,
      listener: (context, s) => showFailure(context, s.failure!),
      builder: (context, state) {
        final doc = state.document;
        return Scaffold(
          appBar: AppBar(
            title: Text(doc?.title ?? 'Document', overflow: TextOverflow.ellipsis),
            actions: [
              if (doc != null)
                IconButton(tooltip: 'Rename', icon: const Icon(AppIcons.edit), onPressed: () => _rename(doc.title)),
              if (doc != null)
                IconButton(tooltip: 'Delete', icon: const Icon(AppIcons.delete), onPressed: _delete),
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
                          child: InteractiveViewer(
                            maxScale: 5,
                            child: Image.file(File(doc.pages[i].imagePath), fit: BoxFit.contain),
                          ),
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
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
                        child: FilledButton.icon(
                          onPressed: state.exporting ? null : _export,
                          icon: const Icon(AppIcons.share, size: 20),
                          label: const Text('Export & share'),
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
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
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
              decoration: const InputDecoration(labelText: 'Quality', prefixIcon: Icon(AppIcons.quality, size: 20)),
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

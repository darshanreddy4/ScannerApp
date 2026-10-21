import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/di.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/widgets/feedback.dart';
import '../../../monetization/domain/repositories/monetization_contracts.dart';
import '../../../monetization/presentation/plan_cubit.dart';
import '../../../scanner/presentation/bloc/scan_session_cubit.dart';
import '../../domain/entities/scanned_document.dart';

class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key});

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  late final TextEditingController _title = TextEditingController(text: defaultScanTitle(DateTime.now()));

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final session = context.read<ScanSessionCubit>();
    final plan = context.read<PlanCubit>().state;
    final doc = await session.save(_title.text);
    if (!mounted) return;
    if (doc == null) {
      if (session.state.error != null) showFailure(context, session.state.error!);
      return;
    }
    await sl<AdService>().showInterstitialIfEligible(plan);
    if (!mounted) return;
    context.go('/');
    context.push('/document/${doc.id}');
  }

  Future<void> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard scan?'),
        content: const Text('The pages you captured will be deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      context.read<ScanSessionCubit>().reset();
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = context.select((ScanSessionCubit c) => c.state.pages);
    final busy = context.select((ScanSessionCubit c) => c.state.busy);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.close), tooltip: 'Discard', onPressed: _confirmDiscard),
        title: Text('Review · ${pagesLabel(pages.length)}'),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: TextField(
                  controller: _title,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(labelText: 'Document name', prefixIcon: Icon(AppIcons.edit, size: 20)),
                ),
              ),
              Expanded(
                child: pages.isEmpty
                    ? const Center(child: Text('No pages yet', style: TextStyle(color: AppColors.inkMuted)))
                    : ReorderableListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                        buildDefaultDragHandles: false,
                        itemCount: pages.length,
                        onReorderItem: context.read<ScanSessionCubit>().reorderPages,
                        itemBuilder: (context, i) => _PageTile(
                          key: ValueKey(pages[i].imagePath),
                          index: i,
                          page: pages[i],
                          onDelete: () => context.read<ScanSessionCubit>().removePage(i),
                        ),
                      ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => context.pop(),
                          icon: const Icon(AppIcons.add, size: 20),
                          label: const Text('Add page'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: pages.isEmpty || busy ? null : _save,
                          icon: const Icon(AppIcons.check, size: 20),
                          label: const Text('Save'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          BusyOverlay(visible: busy, label: 'Saving securely'),
        ],
      ),
    );
  }
}

class _PageTile extends StatelessWidget {
  const _PageTile({super.key, required this.index, required this.page, required this.onDelete});

  final int index;
  final NewPage page;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm + 4),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 56,
                    height: 72,
                    child: Image.file(File(page.imagePath), fit: BoxFit.cover, cacheWidth: 200),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Page ${index + 1}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text('${page.width} × ${page.height}px', style: const TextStyle(color: AppColors.inkMuted, fontSize: 12)),
                    ],
                  ),
                ),
                IconButton(tooltip: 'Delete page', icon: const Icon(AppIcons.delete), color: AppColors.danger, onPressed: onDelete),
                ReorderableDragStartListener(
                  index: index,
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(AppIcons.dragHandle, color: AppColors.inkMuted),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

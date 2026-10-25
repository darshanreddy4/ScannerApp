import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/di.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/widgets/dialogs.dart';
import '../../../../core/widgets/feedback.dart';
import '../../../../core/widgets/responsive.dart';
import '../../../markup/domain/markup.dart';
import '../../../markup/presentation/markup_page.dart';
import '../../../monetization/domain/repositories/monetization_contracts.dart';
import '../../../monetization/presentation/plan_cubit.dart';
import '../../domain/entities/scan_page.dart';
import '../add_content.dart';
import '../bloc/scan_session_cubit.dart';
import '../widgets/filter_labels.dart';

/// Review and enhance all captured pages, then save the document.
class EditPage extends StatefulWidget {
  const EditPage({super.key});

  @override
  State<EditPage> createState() => _EditPageState();
}

class _EditPageState extends State<EditPage> {
  late final PageController _pager;
  bool _showColor = true;
  bool _showOriginal = false;

  /// Set once this screen is on its way out, so only one navigation ever fires.
  bool _leaving = false;

  /// True while the pager is being moved by code rather than by the user.
  bool _jumping = false;

  ScanSessionCubit get _session => context.read<ScanSessionCubit>();

  @override
  void initState() {
    super.initState();
    _pager = PageController(initialPage: _session.state.selected);
    WidgetsBinding.instance.addPostFrameCallback((_) => _session.loadPageAssets(_session.state.selected));
  }

  /// Moves the pager to the selected page once the PageView has laid out the new page count.
  void _syncPagerAfterLayout() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pager.hasClients || !_pager.position.hasContentDimensions) return;
      final target = _session.state.selected;
      if (target < 0 || target >= _session.state.pages.length) return;
      if ((_pager.page?.round() ?? target) != target) {
        // While the PageView settles on its new page count it reports stale intermediate pages; ignore them.
        _jumping = true;
        _pager.jumpToPage(target);
        WidgetsBinding.instance.addPostFrameCallback((_) => _jumping = false);
      }
    });
  }

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final plan = context.read<PlanCubit>().state;
    final editingSaved = _session.state.editingDocumentId != null;
    // A successful save resets the session to zero pages; that must not also trigger the "no pages" exit.
    _leaving = true;
    final doc = await _session.save();
    if (!mounted) return;
    if (doc == null) {
      _leaving = false;
      if (_session.state.error != null) showFailure(context, _session.state.error!);
      return;
    }
    await sl<AdService>().showInterstitialIfEligible(plan);
    if (!mounted) return;
    // Going back (not to the same address) lets the open document screen reload the pages that were replaced.
    if (editingSaved && context.canPop()) {
      context.pop();
    } else {
      context.go('/document/${doc.id}');
    }
  }

  Future<void> _confirmDiscard() async {
    final editing = _session.state.editingDocumentId != null;
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(editing ? 'Discard changes?' : 'Discard scan?'),
        content: Text(editing ? 'Your edits will be lost. The saved document stays as it was.' : 'The pages you captured will be deleted.'),
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
    if (discard == true && mounted && !_leaving) {
      _leaving = true;
      context.go('/');
    }
  }

  Future<void> _renameDialog() async {
    final title = await promptText(context, title: 'Document name', initial: _session.state.title);
    if (title != null && mounted) _session.setTitle(title);
  }

  /// Deletes the page on screen. Offers Undo, except for the last page, which discards the scan after confirming.
  Future<void> _deleteCurrent() async {
    final state = _session.state;
    final index = state.selected;
    if (index < 0 || index >= state.pages.length) return;

    if (state.pages.length == 1) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete the last page?'),
          content: const Text('This scan will be discarded.'),
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
      if (ok == true) _session.removePage(index);
      return;
    }

    final removed = state.pages[index];
    _session.removePage(index);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Page deleted'),
          persist: false,
          duration: const Duration(seconds: 3),
          // Sit above the bottom toolbar so the tools stay tappable.
          margin: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.paddingOf(context).bottom + 84),
          action: SnackBarAction(label: 'Undo', onPressed: () => _session.restorePage(index, removed)),
        ),
      );
  }

  Future<void> _recrop(int index) async {
    if (_session.state.pages[index].preMarkup != null) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Crop again?'),
          content: const Text('Cropping starts again from the original photo, so the marks on this page will be removed.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Crop')),
          ],
        ),
      );
      if (go != true || !mounted) return;
    }
    _session.editPageCrop(index);
    if (mounted) context.push('/scan/crop');
  }

  /// Opens the markup screen for the page on show and draws what comes back onto the page.
  Future<void> _markup(int index) async {
    final state = _session.state;
    if (index < 0 || index >= state.pages.length) return;
    final page = state.pages[index];
    final path = page.croppedPath, w = page.croppedWidth, h = page.croppedHeight;
    if (path == null || w == null || h == null) return;
    final preview = state.previews[page.id];
    final items = await context.push<List<MarkupItem>>(
      '/scan/markup',
      extra: MarkupArgs(width: w, height: h, imagePath: path, previewBytes: preview != null && preview.settings == page.settings ? preview.bytes : null),
    );
    if (items == null || items.isEmpty || !mounted) return;
    await _session.applyMarkup(index, items);
  }

  Future<void> _rearrange() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => BlocProvider.value(value: _session, child: const _RearrangeSheet()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = context.select((ScanSessionCubit c) => c.state.pages);
    final selected = context.select((ScanSessionCubit c) => c.state.selected);
    final title = context.select((ScanSessionCubit c) => c.state.title);
    final busy = context.select((ScanSessionCubit c) => c.state.busy);
    final busyLabel = context.select((ScanSessionCubit c) => c.state.busyLabel);

    return BlocListener<ScanSessionCubit, ScanSessionState>(
      listenWhen: (a, b) =>
          a.selected != b.selected ||
          a.pages.length != b.pages.length ||
          a.selectedPage?.croppedPath != b.selectedPage?.croppedPath ||
          (a.error != b.error && b.error != null),
      listener: (context, s) {
        if (s.error != null) showFailure(context, s.error!);
        if (s.pages.isEmpty) {
          if (!_leaving) {
            _leaving = true;
            context.go('/');
          }
          return;
        }
        // Only the pager reports swipes (via selectPage); here we follow the session, never write back to it.
        _syncPagerAfterLayout();
        _session.loadPageAssets(s.selected);
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          leading: IconButton(icon: const Icon(AppIcons.back), onPressed: busy ? null : _confirmDiscard),
          titleSpacing: 0,
          title: InkWell(
            onTap: _renameDialog,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      title,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(AppIcons.edit, size: 16, color: AppColors.inkMuted),
                ],
              ),
            ),
          ),
        ),
        body: Stack(
          children: [
            Builder(
              builder: (context) {
                final pager = _PagePager(
                  pager: _pager,
                  pages: pages,
                  showOriginal: _showOriginal,
                  onOriginal: (v) => setState(() => _showOriginal = v),
                  onDelete: _deleteCurrent,
                  onRemoveMarkup: () => _session.removeMarkup(selected),
                  onPageChanged: (i) {
                    if (!_jumping) _session.selectPage(i);
                  },
                );
                final colorPanel = _showColor && pages.isNotEmpty ? _ColorPanel(page: pages[selected.clamp(0, pages.length - 1)]) : null;
                final toolbar = _Toolbar(
                  colorActive: _showColor,
                  onCrop: () => _recrop(selected),
                  onColor: () => setState(() => _showColor = !_showColor),
                  onMarkup: () => _markup(selected),
                  onRotate: () => _session.rotatePage(selected),
                  onRearrange: _rearrange,
                  onAdd: () => showAddSheet(context, append: true),
                  onSave: busy || pages.isEmpty ? null : _save,
                );
                final size = MediaQuery.sizeOf(context);
                // A wide, landscape screen gets the tools in a side panel so the page keeps its height.
                if (size.width >= Breakpoints.expanded && size.width > size.height) {
                  return Row(
                    children: [
                      Expanded(child: pager),
                      const VerticalDivider(width: 1),
                      SizedBox(
                        width: 400,
                        child: Column(
                          children: [
                            Expanded(child: SingleChildScrollView(child: colorPanel ?? const SizedBox.shrink())),
                            const Divider(height: 1),
                            toolbar,
                          ],
                        ),
                      ),
                    ],
                  );
                }
                return Column(
                  children: [
                    Expanded(child: pager),
                    const Divider(),
                    ?colorPanel,
                    toolbar,
                  ],
                );
              },
            ),
            BusyOverlay(visible: busy, label: busyLabel),
          ],
        ),
      ),
    );
  }
}

class _PagePager extends StatelessWidget {
  const _PagePager({
    required this.pager,
    required this.pages,
    required this.showOriginal,
    required this.onOriginal,
    required this.onDelete,
    required this.onRemoveMarkup,
    required this.onPageChanged,
  });

  final PageController pager;
  final List<ScanPage> pages;
  final bool showOriginal;
  final ValueChanged<bool> onOriginal;
  final VoidCallback onDelete;
  final VoidCallback onRemoveMarkup;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    final previews = context.select((ScanSessionCubit c) => c.state.previews);
    final selected = context.select((ScanSessionCubit c) => c.state.selected);

    return Stack(
      children: [
        PageView.builder(
          controller: pager,
          itemCount: pages.length,
          onPageChanged: onPageChanged,
          itemBuilder: (_, i) {
            final page = pages[i];
            final preview = previews[page.id];
            return Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: AppColors.border),
                ),
                child: InteractiveViewer(
                  maxScale: 5,
                  child: (showOriginal || preview == null) && page.croppedPath != null
                      // Marks are part of croppedPath, so the original is the picture saved before them.
                      ? Image.file(
                          File(showOriginal ? (page.preMarkup?.croppedPath ?? page.croppedPath!) : page.croppedPath!),
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                          cacheWidth: 1200,
                        )
                      : Image.memory(preview!.bytes, fit: BoxFit.contain, gaplessPlayback: true),
                ),
              ),
            );
          },
        ),
        Positioned(
          bottom: 14,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(color: AppColors.ink.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(16)),
              child: Text(
                '${selected + 1}/${pages.length}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 62,
          right: 16,
          child: Tooltip(
            message: 'Delete this page',
            child: GestureDetector(
              onTap: onDelete,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: AppColors.ink.withValues(alpha: 0.8), shape: BoxShape.circle),
                child: const Icon(AppIcons.delete, color: Colors.white, size: 20),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 8,
          right: 16,
          // Raw pointer events (no gesture arena or tooltip) so holding keeps the original visible until release.
          child: Listener(
            onPointerDown: (_) => onOriginal(true),
            onPointerUp: (_) => onOriginal(false),
            onPointerCancel: (_) => onOriginal(false),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: showOriginal ? AppColors.primary : AppColors.ink.withValues(alpha: 0.8), shape: BoxShape.circle),
              child: const Icon(AppIcons.compare, color: Colors.white, size: 20),
            ),
          ),
        ),
        if (pages.isNotEmpty && pages[selected.clamp(0, pages.length - 1)].preMarkup != null)
          Positioned(
            top: 12,
            right: 16,
            child: ActionChip(
              key: const ValueKey('remove-markup'),
              avatar: const Icon(AppIcons.close, size: 16),
              label: const Text('Remove markup'),
              onPressed: onRemoveMarkup,
              backgroundColor: AppColors.surface,
            ),
          ),
        if (showOriginal)
          Positioned(
            top: 12,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(color: AppColors.ink.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(12)),
                child: const Text(
                  'Original',
                  style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ColorPanel extends StatelessWidget {
  const _ColorPanel({required this.page});
  final ScanPage page;

  @override
  Widget build(BuildContext context) {
    final session = context.read<ScanSessionCubit>();
    final thumbs = context.select((ScanSessionCubit c) => c.state.thumbs[page.id]);
    final applyAll = context.select((ScanSessionCubit c) => c.state.applyToAll);
    final multiple = context.select((ScanSessionCubit c) => c.state.pages.length > 1);
    final settings = page.settings;

    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 104,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: thumbFilters.length,
              separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm + 4),
              itemBuilder: (_, i) {
                final filter = thumbFilters[i];
                final active = settings.filter == filter;
                return GestureDetector(
                  onTap: () => session.updateSettings(settings.copyWith(filter: filter), immediate: true),
                  child: SizedBox(
                    width: 78,
                    child: Column(
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: active ? AppColors.primary : AppColors.border, width: active ? 2.5 : 1),
                              color: AppColors.background,
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: thumbs == null
                                  ? const Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                                  : Image.memory(thumbs[i], fit: BoxFit.cover, width: double.infinity, gaplessPlayback: true),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          filter.label.replaceFirst('Document ', ''),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                            color: active ? AppColors.primary : AppColors.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          _MiniSlider(
            icon: AppIcons.brightness,
            value: settings.brightness,
            onChanged: (v) => session.updateSettings(settings.copyWith(brightness: v)),
          ),
          _MiniSlider(
            icon: AppIcons.contrast,
            value: settings.contrast,
            onChanged: (v) => session.updateSettings(settings.copyWith(contrast: v)),
          ),
          if (multiple)
            InkWell(
              onTap: () => session.setApplyToAll(!applyAll),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Checkbox(value: applyAll, onChanged: (v) => session.setApplyToAll(v ?? false), visualDensity: VisualDensity.compact),
                    const Text(
                      'Apply to all pages',
                      style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MiniSlider extends StatelessWidget {
  const _MiniSlider({required this.icon, required this.value, required this.onChanged});
  final IconData icon;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 36,
    child: Row(
      children: [
        Icon(icon, size: 18, color: AppColors.inkMuted),
        Expanded(
          child: Slider(value: value, min: -100, max: 100, onChanged: onChanged),
        ),
        SizedBox(
          width: 32,
          child: Text(
            '${value.round()}',
            textAlign: TextAlign.end,
            style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
          ),
        ),
      ],
    ),
  );
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.colorActive,
    required this.onCrop,
    required this.onColor,
    required this.onMarkup,
    required this.onRotate,
    required this.onRearrange,
    required this.onAdd,
    required this.onSave,
  });

  final bool colorActive;
  final VoidCallback onCrop;
  final VoidCallback onColor;
  final VoidCallback onMarkup;
  final VoidCallback onRotate;
  final VoidCallback onRearrange;
  final VoidCallback onAdd;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm, horizontal: AppSpacing.sm),
          child: Row(
            children: [
              _ToolItem(icon: AppIcons.crop, label: 'Crop', onTap: onCrop),
              _ToolItem(icon: AppIcons.filterMagic, label: 'Color', onTap: onColor, active: colorActive),
              _ToolItem(icon: AppIcons.markup, label: 'Markup', onTap: onMarkup),
              _ToolItem(icon: AppIcons.rotate, label: 'Rotate', onTap: onRotate),
              _ToolItem(icon: AppIcons.dragHandle, label: 'Reorder', onTap: onRearrange),
              _ToolItem(icon: AppIcons.add, label: 'Add', onTap: onAdd),
              const SizedBox(width: AppSpacing.sm),
              SizedBox(
                width: 56,
                height: 48,
                child: FilledButton(
                  onPressed: onSave,
                  style: FilledButton.styleFrom(minimumSize: const Size(56, 48), padding: EdgeInsets.zero, backgroundColor: AppColors.success),
                  child: const Icon(AppIcons.check, size: 24),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolItem extends StatelessWidget {
  const _ToolItem({required this.icon, required this.label, required this.onTap, this.active = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.primary : AppColors.ink;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: TextStyle(color: color, fontSize: 11, fontWeight: active ? FontWeight.w700 : FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RearrangeSheet extends StatelessWidget {
  const _RearrangeSheet();

  @override
  Widget build(BuildContext context) {
    final pages = context.select((ScanSessionCubit c) => c.state.pages);
    final session = context.read<ScanSessionCubit>();
    // Deleting the last page from this sheet ends the session; close the sheet with it.
    if (pages.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
      });
    }
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text('Rearrange pages', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            ),
            Flexible(
              child: ReorderableListView.builder(
                shrinkWrap: true,
                buildDefaultDragHandles: false,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                itemCount: pages.length,
                onReorderItem: session.reorderPages,
                itemBuilder: (context, i) => Card(
                  key: ValueKey(pages[i].id),
                  margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: SizedBox(
                        width: 40,
                        height: 52,
                        child: pages[i].croppedPath == null ? null : Image.file(File(pages[i].croppedPath!), fit: BoxFit.cover, cacheWidth: 120),
                      ),
                    ),
                    title: Text('Page ${i + 1}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Delete page',
                          icon: const Icon(AppIcons.delete, color: AppColors.danger),
                          onPressed: () => session.removePage(i),
                        ),
                        ReorderableDragStartListener(
                          index: i,
                          child: const Icon(AppIcons.dragHandle, color: AppColors.inkMuted),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

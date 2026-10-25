import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/widgets/feedback.dart';
import '../../../../core/widgets/responsive.dart';
import '../../../monetization/presentation/ad_banner_slot.dart';
import '../../../qr/presentation/active_shares_banner.dart';
import '../../../scanner/presentation/add_content.dart';
import '../../../settings/presentation/settings_view.dart';
import '../../../tools/presentation/tools_view.dart';
import '../../domain/entities/scanned_document.dart';
import '../bloc/documents_cubit.dart';
import '../widgets/folder_editor.dart';
import '../widgets/folder_style.dart';
import '../widgets/document_actions.dart' show confirmOwner;
import '../widgets/document_widgets.dart';
import '../widgets/refresh_on_return.dart';

/// Floating action pill: tap the camera to scan immediately, or "+" for more options.
class ScanFab extends StatelessWidget {
  const ScanFab({super.key, this.folderId});
  final String? folderId;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.primary,
    elevation: 3,
    borderRadius: BorderRadius.circular(28),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () => startScan(context, folderId: folderId),
          borderRadius: const BorderRadius.horizontal(left: Radius.circular(28)),
          child: const Padding(
            padding: EdgeInsets.fromLTRB(22, 16, 16, 16),
            child: Icon(AppIcons.camera, color: Colors.white),
          ),
        ),
        Container(width: 1, height: 26, color: Colors.white38),
        InkWell(
          onTap: () => showAddSheet(context, folderId: folderId),
          borderRadius: const BorderRadius.horizontal(right: Radius.circular(28)),
          child: const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 22, 16),
            child: Icon(AppIcons.add, color: Colors.white),
          ),
        ),
      ],
    ),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final selecting = context.select((DocumentsCubit c) => c.state.selecting);
    final wide = MediaQuery.sizeOf(context).width >= Breakpoints.medium;
    return RefreshOnReturn(
      child: PopScope(
        canPop: !selecting,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) context.read<DocumentsCubit>().clearSelection();
        },
        child: Scaffold(
          appBar: _tab == 0
              ? const DocumentsAppBar(title: 'Documents')
              : AppBar(
                  title: Text(_tab == 1 ? 'Tools' : 'Settings'),
                  bottom: const PreferredSize(preferredSize: Size.fromHeight(1), child: Divider()),
                ),
          body: wide
              ? Row(
                  children: [
                    NavigationRail(
                      selectedIndex: _tab,
                      labelType: NavigationRailLabelType.all,
                      onDestinationSelected: (i) => setState(() => _tab = i),
                      destinations: const [
                        NavigationRailDestination(icon: Icon(AppIcons.home), selectedIcon: Icon(AppIcons.homeActive), label: Text('Documents')),
                        NavigationRailDestination(icon: Icon(AppIcons.tools), selectedIcon: Icon(AppIcons.toolsActive), label: Text('Tools')),
                        NavigationRailDestination(icon: Icon(AppIcons.settings), selectedIcon: Icon(AppIcons.settingsActive), label: Text('Settings')),
                      ],
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: IndexedStack(index: _tab, children: const [_DocumentsView(), ToolsView(), SettingsView()]),
                    ),
                  ],
                )
              : IndexedStack(index: _tab, children: const [_DocumentsView(), ToolsView(), SettingsView()]),
          floatingActionButton: _tab == 0 && !selecting ? const ScanFab() : null,
          bottomNavigationBar: wide
              ? const AdBannerSlot()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const AdBannerSlot(),
                    const Divider(),
                    NavigationBar(
                      selectedIndex: _tab,
                      height: 64,
                      onDestinationSelected: (i) => setState(() => _tab = i),
                      destinations: const [
                        NavigationDestination(icon: Icon(AppIcons.home), selectedIcon: Icon(AppIcons.homeActive), label: 'Documents'),
                        NavigationDestination(icon: Icon(AppIcons.tools), selectedIcon: Icon(AppIcons.toolsActive), label: 'Tools'),
                        NavigationDestination(icon: Icon(AppIcons.settings), selectedIcon: Icon(AppIcons.settingsActive), label: 'Settings'),
                      ],
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _DocumentsView extends StatefulWidget {
  const _DocumentsView();

  @override
  State<_DocumentsView> createState() => _DocumentsViewState();
}

class _DocumentsViewState extends State<_DocumentsView> {
  final _search = TextEditingController();
  Timer? _textDebounce;
  String _query = '';
  bool _favoritesOnly = false;

  @override
  void dispose() {
    _textDebounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _newFolder() async {
    final edit = await showFolderEditor(context, title: 'New folder');
    if (edit == null || !mounted) return;
    final failure = await context.read<DocumentsCubit>().createFolder(edit.name, style: edit.style);
    if (failure != null && mounted) showFailure(context, failure);
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<DocumentsCubit, DocumentsState>(
      listenWhen: (a, b) => b.status == LoadStatus.failed && a.failure != b.failure,
      listener: (context, s) => showFailure(context, s.failure!),
      builder: (context, state) {
        if (state.status == LoadStatus.loading) return const Center(child: CircularProgressIndicator());
        if (state.documents.isEmpty && state.folders.isEmpty) return const _EmptyState();

        final q = _query.trim().toLowerCase();
        final searching = q.isNotEmpty;
        final folders = _favoritesOnly ? state.favoriteFolders : state.folders;
        final docs = searching
            ? (_favoritesOnly ? state.favoriteDocuments.where((d) => state.searchDocuments(q).contains(d)).toList() : state.searchDocuments(q))
            : (_favoritesOnly ? state.favoriteDocuments : state.inFolder(null));

        return ContentWidth(
          maxWidth: 1100,
          child: RefreshIndicator(
            onRefresh: context.read<DocumentsCubit>().load,
            child: CustomScrollView(
              slivers: [
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.only(top: AppSpacing.sm),
                    child: ActiveSharesBanner(),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
                    child: TextField(
                      controller: _search,
                      onChanged: (v) {
                        setState(() => _query = v);
                        _textDebounce?.cancel();
                        // Searching inside recognised text touches the database, so wait for a pause in typing.
                        _textDebounce = Timer(const Duration(milliseconds: 300), () {
                          if (mounted) context.read<DocumentsCubit>().searchInText(v);
                        });
                      },
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Search documents',
                        prefixIcon: const Icon(AppIcons.search, size: 20),
                        isDense: true,
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(AppIcons.close, size: 18),
                                onPressed: () {
                                  setState(() {
                                    _search.clear();
                                    _query = '';
                                  });
                                  context.read<DocumentsCubit>().searchInText('');
                                },
                              ),
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                    child: Row(
                      children: [
                        ChoiceChip(label: const Text('All'), selected: !_favoritesOnly, onSelected: (_) => setState(() => _favoritesOnly = false)),
                        const SizedBox(width: AppSpacing.sm),
                        ChoiceChip(
                          avatar: const Icon(AppIcons.star, size: 16),
                          label: const Text('Favourites'),
                          selected: _favoritesOnly,
                          onSelected: (_) => setState(() => _favoritesOnly = true),
                        ),
                      ],
                    ),
                  ),
                ),
                if (!searching) ...[
                  SliverToBoxAdapter(
                    child: _SectionHeader(
                      title: _favoritesOnly ? 'Favourite folders (${folders.length})' : 'Folders (${folders.length})',
                      trailing: IconButton(tooltip: 'New folder', icon: const Icon(AppIcons.add, size: 22), onPressed: _newFolder),
                    ),
                  ),
                  if (folders.isEmpty && _favoritesOnly)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
                        child: Text('No favourite folders. Use a folder\'s menu to add one.', style: TextStyle(color: AppColors.inkMuted)),
                      ),
                    )
                  else if (folders.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
                        child: OutlinedButton.icon(
                          onPressed: _newFolder,
                          icon: const Icon(AppIcons.emptyDocs, size: 18),
                          label: const Text('Create a folder'),
                          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                      sliver: SliverGrid(
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 190,
                          mainAxisExtent: 124,
                          crossAxisSpacing: AppSpacing.sm + 4,
                          mainAxisSpacing: AppSpacing.sm + 4,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (_, i) => _FolderCard(folder: folders[i], count: state.countIn(folders[i].id)),
                          childCount: folders.length,
                        ),
                      ),
                    ),
                ],
                SliverToBoxAdapter(
                  child: _SectionHeader(
                    title: searching
                        ? '${docs.length} result${docs.length == 1 ? '' : 's'}'
                        : (_favoritesOnly ? 'Favourite documents (${docs.length})' : 'Documents (${docs.length})'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PopupMenuButton<DocumentSort>(
                          tooltip: 'Sort',
                          icon: const Icon(AppIcons.quality, size: 20, color: AppColors.inkMuted),
                          initialValue: state.sort,
                          onSelected: context.read<DocumentsCubit>().setSort,
                          itemBuilder: (_) => [for (final s in DocumentSort.values) PopupMenuItem(value: s, child: Text(s.label))],
                        ),
                        IconButton(
                          tooltip: state.gridView ? 'List view' : 'Grid view',
                          icon: Icon(state.gridView ? AppIcons.library : AppIcons.document, size: 20, color: AppColors.inkMuted),
                          onPressed: context.read<DocumentsCubit>().toggleView,
                        ),
                      ],
                    ),
                  ),
                ),
                if (docs.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: Center(
                        child: Text(
                          searching
                              ? 'No documents match your search'
                              : (_favoritesOnly ? 'No favourites yet. Open a document\'s menu, then More, then Add to favourites.' : 'No documents here yet'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.inkMuted),
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, 96),
                    sliver: DocumentsCollection(documents: docs, gridView: state.gridView),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.sm, 0),
    child: SizedBox(
      height: 44,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.inkMuted, letterSpacing: 0.2),
            ),
          ),
          ?trailing,
        ],
      ),
    ),
  );
}

enum _FolderAction { rename, favorite, lock, delete }

class _FolderCard extends StatelessWidget {
  const _FolderCard({required this.folder, required this.count});
  final Folder folder;
  final int count;

  Future<void> _action(BuildContext context, _FolderAction action) async {
    final cubit = context.read<DocumentsCubit>();
    if (folder.locked && !await confirmOwner(context, 'Unlock "${folder.name}"', allowIfUnavailable: true)) return;
    if (!context.mounted) return;
    switch (action) {
      case _FolderAction.favorite:
        final f = await cubit.setFolderFlags(folder.id, favorite: !folder.favorite);
        if (f != null && context.mounted) showFailure(context, f);
      case _FolderAction.lock:
        if (!folder.locked && !await confirmOwner(context, 'Lock "${folder.name}"')) return;
        if (!context.mounted) return;
        final f = await cubit.setFolderFlags(folder.id, locked: !folder.locked);
        if (!context.mounted) return;
        if (f != null) {
          showFailure(context, f);
        } else {
          showMessage(context, folder.locked ? 'Folder unlocked' : 'Folder locked. Opening it now needs your phone lock.');
        }
      case _FolderAction.rename:
        final edit = await showFolderEditor(context, title: 'Edit folder', folder: folder);
        if (edit == null) return;
        final f = await cubit.editFolder(folder.id, name: edit.name, style: edit.style);
        if (f != null && context.mounted) showFailure(context, f);
      case _FolderAction.delete:
        final ok = await confirmDestructive(
          context,
          title: 'Delete folder?',
          message: 'Documents inside "${folder.name}" are kept and moved back to the main list.',
        );
        if (!ok || !context.mounted) return;
        final f = await cubit.deleteFolder(folder.id);
        if (f != null && context.mounted) showFailure(context, f);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = folderAccent(folder.color);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          if (folder.locked && !await confirmOwner(context, 'Unlock "${folder.name}"', allowIfUnavailable: true)) return;
          if (!context.mounted) return;
          await context.push('/folder/${folder.id}');
          if (context.mounted) context.read<DocumentsCubit>().load();
        },
        child: Stack(
          children: [
            Positioned(top: 0, left: 0, right: 0, height: 4, child: ColoredBox(color: accent)),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.md - 2, AppSpacing.sm, AppSpacing.sm),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FolderBadge.of(folder, size: 48),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    folder.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  Text('$count item${count == 1 ? '' : 's'}', style: const TextStyle(color: AppColors.inkMuted, fontSize: 12)),
                ],
              ),
            ),
            if (folder.favorite) const Positioned(top: 10, left: 8, child: Icon(AppIcons.star, size: 14, color: AppColors.warning)),
            Positioned(
              top: 2,
              right: 0,
              child: SizedBox(
                width: 32,
                height: 32,
                child: PopupMenuButton<_FolderAction>(
                  padding: EdgeInsets.zero,
                  icon: const Icon(AppIcons.more, size: 18, color: AppColors.inkMuted),
                  onSelected: (a) => _action(context, a),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: _FolderAction.rename, child: Text('Edit name and icon')),
                    PopupMenuItem(value: _FolderAction.favorite, child: Text(folder.favorite ? 'Remove from favourites' : 'Add to favourites')),
                    PopupMenuItem(value: _FolderAction.lock, child: Text(folder.locked ? 'Unlock folder' : 'Lock folder')),
                    const PopupMenuItem(
                      value: _FolderAction.delete,
                      child: Text('Delete', style: TextStyle(color: AppColors.danger)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(color: AppColors.primarySoft, shape: BoxShape.circle),
              child: const Icon(AppIcons.emptyDocs, size: 44, color: AppColors.primary),
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text('No documents yet', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Scan a document or import images.\nEverything stays on this device.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.inkMuted, height: 1.4),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(220, 48)),
              onPressed: () => startScan(context),
              icon: const Icon(AppIcons.camera, size: 20),
              label: const Text('Scan a document'),
            ),
            const SizedBox(height: AppSpacing.sm + 4),
            TextButton.icon(onPressed: () => startImport(context), icon: const Icon(AppIcons.gallery, size: 20), label: const Text('Import images')),
          ],
        ),
      ),
    );
  }
}

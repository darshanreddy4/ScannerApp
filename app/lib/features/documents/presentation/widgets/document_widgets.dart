import 'folder_style.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/widgets/responsive.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/widgets/feedback.dart';
import '../../domain/entities/scanned_document.dart';
import '../bloc/documents_cubit.dart';
import 'document_actions.dart';

export '../../../../core/widgets/dialogs.dart' show promptText;

Future<bool> confirmDestructive(BuildContext context, {required String title, required String message, String action = 'Delete'}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(foregroundColor: AppColors.danger),
          child: Text(action),
        ),
      ],
    ),
  );
  return result ?? false;
}

class MoveChoice {
  const MoveChoice(this.folderId);
  final String? folderId;
}

Future<MoveChoice?> pickFolder(BuildContext context, List<Folder> folders, String? current) => showModalBottomSheet<MoveChoice>(
  context: context,
  builder: (_) => _MoveSheet(folders: folders, current: current),
);

class _MoveSheet extends StatelessWidget {
  const _MoveSheet({required this.folders, required this.current});
  final List<Folder> folders;
  final String? current;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.6),
      child: ListView(
        shrinkWrap: true,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
            child: Text('Move to folder', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          ),
          ListTile(
            leading: const Icon(AppIcons.home),
            title: const Text('No folder'),
            trailing: current == null ? const Icon(AppIcons.check, color: AppColors.primary) : null,
            onTap: () => Navigator.pop(context, const MoveChoice(null)),
          ),
          for (final f in folders)
            ListTile(
              leading: FolderBadge.of(f, size: 36),
              title: Text(f.name),
              trailing: current == f.id ? const Icon(AppIcons.check, color: AppColors.primary) : null,
              onTap: () => Navigator.pop(context, MoveChoice(f.id)),
            ),
          if (folders.isEmpty)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: Text('Create a folder from the home screen first.', style: TextStyle(color: AppColors.inkMuted)),
            ),
        ],
      ),
    ),
  );
}

class DocMenuButton extends StatelessWidget {
  const DocMenuButton({super.key, required this.document});
  final ScannedDocument document;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<DocumentsCubit>();
    return IconButton(
      tooltip: 'More',
      icon: const Icon(AppIcons.more, size: 20, color: AppColors.inkMuted),
      onPressed: () => showDocumentActions(context, document, refresh: cubit.load),
    );
  }
}

Future<void> openDocument(BuildContext context, ScannedDocument doc) async {
  if (doc.locked && !await confirmOwner(context, 'Unlock "${doc.title}"', allowIfUnavailable: true)) return;
  if (!context.mounted) return;
  await context.push('/document/${doc.id}');
  if (context.mounted) context.read<DocumentsCubit>().load();
}

/// Tap opens the document; while selecting, tap toggles. Long-press starts selection.
void _onTap(BuildContext context, ScannedDocument doc) {
  final cubit = context.read<DocumentsCubit>();
  if (cubit.state.selecting) {
    cubit.toggleSelect(doc.id);
  } else {
    openDocument(context, doc);
  }
}

class DocThumb extends StatelessWidget {
  const DocThumb({super.key, required this.document, this.cacheWidth = 240});
  final ScannedDocument document;
  final int cacheWidth;

  @override
  Widget build(BuildContext context) {
    final cover = document.cover;
    if (document.locked)
      return const ColoredBox(
        color: AppColors.primarySoft,
        child: Center(child: Icon(AppIcons.lock, color: AppColors.primary)),
      );
    return cover == null
        ? const Icon(AppIcons.document, color: AppColors.inkMuted)
        : Image.file(
            File(cover.imagePath),
            fit: BoxFit.cover,
            cacheWidth: cacheWidth,
            errorBuilder: (_, _, _) => const Icon(AppIcons.document, color: AppColors.inkMuted),
          );
  }
}

/// Circle showing the selection order number, or an empty ring while selecting.
class SelectionBadge extends StatelessWidget {
  const SelectionBadge({super.key, required this.order});

  /// Zero-based pick order, or -1 when not selected.
  final int order;

  @override
  Widget build(BuildContext context) {
    final on = order >= 0;
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on ? AppColors.primary : Colors.white,
        border: Border.all(color: on ? AppColors.primary : AppColors.inkMuted, width: 1.5),
      ),
      child: on
          ? Text(
              '${order + 1}',
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
            )
          : null,
    );
  }
}

class DocumentListTile extends StatelessWidget {
  const DocumentListTile({super.key, required this.document});
  final ScannedDocument document;

  @override
  Widget build(BuildContext context) {
    final order = context.select((DocumentsCubit c) => c.state.selection.indexOf(document.id));
    final selecting = context.select((DocumentsCubit c) => c.state.selecting);

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        side: BorderSide(color: order >= 0 ? AppColors.primary : AppColors.border, width: order >= 0 ? 2 : 1),
      ),
      child: InkWell(
        onTap: () => _onTap(context, document),
        onLongPress: () => context.read<DocumentsCubit>().toggleSelect(document.id),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm + 2),
          child: Row(
            children: [
              if (selecting) ...[SelectionBadge(order: order), const SizedBox(width: AppSpacing.sm + 2)],
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 56,
                  height: 72,
                  color: AppColors.background,
                  child: DocThumb(document: document),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            document.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                          ),
                        ),
                        _Flags(document: document),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [formatDate(document.updatedAt), if (document.tags.isNotEmpty) document.tags.map((t) => '#$t').join(' ')].join('  ·  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.inkMuted, fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    _PagesChip(count: document.pageCount),
                  ],
                ),
              ),
              if (!selecting) DocMenuButton(document: document),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small favourite and pin markers shown next to a document title.
class _Flags extends StatelessWidget {
  const _Flags({required this.document});
  final ScannedDocument document;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (document.favorite)
        const Padding(
          padding: EdgeInsets.only(left: 6),
          child: Icon(AppIcons.star, size: 14, color: AppColors.warning),
        ),
      if (document.pinned)
        const Padding(
          padding: EdgeInsets.only(left: 6),
          child: Icon(AppIcons.pin, size: 14, color: AppColors.primary),
        ),
      if (document.locked)
        const Padding(
          padding: EdgeInsets.only(left: 6),
          child: Icon(AppIcons.lock, size: 14, color: AppColors.inkMuted),
        ),
    ],
  );
}

class _PagesChip extends StatelessWidget {
  const _PagesChip({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(10)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(AppIcons.document, size: 12, color: AppColors.primary),
        const SizedBox(width: 4),
        Text(
          pagesLabel(count),
          style: const TextStyle(color: AppColors.primaryDark, fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}

class DocumentGridCard extends StatelessWidget {
  const DocumentGridCard({super.key, required this.document});
  final ScannedDocument document;

  @override
  Widget build(BuildContext context) {
    final order = context.select((DocumentsCubit c) => c.state.selection.indexOf(document.id));
    final selecting = context.select((DocumentsCubit c) => c.state.selecting);

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        side: BorderSide(color: order >= 0 ? AppColors.primary : AppColors.border, width: order >= 0 ? 2 : 1),
      ),
      child: InkWell(
        onTap: () => _onTap(context, document),
        onLongPress: () => context.read<DocumentsCubit>().toggleSelect(document.id),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    color: AppColors.background,
                    child: DocThumb(document: document, cacheWidth: 420),
                  ),
                  Positioned(top: 8, left: 8, child: _PagesChip(count: document.pageCount)),
                  if (selecting) Positioned(top: 8, right: 8, child: SelectionBadge(order: order)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.sm + 4, AppSpacing.sm, 0, AppSpacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                document.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                              ),
                            ),
                            _Flags(document: document),
                          ],
                        ),
                        Text(formatDate(document.updatedAt), style: const TextStyle(color: AppColors.inkMuted, fontSize: 12)),
                      ],
                    ),
                  ),
                  if (selecting) const SizedBox(width: AppSpacing.sm + 4) else DocMenuButton(document: document),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Documents as a list or a grid, depending on [gridView].
class DocumentsCollection extends StatelessWidget {
  const DocumentsCollection({super.key, required this.documents, required this.gridView});
  final List<ScannedDocument> documents;
  final bool gridView;

  @override
  Widget build(BuildContext context) {
    if (gridView) {
      return SliverGrid.builder(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 220,
          crossAxisSpacing: AppSpacing.md,
          mainAxisSpacing: AppSpacing.md,
          childAspectRatio: 0.76,
        ),
        itemCount: documents.length,
        itemBuilder: (_, i) => DocumentGridCard(document: documents[i]),
      );
    }
    // Two columns once there is room, so rows do not stretch across a tablet.
    if (MediaQuery.sizeOf(context).width >= Breakpoints.medium) {
      return SliverGrid.builder(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 520,
          mainAxisExtent: 96,
          crossAxisSpacing: AppSpacing.md,
          mainAxisSpacing: AppSpacing.sm + 2,
        ),
        itemCount: documents.length,
        itemBuilder: (_, i) => DocumentListTile(document: documents[i]),
      );
    }
    return SliverList.separated(
      itemCount: documents.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm + 2),
      itemBuilder: (_, i) => DocumentListTile(document: documents[i]),
    );
  }
}

/// App bar that turns into a contextual action bar (merge, move, delete) while documents are selected.
class DocumentsAppBar extends StatelessWidget implements PreferredSizeWidget {
  const DocumentsAppBar({super.key, required this.title});
  final String title;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 1);

  Future<void> _merge(BuildContext context) async {
    final cubit = context.read<DocumentsCubit>();
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final count = cubit.state.selection.length;
    final choice = await showDialog<({String title, bool deleteOriginals})>(
      context: context,
      builder: (_) => _MergeDialog(count: count),
    );
    if (choice == null) return;
    final result = await cubit.mergeSelected(title: choice.title, deleteOriginals: choice.deleteOriginals);
    if (result.failure != null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(result.failure!.message)));
      return;
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Merged $count documents'),
          persist: false,
          action: result.id == null ? null : SnackBarAction(label: 'Open', onPressed: () => router.push('/document/${result.id}')),
        ),
      );
  }

  Future<void> _move(BuildContext context) async {
    final cubit = context.read<DocumentsCubit>();
    final target = await pickFolder(context, cubit.state.folders, null);
    if (target == null) return;
    final f = await cubit.moveSelected(target.folderId);
    if (f != null && context.mounted) showFailure(context, f);
  }

  Future<void> _delete(BuildContext context) async {
    final cubit = context.read<DocumentsCubit>();
    final n = cubit.state.selection.length;
    final ok = await confirmDestructive(
      context,
      title: 'Delete $n document${n == 1 ? '' : 's'}?',
      message: 'They will be permanently removed from this device.',
    );
    if (!ok || !context.mounted) return;
    final f = await cubit.deleteSelected();
    if (f != null && context.mounted) showFailure(context, f);
  }

  @override
  Widget build(BuildContext context) {
    final selection = context.select((DocumentsCubit c) => c.state.selection);
    if (selection.isEmpty) {
      return AppBar(
        title: Text(title),
        bottom: const PreferredSize(preferredSize: Size.fromHeight(1), child: Divider()),
      );
    }
    final cubit = context.read<DocumentsCubit>();
    return AppBar(
      backgroundColor: AppColors.primarySoft,
      leading: IconButton(tooltip: 'Cancel selection', icon: const Icon(AppIcons.close), onPressed: cubit.clearSelection),
      title: Text('${selection.length} selected'),
      actions: [
        IconButton(
          tooltip: selection.length < 2 ? 'Select at least 2 documents to merge' : 'Merge into one document',
          icon: const Icon(AppIcons.merge),
          onPressed: selection.length < 2 ? null : () => _merge(context),
        ),
        IconButton(tooltip: 'Move to folder', icon: const Icon(AppIcons.emptyDocs), onPressed: () => _move(context)),
        IconButton(
          tooltip: 'Delete',
          icon: const Icon(AppIcons.delete, color: AppColors.danger),
          onPressed: () => _delete(context),
        ),
      ],
      bottom: const PreferredSize(preferredSize: Size.fromHeight(1), child: Divider()),
    );
  }
}

class _MergeDialog extends StatefulWidget {
  const _MergeDialog({required this.count});
  final int count;

  @override
  State<_MergeDialog> createState() => _MergeDialogState();
}

class _MergeDialogState extends State<_MergeDialog> {
  late final TextEditingController _title = TextEditingController(text: 'Merged ${formatDate(DateTime.now())}');
  bool _deleteOriginals = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Merge ${widget.count} documents'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Pages are combined in the order you selected the documents.', style: TextStyle(color: AppColors.inkMuted, fontSize: 13)),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _title,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'New document name'),
        ),
        const SizedBox(height: AppSpacing.sm),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _deleteOriginals,
          onChanged: (v) => setState(() => _deleteOriginals = v ?? false),
          title: const Text('Delete the original documents'),
        ),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      TextButton(onPressed: () => Navigator.pop(context, (title: _title.text, deleteOriginals: _deleteOriginals)), child: const Text('Merge')),
    ],
  );
}

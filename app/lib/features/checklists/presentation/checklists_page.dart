import 'package:flutter/material.dart' hide Text;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/di.dart';
import '../../../core/i18n/tr.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/region.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/text.dart';
import '../../documents/domain/entities/scanned_document.dart';
import '../../documents/presentation/bloc/documents_cubit.dart';
import '../../documents/presentation/widgets/document_widgets.dart' show confirmDestructive;
import '../../export/domain/repositories/export_repository.dart';
import '../data/checklist_store.dart';
import '../domain/checklists.dart';

IconData templateIcon(String id) => switch (id) {
  'rent' => AppIcons.tplRent,
  'job' => AppIcons.tplJob,
  'car' => AppIcons.tplCar,
  'move' => AppIcons.tplMove,
  'baby' => AppIcons.tplBaby,
  'wedding' => AppIcons.tplWedding,
  'visa' => AppIcons.tplVisa,
  'tax' => AppIcons.tplTax,
  _ => AppIcons.tplBlank,
};

List<ScannedDocument> _libraryDocuments(BuildContext context) => context.read<DocumentsCubit>().state.documents;

Future<void> _shareText(String text, String subject) async {
  await sl<ShareService>().shareText(text: text, subject: subject);
}

({String text, Color color})? dueBadge(Checklist list, DateTime now) {
  final state = dueStateOf(list, now);
  final due = list.due;
  return switch (state) {
    DueState.done => (text: tr('All done'), color: AppColors.success),
    DueState.overdue => (text: trf('Was due {date}', {'date': formatDate(due!)}), color: AppColors.danger),
    DueState.soon => (text: trf('Due {date}', {'date': formatDate(due!)}), color: AppColors.warning),
    DueState.later => (text: trf('Due {date}', {'date': formatDate(due!)}), color: AppColors.inkMuted),
    DueState.none => null,
  };
}

/// The checklists, each with how far it is, and a way to start one from a ready-made list.
class ChecklistsPage extends StatefulWidget {
  const ChecklistsPage({super.key, this.store = const ChecklistStore(), this.now, this.region});
  final ChecklistStore store;
  final DateTime Function()? now;
  final String? region;

  @override
  State<ChecklistsPage> createState() => _ChecklistsPageState();
}

class _ChecklistsPageState extends State<ChecklistsPage> {
  List<Checklist> _lists = const [];
  bool _loaded = false;

  DateTime get _now => (widget.now ?? DateTime.now)();

  String get _region => widget.region ?? Region.toolRegion.name;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await widget.store.load();
    if (mounted) {
      setState(() {
        _lists = all;
        _loaded = true;
      });
    }
  }

  Future<void> _start() async {
    if (_lists.length >= maxChecklists) {
      showMessage(context, 'You have 30 checklists, the most there is room for. Delete one to start another.');
      return;
    }
    final template = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _TemplateSheet(region: _region),
    );
    if (template == null || !mounted) return;
    Checklist list;
    final id = widget.store.newId(_lists, _now);
    if (template is ChecklistTemplate) {
      list = checklistFromTemplate(template, region: _region, id: id, now: _now);
    } else {
      final name = await showDialog<String>(context: context, builder: (_) => const _NameDialog());
      if (name == null || !mounted) return;
      list = Checklist(id: id, title: name.trim(), createdAt: _now.millisecondsSinceEpoch);
    }
    await widget.store.put(list);
    if (!mounted) return;
    await context.push<void>('/checklist', extra: id);
    if (mounted) await _load();
  }

  Future<void> _open(Checklist l) async {
    await context.push<void>('/checklist', extra: l.id);
    if (mounted) await _load();
  }

  Future<void> _delete(Checklist l) async {
    final ok = await confirmDestructive(
      context,
      title: 'Delete this checklist?',
      message: 'The list and its ticks are removed from this phone. Your documents are not deleted.',
    );
    if (!ok || !mounted) return;
    await widget.store.remove(l.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final lists = [..._lists]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return Scaffold(
      appBar: AppBar(title: const Text('Checklists')),
      floatingActionButton: _lists.isEmpty
          ? null
          : FloatingActionButton.extended(
              key: const ValueKey('lists-new'),
              onPressed: _start,
              icon: const Icon(AppIcons.add),
              label: const Text('New checklist'),
            ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : _lists.isEmpty
          ? Center(
              child: SingleChildScrollView(
                padding: contentPadding(context, vertical: AppSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(AppIcons.checklist, size: 56, color: AppColors.inkMuted),
                    const SizedBox(height: AppSpacing.md),
                    const Text('No checklists yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: AppSpacing.sm),
                    const Text(
                      'Moving, a new job, a visa, taxes: pick a ready-made list of the papers you need, tick them off and link the scans you already have.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.inkMuted, height: 1.4),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    FilledButton.icon(
                      key: const ValueKey('empty-start'),
                      onPressed: _start,
                      icon: const Icon(AppIcons.add),
                      label: const Text('Start a checklist'),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: contentPadding(context).copyWith(bottom: 96),
              children: [for (final l in lists) _ListTile(list: l, now: _now, onOpen: () => _open(l), onDelete: () => _delete(l))],
            ),
    );
  }
}

class _ListTile extends StatelessWidget {
  const _ListTile({required this.list, required this.now, required this.onOpen, required this.onDelete});
  final Checklist list;
  final DateTime now;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final badge = dueBadge(list, now);
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: InkWell(
        key: ValueKey('list-${list.id}'),
        onTap: onOpen,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, 4, AppSpacing.md),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(12)),
                child: Icon(templateIcon(list.templateId), color: AppColors.primary),
              ),
              const SizedBox(width: AppSpacing.sm + 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(text: list.title),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(value: list.progress, minHeight: 6, backgroundColor: AppColors.border),
                    ),
                    const SizedBox(height: 6),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: trf('{done} of {total} done', {'done': list.doneCount, 'total': list.items.length})),
                          if (badge != null)
                            TextSpan(
                              text: '  \u00B7  ${badge.text}',
                              style: TextStyle(color: badge.color, fontWeight: FontWeight.w600),
                            ),
                        ],
                      ),
                      style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
                    ),
                  ],
                ),
              ),
              IconButton(key: ValueKey('list-delete-${list.id}'), tooltip: tr('Delete'), icon: const Icon(AppIcons.delete, size: 20), onPressed: onDelete),
            ],
          ),
        ),
      ),
    );
  }
}

class _TemplateSheet extends StatelessWidget {
  const _TemplateSheet({required this.region});
  final String region;

  @override
  Widget build(BuildContext context) {
    final templates = orderedTemplates(region);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
              child: Text('Start a checklist', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ),
            ListTile(
              key: const ValueKey('template-blank'),
              leading: const Icon(AppIcons.tplBlank),
              title: const Text('Blank list'),
              subtitle: const Text('Write your own steps'),
              onTap: () => Navigator.pop(context, 'blank'),
            ),
            for (final t in templates)
              ListTile(
                key: ValueKey('template-${t.id}'),
                leading: Icon(templateIcon(t.id)),
                title: Text(t.title),
                subtitle: Text(t.hint),
                onTap: () => Navigator.pop(context, t),
              ),
          ],
        ),
      ),
    );
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog();

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _c = TextEditingController();
  bool _tried = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _ok() {
    setState(() => _tried = true);
    if (titleProblem(_c.text) == null) Navigator.pop(context, _c.text.trim());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Name the list'),
    content: TextField(
      key: const ValueKey('list-name'),
      controller: _c,
      autofocus: true,
      textCapitalization: TextCapitalization.sentences,
      onSubmitted: (_) => _ok(),
      decoration: InputDecoration(labelText: tr('List name *'), errorText: _tried ? titleProblem(_c.text)?.text : null),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(key: const ValueKey('list-name-ok'), onPressed: _ok, child: const Text('Create')),
    ],
  );
}

/// One list: tick the steps, add notes, link the scanned proof, and send the list to someone.
class ChecklistPage extends StatefulWidget {
  const ChecklistPage({
    super.key,
    required this.listId,
    this.store = const ChecklistStore(),
    this.now,
    this.documentsOf = _libraryDocuments,
    this.share = _shareText,
  });
  final String listId;
  final ChecklistStore store;
  final DateTime Function()? now;
  final List<ScannedDocument> Function(BuildContext context) documentsOf;
  final Future<void> Function(String text, String subject) share;

  @override
  State<ChecklistPage> createState() => _ChecklistPageState();
}

class _ChecklistPageState extends State<ChecklistPage> {
  Checklist? _list;
  bool _loaded = false;
  final _newStep = TextEditingController();
  String? _addError;

  DateTime get _now => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _newStep.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final all = await widget.store.load();
    if (mounted) {
      setState(() {
        _list = all.where((l) => l.id == widget.listId).firstOrNull;
        _loaded = true;
      });
    }
  }

  Future<void> _save(Checklist list) async {
    setState(() => _list = list);
    await widget.store.put(list);
  }

  Future<void> _toggle(ChecklistItem item, bool done) =>
      _save(_list!.copyWith(items: [for (final i in _list!.items) i.id == item.id ? i.copyWith(done: done) : i]));

  Future<void> _add() async {
    final list = _list!;
    final text = _newStep.text.trim();
    final problem = stepProblem(text);
    if (problem != null) {
      setState(() => _addError = problem.text);
      return;
    }
    if (list.items.length >= maxChecklistItems) {
      setState(() => _addError = tr('A list has up to 40 steps. Delete one to add another.'));
      return;
    }
    _newStep.clear();
    setState(() => _addError = null);
    await _save(
      list.copyWith(
        items: [
          ...list.items,
          ChecklistItem(id: list.nextId, text: text),
        ],
      ),
    );
  }

  Future<void> _edit(ChecklistItem item) async {
    final edited = await showDialog<ChecklistItem>(
      context: context,
      builder: (_) => _StepDialog(item: item),
    );
    if (edited == null) return;
    await _save(_list!.copyWith(items: [for (final i in _list!.items) i.id == item.id ? edited : i]));
  }

  Future<void> _deleteStep(ChecklistItem item) => _save(_list!.copyWith(items: _list!.items.where((i) => i.id != item.id).toList()));

  Future<void> _link(ChecklistItem item) async {
    final docs = widget.documentsOf(context);
    final id = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _DocumentPicker(documents: docs),
    );
    if (id == null) return;
    await _save(_list!.copyWith(items: [for (final i in _list!.items) i.id == item.id ? i.copyWith(docId: id, done: true) : i]));
  }

  Future<void> _unlink(ChecklistItem item) => _save(_list!.copyWith(items: [for (final i in _list!.items) i.id == item.id ? i.copyWith(docId: null) : i]));

  Future<void> _rename() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(initial: _list!.title),
    );
    if (name != null) await _save(_list!.copyWith(title: name.trim()));
  }

  Future<void> _pickDue() async {
    final today = _now;
    final picked = await showDatePicker(
      context: context,
      initialDate: _list!.due ?? DateTime(today.year, today.month, today.day + 7),
      firstDate: DateTime(today.year - 1),
      lastDate: DateTime(today.year + 10),
      helpText: tr('Finish by'),
    );
    if (picked != null) await _save(_list!.copyWith(due: picked));
  }

  Future<void> _resetTicks() async {
    final ok = await confirmDestructive(
      context,
      title: 'Clear all ticks?',
      message: 'Every step goes back to not done. The steps and links stay.',
      action: 'Clear ticks',
    );
    if (!ok) return;
    await _save(_list!.copyWith(items: [for (final i in _list!.items) i.copyWith(done: false)]));
  }

  Future<void> _deleteList() async {
    final ok = await confirmDestructive(
      context,
      title: 'Delete this checklist?',
      message: 'The list and its ticks are removed from this phone. Your documents are not deleted.',
    );
    if (!ok || !mounted) return;
    await widget.store.remove(widget.listId);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    if (list == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: _loaded ? const Text('This checklist was not found.') : const CircularProgressIndicator()),
      );
    }
    final docs = widget.documentsOf(context);
    final badge = dueBadge(list, _now);
    return Scaffold(
      appBar: AppBar(
        title: Text.rich(TextSpan(text: list.title), maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            key: const ValueKey('list-share'),
            tooltip: tr('Share the list'),
            icon: const Icon(AppIcons.share),
            onPressed: () => widget.share(checklistAsText(list), list.title),
          ),
          PopupMenuButton<int>(
            key: const ValueKey('list-menu'),
            tooltip: tr('More'),
            onSelected: (v) => switch (v) {
              0 => _rename(),
              1 => _pickDue(),
              2 => _save(list.copyWith(due: null)),
              3 => _resetTicks(),
              _ => _deleteList(),
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 0, child: Text('Rename')),
              const PopupMenuItem(value: 1, child: Text('Set the finish date')),
              if (list.due != null) const PopupMenuItem(value: 2, child: Text('Clear the finish date')),
              const PopupMenuItem(value: 3, child: Text('Clear all ticks')),
              const PopupMenuItem(value: 4, child: Text('Delete the list')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: contentPadding(context).copyWith(bottom: AppSpacing.xl),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    trf('{done} of {total} done', {'done': list.doneCount, 'total': list.items.length}),
                    key: const ValueKey('list-progress'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(value: list.progress, minHeight: 8, backgroundColor: AppColors.border),
                  ),
                  if (badge != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      badge.text,
                      style: TextStyle(color: badge.color, fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (list.items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: Text('This list has no steps yet. Add the first one below.', style: TextStyle(color: AppColors.inkMuted)),
            ),
          for (final item in list.items)
            _StepTile(
              item: item,
              doc: item.docId == null ? null : docs.where((d) => d.id == item.docId).firstOrNull,
              onToggle: (v) => _toggle(item, v),
              onEdit: () => _edit(item),
              onDelete: () => _deleteStep(item),
              onLink: () => _link(item),
              onUnlink: () => _unlink(item),
              onOpenDoc: () => context.push('/document/${item.docId}'),
            ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: const ValueKey('new-step'),
            controller: _newStep,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _add(),
            onChanged: (_) {
              if (_addError != null) setState(() => _addError = null);
            },
            decoration: InputDecoration(
              labelText: tr('Add a step'),
              errorText: _addError,
              errorMaxLines: 2,
              suffixIcon: IconButton(key: const ValueKey('add-step'), tooltip: tr('Add'), icon: const Icon(AppIcons.add), onPressed: _add),
            ),
          ),
          if (list.isComplete)
            const Padding(
              padding: EdgeInsets.only(top: AppSpacing.md),
              child: Row(
                children: [
                  Icon(AppIcons.check, color: AppColors.success),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Everything on this list is done.',
                      style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({
    required this.item,
    required this.doc,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
    required this.onLink,
    required this.onUnlink,
    required this.onOpenDoc,
  });
  final ChecklistItem item;
  final ScannedDocument? doc;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onLink;
  final VoidCallback onUnlink;
  final VoidCallback onOpenDoc;

  @override
  Widget build(BuildContext context) {
    final linked = item.docId != null;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 0, 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(key: ValueKey('step-check-${item.id}'), value: item.done, onChanged: (v) => onToggle(v ?? false)),
            Expanded(
              child: InkWell(
                key: ValueKey('step-${item.id}'),
                onTap: () => onToggle(!item.done),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(text: item.text),
                        style: TextStyle(
                          fontSize: 15,
                          decoration: item.done ? TextDecoration.lineThrough : null,
                          color: item.done ? AppColors.inkMuted : AppColors.ink,
                        ),
                      ),
                      if (item.note.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text.rich(
                            TextSpan(text: item.note),
                            style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
                          ),
                        ),
                      if (linked)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: doc != null
                              ? ActionChip(
                                  key: ValueKey('step-doc-${item.id}'),
                                  avatar: const Icon(AppIcons.document, size: 16),
                                  label: Text.rich(TextSpan(text: doc!.title), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  onPressed: onOpenDoc,
                                )
                              : const Text('The linked document is no longer in your library.', style: TextStyle(fontSize: 12.5, color: AppColors.danger)),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            PopupMenuButton<int>(
              key: ValueKey('step-menu-${item.id}'),
              tooltip: tr('More'),
              onSelected: (v) => switch (v) {
                0 => onEdit(),
                1 => onLink(),
                2 => onUnlink(),
                _ => onDelete(),
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 0, child: Text('Edit step')),
                PopupMenuItem(value: 1, child: Text(linked ? 'Choose another document' : 'Link a document')),
                if (linked) const PopupMenuItem(value: 2, child: Text('Remove the link')),
                const PopupMenuItem(value: 3, child: Text('Delete step')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StepDialog extends StatefulWidget {
  const _StepDialog({required this.item});
  final ChecklistItem item;

  @override
  State<_StepDialog> createState() => _StepDialogState();
}

class _StepDialogState extends State<_StepDialog> {
  late final _text = TextEditingController(text: widget.item.text);
  late final _note = TextEditingController(text: widget.item.note);
  bool _tried = false;

  @override
  void dispose() {
    _text.dispose();
    _note.dispose();
    super.dispose();
  }

  void _ok() {
    setState(() => _tried = true);
    if (stepProblem(_text.text, note: _note.text) == null) Navigator.pop(context, widget.item.copyWith(text: _text.text.trim(), note: _note.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final problem = _tried ? stepProblem(_text.text, note: _note.text) : null;
    final noteBad = problem != null && _text.text.trim().isNotEmpty && _text.text.trim().length <= maxChecklistItemText;
    return AlertDialog(
      title: const Text('Edit step'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('step-text'),
              controller: _text,
              autofocus: true,
              minLines: 1,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: tr('Step *'), errorText: problem != null && !noteBad ? problem.text : null, errorMaxLines: 2),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('step-note'),
              controller: _note,
              minLines: 1,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: tr('Note (optional)'), errorText: noteBad ? problem.text : null, errorMaxLines: 2),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(key: const ValueKey('step-ok'), onPressed: _ok, child: const Text('Save')),
      ],
    );
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});
  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _controller = TextEditingController(text: widget.initial);
  bool _tried = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _ok() {
    setState(() => _tried = true);
    if (titleProblem(_controller.text) == null) Navigator.pop(context, _controller.text);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Rename'),
    content: TextField(
      key: const ValueKey('rename-field'),
      controller: _controller,
      autofocus: true,
      onSubmitted: (_) => _ok(),
      decoration: InputDecoration(labelText: tr('List name *'), errorText: _tried ? titleProblem(_controller.text)?.text : null),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(key: const ValueKey('rename-ok'), onPressed: _ok, child: const Text('Save')),
    ],
  );
}

class _DocumentPicker extends StatefulWidget {
  const _DocumentPicker({required this.documents});
  final List<ScannedDocument> documents;

  @override
  State<_DocumentPicker> createState() => _DocumentPickerState();
}

class _DocumentPickerState extends State<_DocumentPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final docs = widget.documents.where((d) => d.title.toLowerCase().contains(_q.trim().toLowerCase())).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
                child: Text('Choose the document', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              ),
              if (widget.documents.length > 6)
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
                  child: TextField(
                    key: const ValueKey('doc-search'),
                    onChanged: (v) => setState(() => _q = v),
                    decoration: InputDecoration(prefixIcon: const Icon(AppIcons.search), hintText: tr('Search your documents')),
                  ),
                ),
              if (widget.documents.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: Text(
                    'You have no saved documents yet. Scan one first, then link it here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.inkMuted),
                  ),
                )
              else if (docs.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: Text('No document matches your search.', style: TextStyle(color: AppColors.inkMuted)),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final d in docs)
                        ListTile(
                          key: ValueKey('pick-${d.id}'),
                          leading: const Icon(AppIcons.document),
                          title: Text.rich(TextSpan(text: d.title), maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(formatDate(d.updatedAt)),
                          onTap: () => Navigator.pop(context, d.id),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'dart:io';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/i18n/tr.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/region.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/text.dart';
import '../../documents/domain/entities/scanned_document.dart';
import '../../documents/presentation/bloc/documents_cubit.dart';
import '../../pdf_tools/presentation/pdf_result_card.dart';
import '../data/packet_builder.dart';
import '../domain/packet.dart';
import 'packet_cubit.dart';

List<ScannedDocument> _libraryDocuments(BuildContext context) => context.read<DocumentsCubit>().state.documents;

/// Puts several documents in one PDF, in the order wanted, with a cover and contents, page numbers and a size limit for portals.
class PacketPage extends StatelessWidget {
  const PacketPage({
    super.key,
    this.initial = const [],
    this.documentsOf = _libraryDocuments,
    this.builder = const SystemPacketBuilder(),
    this.outputDir = getTemporaryDirectory,
    this.coverRenderer = renderCover,
  });
  final List<String> initial;
  final List<ScannedDocument> Function(BuildContext context) documentsOf;
  final PacketBuilder builder;
  final Future<Directory> Function() outputDir;
  final CoverRenderer coverRenderer;

  @override
  Widget build(BuildContext context) {
    final docs = documentsOf(context);
    return BlocProvider(
      create: (_) => PacketCubit(
        builder: builder,
        outputDir: outputDir,
        library: docs,
        initial: initial,
        letter: Region.letter,
        rtl: Strings.code == 'ar' || Strings.code == 'ur',
        coverRenderer: coverRenderer,
      ),
      child: _PacketView(documents: docs),
    );
  }
}

class _PacketView extends StatefulWidget {
  const _PacketView({required this.documents});
  final List<ScannedDocument> documents;

  @override
  State<_PacketView> createState() => _PacketViewState();
}

class _PacketViewState extends State<_PacketView> {
  late final _title = TextEditingController(text: tr('Application packet'));
  final _name = TextEditingController();
  final _purpose = TextEditingController();
  bool _titleTouched = false;

  @override
  void initState() {
    super.initState();
    context.read<PacketCubit>().setSettings(context.read<PacketCubit>().state.settings.copyWith(title: _title.text));
  }

  @override
  void dispose() {
    _title.dispose();
    _name.dispose();
    _purpose.dispose();
    super.dispose();
  }

  void _settings(PacketSettings Function(PacketSettings s) change) {
    final cubit = context.read<PacketCubit>();
    cubit.setSettings(change(cubit.state.settings));
  }

  Future<void> _add() async {
    final cubit = context.read<PacketCubit>();
    final have = cubit.state.entries.map((e) => e.docId).toSet();
    final ids = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _DocumentPicker(documents: widget.documents.where((d) => !have.contains(d.id)).toList(), room: maxPacketDocuments - have.length),
    );
    if (ids != null) cubit.addDocuments(ids);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Application packet')),
      body: BlocBuilder<PacketCubit, PacketState>(
        builder: (context, state) {
          final s = state.settings;
          final titleError = (state.tried || _titleTouched) ? titleIssue(s.title) : null;
          final docsError = state.tried && state.entries.isEmpty ? const PacketProblem('Add at least one document.') : null;
          final tooMany = state.entries.length > maxPacketDocuments || totalPages(state.entries) > maxPacketPages;
          final blocking = packetProblem(s, state.entries);
          final shownBlock = state.tried ? blocking : null;
          final result = state.result;
          return ListView(
            padding: contentPadding(context).copyWith(bottom: AppSpacing.xl),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              const Text(
                'Put the papers for an application in one PDF: in the order you choose, with a cover and contents, page numbers, and a size small enough for the portal. It is made on this phone.',
                style: TextStyle(fontSize: 13, color: AppColors.inkMuted, height: 1.4),
              ),
              const SizedBox(height: AppSpacing.md),
              _Section(
                title: 'Documents in the packet',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (state.entries.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: Text(
                          docsError == null ? 'No documents yet. Add the ones the application asks for.' : docsError.text,
                          key: const ValueKey('packet-empty'),
                          style: TextStyle(color: docsError == null ? AppColors.inkMuted : AppColors.danger, fontSize: 13),
                        ),
                      ),
                    for (var i = 0; i < state.entries.length; i++)
                      _EntryRow(
                        entry: state.entries[i],
                        index: i,
                        last: i == state.entries.length - 1,
                        onUp: () => context.read<PacketCubit>().move(state.entries[i].docId, -1),
                        onDown: () => context.read<PacketCubit>().move(state.entries[i].docId, 1),
                        onRemove: () => context.read<PacketCubit>().remove(state.entries[i].docId),
                      ),
                    if (state.entries.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 8),
                        child: Text(
                          trf('{pages} pages in all', {'pages': packetPageCount(state.entries, cover: s.cover)}),
                          key: const ValueKey('packet-total'),
                          style: TextStyle(fontSize: 12.5, color: tooMany ? AppColors.danger : AppColors.inkMuted),
                        ),
                      ),
                    OutlinedButton.icon(
                      key: const ValueKey('packet-add'),
                      onPressed: _add,
                      icon: const Icon(AppIcons.add, size: 18),
                      label: const Text('Add documents'),
                    ),
                  ],
                ),
              ),
              _Section(
                title: 'About the packet',
                child: Column(
                  children: [
                    TextField(
                      key: const ValueKey('packet-title'),
                      controller: _title,
                      textCapitalization: TextCapitalization.sentences,
                      onChanged: (v) => _settings((x) => x.copyWith(title: v)),
                      onTapOutside: (_) => setState(() => _titleTouched = true),
                      decoration: InputDecoration(labelText: tr('Title *'), errorText: titleError?.text, errorMaxLines: 2),
                    ),
                    const SizedBox(height: AppSpacing.sm + 4),
                    TextField(
                      key: const ValueKey('packet-name'),
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      onChanged: (v) => _settings((x) => x.copyWith(name: v)),
                      decoration: InputDecoration(labelText: tr('Your name (optional)'), errorText: nameIssue(s.name)?.text, errorMaxLines: 2),
                    ),
                    const SizedBox(height: AppSpacing.sm + 4),
                    TextField(
                      key: const ValueKey('packet-purpose'),
                      controller: _purpose,
                      textCapitalization: TextCapitalization.sentences,
                      onChanged: (v) => _settings((x) => x.copyWith(purpose: v)),
                      decoration: InputDecoration(
                        labelText: tr('What it is for (optional)'),
                        hintText: tr('For example: Visa application'),
                        errorText: purposeIssue(s.purpose)?.text,
                        errorMaxLines: 2,
                      ),
                    ),
                  ],
                ),
              ),
              _Section(
                title: 'Options',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      key: const ValueKey('packet-cover'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Cover page with contents'),
                      subtitle: const Text('Lists each document and the pages it is on'),
                      value: s.cover,
                      onChanged: (v) => _settings((x) => x.copyWith(cover: v)),
                    ),
                    SwitchListTile(
                      key: const ValueKey('packet-numbers'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Number the pages'),
                      subtitle: const Text('Shows 3 / 12 at the foot of each page'),
                      value: s.numbers,
                      onChanged: (v) => _settings((x) => x.copyWith(numbers: v)),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Largest file size',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.inkMuted),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final l in PacketLimit.values)
                          ChoiceChip(
                            key: ValueKey('packet-limit-${l.name}'),
                            label: Text(l.label),
                            selected: s.limit == l,
                            onSelected: (_) => _settings((x) => x.copyWith(limit: l)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Many portals accept only a small file. Doculoom lowers the picture quality just enough to fit, and keeps it as high as it can.',
                      style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted, height: 1.4),
                    ),
                  ],
                ),
              ),
              if (shownBlock != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Text(
                    shownBlock.text,
                    key: const ValueKey('packet-problem'),
                    style: const TextStyle(color: AppColors.danger, fontSize: 13),
                  ),
                ),
              FilledButton.icon(
                key: const ValueKey('packet-make'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: state.status == PacketStatus.building ? null : () => context.read<PacketCubit>().make(),
                icon: state.status == PacketStatus.building
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(AppIcons.pdf, size: 18),
                label: Text(state.status == PacketStatus.building ? 'Making the packet...' : 'Make the packet'),
              ),
              if (state.status == PacketStatus.failed && state.problem != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(
                    state.problem!,
                    key: const ValueKey('packet-failed'),
                    style: const TextStyle(color: AppColors.danger, fontSize: 13),
                  ),
                ),
              if (state.status == PacketStatus.done && result != null) ...[
                const SizedBox(height: AppSpacing.md),
                if (!result.fits)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Text(
                      trf('Even at the lowest picture quality the file is {size}, above the {limit} limit. Remove some pages or choose a larger limit.', {
                        'size': sizeLabel(result.bytes),
                        'limit': s.limit.label,
                      }),
                      key: const ValueKey('packet-too-big'),
                      style: const TextStyle(color: AppColors.danger, fontSize: 13, height: 1.4),
                    ),
                  ),
                PdfResultCard(
                  title: tr('Your packet is ready'),
                  message: [
                    trf('{pages} pages, {size}.', {'pages': result.pageCount, 'size': sizeLabel(result.bytes)}),
                    if (result.reduced) tr('The pictures were made smaller to fit the limit.'),
                  ].join(' '),
                  path: result.path,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: AppSpacing.sm),
            child,
          ],
        ),
      ),
    ),
  );
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry, required this.index, required this.last, required this.onUp, required this.onDown, required this.onRemove});
  final PacketEntry entry;
  final int index;
  final bool last;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Container(
    key: ValueKey('packet-doc-${entry.docId}'),
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsetsDirectional.fromSTEB(12, 4, 0, 4),
    decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(10)),
    child: Row(
      children: [
        SizedBox(
          width: 22,
          child: Text(
            '${index + 1}',
            style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.inkMuted),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(text: entry.title),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(trf('{n} pages', {'n': entry.pageCount}), style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
            ],
          ),
        ),
        IconButton(
          key: ValueKey('packet-up-${entry.docId}'),
          tooltip: tr('Move up'),
          visualDensity: VisualDensity.compact,
          icon: const Icon(AppIcons.moveUp, size: 20),
          onPressed: index == 0 ? null : onUp,
        ),
        IconButton(
          key: ValueKey('packet-down-${entry.docId}'),
          tooltip: tr('Move down'),
          visualDensity: VisualDensity.compact,
          icon: const Icon(AppIcons.moveDown, size: 20),
          onPressed: last ? null : onDown,
        ),
        IconButton(
          key: ValueKey('packet-remove-${entry.docId}'),
          tooltip: tr('Remove'),
          visualDensity: VisualDensity.compact,
          icon: const Icon(AppIcons.close, size: 20),
          onPressed: onRemove,
        ),
      ],
    ),
  );
}

class _DocumentPicker extends StatefulWidget {
  const _DocumentPicker({required this.documents, required this.room});
  final List<ScannedDocument> documents;
  final int room;

  @override
  State<_DocumentPicker> createState() => _DocumentPickerState();
}

class _DocumentPickerState extends State<_DocumentPicker> {
  final _picked = <String>[];
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final docs = widget.documents.where((d) => d.title.toLowerCase().contains(_q.trim().toLowerCase())).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final full = _picked.length >= widget.room;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
                child: Text('Choose the documents', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              ),
              if (widget.documents.length > 6)
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
                  child: TextField(
                    key: const ValueKey('packet-search'),
                    onChanged: (v) => setState(() => _q = v),
                    decoration: InputDecoration(prefixIcon: const Icon(AppIcons.search), hintText: tr('Search your documents')),
                  ),
                ),
              if (widget.documents.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: Text(
                    'There are no more documents to add. Scan or import one first.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.inkMuted),
                  ),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final d in docs)
                        CheckboxListTile(
                          key: ValueKey('packet-pick-${d.id}'),
                          value: _picked.contains(d.id),
                          onChanged: d.locked || d.pages.isEmpty || (full && !_picked.contains(d.id))
                              ? null
                              : (v) => setState(() {
                                  if (v ?? false) {
                                    _picked.add(d.id);
                                  } else {
                                    _picked.remove(d.id);
                                  }
                                }),
                          title: Text.rich(TextSpan(text: d.title), maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            d.locked
                                ? tr('Locked: unlock it first to add it')
                                : '${trf('{n} pages', {'n': d.pages.length})}  \u00B7  ${formatDate(d.updatedAt)}',
                          ),
                        ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: FilledButton(
                  key: const ValueKey('packet-pick-done'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                  onPressed: _picked.isEmpty ? null : () => Navigator.pop(context, _picked),
                  child: Text(_picked.isEmpty ? 'Choose at least one' : trf('Add {n}', {'n': _picked.length})),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

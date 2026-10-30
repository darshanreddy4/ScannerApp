import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path_provider/path_provider.dart';

import '../../../app/di.dart';
import '../../../core/error/failures.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/responsive.dart';
import '../../export/domain/repositories/export_repository.dart';
import '../domain/pdf_pages.dart';
import 'pdf_pages_cubit.dart';
import '../../../core/widgets/text.dart';
import '../../../core/i18n/tr.dart';

/// Pick, remove, turn and split the pages of a PDF, and print page numbers, a header or a footer on them.
class PdfPagesPage extends StatelessWidget {
  const PdfPagesPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => PdfPagesCubit(service: sl<PdfPageService>(), outputDir: getTemporaryDirectory),
    child: const _PagesView(),
  );
}

class _PagesView extends StatelessWidget {
  const _PagesView();

  Future<void> _pick(BuildContext context) async {
    try {
      final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['pdf']);
      final path = picked.isEmpty ? null : picked.first.path;
      if (path == null || !context.mounted) return;
      await context.read<PdfPagesCubit>().open(path);
    } catch (_) {
      if (context.mounted) showFailure(context, const PermissionFailure('The file picker is unavailable.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PdfPagesCubit, PdfPagesState>(
      builder: (context, state) {
        final cubit = context.read<PdfPagesCubit>();
        final pad = contentPadding(context, base: AppSpacing.md, maxWidth: 640);
        return Scaffold(
          appBar: AppBar(
            title: const Text('Split and number PDF'),
            actions: [if (state.pdf != null && !state.busy) TextButton(onPressed: cubit.clear, child: const Text('Clear'))],
          ),
          body: SafeArea(
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: pad.copyWith(bottom: 0),
                  sliver: SliverToBoxAdapter(
                    child: _Header(state: state, onPick: () => _pick(context)),
                  ),
                ),
                if (state.pdf != null) ...[
                  SliverPadding(
                    padding: pad.copyWith(top: AppSpacing.sm, bottom: 0),
                    sliver: SliverToBoxAdapter(child: _SelectBar(state: state)),
                  ),
                  SliverPadding(
                    padding: pad.copyWith(top: AppSpacing.sm, bottom: 0),
                    sliver: SliverGrid.builder(
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 112,
                        mainAxisSpacing: AppSpacing.sm,
                        crossAxisSpacing: AppSpacing.sm,
                        childAspectRatio: 0.7,
                      ),
                      itemCount: state.pageCount,
                      itemBuilder: (_, i) => _PageTile(
                        key: ValueKey('page-$i'),
                        index: i,
                        path: state.pdf!.pages[i],
                        selected: state.selected.contains(i),
                        turns: state.rotations[i] ?? 0,
                        onTap: state.busy ? null : () => cubit.toggle(i),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: pad.copyWith(top: AppSpacing.md),
                    sliver: SliverToBoxAdapter(child: _Actions(state: state)),
                  ),
                ] else
                  SliverPadding(
                    padding: pad.copyWith(top: AppSpacing.md),
                    sliver: const SliverToBoxAdapter(child: _Note()),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state, required this.onPick});
  final PdfPagesState state;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    if (state.status == PagesStatus.opening) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            CircularProgressIndicator(),
            SizedBox(height: AppSpacing.sm),
            Text('Reading the pages'),
          ],
        ),
      );
    }
    final pdf = state.pdf;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pdf == null)
          FilledButton.icon(onPressed: onPick, icon: const Icon(AppIcons.importFile, size: 18), label: const Text('Choose a PDF'))
        else
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(AppIcons.pdf, color: AppColors.primary),
              title: Text('${pdf.name}.pdf', maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text('${state.pageCount} ${state.pageCount == 1 ? 'page' : 'pages'}. Tap pages to select them.'),
              trailing: state.busy ? null : TextButton(onPressed: onPick, child: const Text('Change')),
            ),
          ),
        if (pdf == null && state.failure != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: Text(state.failure!.message, style: const TextStyle(color: AppColors.danger, height: 1.4)),
          ),
      ],
    );
  }
}

class _SelectBar extends StatefulWidget {
  const _SelectBar({required this.state});
  final PdfPagesState state;

  @override
  State<_SelectBar> createState() => _SelectBarState();
}

class _SelectBarState extends State<_SelectBar> {
  final _range = TextEditingController();

  @override
  void dispose() {
    _range.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<PdfPagesCubit>();
    final state = widget.state;
    final busy = state.busy;
    final none = state.selected.isEmpty;
    ButtonStyle small() => OutlinedButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 12));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            OutlinedButton(style: small(), onPressed: busy ? null : cubit.selectAll, child: const Text('All')),
            OutlinedButton(style: small(), onPressed: busy || none ? null : cubit.selectNone, child: const Text('None')),
            OutlinedButton(style: small(), onPressed: busy ? null : () => cubit.selectParity(odd: true), child: const Text('Odd')),
            OutlinedButton(style: small(), onPressed: busy ? null : () => cubit.selectParity(odd: false), child: const Text('Even')),
            OutlinedButton.icon(
              style: small(),
              onPressed: busy || none ? null : () => cubit.rotateSelected(-1),
              icon: const Icon(AppIcons.reset, size: 16),
              label: const Text('Turn left'),
            ),
            OutlinedButton.icon(
              style: small(),
              onPressed: busy || none ? null : () => cubit.rotateSelected(1),
              icon: const Icon(AppIcons.rotate, size: 16),
              label: const Text('Turn right'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _range,
                enabled: !busy,
                keyboardType: TextInputType.text,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,;\-– ]'))],
                decoration: InputDecoration(isDense: true, hintText: tr('Select pages, for example 1-3, 5'), errorText: state.rangeError, errorMaxLines: 3),
                onSubmitted: cubit.selectRanges,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            OutlinedButton(style: small(), onPressed: busy ? null : () => cubit.selectRanges(_range.text), child: const Text('Select')),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: Text(
            none ? 'No pages selected' : '${state.selected.length} of ${state.pageCount} selected',
            style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
          ),
        ),
      ],
    );
  }
}

class _PageTile extends StatelessWidget {
  const _PageTile({super.key, required this.index, required this.path, required this.selected, required this.turns, required this.onTap});
  final int index;
  final String path;
  final bool selected;
  final int turns;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: 'Page ${index + 1}${selected ? ', selected' : ''}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: selected ? AppColors.primary : AppColors.border, width: selected ? 2.5 : 1),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Padding(
                padding: const EdgeInsets.all(4),
                child: RotatedBox(
                  quarterTurns: turns,
                  child: Image.file(
                    File(path),
                    fit: BoxFit.contain,
                    cacheWidth: 240,
                    errorBuilder: (_, _, _) => const Center(child: Icon(AppIcons.document)),
                  ),
                ),
              ),
              Positioned(
                left: 4,
                bottom: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              if (selected)
                const Positioned(
                  top: 4,
                  right: 4,
                  child: CircleAvatar(
                    radius: 10,
                    backgroundColor: AppColors.primary,
                    child: Icon(AppIcons.check, size: 13, color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Actions extends StatefulWidget {
  const _Actions({required this.state});
  final PdfPagesState state;

  @override
  State<_Actions> createState() => _ActionsState();
}

class _ActionsState extends State<_Actions> {
  late final _every = TextEditingController(text: '${widget.state.splitEvery}');
  late final _ranges = TextEditingController(text: widget.state.splitRanges);
  late final _header = TextEditingController(text: widget.state.marks.header);
  late final _footer = TextEditingController(text: widget.state.marks.footer);

  @override
  void dispose() {
    _every.dispose();
    _ranges.dispose();
    _header.dispose();
    _footer.dispose();
    super.dispose();
  }

  Future<void> _share(List<PdfPart> parts) async {
    final failure = (await sl<ShareService>().shareFiles(paths: [for (final p in parts) p.path], mimeType: 'application/pdf')).failureOrNull;
    if (failure != null && mounted) showFailure(context, failure);
  }

  Future<void> _save(PdfPart part) async {
    final result = await sl<SaveService>().saveToFiles(sourcePath: part.path, fileName: part.name, mimeType: 'application/pdf');
    if (!mounted) return;
    final failure = result.failureOrNull;
    if (failure != null) {
      showFailure(context, failure);
    } else if (result.valueOrNull == true) {
      showMessage(context, 'Saved');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<PdfPagesCubit>();
    final state = widget.state;
    final busy = state.busy;
    final marks = state.marks;
    final running = state.status == PagesStatus.running;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('What to make', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            for (final a in PageAction.values)
              ChoiceChip(label: Text(a.label), selected: state.action == a, onSelected: busy ? null : (_) => cubit.setAction(a)),
          ],
        ),
        if (state.action == PageAction.split) ...[
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              for (final m in SplitMode.values)
                ChoiceChip(label: Text(m.label), selected: state.splitMode == m, onSelected: busy ? null : (_) => cubit.setSplitMode(m)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (state.splitMode == SplitMode.every)
            TextField(
              controller: _every,
              enabled: !busy,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
              decoration: InputDecoration(isDense: true, labelText: tr('Pages in each file')),
              onChanged: (v) {
                final n = int.tryParse(v);
                if (n != null && n > 0) cubit.setSplitEvery(n);
              },
            ),
          if (state.splitMode == SplitMode.ranges)
            TextField(
              controller: _ranges,
              enabled: !busy,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,;\-– ]'))],
              decoration: InputDecoration(isDense: true, labelText: tr('One file per part'), hintText: tr('1-3, 4-6, 7-')),
              onChanged: cubit.setSplitRanges,
            ),
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(switch (state.splitMode) {
              SplitMode.each => 'One PDF for every page.',
              SplitMode.every => 'The last file may have fewer pages.',
              SplitMode.ranges => 'Each part separated by a comma becomes its own PDF.',
            }, style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            shape: const Border(),
            collapsedShape: const Border(),
            leading: const Icon(AppIcons.edit, color: AppColors.primary),
            title: const Text('Page numbers, header, footer', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(marks.isEmpty ? 'Off' : 'On', style: const TextStyle(fontSize: 12.5)),
            childrenPadding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final n in PageNumberStyle.values)
                    ChoiceChip(
                      label: Text(n.label),
                      selected: marks.numbers == n,
                      onSelected: busy ? null : (_) => cubit.setMarks(marks.copyWith(numbers: n)),
                    ),
                ],
              ),
              if (marks.numbers != PageNumberStyle.none) ...[
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final n in NumberPosition.values)
                      ChoiceChip(
                        label: Text(n.label),
                        selected: marks.position == n,
                        onSelected: busy ? null : (_) => cubit.setMarks(marks.copyWith(position: n)),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _header,
                enabled: !busy,
                maxLength: 80,
                decoration: InputDecoration(isDense: true, labelText: tr('Header (top of every page)'), counterText: ''),
                onChanged: (v) => cubit.setMarks(cubit.state.marks.copyWith(header: v)),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _footer,
                enabled: !busy,
                maxLength: 80,
                decoration: InputDecoration(isDense: true, labelText: tr('Footer (bottom of every page)'), counterText: ''),
                onChanged: (v) => cubit.setMarks(cubit.state.marks.copyWith(footer: v)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Leave the first page clean'),
                value: marks.skipFirst,
                onChanged: busy ? null : (v) => cubit.setMarks(marks.copyWith(skipFirst: v)),
              ),
              const Text(
                'Text is printed over the page, so it can cover content at the very edge. Numbers count the pages of each new file.',
                style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted, height: 1.4),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        FilledButton.icon(
          onPressed: busy ? null : cubit.run,
          icon: running
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(AppIcons.pdfPages, size: 18),
          label: Text(running ? 'Working on page ${state.done} of ${state.total}' : 'Create PDF'),
        ),
        if (state.failure != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: Text(state.failure!.message, style: const TextStyle(color: AppColors.danger, height: 1.4)),
          ),
        if (state.parts.isNotEmpty) ...[const SizedBox(height: AppSpacing.md), _Results(parts: state.parts, onShare: () => _share(state.parts), onSave: _save)],
        const SizedBox(height: AppSpacing.md),
        const _Note(),
      ],
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({required this.parts, required this.onShare, required this.onSave});
  final List<PdfPart> parts;
  final VoidCallback onShare;
  final void Function(PdfPart) onSave;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      color: AppColors.primarySoft,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(parts.length == 1 ? 'Your PDF is ready' : '${parts.length} PDFs are ready', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: AppSpacing.sm),
            for (final part in parts)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${part.name}\n${part.pages} ${part.pages == 1 ? 'page' : 'pages'}, ${formatBytes(part.bytes)}',
                        style: const TextStyle(fontSize: 12.5, height: 1.35),
                      ),
                    ),
                    IconButton(tooltip: 'Save ${part.name} to Files', icon: const Icon(AppIcons.storage, size: 20), onPressed: () => onSave(part)),
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.xs),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: onShare,
              icon: const Icon(AppIcons.share, size: 18),
              label: Text(parts.length == 1 ? 'Share' : 'Share all'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note();

  @override
  Widget build(BuildContext context) => const Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(AppIcons.info, size: 20, color: AppColors.primary),
          SizedBox(width: AppSpacing.sm + 4),
          Expanded(
            child: Text(
              'Pick, remove, turn or split pages, and add page numbers. New PDFs are made from page pictures, so text in them can no longer be selected. Password-protected PDFs cannot be opened.',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    ),
  );
}

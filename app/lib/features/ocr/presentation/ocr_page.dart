import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../app/di.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/responsive.dart';
import '../../documents/domain/entities/scanned_document.dart';
import '../../export/domain/repositories/export_repository.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../domain/ocr_models.dart';
import 'markdown_math_view.dart';
import 'ocr_cubit.dart';

/// Reads the text of a saved document on the phone and shows it with headings, lists and typeset formulas.
class OcrPage extends StatelessWidget {
  const OcrPage({super.key, required this.document});
  final ScannedDocument document;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => OcrCubit(document: document, recognize: sl(), repository: sl(), initialScript: context.read<SettingsCubit>().state.ocrScript)..load(),
    child: _OcrView(document: document),
  );
}

class _OcrView extends StatelessWidget {
  const _OcrView({required this.document});
  final ScannedDocument document;

  Future<void> _start(BuildContext context) async {
    final cubit = context.read<OcrCubit>();
    // Remember the language for next time.
    await context.read<SettingsCubit>().update((s) => s.copyWith(ocrScript: cubit.state.script));
    await cubit.run();
  }

  Future<void> _share(BuildContext context, String markdown) async {
    final dir = await getTemporaryDirectory();
    final folder = await Directory(p.join(dir.path, 'exports')).create(recursive: true);
    final safe = document.title.replaceAll(RegExp(r'[^\w\- ]+'), '').trim().replaceAll(RegExp(r'\s+'), '_');
    final file = await File(p.join(folder.path, '${safe.isEmpty ? 'document' : safe}.md')).writeAsString(markdown);
    final result = await sl<ShareService>().shareFile(path: file.path, mimeType: 'text/markdown', subject: document.title);
    final failure = result.failureOrNull;
    if (failure != null && context.mounted) showFailure(context, failure);
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<OcrCubit, OcrState>(
      listenWhen: (a, b) => b.failure != null && a.failure != b.failure && b.status == OcrStatus.ready,
      listener: (context, s) => showFailure(context, s.failure!),
      builder: (context, state) {
        final ready = state.status == OcrStatus.ready;
        return Scaffold(
          appBar: AppBar(
            title: Text(document.title, overflow: TextOverflow.ellipsis),
            actions: [
              if (ready)
                IconButton(
                  tooltip: 'Copy all text',
                  icon: const Icon(AppIcons.copy),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: state.fullMarkdown));
                    if (context.mounted) showMessage(context, 'Text copied');
                  },
                ),
              if (ready)
                PopupMenuButton<String>(
                  tooltip: 'More',
                  icon: const Icon(AppIcons.more),
                  onSelected: (v) {
                    switch (v) {
                      case 'share':
                        _share(context, state.fullMarkdown);
                      case 'again':
                        context.read<OcrCubit>().run();
                      case 'delete':
                        context.read<OcrCubit>().deleteText();
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'share', child: Text('Share as Markdown file')),
                    PopupMenuItem(value: 'again', child: Text('Read the pages again')),
                    PopupMenuItem(value: 'delete', child: Text('Delete extracted text')),
                  ],
                ),
            ],
          ),
          body: switch (state.status) {
            OcrStatus.loading => const Center(child: CircularProgressIndicator()),
            OcrStatus.empty => _Start(onStart: () => _start(context), message: null),
            OcrStatus.failed => _Start(onStart: () => _start(context), message: state.failure?.message ?? 'The text could not be read.'),
            OcrStatus.running => _Running(state: state),
            OcrStatus.ready => const _Result(),
          },
        );
      },
    );
  }
}

class _Start extends StatelessWidget {
  const _Start({required this.onStart, required this.message});
  final VoidCallback onStart;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<OcrCubit>().state;
    return ListView(
      padding: contentPadding(context, base: AppSpacing.lg, maxWidth: 560),
      children: [
        const SizedBox(height: AppSpacing.lg),
        const Icon(AppIcons.ocr, size: 56, color: AppColors.primary),
        const SizedBox(height: AppSpacing.md),
        const Text(
          'Extract the text',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppSpacing.sm),
        const Text(
          'Reads every page on this phone and shows the words with headings, lists and formulas. Nothing is uploaded, and it works offline.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.inkMuted, height: 1.4),
        ),
        if (message != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            message!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.danger),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        DropdownButtonFormField<OcrScript>(
          initialValue: state.script,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Language of the text', prefixIcon: Icon(AppIcons.language, size: 20)),
          items: [for (final s in OcrScript.values) DropdownMenuItem(value: s, child: Text(s.label))],
          onChanged: (s) {
            if (s != null) context.read<OcrCubit>().setScript(s);
          },
        ),
        const SizedBox(height: 6),
        Text(state.script.languages, style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
        const SizedBox(height: AppSpacing.lg),
        FilledButton.icon(onPressed: onStart, icon: const Icon(AppIcons.ocr, size: 20), label: Text(message == null ? 'Extract text' : 'Try again')),
        const SizedBox(height: AppSpacing.md),
        const Text(
          'Printed text works best. Arabic is not supported yet, and handwriting and complex formulas may be read incorrectly.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: AppColors.inkMuted, height: 1.4),
        ),
      ],
    );
  }
}

class _Running extends StatelessWidget {
  const _Running({required this.state});
  final OcrState state;

  @override
  Widget build(BuildContext context) {
    final page = (state.done + 1).clamp(1, state.total == 0 ? 1 : state.total);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 260, child: LinearProgressIndicator(value: state.total == 0 ? null : state.done / state.total)),
            const SizedBox(height: AppSpacing.md),
            Text('Reading page $page of ${state.total}', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton(onPressed: context.read<OcrCubit>().cancel, child: const Text('Cancel')),
          ],
        ),
      ),
    );
  }
}

class _Result extends StatefulWidget {
  const _Result();

  @override
  State<_Result> createState() => _ResultState();
}

class _ResultState extends State<_Result> {
  bool _editing = false;
  late final TextEditingController _controller = TextEditingController();
  String _loadedFor = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _syncEditor(PageText? page) {
    final key = page == null ? '' : '${page.position}:${page.markdown.hashCode}';
    if (key != _loadedFor) {
      _loadedFor = key;
      _controller.text = page?.markdown ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<OcrCubit>().state;
    final cubit = context.read<OcrCubit>();
    final page = state.current;
    _syncEditor(page);
    final empty = page == null || page.markdown.trim().isEmpty;
    final dirty = page != null && _controller.text != page.markdown;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.sm, AppSpacing.sm, 0),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (state.pages.length > 1) ...[
                IconButton(
                  tooltip: 'Previous page',
                  onPressed: state.selected > 0 ? () => cubit.selectPage(state.selected - 1) : null,
                  icon: const Icon(AppIcons.back),
                ),
                Text('Page ${state.selected + 1} of ${state.pages.length}', style: const TextStyle(fontWeight: FontWeight.w600)),
                IconButton(
                  tooltip: 'Next page',
                  onPressed: state.selected < state.pages.length - 1 ? () => cubit.selectPage(state.selected + 1) : null,
                  icon: const Icon(AppIcons.next),
                ),
              ],
              SegmentedButton<bool>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: const [
                  ButtonSegment(value: false, label: Text('Formatted')),
                  ButtonSegment(value: true, label: Text('Edit')),
                ],
                selected: {_editing},
                onSelectionChanged: (s) => setState(() => _editing = s.first),
              ),
            ],
          ),
        ),
        const Divider(height: 16),
        Expanded(
          child: _editing
              ? Padding(
                  padding: contentPadding(context, base: AppSpacing.md, maxWidth: 820, vertical: AppSpacing.sm),
                  child: Column(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          maxLines: null,
                          expands: true,
                          textAlignVertical: TextAlignVertical.top,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 14, height: 1.4),
                          decoration: const InputDecoration(hintText: 'Text with Markdown. Formulas go between \$ signs.'),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(onPressed: dirty ? () => setState(() => _controller.text = page.markdown) : null, child: const Text('Undo changes')),
                          const SizedBox(width: AppSpacing.sm),
                          FilledButton(
                            style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                            onPressed: dirty
                                ? () async {
                                    await cubit.saveEdit(_controller.text);
                                    if (context.mounted) showMessage(context, 'Text saved');
                                  }
                                : null,
                            child: const Text('Save'),
                          ),
                        ],
                      ),
                    ],
                  ),
                )
              : empty
              ? const Center(
                  child: Text('No text was found on this page.', style: TextStyle(color: AppColors.inkMuted)),
                )
              : SingleChildScrollView(
                  padding: contentPadding(context, base: AppSpacing.md, maxWidth: 820, vertical: AppSpacing.md),
                  child: MarkdownMathView(markdown: page.markdown),
                ),
        ),
        if (page?.edited ?? false)
          const Padding(
            padding: EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text('Edited by you', style: TextStyle(fontSize: 12, color: AppColors.inkMuted)),
          ),
      ],
    );
  }
}

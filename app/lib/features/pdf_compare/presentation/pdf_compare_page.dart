import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path_provider/path_provider.dart';

import '../../../app/di.dart';
import '../../../core/error/failures.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/responsive.dart';
import '../../export/domain/repositories/export_repository.dart';
import '../../ocr/domain/ocr_engine.dart';
import '../../pdf_tools/data/pdf_picture_pages.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../domain/pdf_comparison.dart';
import '../domain/text_compare.dart';
import 'pdf_compare_cubit.dart';
import '../../../core/widgets/text.dart';

/// Where a PDF is chosen; replaced in tests.
typedef PdfPicker = Future<String?> Function();

Future<String?> _pickPdf() async {
  final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['pdf']);
  return picked.isEmpty ? null : picked.first.path;
}

const _removedColor = Color(0xFFE11D48);
const _addedColor = Color(0xFF16A34A);
const _looksColor = Color(0xFFF59E0B);

/// Compares two versions of a PDF: the words that were taken out and put in, and the pages that look different, with the places marked.
class PdfComparePage extends StatelessWidget {
  const PdfComparePage({super.key, this.engine, this.pdfPages, this.readWords, this.pickPdf = _pickPdf, this.maxPages = 60});

  /// For tests; the phone's text reader and PDF reader are used otherwise.
  final OcrEngine? engine;
  final PdfPicturePages Function()? pdfPages;
  final Future<List<PageWords>> Function(Uint8List bytes, int maxPages)? readWords;
  final PdfPicker pickPdf;
  final int maxPages;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) => PdfCompareCubit(
      engine: engine ?? sl<OcrEngine>(),
      outputDir: getTemporaryDirectory,
      script: context.read<SettingsCubit>().state.ocrScript,
      pdfPages: pdfPages,
      readWords: readWords,
      maxPages: maxPages,
    ),
    child: _CompareView(pickPdf: pickPdf),
  );
}

enum _Tab { text, pages }

class _CompareView extends StatefulWidget {
  const _CompareView({required this.pickPdf});
  final PdfPicker pickPdf;

  @override
  State<_CompareView> createState() => _CompareViewState();
}

class _CompareViewState extends State<_CompareView> {
  var _tab = _Tab.text;

  Future<void> _choose(bool original) async {
    try {
      final path = await widget.pickPdf();
      if (path == null || !mounted) return;
      final cubit = context.read<PdfCompareCubit>();
      original ? cubit.setOriginal(path) : cubit.setRevised(path);
    } catch (_) {
      if (mounted) showFailure(context, const PermissionFailure('The file picker is unavailable.'));
    }
  }

  Future<void> _share(Future<String?> Function() make, String mime) async {
    final path = await make();
    if (path == null || !mounted) return;
    final failure = (await sl<ShareService>().shareFile(path: path, mimeType: mime, subject: 'Changes between two PDFs')).failureOrNull;
    if (failure != null && mounted) showFailure(context, failure);
  }

  @override
  Widget build(BuildContext context) => BlocConsumer<PdfCompareCubit, PdfCompareState>(
    listenWhen: (a, b) => a.result == null && b.result != null,
    listener: (context, s) => setState(() => _tab = s.result!.text.changes.isEmpty && s.result!.pages.isNotEmpty ? _Tab.pages : _Tab.text),
    builder: (context, state) {
      final cubit = context.read<PdfCompareCubit>();
      final result = state.result;
      return Scaffold(
        appBar: AppBar(title: const Text('Compare two PDFs')),
        body: SafeArea(
          child: ListView(
            padding: contentPadding(context, base: AppSpacing.md, maxWidth: 720),
            children: [
              _ChooseCard(state: state, onOriginal: () => _choose(true), onRevised: () => _choose(false)),
              if (state.comparing) ...[const SizedBox(height: AppSpacing.md), _Progress(state: state)],
              for (final n in state.notes)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(
                    n,
                    key: const ValueKey('compare-note'),
                    style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted, height: 1.4),
                  ),
                ),
              if (state.failure != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.md),
                  child: Text(
                    state.failure!.message,
                    key: const ValueKey('compare-failure'),
                    style: const TextStyle(color: AppColors.danger, height: 1.4),
                  ),
                ),
              if (result != null) ...[
                const SizedBox(height: AppSpacing.md),
                _Summary(result: result, nameA: state.nameA, nameB: state.nameB),
                if (!result.identical) ...[
                  const SizedBox(height: AppSpacing.md),
                  SegmentedButton<_Tab>(
                    key: const ValueKey('compare-tabs'),
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: _Tab.text,
                        label: Text('Words (${result.text.changes.length})', key: const ValueKey('compare-tab-text')),
                      ),
                      ButtonSegment(
                        value: _Tab.pages,
                        label: Text('Pages (${result.pages.length})', key: const ValueKey('compare-tab-pages')),
                      ),
                    ],
                    selected: {_tab},
                    onSelectionChanged: (s) => setState(() => _tab = s.first),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (_tab == _Tab.text) ..._textTab(result) else ..._pagesTab(result),
                ],
              ],
              const SizedBox(height: AppSpacing.md),
              const _Note(),
            ],
          ),
        ),
        bottomNavigationBar: result == null || result.identical || state.comparing
            ? null
            : _Actions(
                onText: () => _share(cubit.writeChangesText, 'text/plain'),
                onPdf: result.pages.isEmpty ? null : () => _share(cubit.writeReportPdf, 'application/pdf'),
              ),
      );
    },
  );

  List<Widget> _textTab(PdfComparison result) {
    final t = result.text;
    if (t.tooDifferent) {
      return const [
        Text(
          'The two files have very little text in common, so the changes are not listed one by one. Look at the pages instead.',
          key: ValueKey('compare-too-different'),
        ),
      ];
    }
    if (t.changes.isEmpty) {
      return [
        Text(
          result.noText
              ? 'There is no text to compare. See the pages that look different.'
              : 'The words are the same in both files. See the pages that look different.',
          key: const ValueKey('compare-no-text-changes'),
        ),
      ];
    }
    return [for (final (i, c) in t.changes.indexed) _ChangeTile(index: i, change: c)];
  }

  List<Widget> _pagesTab(PdfComparison result) {
    if (result.pages.isEmpty) return const [Text('No page looks different.', key: ValueKey('compare-no-pages'))];
    return [for (final p in result.pages) _PageCard(page: p)];
  }
}

class _ChooseCard extends StatelessWidget {
  const _ChooseCard({required this.state, required this.onOriginal, required this.onRevised});
  final PdfCompareState state;
  final VoidCallback onOriginal;
  final VoidCallback onRevised;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<PdfCompareCubit>();
    final busy = state.comparing;
    Widget row(String key, String label, String? name, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
                Text(
                  name == null || name.isEmpty ? 'Not chosen' : name,
                  key: ValueKey('$key-name'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          OutlinedButton(
            key: ValueKey(key),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
            onPressed: busy ? null : onTap,
            child: Text(name == null ? 'Choose' : 'Change'),
          ),
        ],
      ),
    );
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Choose the two files', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'The original is the older file and the revised is the newer one. You see what was taken out, what was put in, and which pages look different.',
              style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted, height: 1.4),
            ),
            const SizedBox(height: AppSpacing.sm),
            row('compare-original', 'Original', state.pathA == null ? null : state.nameA, onOriginal),
            row('compare-revised', 'Revised', state.pathB == null ? null : state.nameB, onRevised),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: const ValueKey('compare-swap'),
                onPressed: busy || !state.ready ? null : cubit.swap,
                icon: const Icon(AppIcons.swap, size: 18),
                label: const Text('Swap the two files'),
              ),
            ),
            SwitchListTile(
              key: const ValueKey('compare-ocr'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Read pages that are pictures'),
              subtitle: const Text('Scanned pages have no text. They are read on the phone so their words can be compared.', style: TextStyle(fontSize: 12)),
              value: state.useOcr,
              onChanged: busy ? null : cubit.setUseOcr,
            ),
            const SizedBox(height: AppSpacing.xs),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const ValueKey('compare-start'),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 46)),
                onPressed: busy || !state.ready ? null : cubit.compare,
                icon: const Icon(AppIcons.fileDiff, size: 18),
                label: Text(state.result == null ? 'Compare' : 'Compare again'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.state});
  final PdfCompareState state;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(state.label, key: const ValueKey('compare-progress'), maxLines: 3, overflow: TextOverflow.ellipsis),
          const SizedBox(height: AppSpacing.sm),
          LinearProgressIndicator(value: state.total > 1 ? (state.done / state.total).clamp(0.0, 1.0) : null),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(key: const ValueKey('compare-cancel'), onPressed: context.read<PdfCompareCubit>().cancel, child: const Text('Stop')),
          ),
        ],
      ),
    ),
  );
}

class _Summary extends StatelessWidget {
  const _Summary({required this.result, required this.nameA, required this.nameB});
  final PdfComparison result;
  final String nameA;
  final String nameB;

  @override
  Widget build(BuildContext context) {
    final t = result.text;
    final same = result.identical;
    String plural(int n, String one, String many) => '$n ${n == 1 ? one : many}';
    return Card(
      key: const ValueKey('compare-summary'),
      margin: EdgeInsets.zero,
      color: same ? const Color(0xFFE8F5EC) : null,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(same ? AppIcons.check : AppIcons.fileDiff, color: same ? AppColors.success : AppColors.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    same ? 'The two files are the same' : 'The two files differ',
                    key: const ValueKey('compare-verdict'),
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Original: ${plural(result.pagesA, 'page', 'pages')}  ·  Revised: ${plural(result.pagesB, 'page', 'pages')}',
              style: const TextStyle(fontSize: 13),
            ),
            if (!t.tooDifferent && !result.noText)
              Text(
                t.changes.isEmpty
                    ? 'Words: no changes'
                    : 'Words: ${plural(t.changes.length, 'change', 'changes')}, ${t.removedWords} removed, ${t.addedWords} added',
                key: const ValueKey('compare-words-line'),
                style: const TextStyle(fontSize: 13),
              ),
            Text(
              'Pages that look different: ${result.pages.length} of ${result.pairs}',
              key: const ValueKey('compare-pages-line'),
              style: const TextStyle(fontSize: 13),
            ),
            if (result.ocrPages > 0)
              Text(
                '${plural(result.ocrPages, 'page was', 'pages were')} read as ${result.ocrPages == 1 ? 'a picture' : 'pictures'}, so mistakes of the text reader can show as changes.',
                style: const TextStyle(fontSize: 12, color: AppColors.inkMuted, height: 1.4),
              ),
          ],
        ),
      ),
    );
  }
}

class _ChangeTile extends StatelessWidget {
  const _ChangeTile({required this.index, required this.change});
  final int index;
  final TextChange change;

  String get _where {
    final a = change.originalPage, b = change.revisedPage;
    if (a != null && b != null) return a == b ? 'Page ${a + 1}' : 'Original page ${a + 1}, revised page ${b + 1}';
    if (a != null) return 'Original page ${a + 1}';
    return 'Revised page ${b! + 1}';
  }

  @override
  Widget build(BuildContext context) {
    const base = TextStyle(fontSize: 14, height: 1.5, color: AppColors.ink);
    return Card(
      key: ValueKey('compare-change-$index'),
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _where,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.inkMuted),
            ),
            const SizedBox(height: 4),
            Text.rich(
              TextSpan(
                style: base,
                children: [
                  if (change.cutBefore) const TextSpan(text: '... '),
                  for (final s in change.spans)
                    TextSpan(
                      text: '${s.text} ',
                      style: switch (s.kind) {
                        WordKind.same => null,
                        WordKind.removed => const TextStyle(color: _removedColor, decoration: TextDecoration.lineThrough, backgroundColor: Color(0x1AE11D48)),
                        WordKind.added => const TextStyle(color: _addedColor, fontWeight: FontWeight.w600, backgroundColor: Color(0x1A16A34A)),
                      },
                    ),
                  if (change.cutAfter) const TextSpan(text: '...'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _Side { original, revised }

class _PageCard extends StatefulWidget {
  const _PageCard({required this.page});
  final ComparedPage page;

  @override
  State<_PageCard> createState() => _PageCardState();
}

class _PageCardState extends State<_PageCard> {
  late _Side _side = widget.page.pageB != null ? _Side.revised : _Side.original;

  String get _title {
    final p = widget.page;
    if (p.pageA == null) return 'Revised page ${p.pageB! + 1} (new)';
    if (p.pageB == null) return 'Original page ${p.pageA! + 1} (removed)';
    return p.pageA == p.pageB ? 'Page ${p.pageA! + 1}' : 'Original page ${p.pageA! + 1}, revised page ${p.pageB! + 1}';
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.page;
    final bytes = _side == _Side.original ? p.imageA : p.imageB;
    final marks = _side == _Side.original ? p.removed : p.added;
    return Card(
      key: ValueKey('compare-page-${p.number}'),
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_title, style: const TextStyle(fontWeight: FontWeight.w700)),
            if (p.sizeChanged) const Text('The page size is not the same.', style: TextStyle(fontSize: 12, color: AppColors.warning)),
            const SizedBox(height: AppSpacing.sm),
            if (p.pageA != null && p.pageB != null)
              SegmentedButton<_Side>(
                key: ValueKey('compare-side-${p.number}'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: _Side.original, label: Text('Original')),
                  ButtonSegment(value: _Side.revised, label: Text('Revised')),
                ],
                selected: {_side},
                onSelectionChanged: (s) => setState(() => _side = s.first),
              ),
            const SizedBox(height: AppSpacing.sm),
            if (bytes != null)
              GestureDetector(
                key: ValueKey('compare-image-${p.number}'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _FullPage(
                      title: _title,
                      bytes: bytes,
                      aspect: p.aspect,
                      marks: marks,
                      visual: p.visual,
                      markColor: _side == _Side.original ? _removedColor : _addedColor,
                    ),
                  ),
                ),
                child: _MarkedPage(
                  bytes: bytes,
                  aspect: p.aspect,
                  marks: marks,
                  visual: p.visual,
                  markColor: _side == _Side.original ? _removedColor : _addedColor,
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: 2,
              children: [
                _Legend(color: _side == _Side.original ? _removedColor : _addedColor, text: _side == _Side.original ? 'Words taken out' : 'Words put in'),
                if (p.visual.isNotEmpty) const _Legend(color: _looksColor, text: 'Looks different'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.text});
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          border: Border.all(color: color, width: 2),
          color: color.withValues(alpha: 0.15),
        ),
      ),
      const SizedBox(width: 6),
      Text(text, style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
    ],
  );
}

/// A page picture with boxes drawn over it at the places that differ.
class _MarkedPage extends StatelessWidget {
  const _MarkedPage({required this.bytes, required this.aspect, required this.marks, required this.visual, required this.markColor});
  final Uint8List bytes;
  final double aspect;
  final List<TextRect> marks;
  final List<TextRect> visual;
  final Color markColor;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(border: Border.all(color: AppColors.border)),
    child: AspectRatio(
      aspectRatio: aspect <= 0 ? 0.7727 : aspect,
      child: LayoutBuilder(
        builder: (context, box) {
          Widget at(TextRect r, Color c) => Positioned(
            left: r.left * box.maxWidth - 2,
            top: r.top * box.maxHeight - 2,
            width: r.width * box.maxWidth + 4,
            height: r.height * box.maxHeight + 4,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: c, width: 2),
                  color: c.withValues(alpha: 0.12),
                ),
              ),
            ),
          );
          return Stack(
            fit: StackFit.expand,
            children: [
              Image.memory(bytes, fit: BoxFit.fill, gaplessPlayback: true),
              for (final r in visual) at(r, _looksColor),
              for (final r in marks) at(r, markColor),
            ],
          );
        },
      ),
    ),
  );
}

class _FullPage extends StatelessWidget {
  const _FullPage({required this.title, required this.bytes, required this.aspect, required this.marks, required this.visual, required this.markColor});
  final String title;
  final Uint8List bytes;
  final double aspect;
  final List<TextRect> marks;
  final List<TextRect> visual;
  final Color markColor;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: InteractiveViewer(
      maxScale: 6,
      child: Center(
        child: _MarkedPage(bytes: bytes, aspect: aspect, marks: marks, visual: visual, markColor: markColor),
      ),
    ),
  );
}

class _Actions extends StatelessWidget {
  const _Actions({required this.onText, required this.onPdf});
  final VoidCallback onText;
  final VoidCallback? onPdf;

  @override
  Widget build(BuildContext context) => Material(
    elevation: 6,
    color: Theme.of(context).colorScheme.surface,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.3),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            FilledButton.icon(
              key: const ValueKey('compare-share-pdf'),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: onPdf,
              icon: const Icon(AppIcons.pdf, size: 18),
              label: const Text('Share marked pages'),
            ),
            OutlinedButton.icon(
              key: const ValueKey('compare-share-text'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: onText,
              icon: const Icon(AppIcons.share, size: 18),
              label: const Text('Share the list'),
            ),
          ],
        ),
      ),
    ),
  );
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
          Icon(AppIcons.shield, size: 20, color: AppColors.success),
          SizedBox(width: AppSpacing.sm + 4),
          Expanded(
            child: Text(
              'Both files are compared on this phone and never uploaded. Up to 60 pages of each are compared. Always read important changes in the file itself.',
              style: TextStyle(fontSize: 13, height: 1.4, color: AppColors.inkMuted),
            ),
          ),
        ],
      ),
    ),
  );
}

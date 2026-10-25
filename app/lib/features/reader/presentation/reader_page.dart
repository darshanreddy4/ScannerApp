import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';

import '../../../app/di.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/feedback.dart';
import '../../export/domain/repositories/export_repository.dart';
import '../../../core/error/failures.dart';
import '../../importer/domain/importer.dart';
import '../../pdf_tools/data/security/pdf_security.dart';
import '../../qr/presentation/qr_share_page.dart';
import '../../scanner/presentation/add_content.dart';
import '../../scanner/presentation/bloc/scan_session_cubit.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../data/docx_reading.dart';
import '../data/pdf_text_extractor.dart';
import '../domain/document_search.dart';

class ReaderArgs {
  const ReaderArgs({required this.path, required this.kind});
  final String path;
  final ImportKind kind;
}

/// Reads a PDF or Word file without importing it. From here it can be edited, saved, shared or sent by QR.
class ReaderPage extends StatefulWidget {
  const ReaderPage({super.key, required this.args, this.workDir = _defaultWorkDir});
  final ReaderArgs args;

  /// Where pages of a Word file are drawn.
  final Future<Directory> Function() workDir;

  static Future<Directory> _defaultWorkDir() async => Directory(p.join((await getTemporaryDirectory()).path, 'scan_work'));

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

enum _ReaderAction { editText, edit, save, share, qr }

class _ReaderPageState extends State<ReaderPage> {
  PdfControllerPinch? _pdf;
  DocxReading? _docx;
  String? _error;
  final _docxPager = PageController();
  int _docxIndex = 0;

  // Search
  final _searchField = TextEditingController();
  final _searchFocus = FocusNode();
  var _searching = false;
  var _indexing = false;
  List<PageTextIndex>? _pdfIndex;
  String? _searchNotice;
  var _hits = const <SearchHit>[];
  var _current = -1;
  Map<int, List<int>> _hitsByPage = const {};

  String get _name => p.basename(widget.args.path);
  String get _mime => widget.args.kind == ImportKind.pdf ? 'application/pdf' : 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';

  @override
  void initState() {
    super.initState();
    if (widget.args.kind == ImportKind.pdf) {
      _pdf = PdfControllerPinch(document: PdfDocument.openFile(widget.args.path));
    } else {
      _loadDocx();
    }
  }

  Future<void> _loadDocx() async {
    try {
      if (!await File(widget.args.path).exists()) throw const ImportFailure('The selected file could not be found.');
      final reading = await loadDocxReading(path: widget.args.path, workDir: await widget.workDir());
      if (reading.pages.isEmpty) {
        reading.dispose();
        throw const ImportFailure('This Word document is empty.');
      }
      if (!mounted) {
        reading.dispose();
        return;
      }
      setState(() => _docx = reading);
    } on Failure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'The file could not be opened. It may be damaged or unsupported.');
    }
  }

  @override
  void dispose() {
    _pdf?.dispose();
    _docx?.dispose();
    _docxPager.dispose();
    _searchField.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // region search

  bool get _isPdf => widget.args.kind == ImportKind.pdf;

  Future<void> _openSearch() async {
    setState(() => _searching = true);
    _searchFocus.requestFocus();
    if (_isPdf && _pdfIndex == null && !_indexing) await _indexPdf();
  }

  void _closeSearch() {
    _searchField.clear();
    _searchFocus.unfocus();
    setState(() {
      _searching = false;
      _hits = const [];
      _current = -1;
      _hitsByPage = const {};
      _searchNotice = null;
    });
  }

  /// Reads the text of the PDF once, in the background, the first time search is opened.
  Future<void> _indexPdf() async {
    setState(() {
      _indexing = true;
      _searchNotice = null;
    });
    String? notice;
    List<PageTextIndex>? index;
    try {
      final bytes = await File(widget.args.path).readAsBytes();
      final found = await Isolate.run(() => extractPdfText(bytes));
      index = found;
      if (!found.any((page) => page.hasText)) {
        notice = 'This PDF has no text to search. It looks like scanned pages: save it to your library and use Extract text (OCR) on it.';
      }
    } on WrongPasswordException {
      notice = 'This PDF is password protected, so it cannot be searched.';
    } catch (_) {
      notice = 'Search is not available for this PDF.';
    }
    if (!mounted) return;
    setState(() {
      _indexing = false;
      _pdfIndex = index;
      _searchNotice = notice;
    });
    if (_searchField.text.isNotEmpty) _runSearch();
  }

  void _runSearch() {
    final q = _searchField.text;
    List<SearchHit> hits = const [];
    if (_isPdf) {
      final index = _pdfIndex;
      if (index != null) hits = searchPages(index, q);
    } else {
      hits = _docx?.search(q) ?? const [];
    }
    final byPage = <int, List<int>>{};
    for (var i = 0; i < hits.length; i++) {
      (byPage[hits[i].page] ??= []).add(i);
    }
    // Start from the first match on the page being read, or after it.
    final here = _isPdf ? (_pdf?.page ?? 1) - 1 : _docxIndex;
    var start = hits.indexWhere((h) => h.page >= here);
    if (start < 0 && hits.isNotEmpty) start = 0;
    setState(() {
      _hits = hits;
      _hitsByPage = byPage;
      _current = hits.isEmpty ? -1 : start;
    });
    if (_current >= 0) _reveal();
  }

  void _step(int delta) {
    if (_hits.isEmpty) return;
    setState(() => _current = ((_current + delta) % _hits.length + _hits.length) % _hits.length);
    _reveal();
  }

  /// Scrolls to the match that is current.
  void _reveal() {
    if (_current < 0 || _current >= _hits.length) return;
    final hit = _hits[_current];
    if (!_isPdf) {
      if (_docxPager.hasClients) _docxPager.animateToPage(hit.page, duration: const Duration(milliseconds: 250), curve: Curves.easeInOut);
      return;
    }
    final c = _pdf;
    if (c == null) return;
    try {
      final pageRect = c.getPageRect(hit.page + 1);
      if (pageRect == null || hit.rects.isEmpty) return;
      final r = hit.rects.first;
      final center = Offset(pageRect.left + (r.left + r.right) / 2 * pageRect.width, pageRect.top + (r.top + r.bottom) / 2 * pageRect.height);
      final view = c.viewRect.size;
      final zoom = math.max(c.zoomRatio, 1.0);
      final last = c.getPageRect(c.pagesCount ?? hit.page + 1) ?? pageRect;
      final margin = pageRect.left;
      final minTx = math.min(0.0, view.width - (pageRect.right + margin) * zoom);
      final minTy = math.min(0.0, view.height - (last.bottom + margin) * zoom);
      final tx = (view.width / 2 - center.dx * zoom).clamp(minTx, 0.0);
      final ty = (view.height / 2 - center.dy * zoom).clamp(minTy, 0.0);
      c.goTo(
        destination: Matrix4.identity()
          ..translateByDouble(tx, ty, 0, 1)
          ..scaleByDouble(zoom, zoom, 1, 1),
      );
    } catch (_) {
      // The viewer is not ready yet; the highlight is still drawn when it is.
    }
  }

  // endregion

  Future<void> _run(_ReaderAction action) async {
    final session = context.read<ScanSessionCubit>();
    final settings = context.read<SettingsCubit>().state;
    switch (action) {
      case _ReaderAction.share:
        final r = await sl<ShareService>().shareFile(path: widget.args.path, mimeType: _mime, subject: _name);
        if (mounted && r.failureOrNull != null) showFailure(context, r.failureOrNull!);
      case _ReaderAction.qr:
        context.push(
          '/qr-share',
          extra: QrShareArgs(filePath: widget.args.path, fileName: _name, mimeType: _mime),
        );
      case _ReaderAction.editText:
        context.push(_isPdf ? '/pdf-edit' : '/docx-edit', extra: widget.args.path);
      case _ReaderAction.edit:
        session.start(defaultFilter: settings.defaultFilter);
        final ok = await runWithProgress(context, session, () => session.importDocumentFile(widget.args.kind, widget.args.path));
        if (!mounted) return;
        if (ok) {
          context.push('/scan/edit');
        } else if (session.state.error != null) {
          showFailure(context, session.state.error!);
        }
      case _ReaderAction.save:
        session.start(defaultFilter: settings.defaultFilter);
        final doc = await runWithProgress(context, session, () async {
          if (!await session.importDocumentFile(widget.args.kind, widget.args.path)) return null;
          return session.save();
        });
        if (!mounted) return;
        if (doc != null) {
          context.go('/document/${doc.id}');
        } else if (session.state.error != null) {
          showFailure(context, session.state.error!);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSearch = _isPdf ? _pdf != null : (_docx != null && _docx!.hasText);
    return Scaffold(
      backgroundColor: const Color(0xFFE9EDF3),
      appBar: AppBar(
        title: Text(_name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16)),
        actions: [
          if (canSearch)
            IconButton(
              key: const ValueKey('reader-search-button'),
              tooltip: 'Search in this file',
              icon: const Icon(AppIcons.search),
              onPressed: _searching ? _closeSearch : _openSearch,
            ),
          PopupMenuButton<_ReaderAction>(
            icon: const Icon(AppIcons.more),
            onSelected: _run,
            itemBuilder: (_) => [
              const PopupMenuItem(value: _ReaderAction.editText, child: _Row(AppIcons.editDocument, 'Edit text')),
              const PopupMenuItem(value: _ReaderAction.edit, child: _Row(AppIcons.edit, 'Edit pages')),
              const PopupMenuItem(value: _ReaderAction.save, child: _Row(AppIcons.storage, 'Save to library')),
              const PopupMenuItem(value: _ReaderAction.share, child: _Row(AppIcons.share, 'Share file')),
              const PopupMenuItem(value: _ReaderAction.qr, child: _Row(AppIcons.qr, 'Share with QR code')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (_searching)
            _SearchBar(
              controller: _searchField,
              focusNode: _searchFocus,
              busy: _indexing,
              hasQuery: _searchField.text.trim().isNotEmpty,
              current: _current,
              total: _hits.length,
              notice: _searchNotice,
              onChanged: (_) => _runSearch(),
              onNext: () => _step(1),
              onPrevious: () => _step(-1),
              onClose: _closeSearch,
            ),
          Expanded(child: _isPdf ? _buildPdf() : _buildDocx()),
        ],
      ),
    );
  }

  Widget _buildPdf() {
    final controller = _pdf!;
    // The viewer keeps its pages at a fixed offset, so no side or top safe-area gap may move them away from the highlights.
    return MediaQuery.removePadding(
      context: context,
      removeLeft: true,
      removeRight: true,
      removeTop: true,
      child: Stack(
        children: [
          PdfViewPinch(
            controller: controller,
            backgroundDecoration: const BoxDecoration(color: Color(0xFFE9EDF3)),
            builders: PdfViewPinchBuilders<DefaultBuilderOptions>(
              options: const DefaultBuilderOptions(),
              documentLoaderBuilder: (_) => const Center(child: CircularProgressIndicator()),
              pageLoaderBuilder: (_) => const Center(child: CircularProgressIndicator()),
              errorBuilder: (_, error) => _ErrorView(message: _friendly(error)),
            ),
          ),
          if (_hits.isNotEmpty)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  key: const ValueKey('pdf-highlights'),
                  painter: _PdfHighlightPainter(controller: controller, hits: _hits, byPage: _hitsByPage, current: _current),
                ),
              ),
            ),
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Center(
              child: ValueListenableBuilder<int>(
                valueListenable: controller.pageListenable,
                builder: (_, page, _) => _PagePill(text: '$page / ${controller.pagesCount ?? '-'}'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _friendly(Object error) {
    final m = error.toString().toLowerCase();
    return m.contains('password')
        ? 'This PDF is password protected. Remove the password first with Tools > Lock or unlock PDF.'
        : 'This PDF could not be opened. It may be damaged.';
  }

  Widget _buildDocx() {
    if (_error != null) return _ErrorView(message: _error!);
    final reading = _docx;
    if (reading == null) {
      return const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 12), Text('Preparing document')]),
      );
    }
    final pages = reading.pages;
    return Stack(
      children: [
        PageView.builder(
          controller: _docxPager,
          itemCount: pages.length,
          onPageChanged: (i) => setState(() => _docxIndex = i),
          itemBuilder: (_, i) {
            final page = pages[i];
            final onPage = _hitsByPage[i] ?? const <int>[];
            Widget picture = Image.file(File(page.imagePath), fit: page.isText ? BoxFit.fill : BoxFit.contain, cacheWidth: 1600);
            if (page.isText) {
              picture = Center(
                child: AspectRatio(
                  aspectRatio: DocxReadPage.textAspect,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      picture,
                      if (onPage.isNotEmpty)
                        CustomPaint(
                          key: ValueKey('docx-highlights-$i'),
                          painter: _RectsPainter(rects: [for (final h in onPage) ..._hits[h].rects.map((r) => (r, h == _current))]),
                        ),
                    ],
                  ),
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 6)],
                ),
                child: InteractiveViewer(maxScale: 5, child: picture),
              ),
            );
          },
        ),
        Positioned(
          bottom: 16,
          left: 0,
          right: 0,
          child: Center(child: _PagePill(text: '${_docxIndex + 1} / ${pages.length}')),
        ),
      ],
    );
  }
}

const _hitColor = Color(0x66FFC107);
const _currentColor = Color(0x99FF6D00);

/// Highlights drawn over a page picture; boxes are shares of the picture.
class _RectsPainter extends CustomPainter {
  _RectsPainter({required this.rects});
  final List<(TextRect, bool)> rects;

  @override
  void paint(Canvas canvas, Size size) {
    for (final (r, current) in rects) {
      final box = Rect.fromLTRB(r.left * size.width, r.top * size.height, r.right * size.width, r.bottom * size.height).inflate(1.5);
      canvas.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(2)), Paint()..color = current ? _currentColor : _hitColor);
    }
  }

  @override
  bool shouldRepaint(_RectsPainter old) => true;
}

/// Highlights drawn over the PDF pages; follows the zoom and scroll of the viewer.
class _PdfHighlightPainter extends CustomPainter {
  _PdfHighlightPainter({required this.controller, required this.hits, required this.byPage, required this.current}) : super(repaint: controller);

  final PdfControllerPinch controller;
  final List<SearchHit> hits;
  final Map<int, List<int>> byPage;
  final int current;

  @override
  void paint(Canvas canvas, Size size) {
    final viewport = Offset.zero & size;
    final m = controller.value;
    for (final entry in byPage.entries) {
      final Rect? pageRect;
      try {
        pageRect = controller.getPageRect(entry.key + 1);
      } catch (_) {
        return;
      }
      if (pageRect == null || !MatrixUtils.transformRect(m, pageRect).overlaps(viewport)) continue;
      for (final h in entry.value) {
        for (final r in hits[h].rects) {
          final doc = Rect.fromLTRB(
            pageRect.left + r.left * pageRect.width,
            pageRect.top + r.top * pageRect.height,
            pageRect.left + r.right * pageRect.width,
            pageRect.top + r.bottom * pageRect.height,
          );
          final box = MatrixUtils.transformRect(m, doc).inflate(1.5);
          canvas.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(2)), Paint()..color = h == current ? _currentColor : _hitColor);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_PdfHighlightPainter old) => old.hits != hits || old.current != current || old.byPage != byPage;
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.focusNode,
    required this.busy,
    required this.hasQuery,
    required this.current,
    required this.total,
    required this.notice,
    required this.onChanged,
    required this.onNext,
    required this.onPrevious,
    required this.onClose,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool busy;
  final bool hasQuery;
  final int current;
  final int total;
  final String? notice;
  final ValueChanged<String> onChanged;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final Widget status;
    if (busy) {
      status = const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2));
    } else if (!hasQuery || notice != null) {
      status = const SizedBox.shrink();
    } else {
      status = Text(
        total == 0 ? 'None' : '${current + 1} of $total',
        key: const ValueKey('search-count'),
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.inkMuted),
      );
    }
    return Material(
      color: Colors.white,
      elevation: 1,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, 6, AppSpacing.xs, 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('reader-search-field'),
                    controller: controller,
                    focusNode: focusNode,
                    textInputAction: TextInputAction.search,
                    onChanged: onChanged,
                    onSubmitted: (_) {
                      onNext();
                      focusNode.requestFocus();
                    },
                    decoration: InputDecoration(
                      hintText: 'Search in this file',
                      isDense: true,
                      prefixIcon: const Icon(AppIcons.search, size: 18),
                      suffixIcon: controller.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear',
                              icon: const Icon(AppIcons.close, size: 16),
                              onPressed: () {
                                controller.clear();
                                onChanged('');
                              },
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 40),
                  child: Center(child: status),
                ),
                IconButton(
                  key: const ValueKey('search-prev'),
                  tooltip: 'Previous match',
                  visualDensity: VisualDensity.compact,
                  onPressed: total == 0 ? null : onPrevious,
                  icon: const Icon(AppIcons.expandLess),
                ),
                IconButton(
                  key: const ValueKey('search-next'),
                  tooltip: 'Next match',
                  visualDensity: VisualDensity.compact,
                  onPressed: total == 0 ? null : onNext,
                  icon: const Icon(AppIcons.expandMore),
                ),
                IconButton(
                  key: const ValueKey('search-close'),
                  tooltip: 'Close search',
                  visualDensity: VisualDensity.compact,
                  onPressed: onClose,
                  icon: const Icon(AppIcons.close),
                ),
              ],
            ),
          ),
          if (notice != null)
            Container(
              width: double.infinity,
              color: const Color(0xFFFFF4E5),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              child: Text(
                notice!,
                key: const ValueKey('search-notice'),
                style: const TextStyle(fontSize: 13, height: 1.35, color: AppColors.warning),
              ),
            ),
        ],
      ),
    );
  }
}

class _PagePill extends StatelessWidget {
  const _PagePill({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
    decoration: BoxDecoration(color: AppColors.ink.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(16)),
    child: Text(
      text,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(children: [Icon(icon, size: 18), const SizedBox(width: 12), Text(label)]);
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(AppIcons.warning, size: 48, color: AppColors.inkMuted),
          const SizedBox(height: AppSpacing.md),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.inkMuted),
          ),
        ],
      ),
    ),
  );
}

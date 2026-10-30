import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

import '../../../core/error/failures.dart';
import '../../ocr/domain/ocr_engine.dart';
import '../../ocr/domain/ocr_models.dart';
import '../../pdf_tools/data/pdf_picture_pages.dart';
import '../../pdf_tools/data/security/pdf_security.dart' show WrongPasswordException;
import '../data/compare_pdf_reader.dart';
import '../data/comparison_report.dart';
import '../domain/page_diff.dart';
import '../domain/pdf_comparison.dart';
import '../domain/text_compare.dart';

enum CompareStatus { idle, comparing, done }

class PdfCompareState extends Equatable {
  const PdfCompareState({
    this.status = CompareStatus.idle,
    this.pathA,
    this.pathB,
    this.useOcr = true,
    this.done = 0,
    this.total = 0,
    this.label = '',
    this.notes = const [],
    this.failure,
    this.result,
  });

  final CompareStatus status;
  final String? pathA;
  final String? pathB;

  /// Pages that are pictures are read with the text reader so their words can be compared.
  final bool useOcr;
  final int done;
  final int total;
  final String label;
  final List<String> notes;
  final Failure? failure;
  final PdfComparison? result;

  bool get comparing => status == CompareStatus.comparing;
  bool get ready => pathA != null && pathB != null;
  String get nameA => pathA == null ? '' : p.basename(pathA!);
  String get nameB => pathB == null ? '' : p.basename(pathB!);

  PdfCompareState copyWith({
    CompareStatus? status,
    Object? pathA = _keep,
    Object? pathB = _keep,
    bool? useOcr,
    int? done,
    int? total,
    String? label,
    List<String>? notes,
    Object? failure = _keep,
    Object? result = _keep,
  }) => PdfCompareState(
    status: status ?? this.status,
    pathA: identical(pathA, _keep) ? this.pathA : pathA as String?,
    pathB: identical(pathB, _keep) ? this.pathB : pathB as String?,
    useOcr: useOcr ?? this.useOcr,
    done: done ?? this.done,
    total: total ?? this.total,
    label: label ?? this.label,
    notes: notes ?? this.notes,
    failure: identical(failure, _keep) ? this.failure : failure as Failure?,
    result: identical(result, _keep) ? this.result : result as PdfComparison?,
  );

  static const _keep = Object();

  @override
  List<Object?> get props => [status, pathA, pathB, useOcr, done, total, label, notes, failure, result];
}

Future<List<PageWords>> _readWordsInBackground(Uint8List bytes, int maxPages) => Isolate.run(() => readPdfWords(bytes, maxPages: maxPages));

/// Compares two PDFs on the phone: the words (read from the pages, or from pictures of them when the pages are scans), and how every
/// page looks. Nothing leaves the phone.
class PdfCompareCubit extends Cubit<PdfCompareState> {
  PdfCompareCubit({
    required OcrEngine engine,
    required Future<Directory> Function() outputDir,
    OcrScript script = OcrScript.latin,
    PdfPicturePages Function()? pdfPages,
    Future<List<PageWords>> Function(Uint8List bytes, int maxPages)? readWords,
    this.maxPages = 60,
    DateTime Function() now = DateTime.now,
  }) : _engine = engine,
       _outputDir = outputDir,
       _script = script,
       _pdfPages = pdfPages ?? PdfxPicturePages.new,
       _readWords = readWords ?? _readWordsInBackground,
       _now = now,
       super(const PdfCompareState());

  final OcrEngine _engine;
  final Future<Directory> Function() _outputDir;
  final OcrScript _script;
  final PdfPicturePages Function() _pdfPages;
  final Future<List<PageWords>> Function(Uint8List bytes, int maxPages) _readWords;
  final DateTime Function() _now;

  /// Longer files are compared up to this many pages.
  final int maxPages;
  var _cancelled = false;

  void setOriginal(String path) => emit(state.copyWith(pathA: path, result: null, failure: null, notes: const []));
  void setRevised(String path) => emit(state.copyWith(pathB: path, result: null, failure: null, notes: const []));

  void swap() {
    if (state.comparing) return;
    emit(state.copyWith(pathA: state.pathB, pathB: state.pathA, result: null, failure: null, notes: const []));
  }

  void setUseOcr(bool value) => emit(state.copyWith(useOcr: value));

  void cancel() => _cancelled = true;

  void _progress(String label, int done, int total) {
    if (!isClosed) emit(state.copyWith(label: label, done: done, total: total));
  }

  Future<void> compare() async {
    final pathA = state.pathA, pathB = state.pathB;
    if (state.comparing || pathA == null || pathB == null) return;
    _cancelled = false;
    emit(state.copyWith(status: CompareStatus.comparing, done: 0, total: 0, label: 'Reading the text', notes: const [], failure: null, result: null));
    final notes = <String>[];
    final renderA = _pdfPages(), renderB = _pdfPages();
    Directory? work;
    try {
      final bytesA = await File(pathA).readAsBytes(), bytesB = await File(pathB).readAsBytes();
      List<PageWords> wordsA, wordsB;
      try {
        _progress('Reading the text of ${state.nameA}', 0, 2);
        wordsA = await _readWords(bytesA, maxPages);
        _progress('Reading the text of ${state.nameB}', 1, 2);
        wordsB = await _readWords(bytesB, maxPages);
      } on WrongPasswordException {
        return _fail(const PasswordFailure('One of the files is protected by a password. Unlock it first with Lock or unlock PDF.'));
      } catch (_) {
        // Odd files: compare how the pages look, and read the pages as pictures when that is allowed.
        wordsA = const [];
        wordsB = const [];
        notes.add('The text of one of the files could not be read directly, so the pages were read as pictures.');
      }
      if (isClosed) return;

      final countA = await renderA.open(pathA), countB = await renderB.open(pathB);
      final nA = countA > maxPages ? maxPages : countA, nB = countB > maxPages ? maxPages : countB;
      if (countA > maxPages) notes.add('"${state.nameA}" has $countA pages; the first $maxPages were compared.');
      if (countB > maxPages) notes.add('"${state.nameB}" has $countB pages; the first $maxPages were compared.');
      List<PageWords> pad(List<PageWords> w, int n) => [for (var i = 0; i < n; i++) i < w.length ? w[i] : const PageWords(words: [])];
      wordsA = pad(wordsA, nA);
      wordsB = pad(wordsB, nB);

      // Pages that are pictures have no words: read them with the text reader.
      var ocrPages = 0;
      if (state.useOcr) {
        work = await Directory(p.join((await _outputDir()).path, 'pdf_compare', '${_now().microsecondsSinceEpoch}')).create(recursive: true);
        final missing = [
          for (var i = 0; i < nA; i++)
            if (wordsA[i].isEmpty) (true, i),
          for (var i = 0; i < nB; i++)
            if (wordsB[i].isEmpty) (false, i),
        ];
        for (var k = 0; k < missing.length; k++) {
          if (_cancelled || isClosed) break;
          final (inA, page) = missing[k];
          _progress('Reading page ${page + 1} of ${inA ? state.nameA : state.nameB}', k, missing.length);
          try {
            final file = File(p.join(work.path, '${inA ? 'a' : 'b'}$page.jpg'));
            await file.writeAsBytes(await (inA ? renderA : renderB).render(page, width: 1654, png: false), flush: true);
            final result = await _engine.recognize(file.path, _script);
            final read = result.valueOrNull;
            if (read == null) {
              notes.add('Page ${page + 1} of ${inA ? state.nameA : state.nameB} could not be read: ${result.failureOrNull?.message ?? 'no text'}');
            } else if (read.blocks.isNotEmpty) {
              final words = wordsFromOcr(read);
              if (inA) {
                wordsA[page] = words;
              } else {
                wordsB[page] = words;
              }
              ocrPages++;
            }
            await file.delete().then((_) {}, onError: (_) {});
          } catch (_) {
            notes.add('Page ${page + 1} of ${inA ? state.nameA : state.nameB} could not be drawn.');
          }
        }
      }
      if (_cancelled || isClosed) return _stopped();

      final text = compareText(wordsA, wordsB);
      final noText = wordsA.every((w) => w.isEmpty) && wordsB.every((w) => w.isEmpty);
      if (noText && nA + nB > 0) {
        notes.add(
          state.useOcr
              ? 'No text was found in either file, so only how the pages look was compared.'
              : 'The pages are pictures. Turn on reading pages as pictures to compare their words.',
        );
      }
      if (text.tooDifferent) notes.add('The two files have very little text in common, so the changes are not listed one by one.');

      // How the pages look, for the pairs of pages that the words line up.
      final pairs = text.pagePairs;
      final pages = <ComparedPage>[];
      for (var k = 0; k < pairs.length; k++) {
        if (_cancelled || isClosed) break;
        final (pa, pb) = pairs[k];
        _progress('Comparing pages', k, pairs.length);
        pages.addAll(await _comparePair(k + 1, pa, pb, text, renderA, renderB, wordsA, wordsB));
      }
      if (_cancelled || isClosed) return _stopped();
      emit(
        state.copyWith(
          status: CompareStatus.done,
          done: pairs.length,
          total: pairs.length,
          label: '',
          notes: notes,
          result: PdfComparison(text: text, pages: pages, pagesA: nA, pagesB: nB, pairs: pairs.length, ocrPages: ocrPages, noText: noText),
        ),
      );
    } on Object catch (e) {
      if (!isClosed) {
        _fail(ImportFailure('The files could not be compared. They may be damaged or not PDFs.', cause: e));
      }
    } finally {
      await renderA.close().then((_) {}, onError: (_) {});
      await renderB.close().then((_) {}, onError: (_) {});
      await work?.delete(recursive: true).then((_) {}, onError: (_) {});
    }
  }

  void _fail(Failure failure) {
    if (!isClosed) emit(state.copyWith(status: CompareStatus.idle, failure: failure, label: ''));
  }

  void _stopped() {
    if (!isClosed) emit(state.copyWith(status: CompareStatus.idle, label: '', notes: const ['Stopped before the comparison was finished.']));
  }

  Future<List<ComparedPage>> _comparePair(
    int number,
    int? pa,
    int? pb,
    TextComparison text,
    PdfPicturePages renderA,
    PdfPicturePages renderB,
    List<PageWords> wordsA,
    List<PageWords> wordsB,
  ) async {
    final removed = [
      if (pa != null)
        for (final c in text.changes)
          for (final b in c.originalBoxes)
            if (b.page == pa) b.rect,
    ];
    final added = [
      if (pb != null)
        for (final c in text.changes)
          for (final b in c.revisedBoxes)
            if (b.page == pb) b.rect,
    ];
    final aspect = pb != null ? wordsB[pb].aspect : wordsA[pa!].aspect;
    if (pa == null || pb == null) {
      final image = await (pa == null ? renderB : renderA).render((pa ?? pb)!, width: _shownWidth, png: false);
      return [
        ComparedPage(
          number: number,
          pageA: pa,
          pageB: pb,
          imageA: pa == null ? null : image,
          imageB: pb == null ? null : image,
          aspect: aspect,
          removed: removed,
          added: added,
          similarity: 0,
        ),
      ];
    }
    final imageA = await renderA.render(pa, width: _shownWidth, png: false);
    final imageB = await renderB.render(pb, width: _shownWidth, png: false);
    // Let the screen draw between pages.
    await Future<void>.delayed(Duration.zero);
    final look = diffPageImages(imageA, imageB);
    final visual = [
      for (final r in look.regions)
        if (!_mostlyUnder(r, removed) && !_mostlyUnder(r, added)) r,
    ];
    final page = ComparedPage(
      number: number,
      pageA: pa,
      pageB: pb,
      imageA: imageA,
      imageB: imageB,
      aspect: aspect,
      removed: removed,
      added: added,
      visual: visual,
      similarity: look.similarity,
      sizeChanged: look.sizeChanged,
    );
    return page.changed ? [page] : const [];
  }

  static const _shownWidth = 800;

  /// The box lies mostly inside marks that already show the change, so it is not shown a second time.
  static bool _mostlyUnder(TextRect r, List<TextRect> marks) {
    final area = r.width * r.height;
    if (area <= 0) return true;
    var covered = 0.0;
    // The boxes of words fit the letters tightly, the boxes found in the pictures have a margin.
    const pad = 0.012;
    for (final m in marks) {
      final w = (r.right < m.right + pad ? r.right : m.right + pad) - (r.left > m.left - pad ? r.left : m.left - pad);
      final h = (r.bottom < m.bottom + pad ? r.bottom : m.bottom + pad) - (r.top > m.top - pad ? r.top : m.top - pad);
      if (w > 0 && h > 0) covered += w * h;
    }
    return covered / area > 0.5;
  }

  void reset() {
    if (state.comparing) return;
    emit(state.copyWith(status: CompareStatus.idle, result: null, failure: null, notes: const []));
  }

  Future<String?> _write(String name, String extension, Future<List<int>?> Function() bytes) async {
    final result = state.result;
    if (result == null) return null;
    try {
      final data = await bytes();
      if (data == null) return null;
      final dir = await Directory(p.join((await _outputDir()).path, 'pdf_compare')).create(recursive: true);
      final file = File(p.join(dir.path, '${name}_${_now().millisecondsSinceEpoch}.$extension'));
      await file.writeAsBytes(data, flush: true);
      return file.path;
    } catch (e) {
      if (!isClosed) emit(state.copyWith(failure: ExportFailure('The file could not be made.', cause: e)));
      return null;
    }
  }

  /// A PDF with each page that differs, the two versions side by side and the differences marked; null when nothing differs.
  Future<String?> writeReportPdf() => _write('Changes', 'pdf', () async {
    final r = state.result!;
    if (r.pages.isEmpty) return null;
    return buildComparisonPdf(r);
  });

  /// The changes as text, with [-removed-] and {+added+} words.
  Future<String?> writeChangesText() =>
      _write('Changes', 'txt', () async => utf8.encode(comparisonText(state.result!, nameA: state.nameA, nameB: state.nameB)));
}

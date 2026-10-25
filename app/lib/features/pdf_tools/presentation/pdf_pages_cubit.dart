import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

import '../../../core/error/failures.dart';
import '../domain/pdf_pages.dart';

enum PageAction {
  keep('Keep selected'),
  remove('Remove selected'),
  split('Split');

  const PageAction(this.label);
  final String label;
}

enum SplitMode {
  each('Every page'),
  every('Every N pages'),
  ranges('By ranges');

  const SplitMode(this.label);
  final String label;
}

enum PagesStatus { idle, opening, running, done }

class PdfPagesState extends Equatable {
  const PdfPagesState({
    this.pdf,
    this.selected = const {},
    this.rotations = const {},
    this.action = PageAction.keep,
    this.splitMode = SplitMode.every,
    this.splitEvery = 2,
    this.splitRanges = '',
    this.marks = const PageMarks(),
    this.status = PagesStatus.idle,
    this.done = 0,
    this.total = 0,
    this.parts = const [],
    this.failure,
    this.rangeError,
  });

  final OpenedPdf? pdf;
  final Set<int> selected;

  /// Quarter turns clockwise, by page index.
  final Map<int, int> rotations;
  final PageAction action;
  final SplitMode splitMode;
  final int splitEvery;
  final String splitRanges;
  final PageMarks marks;
  final PagesStatus status;
  final int done;
  final int total;
  final List<PdfPart> parts;
  final Failure? failure;

  /// Shown under the "select pages" field.
  final String? rangeError;

  int get pageCount => pdf?.pages.length ?? 0;
  bool get busy => status == PagesStatus.opening || status == PagesStatus.running;

  PdfPagesState copyWith({
    Object? pdf = _keep,
    Set<int>? selected,
    Map<int, int>? rotations,
    PageAction? action,
    SplitMode? splitMode,
    int? splitEvery,
    String? splitRanges,
    PageMarks? marks,
    PagesStatus? status,
    int? done,
    int? total,
    List<PdfPart>? parts,
    Object? failure = _keep,
    Object? rangeError = _keep,
  }) => PdfPagesState(
    pdf: identical(pdf, _keep) ? this.pdf : pdf as OpenedPdf?,
    selected: selected ?? this.selected,
    rotations: rotations ?? this.rotations,
    action: action ?? this.action,
    splitMode: splitMode ?? this.splitMode,
    splitEvery: splitEvery ?? this.splitEvery,
    splitRanges: splitRanges ?? this.splitRanges,
    marks: marks ?? this.marks,
    status: status ?? this.status,
    done: done ?? this.done,
    total: total ?? this.total,
    parts: parts ?? this.parts,
    failure: identical(failure, _keep) ? this.failure : failure as Failure?,
    rangeError: identical(rangeError, _keep) ? this.rangeError : rangeError as String?,
  );

  static const _keep = Object();

  @override
  List<Object?> get props => [
    pdf?.name,
    pageCount,
    selected,
    rotations,
    action,
    splitMode,
    splitEvery,
    splitRanges,
    marks,
    status,
    done,
    total,
    parts.map((e) => e.path).toList(),
    failure,
    rangeError,
  ];
}

class PdfPagesCubit extends Cubit<PdfPagesState> {
  PdfPagesCubit({required PdfPageService service, required Future<Directory> Function() outputDir, DateTime Function()? now})
    : _service = service,
      _outputDir = outputDir,
      _now = now ?? DateTime.now,
      super(const PdfPagesState());

  final PdfPageService _service;
  final Future<Directory> Function() _outputDir;
  final DateTime Function() _now;

  static const maxSplitFiles = 100;

  Future<void> open(String path) async {
    if (state.busy) return;
    emit(const PdfPagesState(status: PagesStatus.opening));
    final result = await _service.open(path);
    if (isClosed) return;
    final pdf = result.valueOrNull;
    emit(pdf == null ? PdfPagesState(failure: result.failureOrNull) : PdfPagesState(pdf: pdf));
  }

  void clear() {
    if (!state.busy) emit(const PdfPagesState());
  }

  void _edit(PdfPagesState Function(PdfPagesState s) change) {
    if (state.busy || state.pdf == null) return;
    emit(change(state).copyWith(status: PagesStatus.idle, parts: const [], failure: null));
  }

  void toggle(int index) => _edit((s) {
    final next = {...s.selected};
    next.contains(index) ? next.remove(index) : next.add(index);
    return s.copyWith(selected: next, rangeError: null);
  });

  void selectAll() => _edit((s) => s.copyWith(selected: {for (var i = 0; i < s.pageCount; i++) i}, rangeError: null));
  void selectNone() => _edit((s) => s.copyWith(selected: const {}, rangeError: null));

  /// Pages 1, 3, 5 ... when [odd] is true, otherwise 2, 4, 6 ...
  void selectParity({required bool odd}) => _edit((s) => s.copyWith(selected: {for (var i = odd ? 0 : 1; i < s.pageCount; i += 2) i}, rangeError: null));

  void selectRanges(String text) => _edit((s) {
    final parsed = PageRanges.parse(text, s.pageCount);
    return parsed.ok ? s.copyWith(selected: parsed.pages.toSet(), rangeError: null) : s.copyWith(rangeError: parsed.error);
  });

  /// Turns the selected pages. [quarterTurns] is 1 for clockwise, -1 (or 3) for counter-clockwise.
  void rotateSelected(int quarterTurns) => _edit((s) {
    if (s.selected.isEmpty) return s;
    final next = {...s.rotations};
    for (final i in s.selected) {
      final turns = ((next[i] ?? 0) + quarterTurns) % 4;
      turns == 0 ? next.remove(i) : next[i] = turns;
    }
    return s.copyWith(rotations: next);
  });

  void setAction(PageAction action) => _edit((s) => s.copyWith(action: action));
  void setSplitMode(SplitMode mode) => _edit((s) => s.copyWith(splitMode: mode));
  void setSplitEvery(int n) => _edit((s) => s.copyWith(splitEvery: n.clamp(1, 999)));
  void setSplitRanges(String text) => _edit((s) => s.copyWith(splitRanges: text));
  void setMarks(PageMarks marks) => _edit((s) => s.copyWith(marks: marks));

  /// Works out which files to make, or explains why that is not possible yet.
  ({List<List<int>> groups, String? error}) plan() {
    final s = state;
    final count = s.pageCount;
    final selected = s.selected.toList()..sort();
    switch (s.action) {
      case PageAction.keep:
        return selected.isEmpty ? (groups: const [], error: 'Tap the pages you want to keep first.') : (groups: [selected], error: null);
      case PageAction.remove:
        if (selected.isEmpty) return (groups: const [], error: 'Tap the pages you want to remove first.');
        final rest = [
          for (var i = 0; i < count; i++)
            if (!s.selected.contains(i)) i,
        ];
        return rest.isEmpty ? (groups: const [], error: 'That would remove every page. Leave at least one.') : (groups: [rest], error: null);
      case PageAction.split:
        final groups = switch (s.splitMode) {
          SplitMode.each => PageRanges.splitEach(count),
          SplitMode.every => PageRanges.splitEvery(s.splitEvery, count),
          SplitMode.ranges => null,
        };
        if (groups != null) {
          if (groups.length < 2) return (groups: const [], error: 'This would give a single file. Use a smaller number of pages per file.');
          return groups.length > maxSplitFiles
              ? (groups: const [], error: 'That would create more than $maxSplitFiles files. Use a larger number of pages per file.')
              : (groups: groups, error: null);
        }
        final parsed = PageRanges.parse(s.splitRanges, count);
        if (!parsed.ok) return (groups: const [], error: parsed.error);
        return parsed.groups.length > maxSplitFiles
            ? (groups: const [], error: 'That would create more than $maxSplitFiles files.')
            : (groups: parsed.groups, error: null);
    }
  }

  List<PartRequest> _requests(List<List<int>> groups) {
    final base = _safe(state.pdf!.name);
    String label(List<int> pages) {
      final text = PageRanges.label(pages);
      return text.length > 30 ? 'selection' : text;
    }

    return switch (state.action) {
      PageAction.keep => [PartRequest(fileName: '${base}_pages_${label(groups.first)}.pdf', pages: groups.first)],
      PageAction.remove => [PartRequest(fileName: '${base}_without_${label(state.selected.toList()..sort())}.pdf', pages: groups.first)],
      PageAction.split => [
        for (var i = 0; i < groups.length; i++)
          PartRequest(
            fileName: state.splitMode == SplitMode.each ? '${base}_page_${groups[i].first + 1}.pdf' : '${base}_part_${i + 1}_p${label(groups[i])}.pdf',
            pages: groups[i],
          ),
      ],
    };
  }

  static String _safe(String name) {
    final cleaned = name.replaceAll(RegExp(r'[^\w\-. ]', unicode: true), '').trim().replaceAll(RegExp(r'\s+'), '_');
    return cleaned.isEmpty ? 'document' : cleaned;
  }

  Future<void> run() async {
    if (state.busy || state.pdf == null) return;
    final plan = this.plan();
    if (plan.error != null) {
      emit(state.copyWith(failure: ExportFailure(plan.error!), status: PagesStatus.idle, parts: const []));
      return;
    }
    final requests = _requests(plan.groups);
    emit(state.copyWith(status: PagesStatus.running, done: 0, total: plan.groups.fold<int>(0, (sum, g) => sum + g.length), parts: const [], failure: null));
    final dir = p.join((await _outputDir()).path, 'pdf_pages', '${_now().millisecondsSinceEpoch}');
    final result = await _service.build(
      source: state.pdf!,
      parts: requests,
      rotations: state.rotations,
      marks: state.marks,
      outputDir: dir,
      onProgress: (done, total) {
        if (!isClosed) emit(state.copyWith(done: done, total: total));
      },
    );
    if (isClosed) return;
    emit(state.copyWith(status: PagesStatus.done, parts: result.valueOrNull ?? const [], failure: result.failureOrNull));
  }
}

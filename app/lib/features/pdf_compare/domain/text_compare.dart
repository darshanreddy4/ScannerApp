import '../../reader/data/pdf_page_reader.dart' show TextRect;
import 'sequence_diff.dart';

export '../../reader/data/pdf_page_reader.dart' show TextRect;

/// One word of a page with where it stands, as shares of the page measured from the top left; the box is null when it is not known.
class PageWord {
  const PageWord(this.text, this.box);
  final String text;
  final TextRect? box;
}

/// The words of one page in reading order, and the page's width divided by its height.
class PageWords {
  const PageWords({required this.words, this.aspect = 0.7727, this.fromOcr = false});
  final List<PageWord> words;
  final double aspect;

  /// The words were read from a picture of the page because it has no text of its own.
  final bool fromOcr;

  bool get isEmpty => words.isEmpty;
}

/// Splits the text of a page into words, each with the box made from the boxes of its letters.
List<PageWord> wordsOfText(String text, List<TextRect?> rects) {
  final out = <PageWord>[];
  var i = 0;
  while (i < text.length) {
    if (_isSpace(text.codeUnitAt(i))) {
      i++;
      continue;
    }
    final from = i;
    TextRect? box;
    while (i < text.length && !_isSpace(text.codeUnitAt(i))) {
      final r = i < rects.length ? rects[i] : null;
      if (r != null) box = box == null ? r : box.union(r);
      i++;
    }
    out.add(PageWord(text.substring(from, i), box));
  }
  return out;
}

bool _isSpace(int c) => c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09 || c == 0xA0 || c == 0x0C;

enum WordKind { same, removed, added }

class WordSpan {
  const WordSpan(this.text, this.kind);
  final String text;
  final WordKind kind;
}

enum ChangeKind { added, removed, changed }

/// A box on a page (from 0).
class PageBox {
  const PageBox(this.page, this.rect);
  final int page;
  final TextRect rect;
}

/// One place where the text differs: the words around it with the removed and the added ones marked, and where they stand on the pages.
class TextChange {
  const TextChange({
    required this.kind,
    required this.spans,
    required this.originalPage,
    required this.revisedPage,
    required this.originalBoxes,
    required this.revisedBoxes,
    required this.removedWords,
    required this.addedWords,
    this.cutBefore = false,
    this.cutAfter = false,
  });

  final ChangeKind kind;
  final List<WordSpan> spans;

  /// The pages (from 0) of the first removed and of the first added word; null when nothing was removed or added.
  final int? originalPage;
  final int? revisedPage;
  final List<PageBox> originalBoxes;
  final List<PageBox> revisedBoxes;
  final int removedWords;
  final int addedWords;

  /// There is more text before or after the words shown.
  final bool cutBefore;
  final bool cutAfter;

  /// The change as plain text: [-removed-] and {+added+}.
  String get plain => [
    if (cutBefore) '...',
    for (final s in spans)
      switch (s.kind) {
        WordKind.same => s.text,
        WordKind.removed => '[-${s.text}-]',
        WordKind.added => '{+${s.text}+}',
      },
    if (cutAfter) '...',
  ].join(' ');
}

/// An original page and the revised page it became; one side is null for a page that was removed or added.
typedef PagePair = (int?, int?);

class TextComparison {
  const TextComparison({required this.changes, required this.removedWords, required this.addedWords, this.tooDifferent = false, this.pagePairs = const []});
  final List<TextChange> changes;

  /// The pages of the two files lined up, so a page inserted in the middle does not shift the pages after it.
  final List<PagePair> pagePairs;
  final int removedWords;
  final int addedWords;

  /// The texts have too little in common to list the changes one by one.
  final bool tooDifferent;

  bool get identical => !tooDifferent && changes.isEmpty;
}

/// Compares the words of two PDFs, page by page in reading order but across page breaks, so a paragraph that moved to the next page
/// is not a change and an inserted page does not turn every later page into one.
TextComparison compareText(List<PageWords> original, List<PageWords> revised, {int context = 4, int mergeGap = 2}) {
  final intern = <String, int>{};
  int key(String w) => intern.putIfAbsent(w, () => intern.length);
  final aWords = <({PageWord word, int page})>[
    for (var p = 0; p < original.length; p++)
      for (final w in original[p].words) (word: w, page: p),
  ];
  final bWords = <({PageWord word, int page})>[
    for (var p = 0; p < revised.length; p++)
      for (final w in revised[p].words) (word: w, page: p),
  ];
  final a = [for (final w in aWords) key(w.word.text)];
  final b = [for (final w in bWords) key(w.word.text)];

  List<DiffOp> ops;
  try {
    ops = diffSequences(a, b);
  } on TooDifferent {
    return TextComparison(
      changes: const [],
      removedWords: a.length,
      addedWords: b.length,
      tooDifferent: true,
      pagePairs: _byIndex(original.length, revised.length),
    );
  }

  // Runs of changed ops, joined when only a word or two of unchanged text lies between them.
  final blocks = <(int, int)>[];
  var i = 0;
  while (i < ops.length) {
    if (ops[i].kind == DiffKind.equal) {
      i++;
      continue;
    }
    var end = i;
    var j = i;
    while (j < ops.length) {
      if (ops[j].kind != DiffKind.equal) {
        end = j;
        j++;
        continue;
      }
      var gap = 0;
      while (j + gap < ops.length && ops[j + gap].kind == DiffKind.equal) {
        gap++;
      }
      if (j + gap < ops.length && gap <= mergeGap) {
        j += gap;
      } else {
        break;
      }
    }
    blocks.add((i, end));
    i = end + 1;
  }

  final changes = <TextChange>[];
  var removedTotal = 0, addedTotal = 0;
  for (var bi = 0; bi < blocks.length; bi++) {
    final (from, to) = blocks[bi];
    // Context words stop where the neighbouring change begins.
    var lo = from - context < 0 ? 0 : from - context;
    var hi = to + context >= ops.length ? ops.length - 1 : to + context;
    if (bi > 0 && lo <= blocks[bi - 1].$2) lo = blocks[bi - 1].$2 + 1;
    if (bi + 1 < blocks.length && hi >= blocks[bi + 1].$1) hi = blocks[bi + 1].$1 - 1;
    final spans = <WordSpan>[];
    final oBoxes = <PageBox>[], rBoxes = <PageBox>[];
    var removed = 0, added = 0;
    int? oPage, rPage;
    for (var k = lo; k <= hi; k++) {
      final op = ops[k];
      final changed = k >= from && k <= to;
      switch (op.kind) {
        case DiffKind.equal:
          spans.add(WordSpan(aWords[op.aIndex].word.text, WordKind.same));
        case DiffKind.delete:
          final w = aWords[op.aIndex];
          spans.add(WordSpan(w.word.text, WordKind.removed));
          if (changed) {
            removed++;
            oPage ??= w.page;
            if (w.word.box != null) oBoxes.add(PageBox(w.page, w.word.box!));
          }
        case DiffKind.insert:
          final w = bWords[op.bIndex];
          spans.add(WordSpan(w.word.text, WordKind.added));
          if (changed) {
            added++;
            rPage ??= w.page;
            if (w.word.box != null) rBoxes.add(PageBox(w.page, w.word.box!));
          }
      }
    }
    removedTotal += removed;
    addedTotal += added;
    changes.add(
      TextChange(
        kind: removed > 0 && added > 0 ? ChangeKind.changed : (removed > 0 ? ChangeKind.removed : ChangeKind.added),
        spans: spans,
        originalPage: oPage,
        revisedPage: rPage,
        originalBoxes: mergeBoxes(oBoxes),
        revisedBoxes: mergeBoxes(rBoxes),
        removedWords: removed,
        addedWords: added,
        cutBefore: lo > 0,
        cutAfter: hi < ops.length - 1,
      ),
    );
  }
  return TextComparison(
    changes: changes,
    removedWords: removedTotal,
    addedWords: addedTotal,
    pagePairs: _alignPages(ops, [for (final w in aWords) w.page], [for (final w in bWords) w.page], original.length, revised.length),
  );
}

List<PagePair> _byIndex(int nA, int nB) => [for (var i = 0; i < (nA > nB ? nA : nB); i++) (i < nA ? i : null, i < nB ? i : null)];

/// Pairs pages that share the most words, never crossing; when too few pages can be paired by their words (pages that are pictures
/// have none) the pages are paired by number.
List<PagePair> _alignPages(List<DiffOp> ops, List<int> aPage, List<int> bPage, int nA, int nB) {
  final shared = <(int, int), int>{};
  final wordsA = List<int>.filled(nA, 0), wordsB = List<int>.filled(nB, 0);
  for (final p in aPage) {
    wordsA[p]++;
  }
  for (final p in bPage) {
    wordsB[p]++;
  }
  for (final op in ops) {
    if (op.kind == DiffKind.equal) shared.update((aPage[op.aIndex], bPage[op.bIndex]), (n) => n + 1, ifAbsent: () => 1);
  }
  final candidates = [
    for (final e in shared.entries)
      if (e.value >= 2 && e.value >= 0.2 * (wordsA[e.key.$1] < wordsB[e.key.$2] ? wordsA[e.key.$1] : wordsB[e.key.$2])) e,
  ]..sort((x, y) => y.value.compareTo(x.value));
  final accepted = <(int, int)>[];
  final usedA = <int>{}, usedB = <int>{};
  for (final c in candidates) {
    final (pa, pb) = c.key;
    if (usedA.contains(pa) || usedB.contains(pb)) continue;
    if (accepted.any((x) => (pa < x.$1 && pb > x.$2) || (pa > x.$1 && pb < x.$2))) continue;
    accepted.add((pa, pb));
    usedA.add(pa);
    usedB.add(pb);
  }
  if (accepted.length * 2 < (nA < nB ? nA : nB)) return _byIndex(nA, nB);
  accepted.sort((x, y) => x.$1.compareTo(y.$1));
  final out = <PagePair>[];
  var ia = 0, ib = 0;
  for (final (pa, pb) in accepted) {
    while (ia < pa) {
      out.add((ia++, null));
    }
    while (ib < pb) {
      out.add((null, ib++));
    }
    out.add((pa, pb));
    ia = pa + 1;
    ib = pb + 1;
  }
  while (ia < nA) {
    out.add((ia++, null));
  }
  while (ib < nB) {
    out.add((null, ib++));
  }
  return out;
}

/// Joins the boxes of words on the same line of a page into one box, so a changed sentence is one mark and not one for each word.
List<PageBox> mergeBoxes(List<PageBox> boxes, {double gap = 0.04}) {
  final out = <PageBox>[];
  for (final b in boxes) {
    var merged = false;
    for (var k = out.length - 1; k >= 0 && k >= out.length - 3; k--) {
      final o = out[k];
      if (o.page != b.page) continue;
      final overlap = (o.rect.bottom < b.rect.bottom ? o.rect.bottom : b.rect.bottom) - (o.rect.top > b.rect.top ? o.rect.top : b.rect.top);
      final smaller = o.rect.height < b.rect.height ? o.rect.height : b.rect.height;
      final sameLine = smaller > 0 && overlap / smaller > 0.5;
      final near = b.rect.left - o.rect.right < gap && o.rect.left - b.rect.right < gap;
      if (sameLine && near) {
        out[k] = PageBox(o.page, o.rect.union(b.rect));
        merged = true;
        break;
      }
    }
    if (!merged) out.add(b);
  }
  return out;
}

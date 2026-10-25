import '../data/pdf_text_extractor.dart';

/// One place a searched word or phrase was found: the page (from 0) and the boxes to highlight, one per line of text.
class SearchHit {
  const SearchHit({required this.page, required this.rects});
  final int page;
  final List<TextRect> rects;
}

/// Lowercases and treats every kind of white space as a plain space, keeping the length so positions still match.
String foldForSearch(String s) {
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (c.trim().isEmpty || c == '\u00A0') {
      b.write(' ');
      continue;
    }
    final lower = c.toLowerCase();
    b.write(lower.length == 1 ? lower : c);
  }
  return b.toString();
}

RegExp? searchPattern(String query) {
  final words = foldForSearch(query).trim().split(RegExp(r' +')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return null;
  return RegExp(words.map(RegExp.escape).join(' +'));
}

/// Every place [query] occurs in [pages], in reading order. Case and line breaks do not matter.
List<SearchHit> searchPages(List<PageTextIndex> pages, String query, {int limit = 2000}) {
  final pattern = searchPattern(query);
  if (pattern == null) return const [];
  final hits = <SearchHit>[];
  for (var p = 0; p < pages.length; p++) {
    final page = pages[p];
    if (!page.hasText) continue;
    final folded = foldForSearch(page.text);
    for (final m in pattern.allMatches(folded)) {
      final rects = lineRects(page.rects, m.start, m.end);
      if (rects.isNotEmpty) hits.add(SearchHit(page: p, rects: rects));
      if (hits.length >= limit) return hits;
    }
  }
  return hits;
}

/// Joins the letter boxes from [start] to [end] into one box for each line (a line of turned text runs down the page).
List<TextRect> lineRects(List<TextRect?> rects, int start, int end) {
  final out = <TextRect>[];
  TextRect? line, prev;
  for (var i = start; i < end && i < rects.length; i++) {
    final r = rects[i];
    if (r == null || r.width <= 0 && r.height <= 0) continue;
    if (line == null || prev == null) {
      line = r;
    } else {
      final across = (r.centerY - prev.centerY).abs() <= 0.6 * (prev.height > r.height ? prev.height : r.height);
      final down = ((r.left + r.right) / 2 - (prev.left + prev.right) / 2).abs() <= 0.6 * (prev.width > r.width ? prev.width : r.width);
      if (across || down) {
        line = line.union(r);
      } else {
        out.add(line);
        line = r;
      }
    }
    prev = r;
  }
  if (line != null) out.add(line);
  return out;
}

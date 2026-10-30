import '../../ocr/domain/ocr_models.dart';
import 'receipt_parser.dart';

/// Default names look like "Scan 2026-10-25 14.07". Anything else was chosen by the person or comes from a file name, so it is left alone.
bool isDefaultScanTitle(String title) => RegExp(r'^(?:Scan|Receipt|Card|ID|Book|Whiteboard|Table) \d{4}-\d{2}-\d{2} \d{2}\.\d{2}$').hasMatch(title.trim());

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _letters(String s) => s.replaceAll(RegExp(r'[^\p{L}]', unicode: true), '');

final _contact = RegExp(r'@|https?://|www\.|\.(?:com|net|org|in|co)\b|^\s*\+?[\d\s().\-]{7,}$', caseSensitive: false);
final _pageWord = RegExp(r'^\s*(?:page|pg\.?)\s*\d+(?:\s*(?:of|/)\s*\d+)?\s*$', caseSensitive: false);

bool _plausible(String text) {
  final letters = _letters(text).length;
  final digits = RegExp(r'\d').allMatches(text).length;
  if (letters < 3 || digits > letters) return false;
  if (text.length > 80) return false;
  if (_contact.hasMatch(text) || _pageWord.hasMatch(text)) return false;
  // A bare date is a date, not a name.
  if (parseReceipt(text).date != null && letters < 8) return false;
  return true;
}

const _smallWords = {'of', 'and', 'the', 'for', 'to', 'in', 'on', 'a', 'an', 'or', 'by', 'at', 'with'};

String _tidy(String raw) {
  var t = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  t = t.replaceAll(RegExp(r'^[\s\-–—:|•*#.,_~=]+|[\s\-–—:|•*#.,_~=]+$'), '');
  final letters = _letters(t);
  // SHOUTING headings read better in title case, but short acronyms such as "ID" or "VAT" stay as they are.
  if (letters.length > 4 && letters == letters.toUpperCase() && letters != letters.toLowerCase()) {
    final words = t.split(' ');
    t = [
      for (var i = 0; i < words.length; i++)
        if (_letters(words[i]).length > 3 || _smallWords.contains(words[i].toLowerCase()))
          (i == 0 || !_smallWords.contains(words[i].toLowerCase())) ? words[i][0] + words[i].substring(1).toLowerCase() : words[i].toLowerCase()
        else
          words[i],
    ].join(' ');
  }
  if (t.length > 50) {
    final cut = t.substring(0, 50);
    final space = cut.lastIndexOf(' ');
    t = (space > 25 ? cut.substring(0, space) : cut).trim();
  }
  return t;
}

/// The heading of a page: the biggest plausible line near the top, joined with the line under it when that continues the heading.
/// Returns null when nothing on the page looks like a name.
String? suggestTitle(OcrPageResult page) {
  final lines = [
    for (final b in page.blocks)
      for (final l in b.lines)
        if (l.text.trim().isNotEmpty && l.height > 0) l,
  ];
  if (lines.isEmpty || page.height <= 0) return null;
  lines.sort((a, b) => a.top.compareTo(b.top));
  // The size of ordinary text: a low quantile, so a heading of several big lines does not count as the usual size.
  final heights = [for (final l in lines) l.height]..sort();
  final body = heights[(heights.length * 0.3).floor()];
  final topLimit = page.height * 0.55;
  final candidates = [
    for (final l in lines)
      if (l.top <= topLimit && _plausible(l.text.replaceAll(RegExp(r'\s+'), ' ').trim())) l,
  ];
  if (candidates.isEmpty) return null;

  var best = candidates.first;
  for (final c in candidates) {
    if (c.height > best.height * 1.05) best = c;
  }
  // Without a clearly bigger line, the first line is the heading.
  if (best.height < body * 1.25) best = candidates.first;

  var text = best.text.replaceAll(RegExp(r'\s+'), ' ').trim();
  final index = lines.indexOf(best);
  if (index + 1 < lines.length) {
    final next = lines[index + 1];
    final sameSize = (next.height - best.height).abs() <= best.height * 0.2;
    final close = next.top - best.bottom <= best.height * 0.8 && next.top >= best.top;
    final alongside = (next.left - best.left).abs() <= page.width * 0.25 || (next.left + next.right - best.left - best.right).abs() <= page.width * 0.2;
    final nextText = next.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (sameSize && close && alongside && best.height >= body * 1.25 && _plausible(nextText) && text.length + nextText.length < 60) {
      text = '$text $nextText';
    }
  }
  final tidy = _tidy(text);
  return tidy.length < 3 ? null : tidy;
}

/// "Scan 12 Mar 2026" for a page that has a date but no heading, or null without a date.
String? suggestTitleFromDate(String text, {DateTime? now}) {
  final d = parseReceipt(text, now: now).date;
  if (d == null) return null;
  return 'Scan ${d.day} ${_months[d.month - 1]} ${d.year}';
}

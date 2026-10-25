import 'math_converter.dart';
import 'ocr_models.dart';

/// Turns recognised lines into Markdown: headings, paragraphs, lists, and formulas as `$...$` / `$$...$$`.
///
/// It relies on the engine's reading order and on line sizes, so it handles ordinary documents well. It does not
/// rebuild tables, multiple columns that the engine interleaves, or formulas drawn in several rows.
abstract final class TextStructurer {
  static final _bullet = RegExp(r'^\s*[•·▪◦‣○●■□▶►\-–—*]\s+');
  static final _numbered = RegExp(r'^\s*\(?(\d{1,3})[\.\)]\s+');
  static final _lettered = RegExp(r'^\s*\(?([A-Za-z])[\.\)]\s+');

  static String toMarkdown(OcrPageResult page) {
    final lines = [for (final b in page.blocks) ...b.lines].where((l) => l.text.trim().isNotEmpty).toList();
    if (lines.isEmpty) return '';

    final median = _median([for (final l in lines) l.height]);
    final out = <String>[];

    for (final block in page.blocks) {
      final blockLines = block.lines.where((l) => l.text.trim().isNotEmpty).toList();
      if (blockLines.isEmpty) continue;
      for (final paragraph in _paragraphs(blockLines, median)) {
        final md = _render(paragraph, median);
        if (md.isNotEmpty) out.add(md);
      }
    }
    return out.join('\n\n');
  }

  /// Splits a block where the vertical gap between lines is clearly larger than normal spacing.
  static List<List<OcrLine>> _paragraphs(List<OcrLine> lines, double median) {
    final result = <List<OcrLine>>[
      [lines.first],
    ];
    for (var i = 1; i < lines.length; i++) {
      final gap = lines[i].top - lines[i - 1].bottom;
      if (median > 0 && gap > median * 0.9) {
        result.add([lines[i]]);
      } else {
        result.last.add(lines[i]);
      }
    }
    return result;
  }

  static String _render(List<OcrLine> lines, double median) {
    final texts = [for (final l in lines) l.text.trim()];

    // A block made only of formulas is shown one display formula per line.
    if (texts.every(MathConverter.isFormulaLine)) {
      return texts.map((t) => '\$\$${MathConverter.toLatex(t)}\$\$').join('\n\n');
    }

    final heading = _heading(lines, texts, median);
    if (heading != null) return heading;

    // "J. Smith" is a name, so lettered items only count as a list when several lines look like items.
    final letteredLines = texts.where(_lettered.hasMatch).length;
    if (texts.any(_listStart) || letteredLines >= 2) return _list(texts);

    return _paragraph(texts);
  }

  static bool _listStart(String text) => _bullet.hasMatch(text) || _numbered.hasMatch(text);

  static String? _heading(List<OcrLine> lines, List<String> texts, double median) {
    if (lines.length != 1 || median <= 0) return null;
    final text = texts.first;
    if (text.length > 90 || RegExp(r'[.,;:]$').hasMatch(text)) return null;
    final ratio = lines.first.height / median;
    final level = ratio >= 1.8
        ? 1
        : ratio >= 1.4
        ? 2
        : 0;
    if (level == 0) return null;
    return '${'#' * level} ${_text(text)}';
  }

  static String _list(List<String> texts) {
    final items = <String>[];
    for (final t in texts) {
      final num = _numbered.firstMatch(t);
      final bullet = _bullet.firstMatch(t);
      final letter = _lettered.firstMatch(t);
      if (num != null) {
        items.add('${num[1]}. ${_text(t.substring(num.end))}');
      } else if (bullet != null) {
        items.add('- ${_text(t.substring(bullet.end))}');
      } else if (letter != null) {
        items.add('- ${_text(t)}');
      } else if (items.isNotEmpty) {
        // A wrapped line belongs to the item above.
        items[items.length - 1] = '${items.last} ${_text(t)}';
      } else {
        items.add(_text(t));
      }
    }
    return items.join('\n');
  }

  static String _paragraph(List<String> texts) {
    final buffer = StringBuffer();
    for (var i = 0; i < texts.length; i++) {
      var t = texts[i];
      final next = i + 1 < texts.length ? texts[i + 1] : null;
      // Words broken across lines: "exam-" + "ple" -> "example".
      if (next != null && RegExp(r'[\p{L}]-$', unicode: true).hasMatch(t) && RegExp(r'^\p{Ll}', unicode: true).hasMatch(next)) {
        t = t.substring(0, t.length - 1);
        buffer.write(t);
        continue;
      }
      buffer.write(t);
      if (next != null) buffer.write(' ');
    }
    return _text(buffer.toString());
  }

  /// Escapes Markdown characters in prose and wraps formula fragments as inline math.
  static String _text(String text) {
    final out = StringBuffer();
    for (final piece in MathConverter.splitInline(text)) {
      if (piece.math) {
        out.write('\$${MathConverter.toLatex(piece.text)}\$');
      } else {
        out.write(escape(piece.text));
      }
    }
    return out.toString();
  }

  /// Protects characters Markdown would treat as formatting. Dollar signs are escaped so prices are not read as formulas.
  static String escape(String text) =>
      text.replaceAllMapped(RegExp(r'[\\`*_\[\]<>#$|]'), (m) => '\\${m[0]}').replaceFirstMapped(RegExp(r'^(\s*)([+\-])(\s)'), (m) => '${m[1]}\\${m[2]}${m[3]}');

  static double _median(List<double> values) {
    final sorted = [...values]..sort();
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
  }
}

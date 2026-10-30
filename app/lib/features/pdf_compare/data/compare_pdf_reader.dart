import 'dart:typed_data';

import '../../ocr/domain/ocr_models.dart';
import '../../reader/data/pdf_text_extractor.dart';
import '../domain/text_compare.dart';

/// The words of every page of a PDF that has text of its own, with where each stands. Pages that are pictures come out empty.
/// Pure Dart, so it can run in an isolate; a file that needs a password throws.
List<PageWords> readPdfWords(Uint8List bytes, {int maxPages = 60}) => [
  for (final p in extractPdfText(bytes, maxPages: maxPages)) PageWords(words: wordsOfText(p.text, p.rects), aspect: p.aspect),
];

/// The words the text reader found on a picture of a page, each with its box (the box of the line when the words are not told apart).
PageWords wordsFromOcr(OcrPageResult page) {
  final w = page.width <= 0 ? 1.0 : page.width, h = page.height <= 0 ? 1.0 : page.height;
  TextRect box(double l, double t, double r, double b) =>
      TextRect((l / w).clamp(0.0, 1.0), (t / h).clamp(0.0, 1.0), (r / w).clamp(0.0, 1.0), (b / h).clamp(0.0, 1.0));
  final out = <PageWord>[];
  for (final block in page.blocks) {
    for (final line in block.lines) {
      final inner = [
        for (final word in line.words)
          if (word.text.trim().isNotEmpty) word,
      ];
      if (inner.isNotEmpty) {
        for (final word in inner) {
          out.add(PageWord(word.text.trim(), box(word.left, word.top, word.right, word.bottom)));
        }
      } else {
        final lineBox = box(line.left, line.top, line.right, line.bottom);
        for (final token in line.text.split(RegExp(r'\s+'))) {
          if (token.isNotEmpty) out.add(PageWord(token, lineBox));
        }
      }
    }
  }
  return PageWords(words: out, aspect: page.height > 0 ? page.width / page.height : 0.7727, fromOcr: true);
}

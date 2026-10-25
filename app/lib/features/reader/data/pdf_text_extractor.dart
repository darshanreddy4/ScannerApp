import 'dart:typed_data';

import '../../pdf_tools/data/security/pdf_rewriter.dart';
import 'pdf_page_reader.dart';

export 'pdf_page_reader.dart' show TextRect;

/// The text of one page with the place of every letter, so words found in it can be highlighted.
class PageTextIndex {
  const PageTextIndex({required this.aspect, required this.text, required this.rects});

  /// Width divided by height of the page as it is shown.
  final double aspect;

  /// One entry in [rects] for every UTF-16 unit of [text]; null for spaces and line breaks added between words.
  final String text;
  final List<TextRect?> rects;

  bool get hasText => text.trim().isNotEmpty;
}

/// Reads the text of every page of a PDF, with positions. Scanned pages have no text and give empty pages.
/// A file that needs a password throws [WrongPasswordException]; pure Dart, so it can run in an isolate.
List<PageTextIndex> extractPdfText(Uint8List bytes, {int maxPages = 1500}) {
  final doc = readPdfDocument(bytes);
  final file = PdfReader(doc);
  final out = <PageTextIndex>[];
  for (final page in file.pages().take(maxPages)) {
    try {
      final read = interpretPage(file, page);
      out.add(PageTextIndex(aspect: read.geometry.aspect, text: read.text, rects: [for (final b in read.boxes) b == null ? null : read.geometry.normalize(b)]));
    } catch (_) {
      out.add(const PageTextIndex(aspect: 0.7727, text: '', rects: []));
    }
  }
  return out;
}

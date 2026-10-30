import 'dart:typed_data';

import 'text_compare.dart';

/// One original page and the revised page it became, with what differs between them. Pages that look the same are not kept.
class ComparedPage {
  const ComparedPage({
    required this.number,
    this.pageA,
    this.pageB,
    this.imageA,
    this.imageB,
    this.aspect = 0.7727,
    this.removed = const [],
    this.added = const [],
    this.visual = const [],
    this.similarity = 1,
    this.sizeChanged = false,
  });

  /// The place in the list of page pairs, from 1.
  final int number;

  /// The pages (from 0) of the original and the revised file; null for a page that exists in only one of them.
  final int? pageA;
  final int? pageB;
  final Uint8List? imageA;
  final Uint8List? imageB;

  /// Width divided by height of the revised page (of the original when there is no revised one).
  final double aspect;

  /// Text that was taken out (on the original page) and text that was put in (on the revised page).
  final List<TextRect> removed;
  final List<TextRect> added;

  /// Other differences in how the page looks: pictures, lines, layout.
  final List<TextRect> visual;
  final double similarity;
  final bool sizeChanged;

  bool get onlyInOriginal => pageB == null;
  bool get onlyInRevised => pageA == null;
  bool get changed => pageA == null || pageB == null || removed.isNotEmpty || added.isNotEmpty || visual.isNotEmpty || sizeChanged;
}

class PdfComparison {
  const PdfComparison({
    required this.text,
    required this.pages,
    required this.pagesA,
    required this.pagesB,
    this.pairs = 0,
    this.ocrPages = 0,
    this.noText = false,
  });

  final TextComparison text;

  /// The pairs of pages that differ, in order.
  final List<ComparedPage> pages;
  final int pagesA;
  final int pagesB;

  /// How many pairs of pages there were, whether they differ or not.
  final int pairs;

  /// Pages that were pictures and were read with the text reader.
  final int ocrPages;

  /// Neither file has any text to compare, so only how the pages look was compared.
  final bool noText;

  bool get identical => text.identical && pages.isEmpty;
}

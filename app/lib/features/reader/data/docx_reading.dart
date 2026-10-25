import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/painting.dart' show TextSelection;
import 'package:uuid/uuid.dart';

import '../../importer/data/docx_parser.dart';
import '../../importer/data/text_page_renderer.dart';
import '../domain/document_search.dart';
import 'pdf_text_extractor.dart';

/// One page of a Word file as the reader shows it.
class DocxReadPage {
  const DocxReadPage({required this.imagePath, required this.isText});
  final String imagePath;

  /// Pages made from the document's text (searchable) rather than a picture inside it.
  final bool isText;

  static const textAspect = TextPageRenderer.pageW / TextPageRenderer.pageH;
}

class _TextBlock {
  _TextBlock(this.text, this.layout, this.firstPage);
  final String text;
  final LaidOutText layout;
  final int firstPage;
}

/// A Word file turned into pages for reading, with the layout of its text kept for searching.
class DocxReading {
  DocxReading._(this.pages, this._blocks);

  final List<DocxReadPage> pages;
  final List<_TextBlock> _blocks;

  bool get hasText => _blocks.any((b) => b.text.trim().isNotEmpty);

  /// Every place [query] occurs, in reading order.
  List<SearchHit> search(String query, {int limit = 2000}) {
    final pattern = searchPattern(query);
    if (pattern == null) return const [];
    final hits = <SearchHit>[];
    for (final block in _blocks) {
      final folded = foldForSearch(block.text);
      final starts = block.layout.starts;
      for (final m in pattern.allMatches(folded)) {
        final boxes = block.layout.painter.getBoxesForSelection(TextSelection(baseOffset: m.start, extentOffset: m.end));
        if (boxes.isEmpty) continue;
        int pageOf(double y) {
          var i = 0;
          while (i + 1 < starts.length && starts[i + 1] <= y) {
            i++;
          }
          return i;
        }

        final first = pageOf((boxes.first.top + boxes.first.bottom) / 2);
        if (first >= block.layout.files.length) continue;
        final rects = <TextRect>[];
        for (final b in boxes) {
          if (pageOf((b.top + b.bottom) / 2) != first) continue;
          final top = b.top - starts[first] + TextPageRenderer.margin;
          rects.add(
            TextRect(
              (b.left + TextPageRenderer.margin) / TextPageRenderer.pageW,
              top / TextPageRenderer.pageH,
              (b.right + TextPageRenderer.margin) / TextPageRenderer.pageW,
              math.min(top + (b.bottom - b.top), TextPageRenderer.pageH) / TextPageRenderer.pageH,
            ),
          );
        }
        if (rects.isNotEmpty) hits.add(SearchHit(page: block.firstPage + first, rects: _mergeLines(rects)));
        if (hits.length >= limit) return hits;
      }
    }
    return hits;
  }

  static List<TextRect> _mergeLines(List<TextRect> rects) {
    final out = <TextRect>[];
    for (final r in rects) {
      if (out.isNotEmpty && (out.last.centerY - r.centerY).abs() < 0.3 * r.height) {
        out[out.length - 1] = out.last.union(r);
      } else {
        out.add(r);
      }
    }
    return out;
  }

  void dispose() {
    for (final b in _blocks) {
      b.layout.painter.dispose();
    }
  }
}

/// Opens a .docx for reading: its text becomes pages and its pictures are kept as they are.
Future<DocxReading> loadDocxReading({required String path, required Directory workDir}) async {
  await workDir.create(recursive: true);
  final prefix = const Uuid().v4();
  final blocks = await Isolate.run(() => parseDocx(path: path, outDir: workDir.path, prefix: prefix));
  final pages = <DocxReadPage>[];
  final textBlocks = <_TextBlock>[];
  final renderer = TextPageRenderer();
  var run = 0;
  for (final b in blocks) {
    if (b.isImage) {
      pages.add(DocxReadPage(imagePath: b.value, isText: false));
    } else {
      final laid = await renderer.renderLaidOut(text: b.value, outDir: workDir.path, prefix: '$prefix-${run++}');
      textBlocks.add(_TextBlock(b.value, laid, pages.length));
      for (final f in laid.files) {
        pages.add(DocxReadPage(imagePath: f, isText: true));
      }
    }
  }
  return DocxReading._(pages, textBlocks);
}

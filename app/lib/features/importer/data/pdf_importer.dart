import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;
import 'package:pdfx/pdfx.dart';

import '../../../core/error/failures.dart';
import '../domain/importer.dart';

/// Renders each PDF page to a JPEG using the platform PDF renderer.
class PdfImporter {
  static const maxPages = 200;
  static const _targetLongSide = 2000.0;

  Future<List<String>> toImages({required String path, required String outDir, required String prefix, ImportProgress? onProgress}) async {
    final doc = await PdfDocument.openFile(path);
    final out = <String>[];
    try {
      final total = doc.pagesCount;
      if (total == 0) throw const ImportFailure('This PDF has no pages.');
      if (total > maxPages) throw ImportFailure('This PDF has $total pages. The limit is $maxPages pages per import.');

      for (var i = 1; i <= total; i++) {
        final page = await doc.getPage(i);
        try {
          // Scale every page to the same target size; oversized pages are scaled down, never rendered at full size.
          final scale = _targetLongSide / math.max(page.width, page.height);
          final image = await page.render(
            width: page.width * scale,
            height: page.height * scale,
            format: PdfPageImageFormat.jpeg,
            backgroundColor: '#FFFFFF',
            quality: 90,
          );
          if (image == null) throw ImportFailure('Page $i could not be rendered.');
          final file = File(p.join(outDir, '$prefix-$i.jpg'));
          await file.writeAsBytes(image.bytes, flush: true);
          out.add(file.path);
        } finally {
          await page.close();
        }
        onProgress?.call(i, total);
      }
    } finally {
      await doc.close();
    }
    return out;
  }
}

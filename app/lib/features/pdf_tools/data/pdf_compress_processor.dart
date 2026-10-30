import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../../../core/error/failures.dart';
import '../../../core/error/result.dart';
import '../../export/data/document_builders.dart';
import '../../export/domain/entities/export_options.dart';
import '../../photo_tools/data/watermark_compositor.dart' show readPictureSize;
import '../domain/pdf_compressor.dart';

/// Makes a PDF smaller by redrawing every page as a picture and lowering the picture quality step by step until the size limit is met.
/// Text stays readable but is no longer selectable, because the pages become pictures.
class PdfCompressProcessor implements PdfCompressor {
  const PdfCompressProcessor({required this.pdfToImages});

  /// Turns a PDF into one picture per page.
  final Future<List<String>> Function(String pdfPath) pdfToImages;

  /// From best quality to smallest file: (longest side in pixels, JPEG quality).
  static const levels = <(int, int)>[(2000, 85), (1700, 78), (1400, 70), (1100, 60), (900, 50), (700, 40)];

  /// Used when no size limit is given.
  static const balancedLevel = 2;

  @override
  Future<Result<CompressedPdf>> compress({
    required String sourcePath,
    required String outputPath,
    required PdfCompressOptions options,
    void Function(int attempt, int attempts)? onProgress,
  }) => guard(() async {
    final source = File(sourcePath);
    if (!await source.exists()) throw const ExportFailure('The file could not be found.');
    final original = await source.length();
    final target = options.targetBytes;

    if (target != null && original <= target) {
      return CompressedPdf(path: sourcePath, bytes: original, originalBytes: original, pages: 0, metTarget: true, unchanged: true);
    }

    final pages = await pdfToImages(sourcePath);
    if (pages.isEmpty) throw const ExportFailure('Nothing could be read from this PDF.');
    final sizes = [for (final path in pages) await Isolate.run(() => readPictureSize(path))];

    final tried = target == null ? [balancedLevel] : [for (var i = 0; i < levels.length; i++) i];
    final dir = await Directory(p.join(p.dirname(outputPath), '.pdf_work_${DateTime.now().microsecondsSinceEpoch}')).create(recursive: true);
    String? bestPath;
    var bestBytes = 0;
    try {
      for (var n = 0; n < tried.length; n++) {
        onProgress?.call(n + 1, tried.length);
        final (maxSide, quality) = levels[tried[n]];
        final pageDir = (await Directory(p.join(dir.path, 'l$n')).create()).path;
        final inputs = [for (var i = 0; i < pages.length; i++) PageSource(path: pages[i], width: sizes[i].width, height: sizes[i].height)];
        final redrawn = await Isolate.run(() => redrawPages(inputs, maxSide, quality, pageDir));
        final candidate = p.join(dir.path, 'c$n.pdf');
        await buildPdfInBackground(redrawn, ExportQuality.high, candidate);
        await Directory(pageDir).delete(recursive: true);

        final size = await File(candidate).length();
        if (bestPath == null || size < bestBytes) {
          bestPath = candidate;
          bestBytes = size;
        }
        if (target == null || size <= target) break;
      }

      // A file that is already compact can come out larger after redrawing.
      if (bestBytes >= original) {
        return CompressedPdf(
          path: sourcePath,
          bytes: original,
          originalBytes: original,
          pages: pages.length,
          metTarget: target == null || original <= target,
          unchanged: true,
        );
      }
      await File(bestPath!).rename(outputPath);
      return CompressedPdf(path: outputPath, bytes: bestBytes, originalBytes: original, pages: pages.length, metTarget: target == null || bestBytes <= target);
    } finally {
      await dir.delete(recursive: true).then((_) {}, onError: (_) {});
    }
  }, onError: (e) => e is Failure ? e : ExportFailure('The PDF could not be made smaller. It may be damaged or protected.', cause: e));
}

/// Redraws pages smaller and more compressed, one at a time to keep memory use low.
List<PageSource> redrawPages(List<PageSource> pages, int maxSide, int quality, String outDir) {
  final out = <PageSource>[];
  for (var i = 0; i < pages.length; i++) {
    final page = pages[i];
    var image = img.decodeImage(File(page.path).readAsBytesSync());
    if (image == null) throw const FormatException('Corrupted page image');
    if (math.max(image.width, image.height) > maxSide) {
      image = image.width >= image.height
          ? img.copyResize(image, width: maxSide, interpolation: img.Interpolation.average)
          : img.copyResize(image, height: maxSide, interpolation: img.Interpolation.average);
    }
    final path = p.join(outDir, 'p$i.jpg');
    File(path).writeAsBytesSync(Uint8List.fromList(img.encodeJpg(image, quality: quality)));
    out.add(PageSource(path: path, width: image.width, height: image.height));
  }
  return out;
}

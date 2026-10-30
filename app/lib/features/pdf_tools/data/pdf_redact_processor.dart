import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../../../core/error/failures.dart';
import '../../../core/error/result.dart';
import '../../export/data/document_builders.dart';
import '../../export/domain/entities/export_options.dart';
import '../domain/pdf_forms.dart';
import '../domain/pdf_redact.dart';
import 'pdf_picture_pages.dart';

/// Paints [boxes] (shares of the page) solid black on a page picture and writes it as a JPEG. Runs in a background isolate.
({int width, int height}) blackenPage(Uint8List picture, List<RedactBox> boxes, String outputPath) {
  var image = img.decodeImage(picture);
  if (image == null) throw const FormatException('Unsupported or damaged image');
  if (image.hasAlpha || image.numChannels != 3) {
    final flat = img.Image(width: image.width, height: image.height, numChannels: 3);
    img.fill(flat, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(flat, image);
    image = flat;
  }
  final w = image.width, h = image.height;
  for (final b in boxes) {
    // A pixel more on each side so no edge of the letters shows through.
    final x1 = (b.left * w).floor() - 1, y1 = (b.top * h).floor() - 1, x2 = (b.right * w).ceil() + 1, y2 = (b.bottom * h).ceil() + 1;
    img.fillRect(image, x1: x1.clamp(0, w - 1), y1: y1.clamp(0, h - 1), x2: x2.clamp(0, w - 1), y2: y2.clamp(0, h - 1), color: img.ColorRgb8(0, 0, 0));
  }
  File(outputPath).writeAsBytesSync(img.encodeJpg(image, quality: 90), flush: true);
  return (width: w, height: h);
}

class PdfRedactProcessor implements PdfRedactService {
  PdfRedactProcessor({PdfPicturePages Function()? pages}) : _pages = pages ?? PdfxPicturePages.new;
  final PdfPicturePages Function() _pages;

  @override
  Future<Result<FilledPdf>> redact({required String sourcePath, required String outputPath, required List<RedactBox> boxes, bool highDetail = false}) =>
      guard(() async {
        if (boxes.isEmpty) throw const ExportFailure('Draw over what to hide first.');
        if (!await File(sourcePath).exists()) throw const ExportFailure('The file could not be found.');
        final pages = _pages();
        final work = await Directory('$outputPath.work').create(recursive: true);
        try {
          final count = await pages.open(sourcePath);
          if (boxes.any((b) => b.page < 0 || b.page >= count)) throw const ExportFailure('A hidden area is on a page that is not in this PDF.');
          final sources = <PageSource>[];
          for (var i = 0; i < count; i++) {
            final picture = await pages.render(i, width: highDetail ? 2480 : 1654, png: true);
            final out = p.join(work.path, 'p$i.jpg');
            final mine = [
              for (final b in boxes)
                if (b.page == i) b,
            ];
            final size = await Isolate.run(() => blackenPage(picture, mine, out));
            sources.add(PageSource(path: out, width: size.width, height: size.height));
          }
          await buildPdfInBackground(sources, ExportQuality.high, outputPath);
          return FilledPdf(path: outputPath, bytes: await File(outputPath).length());
        } finally {
          await pages.close().then((_) {}, onError: (_) {});
          await work.delete(recursive: true).then((_) {}, onError: (_) {});
        }
      }, onError: (e) => e is Failure ? e : ExportFailure('This PDF could not be processed. It may be damaged or protected.', cause: e));
}

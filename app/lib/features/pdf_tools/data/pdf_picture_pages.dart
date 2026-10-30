import 'dart:typed_data';

import 'package:pdfx/pdfx.dart';

/// Draws the pages of a PDF as picture files' contents.
abstract interface class PdfPicturePages {
  /// Opens the PDF and returns how many pages it has.
  Future<int> open(String path);

  /// The page (from 0) as a picture [width] pixels wide.
  Future<Uint8List> render(int page, {required int width, required bool png});

  Future<void> close();
}

class PdfxPicturePages implements PdfPicturePages {
  PdfDocument? _document;

  @override
  Future<int> open(String path) async {
    await close();
    final doc = await PdfDocument.openFile(path);
    _document = doc;
    return doc.pagesCount;
  }

  @override
  Future<Uint8List> render(int page, {required int width, required bool png}) async {
    final doc = _document;
    if (doc == null) throw StateError('No PDF is open');
    final p = await doc.getPage(page + 1);
    try {
      final image = await p.render(
        width: width.toDouble(),
        height: width * p.height / p.width,
        format: png ? PdfPageImageFormat.png : PdfPageImageFormat.jpeg,
        backgroundColor: '#FFFFFF',
        quality: 92,
      );
      if (image == null) throw StateError('The page could not be drawn');
      return image.bytes;
    } finally {
      await p.close();
    }
  }

  @override
  Future<void> close() async {
    final doc = _document;
    _document = null;
    if (doc != null) await doc.close();
  }
}

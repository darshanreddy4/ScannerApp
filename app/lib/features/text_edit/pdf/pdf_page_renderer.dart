import 'dart:typed_data';

import 'package:pdfx/pdfx.dart';

/// Draws the pages of a PDF as pictures, for the text editor to show.
abstract interface class PdfPageRenderer {
  int get pageCount;

  /// The page (from 0) as a picture [width] pixels wide.
  Future<Uint8List> render(int page, {required int width});

  Future<void> dispose();
}

class PdfxPageRenderer implements PdfPageRenderer {
  PdfxPageRenderer._(this._document);

  final PdfDocument _document;

  static Future<PdfPageRenderer> open(String path) async => PdfxPageRenderer._(await PdfDocument.openFile(path));

  @override
  int get pageCount => _document.pagesCount;

  @override
  Future<Uint8List> render(int page, {required int width}) async {
    final p = await _document.getPage(page + 1);
    try {
      final image = await p.render(
        width: width.toDouble(),
        height: width * p.height / p.width,
        format: PdfPageImageFormat.jpeg,
        backgroundColor: '#FFFFFF',
        quality: 88,
      );
      if (image == null) throw StateError('The page could not be drawn');
      return image.bytes;
    } finally {
      await p.close();
    }
  }

  @override
  Future<void> dispose() => _document.close();
}

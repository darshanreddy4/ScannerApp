import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/utils/region.dart';
import '../domain/entities/export_options.dart';

/// Source page for builders: only primitives so work can run inside an isolate.
class PageSource {
  const PageSource({required this.path, required this.width, required this.height});
  final String path;
  final int width;
  final int height;
}

/// Reads a page as JPEG bytes, downscaling/recompressing when [quality] asks for it.
/// Pages are loaded one at a time to keep peak memory low on large documents.
({Uint8List bytes, int width, int height}) loadPageBytes(PageSource page, ExportQuality quality) {
  final raw = File(page.path).readAsBytesSync();
  final maxSide = quality.maxSide;
  if (maxSide == null || math.max(page.width, page.height) <= maxSide) {
    return (bytes: raw, width: page.width, height: page.height);
  }
  final decoded = img.decodeImage(raw);
  if (decoded == null) throw const FormatException('Corrupted page image');
  final resized = decoded.width >= decoded.height
      ? img.copyResize(decoded, width: maxSide, interpolation: img.Interpolation.average)
      : img.copyResize(decoded, height: maxSide, interpolation: img.Interpolation.average);
  return (bytes: Uint8List.fromList(img.encodeJpg(resized, quality: quality.jpegQuality)), width: resized.width, height: resized.height);
}

/// Builds the PDF in another isolate, with the paper of the region chosen on the phone (the isolate cannot read the settings itself).
Future<void> buildPdfInBackground(List<PageSource> pages, ExportQuality quality, String outputPath) {
  final letter = Region.letter;
  return Isolate.run(() => buildPdf(pages, quality, outputPath, letter: letter));
}

/// Pages are as big as their pictures, fitted into a sheet of paper: A4, or US Letter when [letter] is set.
Future<void> buildPdf(List<PageSource> pages, ExportQuality quality, String outputPath, {bool letter = false}) async {
  final doc = pw.Document(compress: true);
  final a4Long = letter ? 792.0 : 842.0, a4Short = letter ? 612.0 : 595.0;

  for (final page in pages) {
    final data = loadPageBytes(page, quality);
    final landscape = data.width > data.height;
    final boxW = landscape ? a4Long : a4Short;
    final boxH = landscape ? a4Short : a4Long;
    final scale = math.min(boxW / data.width, boxH / data.height);
    final format = PdfPageFormat(data.width * scale, data.height * scale);
    final image = pw.MemoryImage(data.bytes);

    doc.addPage(
      pw.Page(
        pageFormat: format,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Image(image, fit: pw.BoxFit.fill),
      ),
    );
  }

  final bytes = await doc.save();
  await File(outputPath).writeAsBytes(bytes, flush: true);
}

/// A Word file with a picture on each page; the page is A4, or US Letter when [letter] is set, with margins of 1 inch.
void buildDocx(List<PageSource> pages, ExportQuality quality, String outputPath, {bool letter = false}) {
  const emuPerInch = 914400;
  final maxW = (letter ? 6.5 : 8.27 - 2) * emuPerInch;
  final maxH = (letter ? 9.0 : 11.69 - 2) * emuPerInch;

  final archive = Archive();
  final body = StringBuffer();
  final rels = StringBuffer();

  for (var i = 0; i < pages.length; i++) {
    final data = loadPageBytes(pages[i], quality);
    final scale = math.min(maxW / data.width, maxH / data.height);
    final cx = (data.width * scale).round();
    final cy = (data.height * scale).round();
    final n = i + 1;

    archive.addFile(ArchiveFile.bytes('word/media/image$n.jpg', data.bytes));
    rels.write(
      '<Relationship Id="rId$n" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" '
      'Target="media/image$n.jpg"/>',
    );

    body.write(
      '<w:p><w:pPr>${i > 0 ? '<w:pageBreakBefore/>' : ''}<w:jc w:val="center"/></w:pPr><w:r><w:drawing>'
      '<wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="$cx" cy="$cy"/>'
      '<wp:docPr id="$n" name="Page $n"/>'
      '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
      '<pic:pic><pic:nvPicPr><pic:cNvPr id="$n" name="image$n.jpg"/><pic:cNvPicPr/></pic:nvPicPr>'
      '<pic:blipFill><a:blip r:embed="rId$n"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
      '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>'
      '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic>'
      '</a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>',
    );
  }

  const header = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';

  final documentXml =
      '$header<w:document '
      'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
      'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
      'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><w:body>$body'
      '<w:sectPr>${letter ? '<w:pgSz w:w="12240" w:h="15840"/>' : '<w:pgSz w:w="11906" w:h="16838"/>'}'
      '<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/>'
      '</w:sectPr></w:body></w:document>';

  const contentTypes =
      '$header<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Default Extension="jpg" ContentType="image/jpeg"/>'
      '<Override PartName="/word/document.xml" '
      'ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>';

  const rootRels =
      '$header<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
      'Target="word/document.xml"/></Relationships>';

  final docRels = '$header<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">$rels</Relationships>';

  Uint8List utf8Bytes(String s) => Uint8List.fromList(utf8.encode(s));

  archive
    ..addFile(ArchiveFile.bytes('[Content_Types].xml', utf8Bytes(contentTypes)))
    ..addFile(ArchiveFile.bytes('_rels/.rels', utf8Bytes(rootRels)))
    ..addFile(ArchiveFile.bytes('word/document.xml', utf8Bytes(documentXml)))
    ..addFile(ArchiveFile.bytes('word/_rels/document.xml.rels', utf8Bytes(docRels)));

  final encoded = ZipEncoder().encode(archive);
  File(outputPath).writeAsBytesSync(encoded, flush: true);
}

import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../../../core/error/failures.dart';
import '../../../core/error/result.dart';
import '../../export/data/document_builders.dart';
import '../../export/domain/entities/export_options.dart';
import '../../photo_tools/data/watermark_compositor.dart' show readPictureSize;
import '../domain/signature.dart';

/// Opens PDFs and photos for signing and puts a signature picture on chosen pages.
/// The pages of a PDF become pictures, so text in the result can no longer be selected.
class DocumentSignerProcessor implements DocumentSigner {
  DocumentSignerProcessor({required this.pdfToImages});

  final Future<List<String>> Function(String pdfPath) pdfToImages;

  static bool isPdf(String path) => p.extension(path).toLowerCase() == '.pdf';

  @override
  Future<Result<SignDocument>> open(String path) => guard(() async {
    if (!await File(path).exists()) throw const ExportFailure('The file could not be found.');
    final name = p.basenameWithoutExtension(path);
    if (isPdf(path)) {
      final pages = await pdfToImages(path);
      if (pages.isEmpty) throw const ExportFailure('Nothing could be read from this PDF.');
      return SignDocument(name: name, pages: pages, sizes: [for (final page in pages) await Isolate.run(() => readPictureSize(page))], isPdf: true);
    }
    final size = await Isolate.run(() => readPictureSize(path));
    return SignDocument(name: name, pages: [path], sizes: [size], isPdf: false);
  }, onError: (e) => e is Failure ? e : ExportFailure('This file could not be opened. It may be damaged or unsupported.', cause: e));

  @override
  Future<Result<SignedFile>> sign({
    required SignDocument document,
    required String signaturePath,
    required SignPlacement placement,
    required List<int> pages,
    required String outputDir,
    void Function(int done, int total)? onProgress,
  }) => guard(() async {
    if (pages.isEmpty || pages.any((i) => i < 0 || i >= document.pages.length)) throw const ExportFailure('Choose the page to sign.');
    if (!await File(signaturePath).exists()) throw const ExportFailure('The signature could not be found. Create it again.');
    final dir = await Directory(outputDir).create(recursive: true);
    final unique = DateTime.now().microsecondsSinceEpoch;
    final signing = pages.toSet();
    final sources = <PageSource>[];
    var done = 0;
    for (var i = 0; i < document.pages.length; i++) {
      final original = document.pages[i];
      if (!signing.contains(i)) {
        if (document.isPdf) {
          final size = await Isolate.run(() => readPictureSize(original));
          sources.add(PageSource(path: original, width: size.width, height: size.height));
        }
        continue;
      }
      final out = p.join(dir.path, '${document.name.replaceAll(RegExp(r'[^\w\-. ]', unicode: true), '_')}_signed_$unique-$i.jpg');
      final size = await Isolate.run(() => signPage(original, signaturePath, out, placement));
      sources.add(PageSource(path: out, width: size.width, height: size.height));
      onProgress?.call(++done, signing.length);
    }

    if (!document.isPdf) {
      return SignedFile(path: sources.single.path, name: '${document.name} signed.jpg', mimeType: 'image/jpeg', pages: 1, signedPages: 1);
    }
    final target = p.join(dir.path, '${document.name.replaceAll(RegExp(r'[^\w\-. ]', unicode: true), '_')}_signed_$unique.pdf');
    await Isolate.run(() => buildPdf(sources, ExportQuality.high, target));
    for (final s in sources) {
      if (s.path.startsWith(dir.path)) await File(s.path).delete().then((_) {}, onError: (_) {});
    }
    return SignedFile(
      path: target,
      name: '${document.name} signed.pdf',
      mimeType: 'application/pdf',
      pages: document.pages.length,
      signedPages: signing.length,
    );
  }, onError: (e) => e is Failure ? e : ExportFailure('The signature could not be added. A page or the signature may be damaged.', cause: e));
}

/// Draws the signature on a page picture and saves it as JPG. Runs in a background isolate.
({int width, int height}) signPage(String pagePath, String signaturePath, String outputPath, SignPlacement placement) {
  var page = img.decodeImage(File(pagePath).readAsBytesSync());
  if (page == null) throw const FormatException('Unsupported or damaged image');
  page = img.bakeOrientation(page);
  if (page.hasAlpha || page.numChannels != 3) {
    final flat = img.Image(width: page.width, height: page.height, numChannels: 3);
    img.fill(flat, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(flat, page);
    page = flat;
  }
  final signature = img.decodeImage(File(signaturePath).readAsBytesSync());
  if (signature == null) throw const FormatException('Damaged signature');

  final aspect = signature.width / signature.height;
  final fitted = placement.clamped(aspect: aspect, pageAspect: page.width / page.height);
  final w = math.max(2, (fitted.width * page.width).round());
  final h = math.max(2, (w / aspect).round());
  final sized = img.copyResize(signature, width: w, height: h, interpolation: img.Interpolation.cubic);
  final left = (fitted.centerX * page.width - w / 2).round().clamp(0, math.max(0, page.width - w)).toInt();
  final top = (fitted.centerY * page.height - h / 2).round().clamp(0, math.max(0, page.height - h)).toInt();
  img.compositeImage(page, sized, dstX: left, dstY: top);
  File(outputPath).writeAsBytesSync(img.encodeJpg(page, quality: 92), flush: true);
  return (width: page.width, height: page.height);
}

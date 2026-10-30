import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../../../core/error/failures.dart';
import '../../../core/error/result.dart';
import '../../export/data/document_builders.dart';
import '../../export/domain/entities/export_options.dart';
import '../../photo_tools/data/watermark_compositor.dart';
import '../../photo_tools/data/watermark_stamp.dart';
import '../../photo_tools/domain/watermark.dart';
import '../domain/pdf_pages.dart';

/// Opens a PDF as page pictures and builds new PDFs from chosen pages, with turns, page numbers, header and footer.
/// The pages become pictures, so text in the result can no longer be selected.
class PdfPagesProcessor implements PdfPageService {
  PdfPagesProcessor({required this.pdfToImages, this.renderer = const WatermarkStampRenderer()});

  final Future<List<String>> Function(String pdfPath) pdfToImages;
  final WatermarkStampRenderer renderer;

  /// Letter height as a share of the page's shorter side.
  static const markSize = 0.018;

  @override
  Future<Result<OpenedPdf>> open(String path) => guard(() async {
    if (!await File(path).exists()) throw const ExportFailure('The file could not be found.');
    final pages = await pdfToImages(path);
    if (pages.isEmpty) throw const ExportFailure('Nothing could be read from this PDF.');
    return OpenedPdf(name: p.basenameWithoutExtension(path), pages: pages);
  }, onError: (e) => e is Failure ? e : ExportFailure('This PDF could not be opened. It may be damaged or protected.', cause: e));

  @override
  Future<Result<List<PdfPart>>> build({
    required OpenedPdf source,
    required List<PartRequest> parts,
    required Map<int, int> rotations,
    required PageMarks marks,
    required String outputDir,
    void Function(int done, int total)? onProgress,
  }) => guard(() async {
    if (parts.isEmpty || parts.any((r) => r.pages.isEmpty)) throw const ExportFailure('Choose at least one page.');
    for (final part in parts) {
      if (part.pages.any((i) => i < 0 || i >= source.pages.length)) throw const ExportFailure('A chosen page is not in this PDF.');
    }
    await Directory(outputDir).create(recursive: true);
    final total = parts.fold<int>(0, (sum, r) => sum + r.pages.length);
    final stamps = <String, Stamp?>{};
    final sizes = <int, ({int width, int height})>{};
    var done = 0;
    final result = <PdfPart>[];

    for (var k = 0; k < parts.length; k++) {
      final part = parts[k];
      final work = await Directory(p.join(outputDir, '.work_${DateTime.now().microsecondsSinceEpoch}_$k')).create();
      try {
        final sources = <PageSource>[];
        for (var position = 0; position < part.pages.length; position++) {
          final index = part.pages[position];
          final turns = (rotations[index] ?? 0) % 4;
          final original = source.pages[index];
          final size = sizes[index] ??= await Isolate.run(() => readPictureSize(original));
          final turnedW = turns.isOdd ? size.height : size.width, turnedH = turns.isOdd ? size.width : size.height;
          final stampsForPage = await _marksFor(
            marks,
            position: position,
            count: part.pages.length,
            shortSide: turnedW < turnedH ? turnedW : turnedH,
            cache: stamps,
          );

          if (turns == 0 && stampsForPage.isEmpty) {
            sources.add(PageSource(path: original, width: size.width, height: size.height));
          } else {
            final out = p.join(work.path, 'p$position.jpg');
            final drawn = await Isolate.run(() => composePage(original, out, turns, stampsForPage));
            sources.add(PageSource(path: out, width: drawn.width, height: drawn.height));
          }
          onProgress?.call(++done, total);
        }
        final target = p.join(outputDir, part.fileName);
        await buildPdfInBackground(sources, ExportQuality.high, target);
        result.add(PdfPart(path: target, name: part.fileName, pages: part.pages.length, bytes: await File(target).length()));
      } finally {
        await work.delete(recursive: true).then((_) {}, onError: (_) {});
      }
    }
    return result;
  }, onError: (e) => e is Failure ? e : ExportFailure('The PDF could not be created. The file may be damaged.', cause: e));

  Future<List<PageMark>> _marksFor(
    PageMarks marks, {
    required int position,
    required int count,
    required int shortSide,
    required Map<String, Stamp?> cache,
  }) async {
    if (marks.isEmpty) return const [];
    final skip = marks.skipFirst && position == 0;
    final header = skip ? '' : marks.header.trim();
    var footer = skip ? '' : marks.footer.trim();
    final number = skip ? '' : marks.numbers.text(position + 1, count);
    final wanted = <(WatermarkPosition, String)>[];
    if (header.isNotEmpty) wanted.add((WatermarkPosition.topCenter, header));
    if (number.isNotEmpty) {
      if (marks.position == NumberPosition.bottomCenter && footer.isNotEmpty) {
        footer = '$footer\n$number';
      } else {
        wanted.add((_numberSpot(marks.position), number));
      }
    }
    if (footer.isNotEmpty) wanted.add((WatermarkPosition.bottomCenter, footer));

    final out = <PageMark>[];
    for (final (spot, text) in wanted) {
      final key = '$text|${(shortSide / 50).round()}';
      final stamp = cache[key] ??= await renderer.render(
        style: const WatermarkStyle(layout: WatermarkLayout.single, opacity: 1, size: markSize, rotation: 0, color: WatermarkColor.black, bold: false),
        text: text,
        shortSide: shortSide,
      );
      if (stamp != null) out.add(PageMark(rgba: stamp.rgba, width: stamp.width, height: stamp.height, position: spot));
    }
    return out;
  }

  static WatermarkPosition _numberSpot(NumberPosition position) => switch (position) {
    NumberPosition.bottomRight => WatermarkPosition.bottomRight,
    NumberPosition.bottomCenter => WatermarkPosition.bottomCenter,
    NumberPosition.bottomLeft => WatermarkPosition.bottomLeft,
  };
}

/// A small transparent picture to print on a page.
class PageMark {
  const PageMark({required this.rgba, required this.width, required this.height, required this.position});
  final Uint8List rgba;
  final int width;
  final int height;
  final WatermarkPosition position;
}

/// Turns a page picture by quarter turns and prints marks on it. Runs in a background isolate.
({int width, int height}) composePage(String sourcePath, String outputPath, int quarterTurns, List<PageMark> marks) {
  var image = img.decodeImage(File(sourcePath).readAsBytesSync());
  if (image == null) throw const FormatException('Unsupported or damaged image');
  image = img.bakeOrientation(image);
  if (quarterTurns % 4 != 0) image = img.copyRotate(image, angle: 90.0 * (quarterTurns % 4));
  if (image.hasAlpha || image.numChannels != 3) {
    final flat = img.Image(width: image.width, height: image.height, numChannels: 3);
    img.fill(flat, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(flat, image);
    image = flat;
  }
  final w = image.width, h = image.height;
  final raw = Uint8List.fromList(image.getBytes(order: img.ChannelOrder.rgb));
  for (final mark in marks) {
    final spots = WatermarkPlacement.spots(
      imageWidth: w,
      imageHeight: h,
      stampWidth: mark.width,
      stampHeight: mark.height,
      layout: WatermarkLayout.single,
      position: mark.position,
    );
    blendStamp(raw, w, h, mark.rgba, mark.width, mark.height, spots);
  }
  final out = img.Image.fromBytes(width: w, height: h, bytes: raw.buffer, numChannels: 3);
  File(outputPath).writeAsBytesSync(img.encodeJpg(out, quality: 90), flush: true);
  return (width: w, height: h);
}

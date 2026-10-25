import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../../../core/error/failures.dart';
import '../../../core/error/result.dart';
import '../../export/data/document_builders.dart';
import '../../export/domain/entities/export_options.dart';
import '../domain/photo_compressor.dart';
import '../domain/watermark.dart';
import '../domain/watermark_service.dart';
import 'watermark_compositor.dart';
import 'watermark_stamp.dart';

/// Adds a watermark to pictures and to every page of a PDF.
class WatermarkProcessor implements WatermarkService {
  WatermarkProcessor({required this.pdfToImages, this.renderer = const WatermarkStampRenderer(), DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// Turns a PDF into one picture per page.
  final Future<List<String>> Function(String pdfPath) pdfToImages;
  final WatermarkStampRenderer renderer;
  final DateTime Function() _now;

  static bool isPdf(String path) => p.extension(path).toLowerCase() == '.pdf';

  @override
  Future<Result<WatermarkOutput>> apply({
    required String inputPath,
    required WatermarkStyle style,
    required String outputDir,
    String businessName = '',
    void Function(int done, int total)? onProgress,
  }) => guard(() async {
    if (style.isEmpty) throw const ExportFailure('Type the words for the watermark or add a logo first.');
    if (!await File(inputPath).exists()) throw const ExportFailure('The file could not be found.');
    await Directory(outputDir).create(recursive: true);
    final text = WatermarkPresets.fill(style.text, name: businessName, date: _now());
    final stamps = <int, Stamp?>{};
    final stamp = _stampFor(style, text, stamps);
    final base = p.basenameWithoutExtension(inputPath);
    final unique = '${_now().microsecondsSinceEpoch}';

    if (isPdf(inputPath)) {
      final pages = await pdfToImages(inputPath);
      if (pages.isEmpty) throw const ExportFailure('Nothing could be read from this PDF.');
      final sources = <PageSource>[];
      for (var i = 0; i < pages.length; i++) {
        final out = p.join(outputDir, '${base}_wm_$unique-$i.jpg');
        final done = await _stampOne(pages[i], out, style, stamp, PhotoFormat.jpg);
        sources.add(PageSource(path: out, width: done.width, height: done.height));
        onProgress?.call(i + 1, pages.length);
      }
      final target = p.join(outputDir, '${base}_watermarked_$unique.pdf');
      await Isolate.run(() => buildPdf(sources, ExportQuality.high, target));
      for (final s in sources) {
        unawaited(File(s.path).delete().then((_) {}, onError: (_) {}));
      }
      return WatermarkOutput(path: target, mimeType: 'application/pdf', name: '$base watermarked.pdf', pages: pages.length);
    }

    final png = p.extension(inputPath).toLowerCase() == '.png';
    final format = png ? PhotoFormat.png : PhotoFormat.jpg;
    final out = p.join(outputDir, '${base}_watermarked_$unique.${format.extension}');
    await _stampOne(inputPath, out, style, stamp, format);
    onProgress?.call(1, 1);
    return WatermarkOutput(path: out, mimeType: format.mimeType, name: '$base watermarked.${format.extension}');
  }, onError: (e) => e is Failure ? e : ExportFailure('The watermark could not be added. The file may be damaged or unsupported.', cause: e));

  Future<Stamp?> Function(int shortSide) _stampFor(WatermarkStyle style, String text, Map<int, Stamp?> cache) {
    return (shortSide) async {
      // Pages of one document have nearly the same size, so one stamp serves them all.
      final key = (shortSide / 50).round();
      if (cache.containsKey(key)) return cache[key];
      return cache[key] = await renderer.render(style: style, text: text, shortSide: shortSide);
    };
  }

  Future<({int width, int height})> _stampOne(
    String source,
    String out,
    WatermarkStyle style,
    Future<Stamp?> Function(int) stampFor,
    PhotoFormat format,
  ) async {
    final size = await Isolate.run(() => readPictureSize(source));
    final stamp = await stampFor(size.width < size.height ? size.width : size.height);
    if (stamp == null) throw const ExportFailure('Type the words for the watermark or add a logo first.');
    final rgba = stamp.rgba, sw = stamp.width, sh = stamp.height;
    final done = await Isolate.run(
      () => applyStamp(
        sourcePath: source,
        outputPath: out,
        stampRgba: rgba,
        stampWidth: sw,
        stampHeight: sh,
        layout: style.layout,
        position: style.position,
        format: format,
      ),
    );
    return (width: done.width, height: done.height);
  }
}

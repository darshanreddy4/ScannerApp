import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../../../core/error/failures.dart';
import '../../../core/error/result.dart';
import '../../export/data/document_builders.dart';
import '../../export/domain/entities/export_options.dart';
import '../../photo_tools/domain/watermark.dart';
import '../../photo_tools/domain/watermark_service.dart';
import '../domain/safe_id.dart';

/// A copy of the picture upright, of a size the phone can read quickly, with no camera data (place, time, phone) in it.
typedef PreparedId = ({String path, int width, int height});

abstract interface class SafeIdService {
  /// Makes the working copy that the text is read from and the covers are laid on.
  Future<Result<PreparedId>> prepare({required String sourcePath, required String outputDir});

  /// Paints the [boxes] black, adds the repeated mark when [markText] is given, and saves a picture or a PDF.
  Future<Result<WatermarkOutput>> make({
    required String workPath,
    required List<CoverBox> boxes,
    String? markText,
    required bool pdf,
    required String name,
    required String outputDir,
  });
}

/// Upright, at most [maxSide] on the long side, without transparency, and saved as a JPEG without any camera data.
PreparedId prepareId(String sourcePath, String outputPath, {int maxSide = maxSafeIdSide}) {
  var image = img.decodeImage(File(sourcePath).readAsBytesSync());
  if (image == null) throw const FormatException('Unsupported or damaged image');
  image = img.bakeOrientation(image);
  if (image.hasAlpha || image.numChannels != 3) {
    final flat = img.Image(width: image.width, height: image.height, numChannels: 3);
    img.fill(flat, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(flat, image);
    image = flat;
  }
  final longSide = math.max(image.width, image.height);
  if (longSide > maxSide) {
    image = image.width >= image.height
        ? img.copyResize(image, width: maxSide, interpolation: img.Interpolation.average)
        : img.copyResize(image, height: maxSide, interpolation: img.Interpolation.average);
  }
  // A new picture has none of the original's metadata.
  final clean = img.Image.from(image, noAnimation: true)..exif.clear();
  File(outputPath).writeAsBytesSync(img.encodeJpg(clean, quality: 92), flush: true);
  return (path: outputPath, width: clean.width, height: clean.height);
}

/// Paints each box solid black on the picture and saves it. What was under the boxes is not in the new file.
({int width, int height}) applyCovers(String sourcePath, String outputPath, List<CoverBox> boxes, {int quality = 92}) {
  final image = img.decodeImage(File(sourcePath).readAsBytesSync());
  if (image == null) throw const FormatException('Unsupported or damaged image');
  final w = image.width, h = image.height;
  for (final b in boxes) {
    final x1 = (b.left * w).floor().clamp(0, w);
    final y1 = (b.top * h).floor().clamp(0, h);
    final x2 = (b.right * w).ceil().clamp(0, w);
    final y2 = (b.bottom * h).ceil().clamp(0, h);
    if (x2 <= x1 || y2 <= y1) continue;
    img.fillRect(image, x1: x1, y1: y1, x2: x2 - 1, y2: y2 - 1, color: img.ColorRgb8(0, 0, 0));
  }
  File(outputPath).writeAsBytesSync(img.encodeJpg(image, quality: quality), flush: true);
  return (width: w, height: h);
}

class SafeIdProcessor implements SafeIdService {
  SafeIdProcessor({required this.watermark, DateTime Function()? now}) : _now = now ?? DateTime.now;

  final WatermarkService watermark;
  final DateTime Function() _now;
  int _made = 0;

  @override
  Future<Result<PreparedId>> prepare({required String sourcePath, required String outputDir}) => guard(() async {
    if (!await File(sourcePath).exists()) throw const ExportFailure('The picture could not be found.');
    await Directory(outputDir).create(recursive: true);
    final out = p.join(outputDir, 'safeid_work_${_now().microsecondsSinceEpoch}.jpg');
    return Isolate.run(() => prepareId(sourcePath, out));
  }, onError: (e) => e is Failure ? e : ExportFailure('The picture could not be opened. It may be damaged or unsupported.', cause: e));

  @override
  Future<Result<WatermarkOutput>> make({
    required String workPath,
    required List<CoverBox> boxes,
    String? markText,
    required bool pdf,
    required String name,
    required String outputDir,
  }) => guard(() async {
    await Directory(outputDir).create(recursive: true);
    final stamp = '${_now().microsecondsSinceEpoch}_${_made++}';
    final covered = p.join(outputDir, 'safeid_cover_$stamp.jpg');
    final size = await Isolate.run(() => applyCovers(workPath, covered, boxes));
    var finished = covered;
    final temporary = <String>[covered];
    if (markText != null) {
      final marked = await watermark.apply(
        inputPath: covered,
        style: WatermarkStyle(text: markText, layout: WatermarkLayout.tiled, opacity: 0.4, size: 0.04, rotation: -30, color: WatermarkColor.red),
        outputDir: outputDir,
      );
      final failure = marked.failureOrNull;
      if (failure != null) throw failure;
      finished = marked.valueOrNull!.path;
      temporary.add(finished);
    }
    final safeName = name.replaceAll(RegExp(r'[^\w\-]+'), '_');
    final String target;
    if (pdf) {
      target = p.join(outputDir, '${safeName}_$stamp.pdf');
      await buildPdfInBackground([PageSource(path: finished, width: size.width, height: size.height)], ExportQuality.high, target);
    } else {
      target = p.join(outputDir, '${safeName}_$stamp.jpg');
      await File(finished).copy(target);
    }
    for (final f in temporary) {
      try {
        await File(f).delete();
      } on Object {
        // A leftover file in the cache is harmless: it holds only the covered copy.
      }
    }
    return WatermarkOutput(path: target, mimeType: pdf ? 'application/pdf' : 'image/jpeg', name: p.basename(target));
  }, onError: (e) => e is Failure ? e : ExportFailure('The copy could not be made. Please try again.', cause: e));
}

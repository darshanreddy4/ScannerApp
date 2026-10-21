import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../domain/entities/filter_settings.dart';
import '../../domain/entities/quad.dart';
import 'document_edge_detector.dart';
import 'image_filters.dart';
import 'rgb_buffer.dart';

typedef ImageResult = ({int width, int height});
typedef PrepareResult = ({int width, int height, List<double>? quad});

/// Heavy image work runs in short-lived isolates so the UI thread stays responsive.
/// Every entry point takes and returns only sendable primitives.
class ImageProcessingService {
  const ImageProcessingService();

  static const maxWorkingSide = 2400;
  static const previewSide = 900;

  Future<PrepareResult> prepare(String sourcePath, String outputPath) =>
      Isolate.run(() => _prepare(sourcePath, outputPath));

  Future<ImageResult> crop(String imagePath, List<double> quad, String outputPath) =>
      Isolate.run(() => _crop(imagePath, quad, outputPath));

  Future<ImageResult> rotate(String imagePath, String outputPath) =>
      Isolate.run(() => _rotate(imagePath, outputPath));

  Future<Uint8List> preview(String imagePath, FilterSettings settings) =>
      Isolate.run(() => _preview(imagePath, settings));

  Future<ImageResult> applyFilter(String imagePath, FilterSettings settings, String outputPath) =>
      Isolate.run(() => _applyFilter(imagePath, settings, outputPath));
}

RgbBuffer _load(String path, {int? maxSide}) {
  final bytes = File(path).readAsBytesSync();
  var image = img.decodeImage(bytes);
  if (image == null) throw const FormatException('Unsupported or corrupted image');
  image = img.bakeOrientation(image);
  if (maxSide != null && math.max(image.width, image.height) > maxSide) {
    image = image.width >= image.height
        ? img.copyResize(image, width: maxSide, interpolation: img.Interpolation.average)
        : img.copyResize(image, height: maxSide, interpolation: img.Interpolation.average);
  }
  return RgbBuffer.fromImage(image);
}

void _save(RgbBuffer buffer, String path, {int quality = 92}) {
  File(path).writeAsBytesSync(buffer.encodeJpeg(quality: quality), flush: true);
}

PrepareResult _prepare(String sourcePath, String outputPath) {
  final buf = _load(sourcePath, maxSide: ImageProcessingService.maxWorkingSide);
  _save(buf, outputPath);

  const grid = 160;
  final scale = grid / math.max(buf.width, buf.height);
  final gw = math.max(16, (buf.width * scale).round());
  final gh = math.max(16, (buf.height * scale).round());
  final quad = const DocumentEdgeDetector().detect(RgbBuffer.grayThumbnail(buf, gw, gh), gw, gh);

  return (
    width: buf.width,
    height: buf.height,
    quad: quad == null ? null : [for (final p in quad.points) ...[p.x, p.y]],
  );
}

ImageResult _crop(String imagePath, List<double> q, String outputPath) {
  final src = _load(imagePath);
  final quad = Quad(NormPoint(q[0], q[1]), NormPoint(q[2], q[3]), NormPoint(q[4], q[5]), NormPoint(q[6], q[7]));
  final out = PerspectiveTransform.warp(src, quad);
  _save(out, outputPath);
  return (width: out.width, height: out.height);
}

ImageResult _rotate(String imagePath, String outputPath) {
  final out = _load(imagePath).rotate90Clockwise();
  _save(out, outputPath);
  return (width: out.width, height: out.height);
}

Uint8List _preview(String imagePath, FilterSettings settings) {
  final src = _load(imagePath, maxSide: ImageProcessingService.previewSide);
  return ImageFilters.apply(src, settings).encodeJpeg(quality: 85);
}

ImageResult _applyFilter(String imagePath, FilterSettings settings, String outputPath) {
  final src = _load(imagePath);
  final out = ImageFilters.apply(src, settings);
  _save(out, outputPath);
  return (width: out.width, height: out.height);
}

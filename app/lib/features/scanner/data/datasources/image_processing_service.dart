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

  static const maxWorkingSide = 4000;
  static const previewSide = 1600;

  Future<PrepareResult> prepare(String sourcePath, String outputPath) => Isolate.run(() => _prepare(sourcePath, outputPath));

  Future<ImageResult> crop(String imagePath, List<double> quad, String outputPath) => Isolate.run(() => _crop(imagePath, quad, outputPath));

  Future<ImageResult> rotate(String imagePath, String outputPath) => Isolate.run(() => _rotate(imagePath, outputPath));

  Future<ImageResult> inspect(String imagePath) => Isolate.run(() => _inspect(imagePath));

  /// [proxyPath] is where a small copy of the picture is kept, so the full-size file is decoded only once however many filters are tried.
  Future<Uint8List> preview(String imagePath, FilterSettings settings, {String? proxyPath}) => Isolate.run(() => _preview(imagePath, settings, proxyPath));

  Future<List<Uint8List>> previewBatch(String imagePath, List<FilterSettings> variants, int maxSide, {String? proxyPath}) =>
      Isolate.run(() => _previewBatch(imagePath, variants, maxSide, proxyPath));

  Future<ImageResult> applyFilter(String imagePath, FilterSettings settings, String outputPath) =>
      Isolate.run(() => _applyFilter(imagePath, settings, outputPath));
}

RgbBuffer _load(String path, {int? maxSide}) {
  final bytes = File(path).readAsBytesSync();
  var image = img.decodeImage(bytes);
  if (image == null) throw const FormatException('Unsupported or corrupted image');
  image = img.bakeOrientation(image);
  final full = RgbBuffer.fromImage(image);
  return maxSide == null ? full : _shrink(full, maxSide);
}

/// Shrinks to at most [maxSide] on the long side: whole-number block averaging first (fast), then a small exact resize.
RgbBuffer _shrink(RgbBuffer buf, int maxSide) {
  final long = math.max(buf.width, buf.height);
  if (long <= maxSide) return buf;
  var out = buf.boxShrink(long ~/ maxSide);
  final left = math.max(out.width, out.height);
  if (left > maxSide) {
    final image = out.toImage();
    final resized = image.width >= image.height
        ? img.copyResize(image, width: maxSide, interpolation: img.Interpolation.average)
        : img.copyResize(image, height: maxSide, interpolation: img.Interpolation.average);
    out = RgbBuffer.fromImage(resized);
  }
  return out;
}

/// A small copy of [path] for previews. The first call decodes the full picture and keeps the small copy at [proxyPath]; later calls read only that.
RgbBuffer _loadProxy(String path, String? proxyPath, int side) {
  if (proxyPath == null) return _load(path, maxSide: side);
  final proxy = File(proxyPath);
  final source = File(path);
  try {
    if (proxy.existsSync() && (!source.existsSync() || !proxy.lastModifiedSync().isBefore(source.lastModifiedSync()))) {
      final image = img.decodeJpg(proxy.readAsBytesSync());
      if (image != null) return RgbBuffer.fromImage(image);
    }
  } catch (_) {
    // A damaged or half-written small copy is simply made again.
  }
  final small = _load(path, maxSide: side);
  try {
    final temp = File('$proxyPath.${Isolate.current.hashCode}.tmp');
    temp.writeAsBytesSync(small.encodeJpeg(quality: 92), flush: true);
    temp.renameSync(proxyPath);
  } on FileSystemException {
    // A preview without a cache is only slower.
  }
  return small;
}

void _save(RgbBuffer buffer, String path, {int quality = 98}) {
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
    quad: quad == null
        ? null
        : [
            for (final p in quad.points) ...[p.x, p.y],
          ],
  );
}

ImageResult _crop(String imagePath, List<double> q, String outputPath) {
  // Nothing to cut: keep the picture exactly as it is instead of resampling it.
  const edge = 0.004;
  final whole = q[0] < edge && q[1] < edge && q[2] > 1 - edge && q[3] < edge && q[4] > 1 - edge && q[5] > 1 - edge && q[6] < edge && q[7] > 1 - edge;
  if (whole) {
    final info = _inspect(imagePath);
    File(imagePath).copySync(outputPath);
    return info;
  }
  final src = _load(imagePath);
  final quad = Quad(NormPoint(q[0], q[1]), NormPoint(q[2], q[3]), NormPoint(q[4], q[5]), NormPoint(q[6], q[7]));
  final out = PerspectiveTransform.warp(src, quad);
  _save(out, outputPath);
  return (width: out.width, height: out.height);
}

ImageResult _inspect(String imagePath) {
  final bytes = File(imagePath).readAsBytesSync();
  final info = img.findDecoderForData(bytes)?.startDecode(bytes);
  if (info == null) throw const FormatException('Unsupported or corrupted image');
  return (width: info.width, height: info.height);
}

ImageResult _rotate(String imagePath, String outputPath) {
  final out = _load(imagePath).rotate90Clockwise();
  _save(out, outputPath);
  return (width: out.width, height: out.height);
}

Uint8List _preview(String imagePath, FilterSettings settings, String? proxyPath) {
  final src = _loadProxy(imagePath, proxyPath, ImageProcessingService.previewSide);
  return ImageFilters.apply(src, settings).encodeJpeg(quality: 85);
}

List<Uint8List> _previewBatch(String imagePath, List<FilterSettings> variants, int maxSide, String? proxyPath) {
  // Thumbnails come from the same small copy as the preview, shrunk further.
  final src = _shrink(_loadProxy(imagePath, proxyPath, ImageProcessingService.previewSide), maxSide);
  return [for (final v in variants) ImageFilters.apply(src, v).encodeJpeg(quality: 80)];
}

ImageResult _applyFilter(String imagePath, FilterSettings settings, String outputPath) {
  final src = _load(imagePath);
  final out = ImageFilters.apply(src, settings);
  _save(out, outputPath, quality: 95);
  return (width: out.width, height: out.height);
}

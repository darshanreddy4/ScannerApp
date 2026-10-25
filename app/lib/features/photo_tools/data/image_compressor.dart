import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../../core/error/failures.dart';
import '../../../core/error/result.dart';
import '../domain/photo_compressor.dart';

/// Shrinks a photo to a file-size limit by lowering JPEG quality first and the pixel size only when needed,
/// so the picture stays as sharp as the limit allows.
class ImageCompressor implements PhotoCompressor {
  const ImageCompressor();

  @override
  Future<Result<CompressedPhoto>> compress({required String sourcePath, required String outputPath, required CompressOptions options}) => guard(
    () => Isolate.run(() => compressPhotoSync(sourcePath, outputPath, options)),
    onError: (e) => ExportFailure('This photo could not be compressed. It may be damaged or in an unsupported format.', cause: e),
  );
}

/// Lowest JPEG quality that still looks fine; below this the size is reduced instead.
const _goodQuality = 60;
const _minSide = 160;

CompressedPhoto compressPhotoSync(String sourcePath, String outputPath, CompressOptions options) {
  final source = File(sourcePath);
  final original = source.readAsBytesSync();
  var image = img.decodeImage(original);
  if (image == null) throw const FormatException('Unsupported or damaged image');
  image = img.bakeOrientation(image);

  final jpg = options.format == PhotoFormat.jpg;
  if (jpg && image.hasAlpha) image = _onWhite(image);

  final maxSide = options.maxSide;
  if (maxSide != null && math.max(image.width, image.height) > maxSide) image = _fit(image, maxSide);

  final target = options.targetBytes;
  late List<int> best;
  late img.Image shown;
  int? quality;
  var met = true;

  if (target == null) {
    shown = image;
    quality = jpg ? 88 : null;
    best = jpg ? img.encodeJpg(image, quality: 88) : img.encodePng(image, level: 6);
  } else if (jpg) {
    final result = options.keepPixelSize ? _searchQualityOnly(image, target) : _searchJpeg(image, target);
    best = result.bytes;
    shown = result.image;
    quality = result.quality;
    met = best.length <= target;
  } else {
    final result = _searchPng(image, target);
    best = result.bytes;
    shown = result.image;
    met = best.length <= target;
  }

  // A photo that is already small enough and was not resized is kept as it is.
  if (target != null && original.length <= target && best.length >= original.length && shown.width == image.width && maxSide == null) {
    final sameFormat = jpg ? _isJpeg(original) : _isPng(original);
    if (sameFormat && !_needsOrientationFix(original)) {
      File(outputPath).writeAsBytesSync(original, flush: true);
      return CompressedPhoto(
        path: outputPath,
        bytes: original.length,
        width: shown.width,
        height: shown.height,
        originalBytes: original.length,
        metTarget: true,
        quality: null,
      );
    }
  }

  File(outputPath).writeAsBytesSync(best, flush: true);
  return CompressedPhoto(
    path: outputPath,
    bytes: best.length,
    width: shown.width,
    height: shown.height,
    originalBytes: original.length,
    metTarget: met,
    quality: quality,
  );
}

typedef _Found = ({List<int> bytes, img.Image image, int quality});

/// Lowers only the quality, down to a floor where the picture is still usable.
_Found _searchQualityOnly(img.Image base, int target) {
  final found = _bestQuality(base, target, 25, 95);
  if (found != null) return (bytes: found.bytes, image: base, quality: found.quality);
  return (bytes: img.encodeJpg(base, quality: 25), image: base, quality: 25);
}

_Found _searchJpeg(img.Image base, int target) {
  // Full size first: the highest quality that fits.
  final atFull = _bestQuality(base, target, _goodQuality, 95);
  if (atFull != null) return (bytes: atFull.bytes, image: base, quality: atFull.quality);

  // Too big even at the lowest good quality: find the largest size that fits at a middling quality.
  final probe = img.encodeJpg(base, quality: _goodQuality).length;
  final minScale = _minSide / math.max(base.width, base.height);
  final estimate = math.sqrt(target / probe);
  var hi = math.max(minScale, math.min(1.0, estimate * 1.35));
  var lo = math.max(minScale, math.min(hi, estimate * 0.5));
  List<int>? fit;
  img.Image? fitImage;
  for (var i = 0; i < 9; i++) {
    final mid = (lo + hi) / 2;
    final scaled = _scale(base, mid);
    final bytes = img.encodeJpg(scaled, quality: 80);
    if (bytes.length <= target) {
      fit = bytes;
      fitImage = scaled;
      lo = mid;
    } else {
      hi = mid;
    }
  }
  if (fit == null) {
    // Even the lower bound did not fit: walk down until it does or the picture gets tiny.
    var scale = lo;
    while (true) {
      final scaled = _scale(base, scale);
      final bytes = img.encodeJpg(scaled, quality: 70);
      if (bytes.length <= target || scale <= minScale) {
        final low = img.encodeJpg(scaled, quality: 40);
        final use = bytes.length <= target ? bytes : low;
        return (bytes: use, image: scaled, quality: bytes.length <= target ? 70 : 40);
      }
      scale = math.max(minScale, scale * 0.85);
    }
  }
  // The size is fixed; use whatever quality headroom is left.
  final bumped = _bestQuality(fitImage!, target, 80, 95);
  if (bumped != null) return (bytes: bumped.bytes, image: fitImage, quality: bumped.quality);
  return (bytes: fit, image: fitImage, quality: 80);
}

({List<int> bytes, int quality})? _bestQuality(img.Image image, int target, int low, int high) {
  List<int>? best;
  var bestQ = 0;
  var lo = low;
  var hi = high;
  while (lo <= hi) {
    final mid = (lo + hi) ~/ 2;
    final bytes = img.encodeJpg(image, quality: mid);
    if (bytes.length <= target) {
      best = bytes;
      bestQ = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return best == null ? null : (bytes: best, quality: bestQ);
}

({List<int> bytes, img.Image image}) _searchPng(img.Image base, int target) {
  var bytes = img.encodePng(base, level: 6);
  if (bytes.length <= target) return (bytes: bytes, image: base);
  // PNG has no quality setting, so only the size can change.
  final minScale = _minSide / math.max(base.width, base.height);
  var lo = minScale;
  var hi = 1.0;
  List<int>? fit;
  img.Image? fitImage;
  for (var i = 0; i < 9; i++) {
    final mid = (lo + hi) / 2;
    final scaled = _scale(base, mid);
    final out = img.encodePng(scaled, level: 6);
    if (out.length <= target) {
      fit = out;
      fitImage = scaled;
      lo = mid;
    } else {
      hi = mid;
    }
  }
  if (fit != null) return (bytes: fit, image: fitImage!);
  final smallest = _scale(base, minScale);
  return (bytes: img.encodePng(smallest, level: 9), image: smallest);
}

img.Image _scale(img.Image image, double scale) {
  if (scale >= 0.999) return image;
  final w = math.max(1, (image.width * scale).round());
  return img.copyResize(image, width: w, interpolation: img.Interpolation.average);
}

img.Image _fit(img.Image image, int maxSide) => image.width >= image.height
    ? img.copyResize(image, width: maxSide, interpolation: img.Interpolation.average)
    : img.copyResize(image, height: maxSide, interpolation: img.Interpolation.average);

img.Image _onWhite(img.Image image) {
  final base = img.Image(width: image.width, height: image.height, numChannels: 3);
  img.fill(base, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(base, image);
  return base;
}

bool _isJpeg(Uint8List b) => b.length > 3 && b[0] == 0xFF && b[1] == 0xD8;
bool _isPng(Uint8List b) => b.length > 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47;

/// A camera photo can carry a rotation flag that only some viewers honour; re-encoding bakes it in.
bool _needsOrientationFix(Uint8List bytes) {
  final orientation = img.decodeJpgExif(bytes)?.imageIfd.orientation;
  return orientation != null && orientation != 1;
}

import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../../core/error/failures.dart';
import '../../../core/error/result.dart';
import '../domain/metadata_cleaner.dart';

class PhotoMetadataCleaner implements MetadataCleaner {
  const PhotoMetadataCleaner();

  static const unsupported = 'Only JPG and PNG photos can be cleaned.';

  @override
  Future<Result<PhotoMetadata>> inspect(String path) => guard(
    () => Isolate.run(() => inspectMetadata(File(path).readAsBytesSync())),
    onError: (e) => e is FormatException ? ExportFailure(e.message, cause: e) : ExportFailure('This photo could not be read.', cause: e),
  );

  @override
  Future<Result<CleanedPhoto>> clean({required String sourcePath, required String outputPath}) => guard(
    () => Isolate.run(() {
      final original = File(sourcePath).readAsBytesSync();
      final cleaned = stripMetadata(original);
      File(outputPath).writeAsBytesSync(cleaned, flush: true);
      return CleanedPhoto(path: outputPath, bytes: cleaned.length, removedBytes: original.length - cleaned.length);
    }),
    onError: (e) =>
        e is FormatException ? ExportFailure(e.message, cause: e) : ExportFailure('The hidden data could not be removed from this photo.', cause: e),
  );
}

bool isJpeg(Uint8List b) => b.length > 3 && b[0] == 0xFF && b[1] == 0xD8;
bool isPng(Uint8List b) => b.length > 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47;

PhotoMetadata inspectMetadata(Uint8List bytes) {
  if (isPng(bytes)) {
    final cleaned = _stripPng(bytes);
    return PhotoMetadata(hasOtherData: cleaned.length < bytes.length, hiddenBytes: bytes.length - cleaned.length, isPng: true);
  }
  if (!isJpeg(bytes)) throw const FormatException(PhotoMetadataCleaner.unsupported);

  final exif = img.decodeJpgExif(bytes);
  final camera = [exif?.imageIfd.make, exif?.imageIfd.model].whereType<String>().map((s) => s.trim()).where((s) => s.isNotEmpty).join(' ');
  final cleaned = stripMetadata(bytes);
  final hidden = bytes.length - cleaned.length;
  final hasGps = exif != null && exif.gpsIfd.data.isNotEmpty && (exif.gpsIfd.data.containsKey(0x0002) || exif.gpsIfd.data.containsKey(0x0004));
  final taken = exif?.exifIfd.data[0x9003]?.toString() ?? exif?.imageIfd.data[0x0132]?.toString();
  final software = exif?.imageIfd.software?.trim();
  final listed = hasGps || camera.isNotEmpty || taken != null || (software != null && software.isNotEmpty);
  return PhotoMetadata(
    hasLocation: hasGps,
    camera: camera.isEmpty ? null : camera,
    takenAt: taken,
    software: software == null || software.isEmpty ? null : software,
    // Something was removed that none of the listed items explains: thumbnails, XMP, comments, trailers.
    hasOtherData: hidden > 0 && !listed || hidden > 2000,
    hiddenBytes: hidden,
  );
}

/// Returns the photo without private data. JPEG and PNG are rewritten block by block, so the picture is untouched.
Uint8List stripMetadata(Uint8List bytes) {
  if (isPng(bytes)) return _stripPng(bytes);
  if (isJpeg(bytes)) return _stripJpeg(bytes);
  throw const FormatException(PhotoMetadataCleaner.unsupported);
}

// region JPEG

Uint8List _stripJpeg(Uint8List b) {
  final orientation = img.decodeJpgExif(b)?.imageIfd.orientation;
  final out = BytesBuilder(copy: false)..add(const [0xFF, 0xD8]);
  var wroteOrientation = orientation == null || orientation == 1;
  var i = 2;

  void addOrientationOnce() {
    if (wroteOrientation) return;
    wroteOrientation = true;
    out.add(_orientationOnlyExif(orientation!));
  }

  while (i + 1 < b.length) {
    if (b[i] != 0xFF) break;
    while (i + 1 < b.length && b[i + 1] == 0xFF) {
      i++;
    }
    final marker = b[i + 1];
    if (marker == 0xD9) {
      addOrientationOnce();
      out.add(const [0xFF, 0xD9]);
      return out.takeBytes();
    }
    // Markers without a length.
    if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
      out.add(b.sublist(i, i + 2));
      i += 2;
      continue;
    }
    if (i + 3 >= b.length) break;
    final length = (b[i + 2] << 8) | b[i + 3];
    final end = i + 2 + length;
    if (end > b.length) break;

    if (marker == 0xDA) {
      // Start of scan: everything up to the end-of-image marker is picture data. Anything after it (trailers,
      // embedded second pictures) is dropped.
      addOrientationOnce();
      var j = end;
      var eoi = -1;
      while (j + 1 < b.length) {
        if (b[j] == 0xFF && b[j + 1] == 0xD9) {
          eoi = j + 2;
          break;
        }
        j++;
      }
      out.add(b.sublist(i, eoi == -1 ? b.length : eoi));
      return out.takeBytes();
    }

    final isApp = marker >= 0xE0 && marker <= 0xEF;
    final keep = !(isApp || marker == 0xFE) || marker == 0xE0 || marker == 0xEE || (marker == 0xE2 && _startsWith(b, i + 4, 'ICC_PROFILE'));
    if (keep) {
      out.add(b.sublist(i, end));
      // The rotation flag goes right after the first header block so viewers still show the photo upright.
      if (marker == 0xE0) addOrientationOnce();
    }
    i = end;
  }
  // Damaged structure: keep what was written plus the rest as it was after the last good block.
  addOrientationOnce();
  out.add(b.sublist(i.clamp(0, b.length)));
  return out.takeBytes();
}

bool _startsWith(Uint8List b, int at, String text) {
  if (at + text.length > b.length) return false;
  for (var k = 0; k < text.length; k++) {
    if (b[at + k] != text.codeUnitAt(k)) return false;
  }
  return true;
}

/// A tiny EXIF block that holds nothing but the orientation.
Uint8List _orientationOnlyExif(int orientation) {
  final tiff = <int>[
    0x4D, 0x4D, 0x00, 0x2A, 0x00, 0x00, 0x00, 0x08, // big-endian header, first directory at 8
    0x00, 0x01, // one entry
    0x01, 0x12, 0x00, 0x03, 0x00, 0x00, 0x00, 0x01, 0x00, orientation & 0xFF, 0x00, 0x00, // Orientation, SHORT
    0x00, 0x00, 0x00, 0x00, // no next directory
  ];
  final body = [...'Exif'.codeUnits, 0, 0, ...tiff];
  final length = body.length + 2;
  return Uint8List.fromList([0xFF, 0xE1, length >> 8, length & 0xFF, ...body]);
}

// endregion

// region PNG

/// Chunks that carry the picture or how to show it. Everything else (text, time, EXIF) is dropped.
const _pngKeep = {'IHDR', 'PLTE', 'IDAT', 'IEND', 'tRNS', 'gAMA', 'cHRM', 'sRGB', 'iCCP', 'pHYs', 'sBIT', 'bKGD', 'acTL', 'fcTL', 'fdAT'};

Uint8List _stripPng(Uint8List b) {
  final out = BytesBuilder(copy: false)..add(b.sublist(0, 8));
  var i = 8;
  while (i + 12 <= b.length) {
    final length = (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];
    final type = String.fromCharCodes(b.sublist(i + 4, i + 8));
    final end = i + 12 + length;
    if (end > b.length) break;
    if (_pngKeep.contains(type)) out.add(b.sublist(i, end));
    i = end;
    if (type == 'IEND') break;
  }
  return out.takeBytes();
}

// endregion

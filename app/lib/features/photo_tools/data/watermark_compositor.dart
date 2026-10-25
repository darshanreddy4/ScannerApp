import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../domain/photo_compressor.dart';
import '../domain/watermark.dart';

typedef WatermarkedFile = ({int width, int height, int bytes});

/// The size of a picture as it will be shown (camera rotation applied), read without decoding all of it.
({int width, int height}) readPictureSize(String path) {
  final bytes = File(path).readAsBytesSync();
  final info = img.findDecoderForData(bytes)?.startDecode(bytes);
  if (info == null) throw const FormatException('Unsupported or damaged image');
  var w = info.width, h = info.height;
  final orientation = img.decodeJpgExif(bytes)?.imageIfd.orientation;
  if (orientation != null && orientation >= 5 && orientation <= 8) {
    final t = w;
    w = h;
    h = t;
  }
  return (width: w, height: h);
}

/// Lays [stamp] over the picture at every spot and saves the result.
WatermarkedFile applyStamp({
  required String sourcePath,
  required String outputPath,
  required Uint8List stampRgba,
  required int stampWidth,
  required int stampHeight,
  required WatermarkLayout layout,
  required WatermarkPosition position,
  PhotoFormat format = PhotoFormat.jpg,
  int jpegQuality = 92,
}) {
  var image = img.decodeImage(File(sourcePath).readAsBytesSync());
  if (image == null) throw const FormatException('Unsupported or damaged image');
  image = img.bakeOrientation(image);
  if (image.hasAlpha || image.numChannels != 3) {
    final flat = img.Image(width: image.width, height: image.height, numChannels: 3);
    img.fill(flat, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(flat, image);
    image = flat;
  }

  final w = image.width, h = image.height;
  final raw = Uint8List.fromList(image.getBytes(order: img.ChannelOrder.rgb));
  final spots = WatermarkPlacement.spots(imageWidth: w, imageHeight: h, stampWidth: stampWidth, stampHeight: stampHeight, layout: layout, position: position);

  blendStamp(raw, w, h, stampRgba, stampWidth, stampHeight, spots);

  final out = img.Image.fromBytes(width: w, height: h, bytes: raw.buffer, numChannels: 3);
  final bytes = format == PhotoFormat.png ? img.encodePng(out) : img.encodeJpg(out, quality: jpegQuality);
  File(outputPath).writeAsBytesSync(bytes, flush: true);
  return (width: w, height: h, bytes: bytes.length);
}

/// Blends the stamp onto RGB pixels at every spot. Spots may reach past the edges; the stamp is cut there.
void blendStamp(Uint8List raw, int w, int h, Uint8List stampRgba, int stampWidth, int stampHeight, List<WatermarkSpot> spots) {
  for (final spot in spots) {
    final x0 = spot.x < 0 ? 0 : spot.x;
    final y0 = spot.y < 0 ? 0 : spot.y;
    final x1 = spot.x + stampWidth > w ? w : spot.x + stampWidth;
    final y1 = spot.y + stampHeight > h ? h : spot.y + stampHeight;
    for (var y = y0; y < y1; y++) {
      var s = ((y - spot.y) * stampWidth + (x0 - spot.x)) * 4;
      var d = (y * w + x0) * 3;
      for (var x = x0; x < x1; x++, s += 4, d += 3) {
        final a = stampRgba[s + 3];
        if (a == 0) continue;
        if (a == 255) {
          raw[d] = stampRgba[s];
          raw[d + 1] = stampRgba[s + 1];
          raw[d + 2] = stampRgba[s + 2];
        } else {
          final inv = 255 - a;
          raw[d] = (raw[d] * inv + stampRgba[s] * a + 127) ~/ 255;
          raw[d + 1] = (raw[d + 1] * inv + stampRgba[s + 1] * a + 127) ~/ 255;
          raw[d + 2] = (raw[d + 2] * inv + stampRgba[s + 2] * a + 127) ~/ 255;
        }
      }
    }
  }
}

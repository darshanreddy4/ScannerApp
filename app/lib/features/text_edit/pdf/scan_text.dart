import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../../../core/error/failures.dart';
import '../../ocr/domain/ocr_engine.dart';
import '../../ocr/domain/ocr_models.dart';

/// A line of text found in a picture of a page, with where it is (shares of the page, from the top left) and the colours around and in it.
class ScanLine {
  const ScanLine({required this.text, required this.left, required this.top, required this.right, required this.bottom, this.background = 0xFFFFFF, this.ink = 0x000000});
  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;

  /// Colour of the paper next to the line, and of the writing, as 0xRRGGBB.
  final int background;
  final int ink;

  double get width => right - left;
  double get height => bottom - top;
}

/// Reads the lines of text from a picture of a page. Takes the PNG of the page and the writing system to look for.
typedef ScanReader = Future<List<ScanLine>> Function(Uint8List pagePng, OcrScript script);

int _pack(int r, int g, int b) => (r.clamp(0, 255) << 16) | (g.clamp(0, 255) << 8) | b.clamp(0, 255);

/// The colour of the paper around a box of a picture and of the writing inside it. Boxes are in pixels.
({int background, int ink}) sampleLineColors(img.Image image, double left, double top, double right, double bottom) {
  final w = image.width, h = image.height;
  int clampX(num v) => v.round().clamp(0, w - 1);
  int clampY(num v) => v.round().clamp(0, h - 1);
  final l = clampX(left), r = clampX(right), t = clampY(top), b = clampY(bottom);

  // The paper: a thin frame just outside the box.
  final rs = <int>[], gs = <int>[], bs = <int>[];
  void take(int x, int y) {
    final px = image.getPixel(x, y);
    rs.add(px.r.toInt());
    gs.add(px.g.toInt());
    bs.add(px.b.toInt());
  }

  final pad = math.max(2, ((b - t) * 0.15).round());
  final step = math.max(1, (r - l) ~/ 60);
  for (var x = l; x <= r; x += step) {
    take(x, clampY(t - pad));
    take(x, clampY(b + pad));
  }
  final stepY = math.max(1, (b - t) ~/ 20);
  for (var y = t; y <= b; y += stepY) {
    take(clampX(l - pad), y);
    take(clampX(r + pad), y);
  }
  int median(List<int> v) => (v..sort())[v.length ~/ 2];
  final br = median(rs), bg = median(gs), bb = median(bs);

  // The writing: the pixels inside the box that differ most from the paper.
  final scored = <({int dist, int r, int g, int b})>[];
  final sx = math.max(1, (r - l) ~/ 120), sy = math.max(1, (b - t) ~/ 40);
  for (var y = t; y <= b; y += sy) {
    for (var x = l; x <= r; x += sx) {
      final px = image.getPixel(x, y);
      final dr = px.r.toInt() - br, dg = px.g.toInt() - bg, db = px.b.toInt() - bb;
      scored.add((dist: dr * dr + dg * dg + db * db, r: px.r.toInt(), g: px.g.toInt(), b: px.b.toInt()));
    }
  }
  scored.sort((a, c) => c.dist.compareTo(a.dist));
  final strongest = scored.take(math.max(1, scored.length ~/ 20)).toList();
  final luminance = (0.299 * br + 0.587 * bg + 0.114 * bb) / 255;
  if (strongest.isEmpty || strongest.first.dist < 60 * 60) {
    return (background: _pack(br, bg, bb), ink: luminance > 0.5 ? 0x000000 : 0xFFFFFF);
  }
  final ar = strongest.fold<int>(0, (m, e) => m + e.r) ~/ strongest.length;
  final ag = strongest.fold<int>(0, (m, e) => m + e.g) ~/ strongest.length;
  final ab = strongest.fold<int>(0, (m, e) => m + e.b) ~/ strongest.length;
  return (background: _pack(br, bg, bb), ink: _pack(ar, ag, ab));
}

/// Looks for text in the picture of a page with the on-device engine and works out the colours of each line. Nothing leaves the phone.
Future<List<ScanLine>> readScanWithEngine(OcrEngine engine, Directory work, Uint8List png, OcrScript script) async {
  final dir = await Directory(p.join(work.path, 'scan_text')).create(recursive: true);
  final file = File(p.join(dir.path, 'page_${DateTime.now().microsecondsSinceEpoch}.png'));
  await file.writeAsBytes(png, flush: true);
  try {
    final result = await engine.recognize(file.path, script);
    final failure = result.failureOrNull;
    if (failure != null) throw failure;
    final page = result.valueOrNull!;
    final raw = [
      for (final b in page.blocks)
        for (final l in b.lines)
          if (l.text.trim().isNotEmpty && l.width > 2 && l.height > 2) l,
    ];
    if (raw.isEmpty || page.width <= 0 || page.height <= 0) return const [];
    final boxes = [for (final l in raw) (l.left, l.top, l.right, l.bottom)];
    final colours = await Isolate.run(() {
      final image = img.decodeImage(png);
      if (image == null) return [for (final _ in boxes) (background: 0xFFFFFF, ink: 0x000000)];
      // The engine reports pixels of the picture it was given, which is this one.
      return [for (final b in boxes) sampleLineColors(image, b.$1, b.$2, b.$3, b.$4)];
    });
    return [
      for (var i = 0; i < raw.length; i++)
        ScanLine(
          text: raw[i].text.trim(),
          left: (raw[i].left / page.width).clamp(0.0, 1.0),
          top: (raw[i].top / page.height).clamp(0.0, 1.0),
          right: (raw[i].right / page.width).clamp(0.0, 1.0),
          bottom: (raw[i].bottom / page.height).clamp(0.0, 1.0),
          background: colours[i].background,
          ink: colours[i].ink,
        ),
    ];
  } finally {
    if (await file.exists()) await file.delete();
  }
}

/// A message for people when the page could not be read.
Failure scanFailure(Object e) => e is Failure ? e : UnexpectedFailure('The text on this page could not be read.', cause: e);

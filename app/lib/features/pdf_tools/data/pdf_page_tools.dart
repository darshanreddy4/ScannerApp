import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../reader/data/pdf_page_reader.dart';
import '../domain/pdf_forms.dart';
import 'forms/pdf_forms_engine.dart' show PdfFormException;
import 'security/pdf_model.dart';
import 'security/pdf_rewriter.dart';

// ------------------------------------------------------------------ cropping

/// Applies [insets] (by page index) as the visible area of the pages. The content outside stays in the file.
Uint8List cropPdfPages(Uint8List bytes, Map<int, CropInsets> insets) {
  final doc = readPdfDocument(bytes);
  final file = PdfReader(doc);
  final pages = file.pages();
  if (pages.isEmpty) throw const PdfFormException('This PDF has no pages.');
  for (final entry in insets.entries) {
    final index = entry.key;
    final cut = entry.value;
    if (index < 0 || index >= pages.length) throw const PdfFormException('A page to crop is not in this PDF.');
    if (cut.isNone) continue;
    if (!cut.isValid) throw const PdfFormException('Too much is cut off. Leave part of the page.');
    final page = pages[index];
    final geo = PageGeometry(page);
    var x0 = geo.x0, y0 = geo.y0, x1 = geo.x0 + geo.w, y1 = geo.y0 + geo.h;
    final w = geo.w, h = geo.h;
    // The insets are measured on the page as it is shown, so a turned page cuts different sides of its own box.
    switch (geo.rotation) {
      case 90:
        y0 += cut.left * h;
        x0 += cut.top * w;
        y1 -= cut.right * h;
        x1 -= cut.bottom * w;
      case 180:
        x1 -= cut.left * w;
        y0 += cut.top * h;
        x0 += cut.right * w;
        y1 -= cut.bottom * h;
      case 270:
        y1 -= cut.left * h;
        x1 -= cut.top * w;
        y0 += cut.right * h;
        x0 += cut.bottom * w;
      default:
        x0 += cut.left * w;
        y1 -= cut.top * h;
        x1 -= cut.right * w;
        y0 += cut.bottom * h;
    }
    String n(double v) => v.toStringAsFixed(3);
    page.dict['CropBox'] = PdfArray([PdfReal(n(x0)), PdfReal(n(y0)), PdfReal(n(x1)), PdfReal(n(y1))]);
  }
  return writePdfDocument(doc);
}

// ------------------------------------------------------------------ pictures inside a PDF

class RawPicture {
  const RawPicture({required this.bytes, required this.extension, required this.width, required this.height, required this.page});
  final Uint8List bytes;
  final String extension;
  final int width;
  final int height;

  /// First page (from 1) that shows it.
  final int page;
}

/// The pictures of a PDF as files' contents. JPEG pictures are taken out exactly as stored; the others are rebuilt as PNG.
/// [skipped] counts pictures in a form that cannot be rebuilt (for example black and white scans in fax compression).
({List<RawPicture> pictures, int skipped}) extractPdfPictures(Uint8List bytes, {int minSide = 24, int maxPictures = 400}) {
  final file = PdfReader(readPdfDocument(bytes));
  final pages = file.pages();
  final seen = <int>{};
  final out = <RawPicture>[];
  var skipped = 0;

  void scan(PdfDict? resources, int page, int depth) {
    final xobjects = file.dict(resources?['XObject']);
    if (xobjects == null || depth > 3) return;
    for (final raw in xobjects.entries.values) {
      if (out.length >= maxPictures) return;
      final id = raw is PdfRef ? raw.number : null;
      if (id != null && !seen.add(id)) continue;
      final obj = file.res(raw);
      if (obj is! PdfStream) continue;
      final subtype = file.res(obj.dict['Subtype']);
      if (subtype is PdfName && subtype.name == 'Form') {
        scan(file.dict(obj.dict['Resources']), page, depth + 1);
        continue;
      }
      if (subtype is! PdfName || subtype.name != 'Image') continue;
      final w = file.number(obj.dict['Width'])?.round() ?? 0, h = file.number(obj.dict['Height'])?.round() ?? 0;
      if (w < minSide || h < minSide) continue;
      if (file.res(obj.dict['ImageMask']) is PdfBool && (file.res(obj.dict['ImageMask'])! as PdfBool).value) continue;
      try {
        final picture = _rebuild(file, obj, raw, w, h, page);
        if (picture == null) {
          skipped++;
        } else {
          out.add(picture);
        }
      } catch (_) {
        skipped++;
      }
    }
  }

  for (var i = 0; i < pages.length; i++) {
    scan(pages[i].resources, i + 1, 0);
  }
  return (pictures: out, skipped: skipped);
}

List<String> _filterNames(PdfReader f, PdfDict d) => switch (f.res(d['Filter'])) {
  PdfName(:final name) => [name],
  PdfArray(:final items) => [
    for (final i in items)
      if (f.res(i) case PdfName(:final name)) name,
  ],
  _ => const [],
};

RawPicture? _rebuild(PdfReader f, PdfStream s, PdfObj raw, int w, int h, int page) {
  final filters = _filterNames(f, s.dict);
  final cs = _colorSpace(f, s.dict['ColorSpace']);
  if (filters.length == 1 && (filters.first == 'DCTDecode' || filters.first == 'DCT')) {
    if (cs?.components == 4) {
      final decoded = img.decodeJpg(s.data);
      if (decoded == null) return null;
      return RawPicture(bytes: Uint8List.fromList(img.encodePng(decoded)), extension: 'png', width: decoded.width, height: decoded.height, page: page);
    }
    return RawPicture(bytes: Uint8List.fromList(s.data), extension: 'jpg', width: w, height: h, page: page);
  }
  if (cs == null) return null;
  final data = f.decoded(raw);
  if (data == null) return null;
  final bpc = f.number(s.dict['BitsPerComponent'])?.round() ?? 8;
  final parms = f.dict(s.dict['DecodeParms']);
  final plain = _unpredict(
    data,
    parms == null ? 1 : (f.number(parms['Predictor'])?.round() ?? 1),
    w,
    cs.components,
    bpc,
    f.number(parms?['Columns'])?.round() ?? w,
  );
  if (plain == null) return null;

  final rowBytes = (w * cs.components * bpc + 7) ~/ 8;
  if (plain.length < rowBytes * h) return null;
  final alpha = _softMask(f, s, w, h);
  final image = img.Image(width: w, height: h, numChannels: alpha == null ? 3 : 4);
  for (var y = 0; y < h; y++) {
    final row = y * rowBytes;
    for (var x = 0; x < w; x++) {
      int r, g, b;
      if (bpc == 8) {
        final o = row + x * cs.components;
        (r, g, b) = cs.rgb(plain, o);
      } else if (cs.components == 1 && (bpc == 1 || bpc == 2 || bpc == 4)) {
        final bit = x * bpc;
        final value = (plain[row + (bit >> 3)] >> (8 - bpc - (bit & 7))) & ((1 << bpc) - 1);
        (r, g, b) = cs.fromSample(value, bpc);
      } else {
        return null;
      }
      if (alpha == null) {
        image.setPixelRgb(x, y, r, g, b);
      } else {
        image.setPixelRgba(x, y, r, g, b, alpha[y * w + x]);
      }
    }
  }
  return RawPicture(bytes: Uint8List.fromList(img.encodePng(image)), extension: 'png', width: w, height: h, page: page);
}

Uint8List? _softMask(PdfReader f, PdfStream s, int w, int h) {
  final mask = f.res(s.dict['SMask']);
  if (mask is! PdfStream) return null;
  if ((f.number(mask.dict['Width'])?.round() ?? 0) != w || (f.number(mask.dict['Height'])?.round() ?? 0) != h) return null;
  if ((f.number(mask.dict['BitsPerComponent'])?.round() ?? 8) != 8) return null;
  final data = f.decoded(s.dict['SMask']);
  if (data == null) return null;
  final parms = f.dict(mask.dict['DecodeParms']);
  final plain = _unpredict(data, parms == null ? 1 : (f.number(parms['Predictor'])?.round() ?? 1), w, 1, 8, f.number(parms?['Columns'])?.round() ?? w);
  return plain != null && plain.length >= w * h ? plain : null;
}

class _Space {
  _Space(this.components, this.rgb, this.fromSample);
  final int components;

  /// The colour of the pixel whose samples start at an offset.
  final (int, int, int) Function(Uint8List data, int offset) rgb;

  /// The colour of a one-sample pixel with fewer than 8 bits.
  final (int, int, int) Function(int value, int bits) fromSample;
}

_Space? _colorSpace(PdfReader f, PdfObj? raw, [int depth = 0]) {
  final o = f.res(raw);
  if (depth > 4) return null;
  (int, int, int) gray(int v, int bits) {
    final g = v * 255 ~/ ((1 << bits) - 1);
    return (g, g, g);
  }

  _Space grey() => _Space(1, (d, o) => (d[o], d[o], d[o]), gray);
  _Space rgbSpace() => _Space(3, (d, o) => (d[o], d[o + 1], d[o + 2]), (v, b) => (0, 0, 0));
  _Space cmyk() => _Space(4, (d, o) {
    final k = 255 - d[o + 3];
    return ((255 - d[o]) * k ~/ 255, (255 - d[o + 1]) * k ~/ 255, (255 - d[o + 2]) * k ~/ 255);
  }, (v, b) => (0, 0, 0));

  if (o is PdfName) {
    return switch (o.name) {
      'DeviceGray' || 'G' || 'CalGray' => grey(),
      'DeviceRGB' || 'RGB' || 'CalRGB' => rgbSpace(),
      'DeviceCMYK' || 'CMYK' => cmyk(),
      _ => null,
    };
  }
  if (o is PdfArray && o.items.isNotEmpty) {
    final kind = f.res(o.items.first);
    final name = kind is PdfName ? kind.name : '';
    switch (name) {
      case 'CalGray':
        return grey();
      case 'CalRGB':
        return rgbSpace();
      case 'ICCBased':
        final profile = o.items.length > 1 ? f.dict(o.items[1]) : null;
        return switch (f.number(profile?['N'])?.round()) {
          1 => grey(),
          3 => rgbSpace(),
          4 => cmyk(),
          _ => null,
        };
      case 'Indexed' || 'I':
        if (o.items.length < 4) return null;
        final base = _colorSpace(f, o.items[1], depth + 1);
        final hival = f.number(o.items[2])?.round() ?? 0;
        final table = switch (f.res(o.items[3])) {
          PdfString(:final bytes) => bytes,
          final PdfStream st => f.decoded(o.items[3]) ?? st.data,
          _ => null,
        };
        if (base == null || table == null || base.components == 0) return null;
        (int, int, int) lookup(int index) {
          final i = math.min(index, hival) * base.components;
          if (i + base.components > table.length) return (0, 0, 0);
          return base.rgb(table, i);
        }

        return _Space(1, (d, off) => lookup(d[off]), (v, b) => lookup(v));
    }
  }
  return null;
}

/// Undoes the row filters (PNG predictors) that PDF can apply before compression; null for ones that are not supported.
Uint8List? _unpredict(Uint8List data, int predictor, int width, int components, int bpc, int columns) {
  if (predictor <= 1) return data;
  if (predictor < 10) return null;
  final bpp = math.max(1, (components * bpc + 7) ~/ 8);
  final rowBytes = (columns * components * bpc + 7) ~/ 8;
  final rows = data.length ~/ (rowBytes + 1);
  final out = Uint8List(rows * rowBytes);
  for (var y = 0; y < rows; y++) {
    final type = data[y * (rowBytes + 1)];
    final src = y * (rowBytes + 1) + 1, dst = y * rowBytes;
    for (var x = 0; x < rowBytes; x++) {
      final raw = data[src + x];
      final left = x >= bpp ? out[dst + x - bpp] : 0;
      final up = y > 0 ? out[dst - rowBytes + x] : 0;
      final upLeft = (x >= bpp && y > 0) ? out[dst - rowBytes + x - bpp] : 0;
      final add = switch (type) {
        0 => 0,
        1 => left,
        2 => up,
        3 => (left + up) >> 1,
        4 => _paeth(left, up, upLeft),
        _ => -1,
      };
      if (add < 0) return null;
      out[dst + x] = (raw + add) & 255;
    }
  }
  return out;
}

int _paeth(int a, int b, int c) {
  final p = a + b - c;
  final pa = (p - a).abs(), pb = (p - b).abs(), pc = (p - c).abs();
  if (pa <= pb && pa <= pc) return a;
  return pb <= pc ? b : c;
}

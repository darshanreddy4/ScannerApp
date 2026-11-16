import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import '../../importer/data/docx_layout/docx_model.dart';
import '../domain/document_search.dart';
import 'pdf_text_extractor.dart' show TextRect;

/// Draws a Word file page by page the way Word does: page size and margins, paragraph looks, lists, tables with
/// shaded cells and borders, pictures. Each page becomes a PNG; where the words are is kept so a search can mark them.

const _lineK = 1.15;
const _pixelsWide = 1240.0;
const _maxPages = 60;

class DocxRenderedPage {
  const DocxRenderedPage(this.path, this.aspect);
  final String path;

  /// Width divided by height.
  final double aspect;
}

class _Place {
  _Place(this.page, this.painter, this.dx, this.dy, this.from, this.to);
  final int page;
  final TextPainter painter;

  /// Where the painter's own top left corner is on the page, in points.
  final double dx, dy;

  /// The part of the painter that is on this page, as heights from its top.
  final double from, to;
}

class DocxRendered {
  DocxRendered._(this.pages, this.plainText, this._places, this._painters, this._pageW, this._pageH);
  final List<DocxRenderedPage> pages;
  final String plainText;
  final List<_Place> _places;
  final List<TextPainter> _painters;
  final double _pageW, _pageH;

  bool get hasText => plainText.trim().isNotEmpty;

  /// Every place [query] occurs, in reading order.
  List<SearchHit> search(String query, {int limit = 2000}) {
    final pattern = searchPattern(query);
    if (pattern == null) return const [];
    final hits = <SearchHit>[];
    for (final place in _places) {
      final text = place.painter.text?.toPlainText() ?? '';
      final folded = foldForSearch(text);
      for (final m in pattern.allMatches(folded)) {
        final boxes = place.painter.getBoxesForSelection(TextSelection(baseOffset: m.start, extentOffset: m.end));
        final rects = <TextRect>[];
        for (final b in boxes) {
          final mid = (b.top + b.bottom) / 2;
          if (mid < place.from - 0.01 || mid > place.to + 0.01) continue;
          rects.add(TextRect((place.dx + b.left) / _pageW, (place.dy + b.top) / _pageH, (place.dx + b.right) / _pageW, (place.dy + b.bottom) / _pageH));
        }
        if (rects.isNotEmpty) hits.add(SearchHit(page: place.page, rects: _mergeLines(rects)));
        if (hits.length >= limit) return hits;
      }
    }
    return hits;
  }

  static List<TextRect> _mergeLines(List<TextRect> rects) {
    final out = <TextRect>[];
    for (final r in rects) {
      if (out.isNotEmpty && (out.last.centerY - r.centerY).abs() < 0.3 * r.height) {
        out[out.length - 1] = out.last.union(r);
      } else {
        out.add(r);
      }
    }
    return out;
  }

  void dispose() {
    for (final p in _painters) {
      p.dispose();
    }
  }
}

/// Lays out and draws the Word file at [path]; null when it is better shown another way (no readable text, or a file
/// this drawing cannot read).
Future<DocxRendered?> renderDocxPages({required String path, required String outDir, required String prefix}) async {
  final bitmaps = <DxImage, ui.Image>{};
  _Layouter? layout;
  try {
    final bytes = await File(path).readAsBytes();
    final doc = await Isolate.run(() => readDocxLayout(bytes));
    if (doc.blocks.isEmpty || doc.textLength == 0) return null;
    await _decodeImages(doc.blocks, bitmaps);
    layout = _Layouter(doc, bitmaps)..run();
    if (layout.pages.isEmpty) {
      layout.dispose();
      return null;
    }
    await Directory(outDir).create(recursive: true);
    final scale = _pixelsWide / layout.pageW;
    final w = _pixelsWide.round(), h = (layout.pageH * scale).round();
    final files = <DocxRenderedPage>[];
    for (var i = 0; i < layout.pages.length; i++) {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
      canvas.drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..color = const Color(0xFFFFFFFF));
      canvas.scale(scale);
      final page = layout.pages[i];
      for (final op in [...page.under, ...page.content, ...page.over]) {
        op(canvas);
      }
      final image = await recorder.endRecording().toImage(w, h);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) continue;
      final file = File(p.join(outDir, '$prefix-page${i + 1}.png'));
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
      files.add(DocxRenderedPage(file.path, layout.pageW / layout.pageH));
    }
    if (files.isEmpty) {
      layout.dispose();
      return null;
    }
    return DocxRendered._(files, layout.plain.join('\n'), layout.places, layout.painters, layout.pageW, layout.pageH);
  } catch (_) {
    layout?.dispose();
    return null;
  } finally {
    for (final b in bitmaps.values) {
      b.dispose();
    }
  }
}

Future<void> _decodeImages(List<DxBlock> blocks, Map<DxImage, ui.Image> out) async {
  Future<void> one(DxImage img) async {
    final bytes = img.bytes;
    if (bytes == null || out.containsKey(img)) return;
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final codec = await ui.instantiateImageCodecWithSize(
        buffer,
        getTargetSize: (w, h) =>
            w > 2000 ? ui.TargetImageSize(width: 2000, height: (h * 2000 / w).round().clamp(1, 1 << 14)) : ui.TargetImageSize(width: w, height: h),
      );
      out[img] = (await codec.getNextFrame()).image;
      codec.dispose();
    } catch (_) {
      // A picture that cannot be read is left out.
    }
  }

  for (final b in blocks) {
    switch (b) {
      case DxPara():
        for (final r in b.runs) {
          if (r.image != null) await one(r.image!);
        }
      case DxTable():
        for (final row in b.rows) {
          for (final c in row.cells) {
            await _decodeImages(c.blocks, out);
          }
        }
    }
  }
}

// ------------------------------------------------------------------------------------------------ boxes

class _Page {
  final under = <void Function(Canvas)>[];
  final content = <void Function(Canvas)>[];
  final over = <void Function(Canvas)>[];
}

abstract class _Box {
  double get height;
  void paint(Canvas c, double x, double y);
  void collect(List<_Place> out, int page, double x, double y);
}

class _Seg {
  _Seg(this.painter, this.dx, this.images);
  final TextPainter painter;
  final double dx;
  final List<ui.Image?> images;
}

class _Float {
  _Float(this.img, this.bitmap);
  final DxImage img;
  final ui.Image? bitmap;
}

class _ParaBox implements _Box {
  _ParaBox({
    required this.fmt,
    required this.width,
    required this.segs,
    required this.textLeft,
    required this.textH,
    required this.floats,
    this.label,
    this.labelDx = 0,
    this.labelDy = 0,
  });
  final DxParaFmt fmt;
  final double width, textLeft, textH;
  final List<_Seg> segs;
  final List<_Float> floats;
  final TextPainter? label;
  final double labelDx, labelDy;

  double get _topW => fmt.top == null || fmt.top!.isNone ? 0 : fmt.top!.widthPt;
  double get _bottomW => fmt.bottom == null || fmt.bottom!.isNone ? 0 : fmt.bottom!.widthPt;
  double get topExtra => _topW == 0 ? 0 : _topW + fmt.topSpace;
  double get bottomExtra => _bottomW == 0 ? 0 : _bottomW + fmt.bottomSpace;
  double get before => fmt.beforePt;
  double get after => fmt.afterPt;

  @override
  double get height => before + topExtra + textH + bottomExtra + after;

  late final List<double> boundaries = _bounds();

  List<double> _bounds() {
    final out = <double>[0];
    if (segs.length == 1) {
      for (final m in segs.first.painter.computeLineMetrics()) {
        final t = m.baseline - m.ascent;
        if (t > out.last + 0.5 && t < textH - 0.5) out.add(t);
      }
    }
    out.add(textH);
    return out;
  }

  @override
  void paint(Canvas c, double x, double y) => paintSlice(c, x, y, 0, textH, first: true, last: true);

  /// Draws the part of the paragraph from [from] to [to] (heights inside its text), with [y] where its top is.
  void paintSlice(Canvas c, double x, double y, double from, double to, {required bool first, required bool last}) {
    final top = y + (first ? before : 0);
    final sliceH = to - from;
    final bodyH = (first ? topExtra : 0) + sliceH + (last ? bottomExtra : 0);
    final l = x + math.max(0.0, fmt.leftPt - fmt.hangingPt);
    final r = x + width - math.max(0.0, fmt.rightPt);
    if (fmt.fill != null) c.drawRect(Rect.fromLTRB(l, top, r, top + bodyH), Paint()..color = Color(fmt.fill!));
    void line(DxBorder b, Offset a, Offset z) => c.drawLine(
      a,
      z,
      Paint()
        ..color = Color(b.color)
        ..strokeWidth = b.widthPt
        ..style = PaintingStyle.stroke,
    );
    if (first && _topW > 0) line(fmt.top!, Offset(l, top + _topW / 2), Offset(r, top + _topW / 2));
    if (last && _bottomW > 0) line(fmt.bottom!, Offset(l, top + bodyH - _bottomW / 2), Offset(r, top + bodyH - _bottomW / 2));
    if (fmt.left != null && !fmt.left!.isNone) {
      final bx = l - fmt.leftSpace - fmt.left!.widthPt / 2;
      line(fmt.left!, Offset(bx, top), Offset(bx, top + bodyH));
    }
    if (fmt.right != null && !fmt.right!.isNone) {
      final bx = r + fmt.rightSpace + fmt.right!.widthPt / 2;
      line(fmt.right!, Offset(bx, top), Offset(bx, top + bodyH));
    }

    final textTop = top + (first ? topExtra : 0);
    c.save();
    c.clipRect(Rect.fromLTRB(x - 24, textTop, x + width + 24, textTop + sliceH));
    for (final s in segs) {
      final origin = Offset(x + textLeft + s.dx, textTop - from);
      s.painter.paint(c, origin);
      final boxes = s.painter.inlinePlaceholderBoxes;
      if (boxes != null) {
        for (var i = 0; i < boxes.length && i < s.images.length; i++) {
          final img = s.images[i];
          if (img == null) continue;
          c.drawImageRect(
            img,
            Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
            boxes[i].toRect().shift(origin),
            Paint()..filterQuality = FilterQuality.medium,
          );
        }
      }
    }
    if (first && label != null) label!.paint(c, Offset(x + labelDx, textTop + labelDy));
    c.restore();
  }

  @override
  void collect(List<_Place> out, int page, double x, double y) {
    final textTop = y + before + topExtra;
    for (final s in segs) {
      out.add(_Place(page, s.painter, x + textLeft + s.dx, textTop, 0, double.infinity));
    }
  }
}

class _CellBox {
  _CellBox({
    required this.x,
    required this.w,
    required this.fill,
    required this.top,
    required this.left,
    required this.bottom,
    required this.right,
    required this.boxes,
    required this.contentH,
    required this.marL,
    required this.marT,
    required this.marB,
    required this.vAlign,
  });
  final double x, w, contentH, marL, marT, marB;
  final int? fill;
  final DxBorder? top, left, bottom, right;
  final List<_Box> boxes;
  final String vAlign;
}

class _RowBox implements _Box {
  _RowBox(this.cells, this.height);
  final List<_CellBox> cells;
  @override
  final double height;

  double _offset(_CellBox c) {
    final free = height - c.marT - c.marB - c.contentH;
    if (free <= 0) return 0;
    return switch (c.vAlign) {
      'center' => free / 2,
      'bottom' => free,
      _ => 0,
    };
  }

  @override
  void paint(Canvas c, double x, double y) {
    for (final cell in cells) {
      final rect = Rect.fromLTWH(x + cell.x, y, cell.w, height);
      if (cell.fill != null) c.drawRect(rect.inflate(0.25), Paint()..color = Color(cell.fill!));
    }
    for (final cell in cells) {
      final rect = Rect.fromLTWH(x + cell.x, y, cell.w, height);
      void edge(DxBorder? b, Offset a, Offset z) {
        if (b == null || b.isNone) return;
        c.drawLine(
          a,
          z,
          Paint()
            ..color = Color(b.color)
            ..strokeWidth = b.widthPt
            ..style = PaintingStyle.stroke,
        );
      }

      edge(cell.top, rect.topLeft, rect.topRight);
      edge(cell.bottom, rect.bottomLeft, rect.bottomRight);
      edge(cell.left, rect.topLeft, rect.bottomLeft);
      edge(cell.right, rect.topRight, rect.bottomRight);
      var cy = y + cell.marT + _offset(cell);
      for (final b in cell.boxes) {
        b.paint(c, x + cell.x + cell.marL, cy);
        cy += b.height;
      }
    }
  }

  @override
  void collect(List<_Place> out, int page, double x, double y) {
    for (final cell in cells) {
      var cy = y + cell.marT + _offset(cell);
      for (final b in cell.boxes) {
        b.collect(out, page, x + cell.x + cell.marL, cy);
        cy += b.height;
      }
    }
  }
}

class _TableBox implements _Box {
  _TableBox(this.rows, this.x0);
  final List<_RowBox> rows;

  /// Where the table starts, from the left of the room it was given.
  final double x0;

  @override
  double get height => rows.fold(0.0, (s, r) => s + r.height);

  @override
  void paint(Canvas c, double x, double y) {
    var cy = y;
    for (final r in rows) {
      r.paint(c, x + x0, cy);
      cy += r.height;
    }
  }

  @override
  void collect(List<_Place> out, int page, double x, double y) {
    var cy = y;
    for (final r in rows) {
      r.collect(out, page, x + x0, cy);
      cy += r.height;
    }
  }
}

// ------------------------------------------------------------------------------------------------ layout

/// Lets a test draw with a font it has loaded; the phone's own default is used otherwise.
@visibleForTesting
String? docxFontForTesting;

String? _family(String? f) {
  final n = f?.toLowerCase() ?? '';
  if (n.contains('courier') || n.contains('consolas') || n.contains('monaco') || n.contains('mono')) {
    return 'monospace';
  }
  if (n.contains('times') || n.contains('georgia') || n.contains('cambria') || n.contains('garamond') || n.contains('palatino')) {
    return 'serif';
  }
  return docxFontForTesting;
}

class _Layouter {
  _Layouter(this.doc, this.bitmaps)
    : pageW = doc.pageW,
      pageH = doc.pageH,
      left = doc.mL,
      contentW = math.max(72.0, doc.pageW - doc.mL - doc.mR),
      top = doc.mT,
      bottom = math.max(doc.mT + 36, doc.pageH - doc.mB);
  final DxDocument doc;
  final Map<DxImage, ui.Image> bitmaps;
  final double pageW, pageH, left, contentW, top, bottom;

  final pages = <_Page>[];
  final places = <_Place>[];
  final painters = <TextPainter>[];
  final plain = <String>[];

  double y = 0;
  bool _used = false;
  double _prevAfter = 0;
  String? _prevStyle;
  bool _prevContextual = false;

  void dispose() {
    for (final p in painters) {
      p.dispose();
    }
  }

  void _newPage() {
    pages.add(_Page());
    y = top;
    _used = false;
    _prevAfter = 0;
    _prevStyle = null;
  }

  void run() {
    _newPage();
    for (final b in doc.blocks) {
      if (pages.length > _maxPages) break;
      switch (b) {
        case DxPara():
          _placePara(b);
        case DxTable():
          _placeTable(b);
      }
    }
    if (pages.length > 1 && !_used) pages.removeLast();
    if (pages.length > _maxPages) pages.removeRange(_maxPages, pages.length);
  }

  // ---- paragraphs

  void _placePara(DxPara para) {
    // A page break inside the paragraph starts the rest on a new page.
    final parts = <List<DxRun>>[[]];
    for (final r in para.runs) {
      if (r.kind == 'pb') {
        parts.add([]);
      } else {
        parts.last.add(r);
      }
    }
    for (var k = 0; k < parts.length; k++) {
      if (k > 0) _newPage();
      final piece = k == 0 && parts.length == 1
          ? para
          : DxPara(
              runs: parts[k],
              fmt: para.fmt,
              markFmt: para.markFmt,
              label: k == 0 ? para.label : null,
              labelFmt: para.labelFmt,
              labelLeftPt: para.labelLeftPt,
            );
      final box = _makePara(piece, contentW, dark: false, maxH: bottom - top);
      plain.add(piece.text);
      _flowPara(box, piece, k == 0 && para.fmt.pageBreakBefore);
    }
  }

  void _flowPara(_ParaBox box, DxPara para, bool breakBefore) {
    if (breakBefore && _used) _newPage();
    final styleKey = para.fmt.styleId;
    // Paragraphs of one style with "don't add space between" sit close together.
    var before = box.before;
    if (para.fmt.contextual && _prevContextual && _prevStyle == styleKey) {
      y -= _prevAfter;
      before = 0;
    }
    if (para.fmt.keepNext && _used && y + box.height + 30 > bottom) _newPage();

    var consumed = 0.0;
    var first = true;
    final bounds = box.boundaries;
    while (true) {
      final head = first ? before + box.topExtra : 0.0;
      final remaining = box.textH - consumed;
      final tail = box.bottomExtra + box.after;
      final fits = y + head + remaining + tail <= bottom + 0.01;
      if (fits || pages.length > _maxPages) {
        _emit(box, para, consumed, box.textH, first: first, last: true, before: before);
        y += head + remaining + tail;
        break;
      }
      // Cut at the last line that fits.
      final room = bottom - y - head;
      var cut = consumed;
      for (final b in bounds) {
        if (b > consumed + 0.5 && b <= consumed + room + 0.01 && b < box.textH - 0.5) cut = b;
      }
      if (cut <= consumed + 0.5) {
        if (_used && y > top + 0.5) {
          _newPage();
          continue;
        }
        // Nothing fits even on an empty page: take the first line anyway.
        cut = bounds.firstWhere((b) => b > consumed + 0.5, orElse: () => box.textH);
        if (cut >= box.textH - 0.5) {
          _emit(box, para, consumed, box.textH, first: first, last: true, before: before);
          y += head + remaining + tail;
          break;
        }
      }
      _emit(box, para, consumed, cut, first: first, last: false, before: before);
      consumed = cut;
      first = false;
      _newPage();
    }
    _used = true;
    _prevAfter = box.after;
    _prevStyle = styleKey;
    _prevContextual = para.fmt.contextual;
  }

  void _emit(_ParaBox box, DxPara para, double from, double to, {required bool first, required bool last, required double before}) {
    final page = pages.length - 1;
    final y0 = y;
    final x = left;
    final saved = box.fmt;
    // The space before may have been taken away by the "same style" rule.
    final adjust = box.before - before;
    pages[page].content.add((c) => box.paintSlice(c, x, y0 - adjust, from, to, first: first, last: last));
    final textTop = y0 + (first ? before + box.topExtra : 0);
    for (final s in box.segs) {
      places.add(_Place(page, s.painter, x + box.textLeft + s.dx, textTop - from, from, to));
    }
    if (first) {
      for (final f in box.floats) {
        _placeFloat(f, page, y0 + before, x);
      }
    }
    assert(saved == box.fmt);
  }

  void _placeFloat(_Float f, int page, double paraY, double paraX) {
    final a = f.img.anchor!;
    final w = f.img.w, h = f.img.h;
    double relX(String from) => switch (from) {
      'page' => 0,
      'margin' || 'leftMargin' || 'insideMargin' => left,
      _ => paraX,
    };
    double relW(String from) => switch (from) {
      'page' => pageW,
      _ => contentW,
    };
    var fx = relX(a.hFrom);
    switch (a.hAlign) {
      case 'center':
        fx += (relW(a.hFrom) - w) / 2;
      case 'right' || 'outside':
        fx += relW(a.hFrom) - w;
      default:
        fx += a.hOff;
    }
    double relY(String from) => switch (from) {
      'page' => 0,
      'margin' || 'topMargin' => top,
      _ => paraY,
    };
    double relH(String from) => switch (from) {
      'page' => pageH,
      'margin' => bottom - top,
      _ => h,
    };
    var fy = relY(a.vFrom);
    switch (a.vAlign) {
      case 'center':
        fy += (relH(a.vFrom) - h) / 2;
      case 'bottom' || 'outside':
        fy += relH(a.vFrom) - h;
      default:
        fy += a.vOff;
    }
    final rect = Rect.fromLTWH(fx, fy, w, h);
    void draw(Canvas c) {
      final bm = f.bitmap;
      if (bm != null) {
        c.drawImageRect(bm, Rect.fromLTWH(0, 0, bm.width.toDouble(), bm.height.toDouble()), rect, Paint()..filterQuality = FilterQuality.medium);
      } else if (f.img.fill != null) {
        final paint = Paint()..color = Color(f.img.fill!);
        f.img.ellipse ? c.drawOval(rect, paint) : c.drawRect(rect, paint);
      }
    }

    (a.behind ? pages[page].under : pages[page].over).add(draw);
  }

  TextStyle _runStyle(DxRunFmt f, {required bool dark, double? mult}) {
    final deco = <TextDecoration>[if (f.underline) TextDecoration.underline, if (f.strike) TextDecoration.lineThrough];
    final size = f.vert != 0 ? f.sizePt * 0.65 : f.sizePt;
    return TextStyle(
      color: Color(f.color ?? (dark ? 0xFFFFFFFF : 0xFF000000)),
      fontSize: size,
      fontWeight: f.bold ? FontWeight.w700 : FontWeight.w400,
      fontStyle: f.italic ? FontStyle.italic : FontStyle.normal,
      decoration: deco.isEmpty ? TextDecoration.none : TextDecoration.combine(deco),
      letterSpacing: f.spacingPt == 0 ? null : f.spacingPt,
      fontFamily: _family(f.font),
      backgroundColor: f.highlight == null ? null : Color(f.highlight!),
      height: _lineK * (mult ?? 1),
      leadingDistribution: TextLeadingDistribution.even,
    );
  }

  ({InlineSpan span, List<PlaceholderDimensions> dims, List<ui.Image?> images}) _spanFor(
    List<DxRun> rs,
    DxParaFmt f, {
    required bool dark,
    required double maxW,
    required double maxH,
    double indent = 0,
    String prefix = '',
    DxRunFmt? prefixFmt,
  }) {
    final kids = <InlineSpan>[];
    final dims = <PlaceholderDimensions>[];
    final images = <ui.Image?>[];
    if (indent > 0) {
      kids.add(
        WidgetSpan(
          child: SizedBox(width: indent, height: 0.1),
          alignment: PlaceholderAlignment.bottom,
        ),
      );
      dims.add(PlaceholderDimensions(size: Size(indent, 0.1), alignment: ui.PlaceholderAlignment.bottom));
      images.add(null);
    }
    if (prefix.isNotEmpty && prefixFmt != null)
      kids.add(
        TextSpan(
          text: prefix,
          style: _runStyle(prefixFmt, dark: dark, mult: f.lineMult),
        ),
      );
    for (final r in rs) {
      switch (r.kind) {
        case 't':
          kids.add(
            TextSpan(
              text: r.fmt.caps ? r.text.toUpperCase() : r.text,
              style: _runStyle(r.fmt, dark: dark, mult: f.lineMult),
            ),
          );
        case 'tab':
          kids.add(
            TextSpan(
              text: '\u2003\u2003',
              style: _runStyle(r.fmt, dark: dark, mult: f.lineMult),
            ),
          );
        case 'br':
          kids.add(
            TextSpan(
              text: '\n',
              style: _runStyle(r.fmt, dark: dark, mult: f.lineMult),
            ),
          );
        case 'img':
          final img = r.image!;
          if (img.anchor != null) break;
          var w = img.w, h = img.h;
          final k = math.min(1.0, math.min(maxW / w, maxH / h));
          w *= k;
          h *= k;
          kids.add(
            WidgetSpan(
              child: SizedBox(width: w, height: h),
              alignment: PlaceholderAlignment.bottom,
            ),
          );
          dims.add(PlaceholderDimensions(size: Size(w, h), alignment: ui.PlaceholderAlignment.bottom));
          images.add(bitmaps[img]);
      }
    }
    return (span: TextSpan(children: kids), dims: dims, images: images);
  }

  TextPainter _painter(InlineSpan span, List<PlaceholderDimensions> dims, TextAlign align, TextDirection dir, StrutStyle? strut, {double? minW, double? maxW}) {
    final tp = TextPainter(text: span, textAlign: align, textDirection: dir, strutStyle: strut);
    if (dims.isNotEmpty) tp.setPlaceholderDimensions(dims);
    tp.layout(minWidth: minW ?? 0, maxWidth: maxW ?? double.infinity);
    painters.add(tp);
    return tp;
  }

  _ParaBox _makePara(DxPara p, double width, {required bool dark, required double maxH}) {
    final f = p.fmt;
    final textLeft = math.max(0.0, f.leftPt);
    final textW = math.max(8.0, width - textLeft - math.max(0.0, f.rightPt));
    final dir = f.bidi ? TextDirection.rtl : TextDirection.ltr;
    final align = switch (f.align) {
      'center' => TextAlign.center,
      'right' || 'end' => f.bidi ? TextAlign.end : TextAlign.right,
      'both' || 'distribute' => TextAlign.justify,
      _ => f.bidi ? TextAlign.start : TextAlign.left,
    };
    final flow = [
      for (final r in p.runs)
        if (!(r.kind == 'img' && r.image!.anchor != null)) r,
    ];
    final floats = [
      for (final r in p.runs)
        if (r.kind == 'img' && r.image!.anchor != null) _Float(r.image!, bitmaps[r.image!]),
    ];
    var maxSize = p.markFmt.sizePt;
    for (final r in flow) {
      if (r.kind == 't') maxSize = math.max(maxSize, r.fmt.sizePt);
    }
    final strut = f.lineExactPt != null
        ? StrutStyle(fontSize: maxSize, height: f.lineExactPt! / maxSize, forceStrutHeight: true, leading: 0, leadingDistribution: TextLeadingDistribution.even)
        : (f.lineAtLeastPt != null
              ? StrutStyle(fontSize: maxSize, height: f.lineAtLeastPt! / maxSize, leadingDistribution: TextLeadingDistribution.even)
              : null);

    final hangingLabel = p.label != null && f.hangingPt > 0;
    final prefix = p.label != null && !hangingLabel ? '${p.label}\u00A0' : '';
    final indent = f.firstLinePt > 0 && p.label == null ? f.firstLinePt : 0.0;

    var segs = <_Seg>[];
    if (flow.any((r) => r.kind == 'tab')) {
      segs = _tabSegments(flow, f, dark: dark, textLeft: textLeft, textW: textW, maxH: maxH, strut: strut, dir: dir) ?? [];
    }
    if (segs.isEmpty) {
      if (flow.isEmpty && prefix.isEmpty) {
        final s = TextSpan(
          text: ' ',
          style: _runStyle(p.markFmt, dark: dark, mult: f.lineMult),
        );
        segs = [_Seg(_painter(s, const [], align, dir, strut, minW: textW, maxW: textW), 0, const [])];
      } else {
        final built = _spanFor(flow, f, dark: dark, maxW: textW, maxH: maxH, indent: indent, prefix: prefix, prefixFmt: p.labelFmt ?? p.markFmt);
        segs = [_Seg(_painter(built.span, built.dims, align, dir, strut, minW: textW, maxW: textW), 0, built.images)];
      }
    }
    var textH = 0.0;
    for (final s in segs) {
      textH = math.max(textH, s.painter.height);
    }

    TextPainter? label;
    var labelDy = 0.0;
    if (hangingLabel) {
      label = _painter(
        TextSpan(
          text: p.label,
          style: _runStyle(p.labelFmt ?? p.markFmt, dark: dark, mult: f.lineMult),
        ),
        const [],
        TextAlign.left,
        TextDirection.ltr,
        null,
      );
      labelDy = segs.first.painter.computeDistanceToActualBaseline(TextBaseline.alphabetic) - label.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    }
    return _ParaBox(fmt: f, width: width, segs: segs, textLeft: textLeft, textH: textH, floats: floats, label: label, labelDx: p.labelLeftPt, labelDy: labelDy);
  }

  /// A line cut by tab stops: each stretch sits where its stop says. Null when it does not fit on one line.
  List<_Seg>? _tabSegments(
    List<DxRun> runs,
    DxParaFmt f, {
    required bool dark,
    required double textLeft,
    required double textW,
    required double maxH,
    required StrutStyle? strut,
    required TextDirection dir,
  }) {
    if (f.bidi || runs.any((r) => r.kind == 'br')) return null;
    final parts = <List<DxRun>>[[]];
    for (final r in runs) {
      if (r.kind == 'tab') {
        parts.add([]);
      } else {
        parts.last.add(r);
      }
    }
    final made = <TextPainter>[];
    final imgs = <List<ui.Image?>>[];
    for (final part in parts) {
      final built = _spanFor(part, f, dark: dark, maxW: textW, maxH: maxH);
      final tp = _painter(part.isEmpty ? const TextSpan(text: '') : built.span, built.dims, TextAlign.left, TextDirection.ltr, strut);
      made.add(tp);
      imgs.add(built.images);
    }
    final limit = textLeft + textW + 1;
    final xs = <double>[textLeft + (f.firstLinePt > 0 ? f.firstLinePt : 0)];
    var cur = xs.first + made.first.width;
    for (var i = 1; i < made.length; i++) {
      DxTab? stop;
      for (final t in f.tabs) {
        if (t.posPt > cur + 0.5) {
          stop = t;
          break;
        }
      }
      final pos = stop?.posPt ?? ((cur / 36).floor() + 1) * 36.0;
      final w = made[i].width;
      var x = switch (stop?.align) {
        'right' || 'end' => pos - w,
        'center' => pos - w / 2,
        _ => pos,
      };
      x = math.max(x, cur);
      if (x + w > limit) return null;
      xs.add(x);
      cur = x + w;
    }
    if (cur > limit) return null;
    return [for (var i = 0; i < made.length; i++) _Seg(made[i], xs[i] - textLeft, imgs[i])];
  }

  // ---- tables

  void _placeTable(DxTable t) {
    final box = _makeTable(t, contentW, dark: false);
    for (final row in box.rows) {
      for (final c in row.cells) {
        _collectPlain(c.boxes);
      }
    }
    for (final row in box.rows) {
      if (pages.length > _maxPages) return;
      if (y + row.height > bottom + 0.01 && _used && y > top + 0.5) _newPage();
      final page = pages.length - 1;
      final x = left + box.x0;
      final y0 = y;
      final tall = y0 + row.height > bottom + 0.01;
      pages[page].content.add((c) {
        if (tall) {
          c.save();
          c.clipRect(Rect.fromLTRB(0, 0, pageW, bottom));
        }
        row.paint(c, x, y0);
        if (tall) c.restore();
      });
      row.collect(places, page, x, y0);
      y += row.height;
      _used = true;
    }
    _prevAfter = 0;
    _prevStyle = null;
    _prevContextual = false;
  }

  void _collectPlain(List<_Box> boxes) {
    for (final b in boxes) {
      if (b is _ParaBox) {
        for (final s in b.segs) {
          plain.add(s.painter.text?.toPlainText().replaceAll('\uFFFC', '').trim() ?? '');
        }
      } else if (b is _TableBox) {
        for (final r in b.rows) {
          for (final c in r.cells) {
            _collectPlain(c.boxes);
          }
        }
      }
    }
  }

  List<_Box> _blocks(List<DxBlock> blocks, double width, {required bool dark}) => [
    for (final b in blocks)
      switch (b) {
        DxPara() => _makePara(b, width, dark: dark, maxH: bottom - top),
        DxTable() => _makeTable(b, width, dark: dark),
      },
  ];

  _TableBox _makeTable(DxTable t, double avail, {required bool dark}) {
    var grid = List<double>.of(t.grid);
    if (grid.isEmpty || grid.fold(0.0, (s, g) => s + g) <= 0) {
      final cols = t.rows.fold<int>(1, (m, r) => math.max(m, r.cells.fold<int>(0, (s, c) => s + c.span)));
      grid = List.filled(cols, avail / cols);
    }
    var total = grid.fold(0.0, (s, g) => s + g);
    var x0 = t.indentPt;
    if (t.align == 'center') x0 = (avail - total) / 2;
    if (t.align == 'right' || t.align == 'end') x0 = avail - total;
    x0 = math.max(0.0, x0);
    if (x0 + total > avail + 0.5) {
      final k = math.max(1.0, avail - x0) / total;
      grid = [for (final g in grid) g * k];
      total *= k;
    }
    final colX = <double>[0];
    for (final g in grid) {
      colX.add(colX.last + g);
    }

    final rows = <_RowBox>[];
    for (var ri = 0; ri < t.rows.length; ri++) {
      final row = t.rows[ri];
      final cells = <_CellBox>[];
      var col = 0;
      var rowH = 0.0;
      for (final cell in row.cells) {
        final start = math.min(col, grid.length);
        final end = math.min(col + cell.span, grid.length);
        final cw = colX[end] - colX[start];
        final marL = cell.marL ?? t.marL, marR = cell.marR ?? t.marR, marT = cell.marT ?? t.marT, marB = cell.marB ?? t.marB;
        final isDark = cell.fill != null && colorLuma(cell.fill!) < 0.45;
        final boxes = _blocks(cell.blocks, math.max(8.0, cw - marL - marR), dark: dark || isDark);
        final contentH = boxes.fold(0.0, (s, b) => s + b.height);
        rowH = math.max(rowH, contentH + marT + marB);
        final cb = cell.borders;
        DxBorder? pick(DxBorder? own, DxBorder? fromTable) => own ?? fromTable;
        final tb = t.borders;
        cells.add(
          _CellBox(
            x: colX[start],
            w: cw,
            fill: cell.fill,
            top: pick(cb?.top, ri == 0 ? tb.top : tb.insideH),
            bottom: pick(cb?.bottom, ri == t.rows.length - 1 ? tb.bottom : tb.insideH),
            left: pick(cb?.left, start == 0 ? tb.left : tb.insideV),
            right: pick(cb?.right, end >= grid.length ? tb.right : tb.insideV),
            boxes: boxes,
            contentH: contentH,
            marL: marL,
            marT: marT,
            marB: marB,
            vAlign: cell.vAlign,
          ),
        );
        col += cell.span;
      }
      final set = row.heightPt;
      if (set != null) rowH = row.exact ? set : math.max(rowH, set);
      rows.add(_RowBox(cells, rowH));
    }
    return _TableBox(rows, x0);
  }
}

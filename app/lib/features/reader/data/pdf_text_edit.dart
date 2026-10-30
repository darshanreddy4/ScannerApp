import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../pdf_tools/data/security/pdf_model.dart';
import '../../pdf_tools/data/security/pdf_rewriter.dart';
import 'pdf_page_reader.dart';

// ------------------------------------------------------------------ what can be edited

/// A line of text on a page that can be retyped or removed.
class PdfLine {
  const PdfLine({
    required this.id,
    required this.text,
    required this.box,
    required this.fontSize,
    required this.bold,
    required this.italic,
    required this.family,
    required this.rgb,
  });

  /// Position among the lines of its page.
  final int id;
  final String text;

  /// Where it is on the shown page, as shares.
  final TextRect box;

  /// In points on the page as it is shown.
  final double fontSize;
  final bool bold;
  final bool italic;

  /// sans, serif or mono.
  final String family;

  /// Colour as 0xRRGGBB.
  final int rgb;
}

class PdfPageEditInfo {
  const PdfPageEditInfo({required this.aspect, required this.widthPt, required this.lines, required this.editable});
  final double aspect;

  /// Width of the shown page in points.
  final double widthPt;
  final List<PdfLine> lines;

  /// False when the page's instructions use a format that cannot be changed; text can still be added.
  final bool editable;
}

/// Finds the lines of text of every page. Pure Dart, so it can run in an isolate.
List<PdfPageEditInfo> analyzePdfForEditing(Uint8List bytes, {int maxPages = 400}) {
  final file = PdfReader(readPdfDocument(bytes));
  final out = <PdfPageEditInfo>[];
  for (final page in file.pages().take(maxPages)) {
    try {
      final read = interpretPage(file, page);
      final lines = buildLines(read);
      final geo = read.geometry;
      final widthPt = (geo.rotation == 90 || geo.rotation == 270) ? geo.h : geo.w;
      out.add(PdfPageEditInfo(aspect: geo.aspect, widthPt: widthPt, lines: [for (final l in lines) l.line], editable: _hasDecodableContent(file, page)));
    } catch (_) {
      final geo = PageGeometry(page);
      out.add(PdfPageEditInfo(aspect: geo.aspect, widthPt: geo.w, lines: const [], editable: false));
    }
  }
  return out;
}

bool _hasDecodableContent(PdfReader file, PdfPageInfo page) {
  final c = file.res(page.dict['Contents']);
  final parts = c is PdfArray ? c.items : [if (c != null) page.dict['Contents']!];
  return parts.every((p) => file.decoded(p) != null);
}

class _Built {
  _Built(this.line, this.glyphIds, this.first);
  final PdfLine line;

  /// Indices into the page's glyph list.
  final List<int> glyphIds;

  /// The first letter that is not a space, which tells where a new text goes.
  final int first;
}

double _vScale(PdfMatrix m) => math.sqrt(m[2] * m[2] + m[3] * m[3]);

/// Groups the letters of a page into lines. Text in a different direction, a far gap or a new baseline starts a new line.
List<_Built> buildLines(PageInterpretation read) {
  final out = <_Built>[];
  final groups = <List<int>>[];
  List<int>? cur;
  PdfGlyph? prev;
  for (var i = 0; i < read.glyphs.length; i++) {
    final g = read.glyphs[i];
    if (g.inForm || !g.visible || g.op < 0 || (g.text.isEmpty && !g.isSpace)) continue;
    var same = false;
    final p = prev;
    if (cur != null && p != null) {
      final pm = p.matrix, gm = g.matrix;
      final angleP = math.atan2(pm[1], pm[0]), angleG = math.atan2(gm[1], gm[0]);
      final fs = math.max(g.fontSize * _vScale(gm), 0.01);
      final ca = math.cos(angleP), sa = math.sin(angleP);
      final dx = gm[4] - pm[4], dy = gm[5] - pm[5];
      final along = dx * ca + dy * sa;
      final across = -dx * sa + dy * ca;
      final advance = p.width / 1000 * p.fontSize * math.sqrt(pm[0] * pm[0] + pm[1] * pm[1]) * p.th;
      same = (angleP - angleG).abs() < 0.05 && across.abs() <= 0.5 * fs && along >= -0.5 * fs && along - advance <= 1.5 * fs;
    }
    if (!same) {
      cur = [];
      groups.add(cur);
    }
    cur!.add(i);
    prev = g;
  }
  for (final ids in groups) {
    final text = StringBuffer();
    PdfGlyph? last;
    var first = -1;
    var box = read.glyphs[ids.first].box;
    for (final i in ids) {
      final g = read.glyphs[i];
      if (last != null && !g.isSpace) {
        final fs = math.max(g.fontSize * _vScale(g.matrix), 0.01);
        final lm = last.matrix;
        final angle = math.atan2(lm[1], lm[0]);
        final dx = g.matrix[4] - lm[4], dy = g.matrix[5] - lm[5];
        final along = dx * math.cos(angle) + dy * math.sin(angle);
        final advance = last.width / 1000 * last.fontSize * math.sqrt(lm[0] * lm[0] + lm[1] * lm[1]) * last.th;
        final s = text.toString();
        if (along - advance > 0.22 * fs && s.isNotEmpty && !s.endsWith(' ')) text.write(' ');
      }
      var t = g.text;
      if (t.isNotEmpty && t.trim().isEmpty) t = ' ';
      text.write(t.split('').map((c) => _ligatureText[c] ?? c).join());
      if (first < 0 && !g.isSpace && g.text.isNotEmpty) first = i;
      box = PdfBox(math.min(box.left, g.box.left), math.min(box.bottom, g.box.bottom), math.max(box.right, g.box.right), math.max(box.top, g.box.top));
      last = g;
    }
    final trimmed = text.toString().trim();
    if (trimmed.isEmpty || first < 0) continue;
    final fg = read.glyphs[first];
    final scale = _vScale(fg.matrix);
    out.add(
      _Built(
        PdfLine(
          id: out.length,
          text: trimmed,
          box: read.geometry.normalize(box),
          fontSize: fg.fontSize * scale,
          bold: fg.font.isBold,
          italic: fg.font.isItalic,
          family: fg.font.isMono ? 'mono' : (fg.font.isSerif ? 'serif' : 'sans'),
          rgb: _rgbOf(fg.colorOps),
        ),
        ids,
        first,
      ),
    );
  }
  return out;
}

const _ligatureText = {'\uFB00': 'ff', '\uFB01': 'fi', '\uFB02': 'fl', '\uFB03': 'ffi', '\uFB04': 'ffl', '\u00AD': ''};

int _rgbOf(String ops) {
  final p = ops.split(' ');
  int c(double v) => (v.clamp(0.0, 1.0) * 255).round();
  try {
    if (ops.endsWith(' g') && p.length == 2) {
      final v = c(double.parse(p[0]));
      return (v << 16) | (v << 8) | v;
    }
    if (ops.endsWith('rg') && p.length == 4) return (c(double.parse(p[0])) << 16) | (c(double.parse(p[1])) << 8) | c(double.parse(p[2]));
    if (ops.endsWith(' k') && p.length == 5) {
      final k = 1 - double.parse(p[3]);
      return (c((1 - double.parse(p[0])) * k) << 16) | (c((1 - double.parse(p[1])) * k) << 8) | c((1 - double.parse(p[2])) * k);
    }
  } catch (_) {
    // Unreadable colours show as black.
  }
  return 0;
}

// ------------------------------------------------------------------ the changes

/// A line retyped (or removed, when [text] is empty).
class LineEdit {
  const LineEdit({required this.page, required this.line, required this.text});
  final int page;
  final int line;
  final String text;
}

/// New text placed on a page. [x] and [y] are shares of the shown page (from the top left) where the baseline starts.
class AddedText {
  const AddedText({
    required this.page,
    required this.x,
    required this.y,
    required this.text,
    required this.sizePt,
    this.rgb = 0,
    this.bold = false,
    this.italic = false,
    this.family = 'sans',
  });
  final int page;
  final double x;
  final double y;
  final String text;
  final double sizePt;
  final int rgb;
  final bool bold;
  final bool italic;
  final String family;
}

class PdfEditPlan {
  const PdfEditPlan({this.edits = const [], this.additions = const []});
  final List<LineEdit> edits;
  final List<AddedText> additions;
  bool get isEmpty => edits.isEmpty && additions.isEmpty;
}

const _cp1252Specials = {
  0x20AC: 0x80, 0x201A: 0x82, 0x0192: 0x83, 0x201E: 0x84, 0x2026: 0x85, 0x2020: 0x86, 0x2021: 0x87, 0x02C6: 0x88, 0x2030: 0x89, 0x0160: 0x8A, 0x2039: 0x8B, //
  0x0152: 0x8C, 0x017D: 0x8E, 0x2018: 0x91, 0x2019: 0x92, 0x201C: 0x93, 0x201D: 0x94, 0x2022: 0x95, 0x2013: 0x96, 0x2014: 0x97, 0x02DC: 0x98, 0x2122: 0x99,
  0x0161: 0x9A, 0x203A: 0x9B, 0x0153: 0x9C, 0x017E: 0x9E, 0x0178: 0x9F,
};

/// The characters of [text] that the built-in fonts cannot show (anything outside Western European letters and common symbols).
String unsupportedCharacters(String text) {
  final bad = <String>{};
  for (final r in text.runes) {
    if (r == 0x0A || r == 0x0D || r == 0x09) continue;
    if ((r >= 0x20 && r < 0x7F) || (r >= 0xA0 && r <= 0xFF) || _cp1252Specials.containsKey(r)) continue;
    bad.add(String.fromCharCode(r));
  }
  return bad.join();
}

Uint8List? winAnsiBytes(String text) {
  final out = <int>[];
  for (final r in text.runes) {
    if (r == 0x0A || r == 0x0D || r == 0x09) {
      out.add(0x20);
    } else if ((r >= 0x20 && r < 0x7F) || (r >= 0xA0 && r <= 0xFF)) {
      out.add(r);
    } else if (_cp1252Specials.containsKey(r)) {
      out.add(_cp1252Specials[r]!);
    } else {
      return null;
    }
  }
  return Uint8List.fromList(out);
}

String _hexOf(List<int> bytes) => '<${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}>';

String _n(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(4).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');

String _baseFont(String family, bool bold, bool italic) => switch (family) {
  'serif' => bold ? (italic ? 'Times-BoldItalic' : 'Times-Bold') : (italic ? 'Times-Italic' : 'Times-Roman'),
  'mono' => bold ? (italic ? 'Courier-BoldOblique' : 'Courier-Bold') : (italic ? 'Courier-Oblique' : 'Courier'),
  _ => bold ? (italic ? 'Helvetica-BoldOblique' : 'Helvetica-Bold') : (italic ? 'Helvetica-Oblique' : 'Helvetica'),
};

class PdfEditException implements Exception {
  const PdfEditException(this.message);
  final String message;
}

/// Applies [plan] to the PDF and returns the new file. Edited lines are taken out of the page and typed again in a built-in font
/// of the same kind (sans, serif or mono, bold, italic); other text on the page is not touched.
Uint8List applyPdfEdits(Uint8List bytes, PdfEditPlan plan) {
  final doc = readPdfDocument(bytes);
  final file = PdfReader(doc);
  final pages = file.pages();
  var nextObject = (doc.objects.keys.isEmpty ? 0 : doc.objects.keys.reduce(math.max)) + 1;
  int addObject(PdfObj o) {
    doc.objects[nextObject] = o;
    return nextObject++;
  }

  PdfStream stream(Uint8List data) => PdfStream(PdfDict({'Filter': const PdfName('FlateDecode')}), Uint8List.fromList(zlib.encode(data)));

  final editPages = {for (final e in plan.edits) e.page, for (final a in plan.additions) a.page};
  for (final pageNo in editPages) {
    if (pageNo < 0 || pageNo >= pages.length) continue;
    final info = pages[pageNo];
    final read = interpretPage(file, info);
    final built = buildLines(read);
    final fonts = <String, String>{}; // base font name -> resource name
    String fontName(String family, bool bold, bool italic) => fonts.putIfAbsent(_baseFont(family, bold, italic), () => 'SVF${fonts.length + 1}');

    final remove = <int>{};
    final drawn = StringBuffer();
    for (final e in plan.edits.where((e) => e.page == pageNo)) {
      if (e.line < 0 || e.line >= built.length) continue;
      final b = built[e.line];
      remove.addAll(b.glyphIds);
      final text = e.text.trim();
      if (text.isEmpty) continue;
      final encoded = winAnsiBytes(text);
      if (encoded == null)
        throw PdfEditException('The text "${unsupportedCharacters(text)}" cannot be placed in a PDF. Use letters, numbers and common symbols.');
      final g = read.glyphs[b.first];
      final m = g.matrix;
      final name = fontName(b.line.family, b.line.bold, b.line.italic);
      final e0 = g.rise * m[2] + m[4], f0 = g.rise * m[3] + m[5];
      drawn.write(
        'q ${g.colorOps} BT /$name ${_n(g.fontSize)} Tf ${_n(g.th * 100)} Tz ${_n(m[0])} ${_n(m[1])} ${_n(m[2])} ${_n(m[3])} ${_n(e0)} ${_n(f0)} Tm ${_hexOf(encoded)} Tj ET Q\n',
      );
    }
    for (final a in plan.additions.where((a) => a.page == pageNo)) {
      final lines = a.text.split(RegExp(r'\r?\n')).where((l) => l.isNotEmpty).toList();
      if (lines.isEmpty) continue;
      final name = fontName(a.family, a.bold, a.italic);
      final (ux, uy) = read.geometry.toPageUnits(a.x, a.y);
      final angle = read.geometry.rotation * math.pi / 180;
      final c = math.cos(angle), s = math.sin(angle);
      final color = '${_n(((a.rgb >> 16) & 255) / 255)} ${_n(((a.rgb >> 8) & 255) / 255)} ${_n((a.rgb & 255) / 255)} rg';
      drawn.write('q $color BT /$name ${_n(a.sizePt)} Tf ${_n(a.sizePt * 1.2)} TL ${_n(c)} ${_n(s)} ${_n(-s)} ${_n(c)} ${_n(ux)} ${_n(uy)} Tm\n');
      for (var i = 0; i < lines.length; i++) {
        final encoded = winAnsiBytes(lines[i]);
        if (encoded == null)
          throw PdfEditException('The text "${unsupportedCharacters(lines[i])}" cannot be placed in a PDF. Use letters, numbers and common symbols.');
        drawn.write('${i == 0 ? '' : 'T* '}${_hexOf(encoded)} Tj\n');
      }
      drawn.write('ET Q\n');
    }

    // The page's own instructions, with the removed letters turned into plain spacing.
    final existing = file.res(info.dict['Contents']);
    final refs = existing is PdfArray ? [...existing.items] : [if (existing != null) info.dict['Contents']!];
    var contents = refs;
    if (remove.isNotEmpty) {
      if (!_hasDecodableContent(file, info)) throw const PdfEditException('This page uses a format that cannot be edited.');
      contents = [PdfRef(addObject(stream(_withoutGlyphs(read, remove))), 0)];
    }
    if (drawn.isNotEmpty) contents = [...contents, PdfRef(addObject(stream(Uint8List.fromList(latin1.encode(drawn.toString())))), 0)];
    info.dict['Contents'] = PdfArray(contents);

    if (fonts.isNotEmpty) {
      final resources = PdfDict(Map.of(info.resources?.entries ?? const <String, PdfObj>{}));
      final fontDict = PdfDict(Map.of(file.dict(resources['Font'])?.entries ?? const <String, PdfObj>{}));
      fonts.forEach((base, name) {
        fontDict[name] = PdfRef(
          addObject(
            PdfDict({
              'Type': const PdfName('Font'),
              'Subtype': const PdfName('Type1'),
              'BaseFont': PdfName(base),
              'Encoding': const PdfName('WinAnsiEncoding'),
            }),
          ),
          0,
        );
      });
      resources['Font'] = fontDict;
      info.dict['Resources'] = resources;
    }
  }
  return writePdfDocument(doc);
}

/// The page's instructions with the given letters (indices into the page's glyph list) replaced by equal spacing, so other text stays where it was.
Uint8List _withoutGlyphs(PageInterpretation read, Set<int> remove) {
  final byOp = <int, Set<int>>{};
  for (final i in remove) {
    final op = read.glyphs[i].op;
    if (op >= 0) (byOp[op] ??= {}).add(i);
  }
  final out = BytesBuilder();
  var last = 0;
  for (final op in byOp.keys.toList()..sort()) {
    final show = read.ops[op];
    out.add(read.data.sublist(last, show.start));
    out.add(latin1.encode(_replacement(read, op, byOp[op]!)));
    last = show.end;
  }
  out.add(read.data.sublist(last));
  return out.toBytes();
}

String _replacement(PageInterpretation read, int opIndex, Set<int> removed) {
  final show = read.ops[opIndex];
  final lexer = ContentLexer(read.data.sublist(show.start, show.end));
  final operands = <Object?>[];
  while (!lexer.done) {
    final v = lexer.next();
    if (v is ContentOp) break;
    if (v is! ContentSkipped) operands.add(v);
  }
  final items = show.kind == 'TJ' ? (operands.last! as List) : [operands.last];
  final prefix = switch (show.kind) {
    "'" => 'T* ',
    '"' => '${_n((operands[0]! as num).toDouble())} Tw ${_n((operands[1]! as num).toDouble())} Tc T* ',
    _ => '',
  };
  // The letters of this instruction, by string and position in it.
  final byItem = <int, List<MapEntry<int, PdfGlyph>>>{};
  for (var i = 0; i < read.glyphs.length; i++) {
    final g = read.glyphs[i];
    if (g.op == opIndex) (byItem[g.item] ??= []).add(MapEntry(i, g));
  }

  final b = StringBuffer('[');
  var chunk = <int>[];
  var adjust = 0.0;
  void flushChunk() {
    if (chunk.isEmpty) return;
    b.write('${_hexOf(chunk)} ');
    chunk = [];
  }

  void flushAdjust() {
    if (adjust == 0) return;
    b.write('${_n(adjust)} ');
    adjust = 0;
  }

  for (var j = 0; j < items.length; j++) {
    final item = items[j];
    if (item is Uint8List) {
      final glyphs = byItem[show.kind == 'TJ' ? j : 0] ?? const [];
      final step = glyphs.isEmpty || !glyphs.first.value.font.twoByte ? 1 : 2;
      var at = 0;
      for (final entry in glyphs) {
        if (at + step > item.length) break;
        final bytes = item.sublist(at, at + step);
        at += step;
        final g = entry.value;
        if (removed.contains(entry.key) && g.fontSize != 0) {
          flushChunk();
          adjust -= g.width + (g.tc + (g.isSpace ? g.tw : 0)) * 1000 / g.fontSize;
        } else {
          flushAdjust();
          chunk.addAll(bytes);
        }
      }
      if (at < item.length) {
        flushAdjust();
        chunk.addAll(item.sublist(at));
      }
    } else if (item is num) {
      flushChunk();
      adjust += item.toDouble();
    }
  }
  flushChunk();
  flushAdjust();
  b.write(']');
  return '$prefix$b TJ';
}

import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../pdf_tools/data/security/pdf_model.dart';
import '../../pdf_tools/data/security/pdf_rewriter.dart';

/// A box on a page as shares of the page (0 to 1), measured from the top left.
class TextRect {
  const TextRect(this.left, this.top, this.right, this.bottom);
  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => bottom - top;
  double get centerY => (top + bottom) / 2;

  TextRect union(TextRect o) => TextRect(math.min(left, o.left), math.min(top, o.top), math.max(right, o.right), math.max(bottom, o.bottom));
}

// ------------------------------------------------------------------ file access

class PdfPageInfo {
  PdfPageInfo(this.dict, this.resources, this.box, this.rotate);
  final PdfDict dict;
  final PdfDict? resources;
  final List<double> box;
  final int rotate;
}

class PdfReader {
  PdfReader(this.doc);
  final PdfDoc doc;

  PdfObj? res(PdfObj? o) {
    var x = o;
    for (var i = 0; i < 24 && x is PdfRef; i++) {
      x = doc.objects[x.number];
    }
    return x is PdfRef ? null : x;
  }

  PdfDict? dict(PdfObj? o) {
    final x = res(o);
    return switch (x) {
      PdfDict() => x,
      PdfStream() => x.dict,
      _ => null,
    };
  }

  List<PdfObj> list(PdfObj? o) {
    final x = res(o);
    return x is PdfArray ? x.items : const [];
  }

  double? number(PdfObj? o) => switch (res(o)) {
    PdfInt(:final value) => value.toDouble(),
    PdfReal(:final text) => double.tryParse(text),
    _ => null,
  };

  List<double>? numbers(PdfObj? o, int count) {
    final items = list(o);
    if (items.length < count) return null;
    final out = <double>[];
    for (var i = 0; i < count; i++) {
      final v = number(items[i]);
      if (v == null) return null;
      out.add(v);
    }
    return out;
  }

  /// Every page in reading order, with the settings pages inherit from the page tree.
  List<PdfPageInfo> pages() {
    final out = <PdfPageInfo>[];
    final root = dict(doc.trailer['Root']);
    final tree = dict(root?['Pages']);
    final seen = HashSet<PdfDict>.identity();

    void walk(PdfDict node, PdfDict? res0, List<double>? box0, int rot0, int depth) {
      if (depth > 40 || !seen.add(node)) return;
      final resources = dict(node['Resources']) ?? res0;
      final box = numbers(node['CropBox'], 4) ?? numbers(node['MediaBox'], 4) ?? box0;
      final rot = number(node['Rotate'])?.round() ?? rot0;
      final kids = res(node['Kids']);
      if (kids is PdfArray && node.nameOf('Type') != 'Page') {
        for (final k in kids.items) {
          final d = dict(k);
          if (d != null) walk(d, resources, box, rot, depth + 1);
        }
      } else {
        out.add(PdfPageInfo(node, resources, box ?? const [0, 0, 612, 792], rot));
      }
    }

    if (tree != null) walk(tree, null, null, 0, 0);
    if (out.isEmpty) {
      // A damaged page tree: pages are found by their type, in file order.
      final keys = doc.objects.keys.toList()..sort();
      for (final k in keys) {
        final d = doc.objects[k];
        if (d is PdfDict && d.nameOf('Type') == 'Page') {
          out.add(
            PdfPageInfo(
              d,
              dict(d['Resources']),
              numbers(d['CropBox'], 4) ?? numbers(d['MediaBox'], 4) ?? const [0, 0, 612, 792],
              number(d['Rotate'])?.round() ?? 0,
            ),
          );
        }
      }
    }
    return out;
  }

  /// The bytes of a stream with its compression taken off; null for formats that are not text (such as JPEG).
  Uint8List? decoded(PdfObj? o) {
    final s = res(o);
    if (s is! PdfStream) return null;
    var data = s.data;
    final filters = switch (res(s.dict['Filter'])) {
      PdfName(:final name) => [name],
      PdfArray(:final items) => [
        for (final i in items)
          if (res(i) case PdfName(:final name)) name,
      ],
      _ => const <String>[],
    };
    for (final f in filters) {
      switch (f) {
        case 'FlateDecode' || 'Fl':
          final inflated = inflateBytes(data);
          if (inflated == null) return null;
          data = inflated;
        case 'ASCIIHexDecode' || 'AHx':
          data = _asciiHex(data);
        case 'ASCII85Decode' || 'A85':
          data = _ascii85(data);
        case 'Crypt':
          break;
        default:
          return null;
      }
    }
    return data;
  }
}

Uint8List? inflateBytes(Uint8List data) {
  try {
    return Uint8List.fromList(zlib.decode(data));
  } catch (_) {
    try {
      return Uint8List.fromList(ZLibCodec(raw: true).decode(data.sublist(2)));
    } catch (_) {
      return null;
    }
  }
}

Uint8List _asciiHex(Uint8List data) {
  final out = BytesBuilder();
  int? high;
  for (final c in data) {
    if (c == 0x3E) break;
    final v = hexValue(c);
    if (v < 0) continue;
    if (high == null) {
      high = v;
    } else {
      out.addByte(high * 16 + v);
      high = null;
    }
  }
  if (high != null) out.addByte(high * 16);
  return out.toBytes();
}

Uint8List _ascii85(Uint8List data) {
  final out = BytesBuilder();
  final group = <int>[];
  void flush(int count) {
    var v = 0;
    for (var i = 0; i < 5; i++) {
      v = v * 85 + (i < group.length ? group[i] : 84);
    }
    final bytes = [(v >> 24) & 255, (v >> 16) & 255, (v >> 8) & 255, v & 255];
    out.add(bytes.sublist(0, count));
    group.clear();
  }

  var i = 0;
  if (data.length > 1 && data[0] == 0x3C && data[1] == 0x7E) i = 2;
  for (; i < data.length; i++) {
    final c = data[i];
    if (c == 0x7E) break;
    if (c == 0x7A && group.isEmpty) {
      out.add(const [0, 0, 0, 0]);
      continue;
    }
    if (c < 0x21 || c > 0x75) continue;
    group.add(c - 0x21);
    if (group.length == 5) flush(4);
  }
  if (group.length > 1) {
    final n = group.length;
    flush(n - 1);
  }
  return out.toBytes();
}

int hexValue(int c) {
  if (c >= 0x30 && c <= 0x39) return c - 0x30;
  if (c >= 0x41 && c <= 0x46) return c - 0x41 + 10;
  if (c >= 0x61 && c <= 0x66) return c - 0x61 + 10;
  return -1;
}

// ------------------------------------------------------------------ matrices

typedef PdfMatrix = List<double>;

PdfMatrix mulMatrix(PdfMatrix a, PdfMatrix b) => [
  a[0] * b[0] + a[1] * b[2],
  a[0] * b[1] + a[1] * b[3],
  a[2] * b[0] + a[3] * b[2],
  a[2] * b[1] + a[3] * b[3],
  a[4] * b[0] + a[5] * b[2] + b[4],
  a[4] * b[1] + a[5] * b[3] + b[5],
];

const identityMatrix = <double>[1, 0, 0, 1, 0, 0];

// ------------------------------------------------------------------ content stream

class ContentOp {
  const ContentOp(this.name);
  final String name;
}

/// Splits a page's drawing instructions into operands and operators.
class ContentLexer {
  ContentLexer(this.b);
  final Uint8List b;
  int pos = 0;

  bool get done => pos >= b.length;

  static bool _ws(int c) => c == 0 || c == 9 || c == 10 || c == 12 || c == 13 || c == 32;
  static bool _delim(int c) => c == 0x28 || c == 0x29 || c == 0x3C || c == 0x3E || c == 0x5B || c == 0x5D || c == 0x7B || c == 0x7D || c == 0x2F || c == 0x25;

  void _skipSpace() {
    while (pos < b.length) {
      final c = b[pos];
      if (_ws(c)) {
        pos++;
      } else if (c == 0x25) {
        while (pos < b.length && b[pos] != 10 && b[pos] != 13) {
          pos++;
        }
      } else {
        break;
      }
    }
  }

  /// Where the next token starts (after white space and comments).
  int mark() {
    _skipSpace();
    return pos;
  }

  /// The next operand (number, name, string, array) or an [ContentOp]; null at the end.
  Object? next() {
    _skipSpace();
    if (pos >= b.length) return null;
    final c = b[pos];
    if (c == 0x2F) return _name();
    if (c == 0x28) return _literal();
    if (c == 0x3C) {
      if (pos + 1 < b.length && b[pos + 1] == 0x3C) {
        _skipDict();
        return const ContentSkipped();
      }
      return _hexString();
    }
    if (c == 0x5B) {
      pos++;
      final items = <Object?>[];
      while (true) {
        _skipSpace();
        if (pos >= b.length) break;
        if (b[pos] == 0x5D) {
          pos++;
          break;
        }
        final v = next();
        if (v is ContentOp) break;
        items.add(v);
      }
      return items;
    }
    if (c == 0x29 || c == 0x3E || c == 0x5D || c == 0x7B || c == 0x7D) {
      pos++;
      return const ContentSkipped();
    }
    final start = pos;
    while (pos < b.length && !_ws(b[pos]) && !_delim(b[pos])) {
      pos++;
    }
    final word = latin1.decode(b.sublist(start, pos));
    final n = num.tryParse(word);
    if (n != null) return n.toDouble();
    switch (word) {
      case 'true':
        return true;
      case 'false':
        return false;
      case 'null':
        return null;
    }
    if (word.isEmpty) {
      pos++;
      return const ContentSkipped();
    }
    return ContentOp(word);
  }

  String _name() {
    pos++;
    final start = pos;
    while (pos < b.length && !_ws(b[pos]) && !_delim(b[pos])) {
      pos++;
    }
    final raw = latin1.decode(b.sublist(start, pos));
    if (!raw.contains('#')) return raw;
    return raw.replaceAllMapped(RegExp(r'#([0-9A-Fa-f]{2})'), (m) => String.fromCharCode(int.parse(m[1]!, radix: 16)));
  }

  Uint8List _literal() {
    pos++;
    final out = BytesBuilder();
    var depth = 1;
    while (pos < b.length) {
      final c = b[pos++];
      if (c == 0x5C) {
        if (pos >= b.length) break;
        final e = b[pos++];
        switch (e) {
          case 0x6E:
            out.addByte(10);
          case 0x72:
            out.addByte(13);
          case 0x74:
            out.addByte(9);
          case 0x62:
            out.addByte(8);
          case 0x66:
            out.addByte(12);
          case 0x0D:
            if (pos < b.length && b[pos] == 0x0A) pos++;
          case 0x0A:
            break;
          default:
            if (e >= 0x30 && e <= 0x37) {
              var v = e - 0x30;
              for (var i = 0; i < 2 && pos < b.length && b[pos] >= 0x30 && b[pos] <= 0x37; i++) {
                v = v * 8 + (b[pos++] - 0x30);
              }
              out.addByte(v & 255);
            } else {
              out.addByte(e);
            }
        }
      } else if (c == 0x28) {
        depth++;
        out.addByte(c);
      } else if (c == 0x29) {
        depth--;
        if (depth == 0) break;
        out.addByte(c);
      } else {
        out.addByte(c);
      }
    }
    return out.toBytes();
  }

  Uint8List _hexString() {
    pos++;
    final out = BytesBuilder();
    int? high;
    while (pos < b.length) {
      final c = b[pos++];
      if (c == 0x3E) break;
      final v = hexValue(c);
      if (v < 0) continue;
      if (high == null) {
        high = v;
      } else {
        out.addByte(high * 16 + v);
        high = null;
      }
    }
    if (high != null) out.addByte(high * 16);
    return out.toBytes();
  }

  void _skipDict() {
    var depth = 0;
    while (pos < b.length) {
      final c = b[pos];
      if (c == 0x3C && pos + 1 < b.length && b[pos + 1] == 0x3C) {
        depth++;
        pos += 2;
      } else if (c == 0x3E && pos + 1 < b.length && b[pos + 1] == 0x3E) {
        depth--;
        pos += 2;
        if (depth == 0) return;
      } else if (c == 0x28) {
        _literal();
      } else if (c == 0x3C) {
        _hexString();
      } else {
        pos++;
      }
    }
  }

  /// Moves past an inline picture (BI ... ID data EI), which holds no text.
  void skipInlineImage() {
    // The picture's settings run up to the ID keyword.
    while (pos < b.length) {
      final v = next();
      if (v is ContentOp && v.name == 'ID') break;
    }
    if (pos < b.length && _ws(b[pos])) pos++;
    while (pos + 1 < b.length) {
      if (b[pos] == 0x45 && b[pos + 1] == 0x49 && (pos == 0 || _ws(b[pos - 1])) && (pos + 2 >= b.length || _ws(b[pos + 2]))) {
        pos += 2;
        return;
      }
      pos++;
    }
    pos = b.length;
  }
}

class ContentSkipped {
  const ContentSkipped();
}

// ------------------------------------------------------------------ fonts

class FontGlyph {
  const FontGlyph(this.code, this.text, this.width, this.isSpace);

  /// The code as written in the text string (one or two bytes).
  final int code;
  final String text;

  /// In thousandths of the font size.
  final double width;
  final bool isSpace;
}

class PdfFont {
  PdfFont({required this.twoByte, required this.toUnicode, required this.encoding, required this.widthOf, this.baseFont = ''});
  final bool twoByte;

  /// The font's name, such as ABCDEF+Arial-BoldMT.
  final String baseFont;

  String get _lower => baseFont.toLowerCase();
  bool get isBold => _lower.contains('bold') || _lower.contains('black') || _lower.contains('heavy') || _lower.contains('semibold');
  bool get isItalic => _lower.contains('italic') || _lower.contains('oblique');
  bool get isMono => _lower.contains('courier') || _lower.contains('mono') || _lower.contains('consolas');
  bool get isSerif =>
      !isMono &&
      (_lower.contains('times') ||
          (_lower.contains('serif') && !_lower.contains('sans')) ||
          _lower.contains('georgia') ||
          _lower.contains('garamond') ||
          _lower.contains('cambria') ||
          _lower.contains('palatino') ||
          _lower.contains('book'));

  final Map<int, String> toUnicode;
  final List<String>? encoding;
  final double Function(int code) widthOf;

  List<FontGlyph> decode(Uint8List s) {
    final out = <FontGlyph>[];
    if (twoByte) {
      for (var i = 0; i + 1 < s.length; i += 2) {
        final code = (s[i] << 8) | s[i + 1];
        out.add(FontGlyph(code, toUnicode[code] ?? '', widthOf(code), false));
      }
    } else {
      for (final code in s) {
        final text = toUnicode[code] ?? (encoding != null ? encoding![code] : winAnsiChar(code));
        out.add(FontGlyph(code, text, widthOf(code), code == 32));
      }
    }
    return out;
  }
}

String winAnsiChar(int code) {
  if (code < 32 || code == 127) return '';
  if (code >= 0x80 && code <= 0x9F) return cp1252High[code - 0x80];
  return String.fromCharCode(code);
}

const cp1252High = [
  '\u20AC', '', '\u201A', '\u0192', '\u201E', '\u2026', '\u2020', '\u2021', '\u02C6', '\u2030', '\u0160', '\u2039', '\u0152', '', '\u017D', '', //
  '', '\u2018', '\u2019', '\u201C', '\u201D', '\u2022', '\u2013', '\u2014', '\u02DC', '\u2122', '\u0161', '\u203A', '\u0153', '', '\u017E', '\u0178',
];

const _macRomanHigh =
    '\u00C4\u00C5\u00C7\u00C9\u00D1\u00D6\u00DC\u00E1\u00E0\u00E2\u00E4\u00E3\u00E5\u00E7\u00E9\u00E8'
    '\u00EA\u00EB\u00ED\u00EC\u00EE\u00EF\u00F1\u00F3\u00F2\u00F4\u00F6\u00F5\u00FA\u00F9\u00FB\u00FC'
    '\u2020\u00B0\u00A2\u00A3\u00A7\u2022\u00B6\u00DF\u00AE\u00A9\u2122\u00B4\u00A8\u2260\u00C6\u00D8'
    '\u221E\u00B1\u2264\u2265\u00A5\u00B5\u2202\u2211\u220F\u03C0\u222B\u00AA\u00BA\u03A9\u00E6\u00F8'
    '\u00BF\u00A1\u00AC\u221A\u0192\u2248\u2206\u00AB\u00BB\u2026\u00A0\u00C0\u00C3\u00D5\u0152\u0153'
    '\u2013\u2014\u201C\u201D\u2018\u2019\u00F7\u25CA\u00FF\u0178\u2044\u20AC\u2039\u203A\uFB01\uFB02'
    '\u2021\u00B7\u201A\u201E\u2030\u00C2\u00CA\u00C1\u00CB\u00C8\u00CD\u00CE\u00CF\u00CC\u00D3\u00D4'
    '\uF8FF\u00D2\u00DA\u00DB\u00D9\u0131\u02C6\u02DC\u00AF\u02D8\u02D9\u02DA\u00B8\u02DD\u02DB\u02C7';

const _glyphNames = <String, String>{
  'space': ' ',
  'exclam': '!',
  'quotedbl': '"',
  'numbersign': '#',
  'dollar': r'$',
  'percent': '%',
  'ampersand': '&',
  'quotesingle': "'",
  'quoteright': '\u2019', //
  'quoteleft': '\u2018', 'parenleft': '(', 'parenright': ')', 'asterisk': '*', 'plus': '+', 'comma': ',', 'hyphen': '-', 'minus': '\u2212', 'period': '.',
  'slash': '/', 'colon': ':', 'semicolon': ';', 'less': '<', 'equal': '=', 'greater': '>', 'question': '?', 'at': '@', 'bracketleft': '[', 'backslash': r'\',
  'bracketright': ']', 'asciicircum': '^', 'underscore': '_', 'grave': '`', 'braceleft': '{', 'bar': '|', 'braceright': '}', 'asciitilde': '~',
  'zero': '0', 'one': '1', 'two': '2', 'three': '3', 'four': '4', 'five': '5', 'six': '6', 'seven': '7', 'eight': '8', 'nine': '9',
  'bullet': '\u2022', 'endash': '\u2013', 'emdash': '\u2014', 'quotedblleft': '\u201C', 'quotedblright': '\u201D', 'quotesinglbase': '\u201A',
  'quotedblbase': '\u201E',
  'ellipsis': '\u2026',
  'fi': 'fi',
  'fl': 'fl',
  'ff': 'ff',
  'ffi': 'ffi',
  'ffl': 'ffl',
  'nbspace': ' ',
  'nonbreakingspace': ' ',
  'sfthyphen': '',
  'copyright': '\u00A9', 'registered': '\u00AE', 'trademark': '\u2122', 'degree': '\u00B0', 'section': '\u00A7', 'paragraph': '\u00B6', 'dagger': '\u2020',
  'Euro': '\u20AC',
  'sterling': '\u00A3',
  'yen': '\u00A5',
  'cent': '\u00A2',
  'currency': '\u00A4',
  'multiply': '\u00D7',
  'divide': '\u00F7',
  'plusminus': '\u00B1',
  'germandbls': '\u00DF', 'ae': '\u00E6', 'AE': '\u00C6', 'oslash': '\u00F8', 'Oslash': '\u00D8', 'aring': '\u00E5', 'Aring': '\u00C5', 'ccedilla': '\u00E7',
  'eacute': '\u00E9', 'egrave': '\u00E8', 'agrave': '\u00E0', 'aacute': '\u00E1', 'adieresis': '\u00E4', 'odieresis': '\u00F6', 'udieresis': '\u00FC',
  'Adieresis': '\u00C4', 'Odieresis': '\u00D6', 'Udieresis': '\u00DC', 'ntilde': '\u00F1', 'iacute': '\u00ED', 'oacute': '\u00F3', 'uacute': '\u00FA',
};

String? _unicodeForGlyphName(String name) {
  final known = _glyphNames[name];
  if (known != null) return known;
  if (name.length == 1) return name;
  final uni = RegExp(r'^uni([0-9A-Fa-f]{4})').firstMatch(name);
  if (uni != null) return String.fromCharCode(int.parse(uni[1]!, radix: 16));
  final u = RegExp(r'^u([0-9A-Fa-f]{4,6})$').firstMatch(name);
  if (u != null) return String.fromCharCode(int.parse(u[1]!, radix: 16));
  final dot = name.indexOf('.');
  if (dot > 0) return _unicodeForGlyphName(name.substring(0, dot));
  return null;
}

const _helveticaWidths = [
  278, 278, 355, 556, 556, 889, 667, 191, 333, 333, 389, 584, 278, 333, 278, 278, 556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 278, 278, 584, 584, 584, //
  556, 1015, 667, 667, 722, 722, 667, 611, 778, 722, 278, 500, 667, 556, 833, 722, 778, 667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 278, 278,
  278, 469, 556, 333, 556, 556, 500, 556, 556, 278, 556, 556, 222, 222, 500, 222, 833, 556, 556, 556, 556, 333, 500, 278, 556, 500, 722, 500, 500, 500,
  334, 260, 334, 584,
];

const _timesWidths = [
  250, 333, 408, 500, 500, 833, 778, 180, 333, 333, 500, 564, 250, 333, 250, 278, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 278, 278, 564, 564, 564, //
  444, 921, 722, 667, 667, 722, 611, 556, 722, 722, 333, 389, 722, 611, 889, 722, 722, 556, 722, 667, 556, 611, 722, 722, 944, 722, 722, 611, 333, 278,
  333, 469, 500, 333, 444, 500, 444, 500, 444, 333, 500, 500, 278, 278, 500, 278, 778, 500, 500, 500, 500, 333, 389, 278, 500, 500, 722, 500, 500, 444,
  480, 200, 480, 541,
];

double Function(int) standardWidths(String baseFont) {
  final n = baseFont.toLowerCase();
  if (n.contains('courier') || n.contains('mono') || n.contains('consolas')) return (_) => 600;
  final serif =
      n.contains('times') ||
      (n.contains('serif') && !n.contains('sans')) ||
      n.contains('georgia') ||
      n.contains('garamond') ||
      n.contains('cambria') ||
      n.contains('palatino');
  final table = serif ? _timesWidths : _helveticaWidths;
  final other = serif ? 500.0 : 556.0;
  return (code) => code >= 32 && code <= 126 ? table[code - 32].toDouble() : other;
}

Map<int, String> _parseToUnicode(Uint8List bytes) {
  final text = latin1.decode(bytes, allowInvalid: true);
  final map = <int, String>{};
  String utf16(String hex) {
    final h = hex.replaceAll(RegExp(r'\s'), '');
    final units = <int>[];
    for (var i = 0; i + 3 < h.length + 1 && i + 4 <= h.length; i += 4) {
      units.add(int.parse(h.substring(i, i + 4), radix: 16));
    }
    if (units.isEmpty && h.length >= 2) units.add(int.parse(h.substring(0, 2), radix: 16));
    return String.fromCharCodes(units);
  }

  int code(String hex) => int.tryParse(hex.replaceAll(RegExp(r'\s'), ''), radix: 16) ?? -1;
  final token = RegExp(r'\[|\]|<([^>]*)>');
  for (final m in RegExp(r'beginbfchar(.*?)endbfchar', dotAll: true).allMatches(text)) {
    final t = token.allMatches(m[1]!).map((x) => x.group(1)).whereType<String>().toList();
    for (var i = 0; i + 1 < t.length; i += 2) {
      final c = code(t[i]);
      if (c >= 0) map[c] = utf16(t[i + 1]);
    }
  }
  for (final m in RegExp(r'beginbfrange(.*?)endbfrange', dotAll: true).allMatches(text)) {
    final toks = token.allMatches(m[1]!).toList();
    var i = 0;
    while (i + 2 < toks.length) {
      final lo = toks[i].group(1), hi = toks[i + 1].group(1);
      if (lo == null || hi == null) {
        i++;
        continue;
      }
      final from = code(lo), to = code(hi);
      final third = toks[i + 2];
      if (third.group(0) == '[') {
        var j = i + 3;
        var c = from;
        while (j < toks.length && toks[j].group(0) != ']') {
          final d = toks[j].group(1);
          if (d != null && c >= 0 && c <= to) map[c] = utf16(d);
          c++;
          j++;
        }
        i = j + 1;
      } else {
        final dst = third.group(1);
        if (dst != null && from >= 0 && to >= from && to - from < 0x10000) {
          final base = utf16(dst);
          if (base.isNotEmpty) {
            final prefix = base.substring(0, base.length - 1);
            final last = base.codeUnitAt(base.length - 1);
            for (var c = from; c <= to; c++) {
              map[c] = prefix + String.fromCharCode(last + (c - from));
            }
          }
        }
        i += 3;
      }
    }
  }
  return map;
}

PdfFont? buildPdfFont(PdfReader file, PdfDict dict) {
  final subtype = dict.nameOf('Subtype') ?? '';
  final baseFont = (file.res(dict['BaseFont']) as PdfName?)?.name ?? '';
  final toUni = file.decoded(dict['ToUnicode']);
  final toUnicode = toUni == null ? <int, String>{} : _parseToUnicode(toUni);

  if (subtype == 'Type0') {
    final desc = file.dict(file.list(dict['DescendantFonts']).firstOrNull);
    final dw = file.number(desc?['DW']) ?? 1000;
    final widths = <int, double>{};
    final w = file.list(desc?['W']);
    var i = 0;
    while (i < w.length) {
      final first = file.number(w[i])?.toInt();
      if (first == null || i + 1 >= w.length) break;
      final next = file.res(w[i + 1]);
      if (next is PdfArray) {
        for (var k = 0; k < next.items.length; k++) {
          widths[first + k] = file.number(next.items[k]) ?? dw;
        }
        i += 2;
      } else {
        final last = file.number(w[i + 1])?.toInt();
        final width = i + 2 < w.length ? file.number(w[i + 2]) : null;
        if (last == null || width == null) break;
        if (last - first < 0x10000) {
          for (var c = first; c <= last; c++) {
            widths[c] = width;
          }
        }
        i += 3;
      }
    }
    return PdfFont(twoByte: true, toUnicode: toUnicode, encoding: null, widthOf: (c) => widths[c] ?? dw, baseFont: baseFont);
  }

  // One byte per letter: the encoding gives each code a glyph name, and the ToUnicode map (when there is one) wins.
  List<String>? encoding;
  final enc = file.res(dict['Encoding']);
  String? baseName;
  PdfDict? differencesFrom;
  if (enc is PdfName) {
    baseName = enc.name;
  } else if (enc is PdfDict) {
    baseName = enc.nameOf('BaseEncoding');
    differencesFrom = enc;
  }
  if (baseName == 'MacRomanEncoding' || differencesFrom != null || baseName != null) {
    encoding = List.generate(256, (c) {
      if (baseName == 'MacRomanEncoding' && c >= 0x80) return _macRomanHigh[c - 0x80];
      return winAnsiChar(c);
    });
  }
  if (differencesFrom != null) {
    var code = 0;
    for (final item in file.list(differencesFrom['Differences'])) {
      final v = file.res(item);
      if (v is PdfInt) {
        code = v.value;
      } else if (v is PdfName) {
        if (code >= 0 && code < 256) {
          final u = _unicodeForGlyphName(v.name);
          if (u != null) encoding![code] = u;
        }
        code++;
      }
    }
  }

  final firstChar = file.number(dict['FirstChar'])?.toInt() ?? 0;
  final widthList = [for (final x in file.list(dict['Widths'])) file.number(x) ?? 0.0];
  final descriptor = file.dict(dict['FontDescriptor']);
  final missing = file.number(descriptor?['MissingWidth']);
  final standard = standardWidths(baseFont);
  double widthOf(int code) {
    final i = code - firstChar;
    if (widthList.isNotEmpty && i >= 0 && i < widthList.length) {
      final w = widthList[i];
      if (w > 0 || missing != null) return w > 0 ? w : missing!;
    }
    return widthList.isEmpty ? standard(code) : (missing ?? standard(code));
  }

  return PdfFont(twoByte: false, toUnicode: toUnicode, encoding: encoding, widthOf: widthOf, baseFont: baseFont);
}

// ------------------------------------------------------------------ reading a page

const _ligatures = {'\uFB00': 'ff', '\uFB01': 'fi', '\uFB02': 'fl', '\uFB03': 'ffi', '\uFB04': 'ffl', '\uFB05': 'st', '\uFB06': 'st', '\u00AD': ''};

/// A box in the page's own units (points), with the origin at the bottom left.
class PdfBox {
  const PdfBox(this.left, this.bottom, this.right, this.top);
  final double left;
  final double bottom;
  final double right;
  final double top;
  double get height => top - bottom;
  double get width => right - left;
  double get centerY => (top + bottom) / 2;
}

/// One letter as drawn on a page, with where it is in the page's instructions so it can be taken out again.
class PdfGlyph {
  const PdfGlyph({
    required this.op,
    required this.item,
    required this.index,
    required this.code,
    required this.text,
    required this.width,
    required this.isSpace,
    required this.box,
    required this.matrix,
    required this.fontSize,
    required this.th,
    required this.tc,
    required this.tw,
    required this.rise,
    required this.font,
    required this.colorOps,
    required this.visible,
    required this.inForm,
  });

  /// Which text instruction (in [PageInterpretation.ops]) draws it, which string of it, and which code of that string.
  final int op;
  final int item;
  final int index;
  final int code;
  final String text;

  /// In thousandths of the font size.
  final double width;
  final bool isSpace;
  final PdfBox box;

  /// Text space to page space at this letter (before the font size is applied).
  final PdfMatrix matrix;
  final double fontSize;
  final double th;
  final double tc;
  final double tw;
  final double rise;
  final PdfFont font;

  /// How the letter is coloured, as instructions such as "0 0 0 rg".
  final String colorOps;

  /// False for the invisible text layer of scanned pages.
  final bool visible;

  /// Letters drawn inside a form object cannot be taken out of the page's own instructions.
  final bool inForm;
}

/// A text-showing instruction in the page's instructions, by position in the (decoded) bytes.
class ShowOp {
  const ShowOp({required this.start, required this.end, required this.kind});
  final int start;
  final int end;

  /// Tj, TJ, ' or ".
  final String kind;
}

/// Everything a page draws as text.
class PageInterpretation {
  PageInterpretation({
    required this.page,
    required this.data,
    required this.ops,
    required this.glyphs,
    required this.text,
    required this.boxes,
    required this.geometry,
  });
  final PdfPageInfo page;

  /// The page's drawing instructions, decoded and joined.
  final Uint8List data;
  final List<ShowOp> ops;
  final List<PdfGlyph> glyphs;

  /// Searchable text with a box for each unit; spaces added between words have none.
  final String text;
  final List<PdfBox?> boxes;
  final PageGeometry geometry;
}

/// Where the page's visible area is and how it is turned, to go between page units and shares of the shown page.
class PageGeometry {
  PageGeometry(PdfPageInfo page)
    : x0 = math.min(page.box[0], page.box[2]),
      y0 = math.min(page.box[1], page.box[3]),
      w = (page.box[2] - page.box[0]).abs() <= 0 ? 612.0 : (page.box[2] - page.box[0]).abs(),
      h = (page.box[3] - page.box[1]).abs() <= 0 ? 792.0 : (page.box[3] - page.box[1]).abs(),
      rotation = ((page.rotate % 360) + 360) % 360;

  final double x0;
  final double y0;
  final double w;
  final double h;

  /// Clockwise, 0, 90, 180 or 270.
  final int rotation;

  double get aspect => (rotation == 90 || rotation == 270) ? h / w : w / h;

  (double, double) _turn(double u, double v) => switch (rotation) {
    90 => (1 - v, u),
    180 => (1 - u, 1 - v),
    270 => (v, 1 - u),
    _ => (u, v),
  };

  /// A box in page units as a share of the page as it is shown.
  TextRect normalize(PdfBox b) {
    final u1 = (b.left - x0) / w, u2 = (b.right - x0) / w;
    final v1 = 1 - (b.top - y0) / h, v2 = 1 - (b.bottom - y0) / h;
    final a = _turn(u1, v1), c = _turn(u2, v2);
    return TextRect(
      math.min(a.$1, c.$1).clamp(0.0, 1.0),
      math.min(a.$2, c.$2).clamp(0.0, 1.0),
      math.max(a.$1, c.$1).clamp(0.0, 1.0),
      math.max(a.$2, c.$2).clamp(0.0, 1.0),
    );
  }

  /// A point of the shown page (shares, from the top left) in page units.
  (double, double) toPageUnits(double u, double v) {
    final (u0, v0) = switch (rotation) {
      90 => (v, 1 - u),
      180 => (1 - u, 1 - v),
      270 => (1 - v, u),
      _ => (u, v),
    };
    return (x0 + u0 * w, y0 + (1 - v0) * h);
  }
}

/// Where a letter starts and which way the line runs, in page units, to tell new words and lines apart (also for turned text).
class LetterFlow {
  const LetterFlow({required this.x, required this.y, required this.angle, required this.advance, required this.size});
  final double x;
  final double y;
  final double angle;

  /// How far the letter moves the pen along the line.
  final double advance;

  /// The font size on the page.
  final double size;
}

class PageTextBuilder {
  final text = StringBuffer();
  final boxes = <PdfBox?>[];
  LetterFlow? _prev;

  void add(String raw, PdfBox box, LetterFlow flow) {
    if (raw.isEmpty) return;
    final isSpace = raw.trim().isEmpty;
    final p = _prev;
    if (p != null && !isSpace && text.isNotEmpty) {
      final dx = flow.x - p.x, dy = flow.y - p.y;
      final along = dx * math.cos(p.angle) + dy * math.sin(p.angle);
      final across = -dx * math.sin(p.angle) + dy * math.cos(p.angle);
      final size = math.max(flow.size, 0.01);
      final newLine = across.abs() > 0.5 * math.max(size, p.size);
      final gap = along - p.advance > 0.22 * size;
      final back = along < -2 * size;
      if (newLine || gap || back) {
        final s = text.toString();
        if (s.isNotEmpty && s[s.length - 1] != ' ') {
          text.write(' ');
          boxes.add(null);
        }
      }
    }
    var out = raw;
    if (out.split('').any(_ligatures.containsKey)) {
      out = out.split('').map((c) => _ligatures[c] ?? c).join();
    }
    if (out.isEmpty) return;
    text.write(isSpace ? ' ' : out);
    final units = isSpace ? 1 : out.length;
    final spanX = box.right - box.left, spanY = box.top - box.bottom;
    // Each unit of a letter that stands for several (like a ligature) gets its share along the longer side of the box.
    final horizontal = spanX >= spanY;
    for (var i = 0; i < units; i++) {
      if (isSpace) {
        boxes.add(box);
      } else if (horizontal) {
        final w = spanX / units;
        boxes.add(PdfBox(box.left + w * i, box.bottom, box.left + w * (i + 1), box.top));
      } else {
        final h = spanY / units;
        boxes.add(PdfBox(box.left, box.bottom + h * i, box.right, box.bottom + h * (i + 1)));
      }
    }
    if (!isSpace) _prev = flow;
  }
}

class GraphicsState {
  GraphicsState();
  PdfMatrix ctm = identityMatrix;
  PdfFont? font;
  double fontSize = 0;
  double tc = 0;
  double tw = 0;
  double th = 1;
  double tl = 0;
  double rise = 0;
  int renderMode = 0;
  String fill = '0 g';

  GraphicsState clone() => GraphicsState()
    ..ctm = ctm
    ..font = font
    ..fontSize = fontSize
    ..tc = tc
    ..tw = tw
    ..th = th
    ..tl = tl
    ..rise = rise
    ..renderMode = renderMode
    ..fill = fill;
}

String _num(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(4).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');

/// Reads what a page draws as text, with the place of every letter and where each one sits in the page's instructions.
PageInterpretation interpretPage(PdfReader file, PdfPageInfo page) {
  final builder = PageTextBuilder();
  final fonts = HashMap<PdfDict, PdfFont?>.identity();
  final glyphs = <PdfGlyph>[];
  final ops = <ShowOp>[];

  Uint8List content() {
    final c = file.res(page.dict['Contents']);
    final parts = c is PdfArray ? c.items : [if (c != null) page.dict['Contents']!];
    final out = BytesBuilder();
    for (final p in parts) {
      final d = file.decoded(p);
      if (d != null) {
        out.add(d);
        out.addByte(10);
      }
    }
    return out.toBytes();
  }

  void run(Uint8List data, PdfDict? resources, GraphicsState start, int depth) {
    final lexer = ContentLexer(data);
    var gs = start;
    final stack = <GraphicsState>[];
    var tm = identityMatrix, tlm = identityMatrix;
    final args = <Object?>[];
    final fontDict = file.dict(resources?['Font']);
    final xobjects = file.dict(resources?['XObject']);
    var argsStart = 0;
    var opIndex = -1;

    PdfFont? fontNamed(String name) {
      final d = file.dict(fontDict?[name]);
      if (d == null) return null;
      return fonts.putIfAbsent(d, () {
        try {
          return buildPdfFont(file, d);
        } catch (_) {
          return null;
        }
      });
    }

    double arg(int i) => i < args.length && args[i] is num ? (args[i] as num).toDouble() : 0.0;

    void show(Uint8List s, int item) {
      final font = gs.font;
      if (font == null || gs.fontSize == 0) return;
      var index = 0;
      for (final g in font.decode(s)) {
        final w0 = g.width / 1000;
        final fs = gs.fontSize;
        final m = mulMatrix(tm, gs.ctm);
        final x1 = w0 * fs * gs.th;
        final yLow = -0.2 * fs + gs.rise, yHigh = 0.8 * fs + gs.rise;
        double px(double x, double y) => x * m[0] + y * m[2] + m[4];
        double py(double x, double y) => x * m[1] + y * m[3] + m[5];
        final xs = [px(0, yLow), px(x1, yLow), px(0, yHigh), px(x1, yHigh)];
        final ys = [py(0, yLow), py(x1, yLow), py(0, yHigh), py(x1, yHigh)];
        final box = PdfBox(xs.reduce(math.min), ys.reduce(math.min), xs.reduce(math.max), ys.reduce(math.max));
        final flow = LetterFlow(
          x: m[4] + gs.rise * m[2],
          y: m[5] + gs.rise * m[3],
          angle: math.atan2(m[1], m[0]),
          advance: w0 * fs * gs.th * math.sqrt(m[0] * m[0] + m[1] * m[1]),
          size: fs * math.sqrt(m[2] * m[2] + m[3] * m[3]),
        );
        builder.add(g.text, box, flow);
        glyphs.add(
          PdfGlyph(
            op: depth == 0 ? opIndex : -1,
            item: item,
            index: index,
            code: g.code,
            text: g.text,
            width: g.width,
            isSpace: g.isSpace,
            box: box,
            matrix: m,
            fontSize: fs,
            th: gs.th,
            tc: gs.tc,
            tw: gs.tw,
            rise: gs.rise,
            font: font,
            colorOps: gs.fill,
            visible: gs.renderMode != 3,
            inForm: depth > 0,
          ),
        );
        index++;
        final tx = (w0 * fs + gs.tc + (g.isSpace ? gs.tw : 0)) * gs.th;
        tm = mulMatrix([1, 0, 0, 1, tx, 0], tm);
      }
    }

    void nextLine(double tx, double ty) {
      tlm = mulMatrix([1, 0, 0, 1, tx, ty], tlm);
      tm = tlm;
    }

    void record(String kind, int start, int end) {
      if (depth != 0) {
        opIndex = -1;
        return;
      }
      ops.add(ShowOp(start: start, end: end, kind: kind));
      opIndex = ops.length - 1;
    }

    for (var guard = 0; !lexer.done && guard < 4000000; guard++) {
      final tokenStart = lexer.mark();
      final v = lexer.next();
      if (v is ContentSkipped) continue;
      if (v is! ContentOp) {
        if (args.isEmpty) argsStart = tokenStart;
        args.add(v);
        if (args.length > 64) args.removeAt(0);
        continue;
      }
      final opStart = args.isEmpty ? tokenStart : argsStart, opEnd = lexer.pos;
      switch (v.name) {
        case 'q':
          stack.add(gs.clone());
        case 'Q':
          if (stack.isNotEmpty) gs = stack.removeLast();
        case 'cm':
          if (args.length >= 6) gs.ctm = mulMatrix([arg(0), arg(1), arg(2), arg(3), arg(4), arg(5)], gs.ctm);
        case 'BT':
          tm = identityMatrix;
          tlm = identityMatrix;
        case 'Tf':
          if (args.isNotEmpty && args[0] is String) gs.font = fontNamed(args[0]! as String);
          gs.fontSize = arg(1);
        case 'Tc':
          gs.tc = arg(0);
        case 'Tw':
          gs.tw = arg(0);
        case 'Tz':
          gs.th = arg(0) / 100;
        case 'TL':
          gs.tl = arg(0);
        case 'Ts':
          gs.rise = arg(0);
        case 'Tr':
          gs.renderMode = arg(0).toInt();
        case 'g':
          if (args.isNotEmpty) gs.fill = '${_num(arg(0))} g';
        case 'rg':
          if (args.length >= 3) gs.fill = '${_num(arg(0))} ${_num(arg(1))} ${_num(arg(2))} rg';
        case 'k':
          if (args.length >= 4) gs.fill = '${_num(arg(0))} ${_num(arg(1))} ${_num(arg(2))} ${_num(arg(3))} k';
        case 'Td':
          nextLine(arg(0), arg(1));
        case 'TD':
          gs.tl = -arg(1);
          nextLine(arg(0), arg(1));
        case 'Tm':
          if (args.length >= 6) {
            tm = [arg(0), arg(1), arg(2), arg(3), arg(4), arg(5)];
            tlm = tm;
          }
        case 'T*':
          nextLine(0, -gs.tl);
        case 'Tj':
          if (args.isNotEmpty && args.last is Uint8List) {
            record('Tj', opStart, opEnd);
            show(args.last! as Uint8List, 0);
          }
        case "'":
          nextLine(0, -gs.tl);
          if (args.isNotEmpty && args.last is Uint8List) {
            record("'", opStart, opEnd);
            show(args.last! as Uint8List, 0);
          }
        case '"':
          if (args.length >= 3) {
            gs.tw = arg(0);
            gs.tc = arg(1);
            nextLine(0, -gs.tl);
            if (args.last is Uint8List) {
              record('"', opStart, opEnd);
              show(args.last! as Uint8List, 0);
            }
          }
        case 'TJ':
          if (args.isNotEmpty && args.last is List) {
            record('TJ', opStart, opEnd);
            final items = args.last! as List;
            for (var j = 0; j < items.length; j++) {
              final item = items[j];
              if (item is Uint8List) {
                show(item, j);
              } else if (item is num) {
                tm = mulMatrix([1, 0, 0, 1, -item.toDouble() / 1000 * gs.fontSize * gs.th, 0], tm);
              }
            }
          }
        case 'Do':
          if (depth < 6 && args.isNotEmpty && args[0] is String) {
            final x = file.res(xobjects?[args[0]! as String]);
            if (x is PdfStream && x.dict.nameOf('Subtype') == 'Form') {
              final form = file.decoded(x);
              if (form != null) {
                final sub = gs.clone();
                final matrix = file.numbers(x.dict['Matrix'], 6);
                if (matrix != null) sub.ctm = mulMatrix(matrix, sub.ctm);
                run(form, file.dict(x.dict['Resources']) ?? resources, sub, depth + 1);
              }
            }
          }
        case 'BI':
          lexer.skipInlineImage();
      }
      args.clear();
    }
  }

  final data = content();
  run(data, page.resources, GraphicsState(), 0);
  return PageInterpretation(
    page: page,
    data: data,
    ops: ops,
    glyphs: glyphs,
    text: builder.text.toString(),
    boxes: builder.boxes,
    geometry: PageGeometry(page),
  );
}

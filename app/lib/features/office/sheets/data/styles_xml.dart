import 'dart:math' as math;

import 'package:xml/xml.dart';

import '../domain/number_format.dart';
import '../domain/sheet_model.dart';

const _indexedColors = <int>[
  0x000000, 0xFFFFFF, 0xFF0000, 0x00FF00, 0x0000FF, 0xFFFF00, 0xFF00FF, 0x00FFFF, //
  0x000000, 0xFFFFFF, 0xFF0000, 0x00FF00, 0x0000FF, 0xFFFF00, 0xFF00FF, 0x00FFFF,
  0x800000, 0x008000, 0x000080, 0x808000, 0x800080, 0x008080, 0xC0C0C0, 0x808080,
  0x9999FF, 0x993366, 0xFFFFCC, 0xCCFFFF, 0x660066, 0xFF8080, 0x0066CC, 0xCCCCFF,
  0x000080, 0xFF00FF, 0xFFFF00, 0x00FFFF, 0x800080, 0x800000, 0x008080, 0x0000FF,
  0x00CCFF, 0xCCFFFF, 0xCCFFCC, 0xFFFF99, 0x99CCFF, 0xFF99CC, 0xCC99FF, 0xFFCC99,
  0x3366FF, 0x33CCCC, 0x99CC00, 0xFFCC00, 0xFF9900, 0xFF6600, 0x666699, 0x969696,
  0x003366, 0x339966, 0x003300, 0x333300, 0x993300, 0x993366, 0x333399, 0x333333,
  0x000000, 0xFFFFFF,
];

/// Colours of the workbook theme, in the order spreadsheet files number them.
List<int> parseThemeColors(XmlDocument? theme) {
  const names = ['lt1', 'dk1', 'lt2', 'dk2', 'accent1', 'accent2', 'accent3', 'accent4', 'accent5', 'accent6', 'hlink', 'folHlink'];
  const fallback = [0xFFFFFF, 0x000000, 0xE7E6E6, 0x44546A, 0x4472C4, 0xED7D31, 0xA5A5A5, 0xFFC000, 0x5B9BD5, 0x70AD47, 0x0563C1, 0x954F72];
  if (theme == null) return [for (final c in fallback) 0xFF000000 | c];
  final scheme = theme.descendants.whereType<XmlElement>().where((e) => e.name.local == 'clrScheme').firstOrNull;
  final out = <int>[];
  for (var i = 0; i < names.length; i++) {
    final e = scheme?.childElements.where((c) => c.name.local == names[i]).firstOrNull;
    final inner = e?.childElements.firstOrNull;
    final hex = inner?.getAttribute('val') ?? inner?.getAttribute('lastClr');
    final v = hex == null ? null : int.tryParse(hex, radix: 16);
    out.add(0xFF000000 | (v ?? fallback[i]));
  }
  return out;
}

/// Applies a tint (-1 to 1) to an RGB colour the way spreadsheets do, by changing its lightness.
int applyTint(int argb, double tint) {
  if (tint == 0) return argb;
  final r = ((argb >> 16) & 0xFF) / 255, g = ((argb >> 8) & 0xFF) / 255, b = (argb & 0xFF) / 255;
  final mx = math.max(r, math.max(g, b)), mn = math.min(r, math.min(g, b));
  var h = 0.0, s = 0.0;
  var l = (mx + mn) / 2;
  final d = mx - mn;
  if (d != 0) {
    s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn);
    if (mx == r) {
      h = (g - b) / d + (g < b ? 6 : 0);
    } else if (mx == g) {
      h = (b - r) / d + 2;
    } else {
      h = (r - g) / d + 4;
    }
    h /= 6;
  }
  l = tint < 0 ? l * (1 + tint) : l * (1 - tint) + tint;
  double hue(double p, double q, double t) {
    var tt = t;
    if (tt < 0) tt += 1;
    if (tt > 1) tt -= 1;
    if (tt < 1 / 6) return p + (q - p) * 6 * tt;
    if (tt < 1 / 2) return q;
    if (tt < 2 / 3) return p + (q - p) * (2 / 3 - tt) * 6;
    return p;
  }

  double nr, ng, nb;
  if (s == 0) {
    nr = ng = nb = l;
  } else {
    final q = l < 0.5 ? l * (1 + s) : l + s - l * s;
    final p = 2 * l - q;
    nr = hue(p, q, h + 1 / 3);
    ng = hue(p, q, h);
    nb = hue(p, q, h - 1 / 3);
  }
  int c(double v) => (v * 255).round().clamp(0, 255);
  return 0xFF000000 | (c(nr) << 16) | (c(ng) << 8) | c(nb);
}

/// Reads a colour element such as <color rgb="FFFF0000"/>, <fgColor theme="4" tint="0.4"/> or <color indexed="10"/>.
int? parseColor(XmlElement? e, List<int> theme) {
  if (e == null) return null;
  final rgb = e.getAttribute('rgb');
  if (rgb != null) {
    final v = int.tryParse(rgb, radix: 16);
    return v == null ? null : (rgb.length <= 6 ? 0xFF000000 | v : v | 0xFF000000);
  }
  final th = e.getAttribute('theme');
  if (th != null) {
    final i = int.tryParse(th);
    if (i == null || i < 0 || i >= theme.length) return null;
    return applyTint(theme[i], double.tryParse(e.getAttribute('tint') ?? '') ?? 0);
  }
  final idx = e.getAttribute('indexed');
  if (idx != null) {
    final i = int.tryParse(idx);
    if (i == null || i < 0 || i >= _indexedColors.length) return null;
    return 0xFF000000 | _indexedColors[i];
  }
  return null;
}

/// The parts of styles.xml that the app reads and edits, kept together with the document so that it can be patched.
class StylesXml {
  StylesXml(this.document, this.theme) {
    root = document.rootElement;
    _numFmts = {
      for (final e in _children(root, 'numFmts').expand((n) => n.childElements))
        if (e.name.local == 'numFmt') int.parse(e.getAttribute('numFmtId') ?? '0'): e.getAttribute('formatCode') ?? 'General',
    };
  }

  final XmlDocument document;
  final List<int> theme;
  late final XmlElement root;
  late final Map<int, String> _numFmts;

  static Iterable<XmlElement> _children(XmlElement parent, String name) => parent.childElements.where((e) => e.name.local == name);

  XmlElement? get _fonts => _children(root, 'fonts').firstOrNull;
  XmlElement? get _fills => _children(root, 'fills').firstOrNull;
  XmlElement? get _cellXfs => _children(root, 'cellXfs').firstOrNull;

  List<XmlElement> get xfs => _cellXfs?.childElements.where((e) => e.name.local == 'xf').toList() ?? const [];
  List<XmlElement> get fonts => _fonts?.childElements.where((e) => e.name.local == 'font').toList() ?? const [];
  List<XmlElement> get fills => _fills?.childElements.where((e) => e.name.local == 'fill').toList() ?? const [];

  String formatCode(int id) => _numFmts[id] ?? NumberFormatter.builtIn[id] ?? 'General';

  /// Every cell style of the file, in the order cells point to them.
  List<CellStyle> readStyles() {
    final fontList = fonts, fillList = fills;
    final out = <CellStyle>[];
    for (final xf in xfs) {
      final fontId = int.tryParse(xf.getAttribute('fontId') ?? '') ?? 0;
      final fillId = int.tryParse(xf.getAttribute('fillId') ?? '') ?? 0;
      final numFmtId = int.tryParse(xf.getAttribute('numFmtId') ?? '') ?? 0;
      final font = fontId < fontList.length ? fontList[fontId] : null;
      final fill = fillId < fillList.length ? fillList[fillId] : null;
      final align = _children(xf, 'alignment').firstOrNull;
      final pattern = fill == null ? null : _children(fill, 'patternFill').firstOrNull;
      int? fillColor;
      if (pattern != null && pattern.getAttribute('patternType') == 'solid') {
        fillColor = parseColor(_children(pattern, 'fgColor').firstOrNull, theme);
      }
      bool on(XmlElement? f, String tag) {
        final e = f == null ? null : _children(f, tag).firstOrNull;
        if (e == null) return false;
        final v = e.getAttribute('val');
        return v == null || (v != '0' && v != 'false' && v != 'none');
      }

      out.add(
        CellStyle(
          bold: on(font, 'b'),
          italic: on(font, 'i'),
          underline: on(font, 'u'),
          fontColor: font == null ? null : parseColor(_children(font, 'color').firstOrNull, theme),
          fontSize: font == null ? null : double.tryParse(_children(font, 'sz').firstOrNull?.getAttribute('val') ?? ''),
          fill: fillColor,
          align: switch (align?.getAttribute('horizontal')) {
            'left' => HAlign.left,
            'center' || 'centerContinuous' => HAlign.center,
            'right' => HAlign.right,
            _ => HAlign.general,
          },
          wrap: align?.getAttribute('wrapText') == '1' || align?.getAttribute('wrapText') == 'true',
          numFmt: formatCode(numFmtId),
        ),
      );
    }
    return out.isEmpty ? [CellStyle.plain] : out;
  }

  /// Adds the styles the app created, each made from the original style it was based on, and fixes the counts.
  void addStyles(StyleTable table) {
    final cellXfs = _cellXfs;
    final fontsEl = _fonts, fillsEl = _fills;
    if (cellXfs == null || fontsEl == null || fillsEl == null) return;
    final baseFonts = fonts, baseFills = fills;
    final baseXfs = xfs;
    final original = readStyles();
    final fontKeys = {for (var i = 0; i < baseFonts.length; i++) baseFonts[i].toXmlString(): i};
    final fillKeys = {for (var i = 0; i < baseFills.length; i++) baseFills[i].toXmlString(): i};

    for (var i = table.originalCount; i < table.styles.length; i++) {
      final style = table.styles[i];
      final baseIndex = table.basedOn[i] ?? 0;
      final base = baseIndex < baseXfs.length ? baseXfs[baseIndex] : null;
      final baseStyle = baseIndex < original.length ? original[baseIndex] : CellStyle.plain;
      final xf =
          base?.copy() ??
          XmlElement(XmlName('xf'), [
            XmlAttribute(XmlName('numFmtId'), '0'),
            XmlAttribute(XmlName('fontId'), '0'),
            XmlAttribute(XmlName('fillId'), '0'),
            XmlAttribute(XmlName('borderId'), '0'),
          ]);
      void set(String name, String value) {
        xf.setAttribute(name, value);
      }

      // Font.
      if (style.bold != baseStyle.bold ||
          style.italic != baseStyle.italic ||
          style.underline != baseStyle.underline ||
          style.fontColor != baseStyle.fontColor ||
          style.fontSize != baseStyle.fontSize) {
        final baseFontId = int.tryParse(base?.getAttribute('fontId') ?? '') ?? 0;
        final font = baseFontId < baseFonts.length ? baseFonts[baseFontId].copy() : XmlElement(XmlName('font'));
        void toggle(String tag, bool on) {
          font.children.removeWhere((c) => c is XmlElement && c.name.local == tag);
          if (on) font.children.insert(0, XmlElement(XmlName(tag)));
        }

        toggle('u', style.underline);
        toggle('i', style.italic);
        toggle('b', style.bold);
        if (style.fontColor != baseStyle.fontColor) {
          font.children.removeWhere((c) => c is XmlElement && c.name.local == 'color');
          if (style.fontColor != null)
            font.children.add(XmlElement(XmlName('color'), [XmlAttribute(XmlName('rgb'), style.fontColor!.toRadixString(16).padLeft(8, '0').toUpperCase())]));
        }
        if (style.fontSize != baseStyle.fontSize && style.fontSize != null) {
          font.children.removeWhere((c) => c is XmlElement && c.name.local == 'sz');
          font.children.add(XmlElement(XmlName('sz'), [XmlAttribute(XmlName('val'), _num(style.fontSize!))]));
        }
        final key = font.toXmlString();
        var id = fontKeys[key];
        if (id == null) {
          fontsEl.children.add(font);
          id = fontKeys.length;
          fontKeys[key] = id;
        }
        set('fontId', '$id');
        set('applyFont', '1');
      }

      // Fill.
      if (style.fill != baseStyle.fill) {
        if (style.fill == null) {
          set('fillId', '0');
        } else {
          final fill = XmlElement(XmlName('fill'), const [], [
            XmlElement(
              XmlName('patternFill'),
              [XmlAttribute(XmlName('patternType'), 'solid')],
              [
                XmlElement(XmlName('fgColor'), [XmlAttribute(XmlName('rgb'), style.fill!.toRadixString(16).padLeft(8, '0').toUpperCase())]),
                XmlElement(XmlName('bgColor'), [XmlAttribute(XmlName('indexed'), '64')]),
              ],
            ),
          ]);
          final key = fill.toXmlString();
          var id = fillKeys[key];
          if (id == null) {
            fillsEl.children.add(fill);
            id = fillKeys.length;
            fillKeys[key] = id;
          }
          set('fillId', '$id');
        }
        set('applyFill', '1');
      }

      // Number format.
      if (style.numFmt != baseStyle.numFmt) {
        set('numFmtId', '${_numFmtId(style.numFmt)}');
        set('applyNumberFormat', '1');
      }

      // Alignment.
      if (style.align != baseStyle.align || style.wrap != baseStyle.wrap) {
        xf.children.removeWhere((c) => c is XmlElement && c.name.local == 'alignment');
        final attrs = <XmlAttribute>[];
        if (style.align != HAlign.general) attrs.add(XmlAttribute(XmlName('horizontal'), style.align.name));
        if (style.wrap) attrs.add(XmlAttribute(XmlName('wrapText'), '1'));
        if (attrs.isNotEmpty) xf.children.insert(0, XmlElement(XmlName('alignment'), attrs));
        set('applyAlignment', '1');
      }
      cellXfs.children.add(xf);
    }
    fontsEl.setAttribute('count', '${fonts.length}');
    fillsEl.setAttribute('count', '${fills.length}');
    cellXfs.setAttribute('count', '${xfs.length}');
  }

  int _numFmtId(String code) {
    for (final e in NumberFormatter.builtIn.entries) {
      if (e.value == code) return e.key;
    }
    for (final e in _numFmts.entries) {
      if (e.value == code) return e.key;
    }
    var id = 164;
    while (_numFmts.containsKey(id)) {
      id++;
    }
    _numFmts[id] = code;
    var holder = _children(root, 'numFmts').firstOrNull;
    if (holder == null) {
      holder = XmlElement(XmlName('numFmts'));
      root.children.insert(0, holder);
    }
    holder.children.add(XmlElement(XmlName('numFmt'), [XmlAttribute(XmlName('numFmtId'), '$id'), XmlAttribute(XmlName('formatCode'), code)]));
    holder.setAttribute('count', '${holder.childElements.length}');
    return id;
  }

  static String _num(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}

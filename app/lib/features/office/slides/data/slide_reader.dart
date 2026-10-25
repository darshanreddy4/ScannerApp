import 'dart:math' as math;

import 'package:xml/xml.dart';

import '../domain/slide_model.dart';
import 'pptx_package.dart';

Iterable<XmlElement> _kids(XmlElement? e, String name) => e == null ? const [] : e.childElements.where((c) => c.name.local == name);
XmlElement? _kid(XmlElement? e, String name) => _kids(e, name).firstOrNull;
XmlElement? _path(XmlElement? e, List<String> names) {
  var cur = e;
  for (final n in names) {
    cur = _kid(cur, n);
    if (cur == null) return null;
  }
  return cur;
}

double? _num(XmlElement? e, String attr) => e == null ? null : double.tryParse(e.getAttribute(attr) ?? '');
bool? _flag(XmlElement? e, String attr) {
  final v = e?.getAttribute(attr);
  if (v == null) return null;
  return v == '1' || v == 'true';
}

// ------------------------------------------------------------------- colours

int _argb(int r, int g, int b, [int a = 255]) => (a << 24) | (r << 16) | (g << 8) | b;

(double, double, double) _toHsl(int c) {
  final r = ((c >> 16) & 0xFF) / 255, g = ((c >> 8) & 0xFF) / 255, b = (c & 0xFF) / 255;
  final mx = math.max(r, math.max(g, b)), mn = math.min(r, math.min(g, b));
  final l = (mx + mn) / 2;
  if (mx == mn) return (0, 0, l);
  final d = mx - mn;
  final s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn);
  double h;
  if (mx == r) {
    h = (g - b) / d + (g < b ? 6 : 0);
  } else if (mx == g) {
    h = (b - r) / d + 2;
  } else {
    h = (r - g) / d + 4;
  }
  return (h / 6, s, l);
}

int _fromHsl(double h, double s, double l, int a) {
  double hue(double p, double q, double t) {
    if (t < 0) t += 1;
    if (t > 1) t -= 1;
    if (t < 1 / 6) return p + (q - p) * 6 * t;
    if (t < 1 / 2) return q;
    if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
    return p;
  }

  double r, g, b;
  if (s == 0) {
    r = g = b = l;
  } else {
    final q = l < 0.5 ? l * (1 + s) : l + s - l * s;
    final p = 2 * l - q;
    r = hue(p, q, h + 1 / 3);
    g = hue(p, q, h);
    b = hue(p, q, h - 1 / 3);
  }
  return _argb((r * 255).round().clamp(0, 255), (g * 255).round().clamp(0, 255), (b * 255).round().clamp(0, 255), a);
}

const _presetColors = {
  'black': 0x000000, 'white': 0xFFFFFF, 'red': 0xFF0000, 'green': 0x008000, 'blue': 0x0000FF, 'yellow': 0xFFFF00, 'gray': 0x808080, 'grey': 0x808080, //
  'orange': 0xFFA500, 'purple': 0x800080, 'pink': 0xFFC0CB, 'brown': 0xA52A2A, 'cyan': 0x00FFFF, 'magenta': 0xFF00FF, 'lime': 0x00FF00, 'navy': 0x000080,
  'silver': 0xC0C0C0, 'maroon': 0x800000, 'olive': 0x808000, 'teal': 0x008080, 'darkBlue': 0x00008B, 'darkRed': 0x8B0000, 'darkGreen': 0x006400,
  'lightGray': 0xD3D3D3, 'lightGrey': 0xD3D3D3, 'darkGray': 0xA9A9A9, 'darkGrey': 0xA9A9A9,
};

/// The colours and fonts the master of a slide defines.
class _Scheme {
  _Scheme(this.colors, this.clrMap, this.major, this.minor);
  final Map<String, int> colors;
  final Map<String, String> clrMap;
  final String? major;
  final String? minor;

  int? lookup(String name) {
    final mapped = clrMap[name] ?? name;
    return colors[mapped];
  }
}

int? _colorFrom(XmlElement? holder, _Scheme scheme, {int? phClr}) {
  if (holder == null) return null;
  XmlElement? c;
  for (final k in holder.childElements) {
    if (const {'srgbClr', 'schemeClr', 'sysClr', 'prstClr', 'hslClr', 'scrgbClr'}.contains(k.name.local)) {
      c = k;
      break;
    }
  }
  if (c == null) return null;
  int? base;
  switch (c.name.local) {
    case 'srgbClr':
      final v = int.tryParse(c.getAttribute('val') ?? '', radix: 16);
      base = v == null ? null : 0xFF000000 | v;
    case 'sysClr':
      final v = int.tryParse(c.getAttribute('lastClr') ?? '', radix: 16);
      base = v != null ? 0xFF000000 | v : (c.getAttribute('val') == 'window' ? 0xFFFFFFFF : 0xFF000000);
    case 'prstClr':
      final v = _presetColors[c.getAttribute('val')];
      base = v == null ? 0xFF000000 : 0xFF000000 | v;
    case 'schemeClr':
      final name = c.getAttribute('val') ?? '';
      base = name == 'phClr' ? phClr : scheme.lookup(name);
    default:
      base = null;
  }
  if (base == null) return null;
  var color = base;
  var alpha = (color >> 24) & 0xFF;
  for (final m in c.childElements) {
    final v = (double.tryParse(m.getAttribute('val') ?? '') ?? 0) / 100000;
    switch (m.name.local) {
      case 'alpha':
        alpha = (v * 255).round().clamp(0, 255);
      case 'lumMod':
        final (h, s, l) = _toHsl(color);
        color = _fromHsl(h, s, (l * v).clamp(0, 1), alpha);
      case 'lumOff':
        final (h, s, l) = _toHsl(color);
        color = _fromHsl(h, s, (l + v).clamp(0, 1), alpha);
      case 'satMod':
        final (h, s, l) = _toHsl(color);
        color = _fromHsl(h, (s * v).clamp(0, 1), l, alpha);
      case 'tint':
        color = _mix(color, 0xFFFFFFFF, 1 - v, alpha);
      case 'shade':
        color = _mix(color, 0xFF000000, 1 - v, alpha);
    }
  }
  return (alpha << 24) | (color & 0xFFFFFF);
}

int _mix(int a, int b, double t, int alpha) {
  int ch(int shift) => (((a >> shift) & 0xFF) * (1 - t) + ((b >> shift) & 0xFF) * t).round().clamp(0, 255);
  return (alpha << 24) | (ch(16) << 16) | (ch(8) << 8) | ch(0);
}

// ----------------------------------------------------------------- text props

class _Props {
  double? sz;
  bool? b, i, u, strike;
  int? color;
  String? font;
  String? algn;
  double? marL, indent;
  String? bullet;
  bool? buNone;
  bool autoNum = false;
  double? lnSpc;
  double? spcBef, spcAft;
  double? spcBefPct, spcAftPct;

  _Props clone() => _Props()
    ..sz = sz
    ..b = b
    ..i = i
    ..u = u
    ..strike = strike
    ..color = color
    ..font = font
    ..algn = algn
    ..marL = marL
    ..indent = indent
    ..bullet = bullet
    ..buNone = buNone
    ..autoNum = autoNum
    ..lnSpc = lnSpc
    ..spcBef = spcBef
    ..spcAft = spcAft
    ..spcBefPct = spcBefPct
    ..spcAftPct = spcAftPct;

  void applyRun(XmlElement? rPr, _Scheme scheme) {
    if (rPr == null) return;
    final s = _num(rPr, 'sz');
    if (s != null) sz = s / 100;
    b = _flag(rPr, 'b') ?? b;
    i = _flag(rPr, 'i') ?? i;
    final u0 = rPr.getAttribute('u');
    if (u0 != null) u = u0 != 'none';
    final st = rPr.getAttribute('strike');
    if (st != null) strike = st != 'noStrike';
    final fill = _kid(rPr, 'solidFill');
    if (fill != null) color = _colorFrom(fill, scheme) ?? color;
    final latin = _kid(rPr, 'latin')?.getAttribute('typeface');
    if (latin != null) {
      font = latin == '+mj-lt' ? scheme.major : (latin == '+mn-lt' ? scheme.minor : latin);
    }
  }

  void applyPara(XmlElement? pPr, _Scheme scheme) {
    if (pPr == null) return;
    marL = _num(pPr, 'marL') ?? marL;
    indent = _num(pPr, 'indent') ?? indent;
    algn = pPr.getAttribute('algn') ?? algn;
    final ln = _kid(_kid(pPr, 'lnSpc'), 'spcPct');
    if (ln != null) lnSpc = (_num(ln, 'val') ?? 100000) / 100000;
    final sb = _kid(pPr, 'spcBef');
    if (sb != null) {
      final pts = _kid(sb, 'spcPts');
      final pct = _kid(sb, 'spcPct');
      if (pts != null) {
        spcBef = (_num(pts, 'val') ?? 0) / 100;
        spcBefPct = null;
      } else if (pct != null) {
        spcBefPct = (_num(pct, 'val') ?? 0) / 100000;
        spcBef = null;
      }
    }
    final sa = _kid(pPr, 'spcAft');
    if (sa != null) {
      final pts = _kid(sa, 'spcPts');
      final pct = _kid(sa, 'spcPct');
      if (pts != null) {
        spcAft = (_num(pts, 'val') ?? 0) / 100;
        spcAftPct = null;
      } else if (pct != null) {
        spcAftPct = (_num(pct, 'val') ?? 0) / 100000;
        spcAft = null;
      }
    }
    if (_kid(pPr, 'buNone') != null) {
      buNone = true;
      bullet = null;
      autoNum = false;
    }
    final char = _kid(pPr, 'buChar');
    if (char != null) {
      buNone = false;
      autoNum = false;
      final font = _kid(pPr, 'buFont')?.getAttribute('typeface') ?? '';
      var c = char.getAttribute('char') ?? '\u2022';
      if (font.startsWith('Wingdings') || font == 'Symbol' || c.runes.any((r) => r > 0xF000 || (r > 0x7F && r < 0x100 && font.isNotEmpty))) c = '\u2022';
      bullet = c;
    }
    if (_kid(pPr, 'buAutoNum') != null) {
      buNone = false;
      autoNum = true;
      bullet = null;
    }
    applyRun(_kid(pPr, 'defRPr'), scheme);
  }
}

class _Ph {
  const _Ph(this.type, this.idx);
  final String type;
  final String? idx;
}

_Ph? _phOf(XmlElement shape) {
  final ph = _path(shape, ['nvSpPr', 'nvPr', 'ph']) ?? _path(shape, ['nvPicPr', 'nvPr', 'ph']) ?? _path(shape, ['nvGraphicFramePr', 'nvPr', 'ph']);
  if (ph == null) return null;
  var type = ph.getAttribute('type') ?? (ph.getAttribute('idx') != null ? 'obj' : 'body');
  if (type == 'ctrTitle') type = 'title';
  if (type == 'subTitle') type = 'body';
  return _Ph(type, ph.getAttribute('idx'));
}

/// What the layout and master of a slide contribute.
class _Template {
  _Template({required this.layout, required this.master, required this.scheme, required this.layoutPath, required this.masterPath});
  final XmlDocument? layout;
  final XmlDocument? master;
  final _Scheme scheme;
  final String? layoutPath;
  final String? masterPath;
}

/// Turns the XML of a slide into shapes with everything resolved, ready to draw and edit.
class SlideReader {
  SlideReader(this.deck);

  final PptxDeck deck;
  final Map<String, _Template> _templates = {};
  late final XmlElement? _defaultTextStyle = _kid(deck.presentation.rootElement, 'defaultTextStyle');

  _Template _templateFor(String? layoutPath) {
    final key = layoutPath ?? '';
    return _templates[key] ??= _buildTemplate(layoutPath);
  }

  _Template _buildTemplate(String? layoutPath) {
    final layout = deck.parseOrNull(layoutPath);
    String? masterPath;
    if (layoutPath != null) {
      masterPath = deck.readRels(layoutPath).where((r) => r.type == 'slideMaster').map((r) => r.target).firstOrNull;
    }
    final master = deck.parseOrNull(masterPath);
    String? themePath;
    if (masterPath != null) themePath = deck.readRels(masterPath).where((r) => r.type == 'theme').map((r) => r.target).firstOrNull;
    final theme = deck.parseOrNull(themePath);

    final colors = <String, int>{};
    final clrScheme = _path(theme?.rootElement, ['themeElements', 'clrScheme']);
    for (final c in clrScheme?.childElements ?? const <XmlElement>[]) {
      final inner = c.childElements.firstOrNull;
      if (inner == null) continue;
      int? v;
      if (inner.name.local == 'srgbClr') {
        v = int.tryParse(inner.getAttribute('val') ?? '', radix: 16);
      } else if (inner.name.local == 'sysClr') {
        v = int.tryParse(inner.getAttribute('lastClr') ?? '', radix: 16) ?? (inner.getAttribute('val') == 'window' ? 0xFFFFFF : 0);
      }
      if (v != null) colors[c.name.local] = 0xFF000000 | v;
    }
    colors.putIfAbsent('dk1', () => 0xFF000000);
    colors.putIfAbsent('lt1', () => 0xFFFFFFFF);
    final clrMap = <String, String>{'bg1': 'lt1', 'tx1': 'dk1', 'bg2': 'lt2', 'tx2': 'dk2'};
    final map = _kid(master?.rootElement, 'clrMap');
    for (final a in map?.attributes ?? const <XmlAttribute>[]) {
      clrMap[a.name.local] = a.value;
    }
    final override = _path(layout?.rootElement, ['clrMapOvr', 'overrideClrMapping']);
    for (final a in override?.attributes ?? const <XmlAttribute>[]) {
      clrMap[a.name.local] = a.value;
    }
    final fonts = _path(theme?.rootElement, ['themeElements', 'fontScheme']);
    final major = _path(fonts, ['majorFont', 'latin'])?.getAttribute('typeface');
    final minor = _path(fonts, ['minorFont', 'latin'])?.getAttribute('typeface');
    return _Template(layout: layout, master: master, scheme: _Scheme(colors, clrMap, major, minor), layoutPath: layoutPath, masterPath: masterPath);
  }

  XmlElement? _tree(XmlDocument? doc) => _path(doc?.rootElement, ['cSld', 'spTree']);

  XmlElement? _findPh(XmlDocument? doc, _Ph ph) {
    final tree = _tree(doc);
    if (tree == null) return null;
    XmlElement? byType;
    for (final s in tree.childElements) {
      final p = _phOf(s);
      if (p == null) continue;
      if (ph.idx != null && p.idx == ph.idx && (p.type == ph.type || ph.type == 'obj' || p.type == 'obj')) return s;
      if (byType == null && p.type == ph.type && (ph.idx == null || p.idx == null || ph.type == 'title')) byType = s;
    }
    return byType;
  }

  // ---------------------------------------------------------------- the slide

  SlideView read(SlidePart slide) {
    final tpl = _templateFor(slide.layoutPath);
    final root = slide.doc.rootElement;
    final shapes = <ShapeView>[];
    final lookup = (String rid) => slide.relById(rid)?.target;
    _walk(slide.spTree, tpl, lookup, shapes, const [], true);

    // Master and layout decoration, unless the layout or the slide switches it off.
    final template = <ShapeView>[];
    final hideAll = root.getAttribute('showMasterSp') == '0';
    final layoutRoot = tpl.layout?.rootElement;
    if (!hideAll) {
      if (layoutRoot?.getAttribute('showMasterSp') != '0') {
        final masterRels = tpl.masterPath == null ? const <Rel>[] : deck.readRels(tpl.masterPath!);
        _walk(
          _tree(tpl.master),
          tpl,
          (rid) => masterRels.where((r) => r.id == rid).map((r) => r.target).firstOrNull,
          template,
          const [],
          false,
          skipPlaceholders: true,
        );
      }
      final layoutRels = tpl.layoutPath == null ? const <Rel>[] : deck.readRels(tpl.layoutPath!);
      _walk(
        _tree(tpl.layout),
        tpl,
        (rid) => layoutRels.where((r) => r.id == rid).map((r) => r.target).firstOrNull,
        template,
        const [],
        false,
        skipPlaceholders: true,
      );
    }
    return SlideView(background: _background(slide, tpl), template: template, shapes: shapes);
  }

  FillView _background(SlidePart slide, _Template tpl) {
    for (final (doc, owner) in [(slide.doc, slide.path), (tpl.layout, tpl.layoutPath), (tpl.master, tpl.masterPath)]) {
      final bg = _path(doc?.rootElement, ['cSld', 'bg']);
      if (bg == null) continue;
      final rels = owner == null ? const <Rel>[] : deck.readRels(owner);
      String? media(String rid) => rels.where((r) => r.id == rid).map((r) => r.target).firstOrNull;
      final props = _kid(bg, 'bgPr');
      if (props != null) {
        final f = _fillOf(props, tpl.scheme, media);
        if (f != null) return f;
      }
      final ref = _kid(bg, 'bgRef');
      if (ref != null) {
        final c = _colorFrom(ref, tpl.scheme);
        if (c != null) return FillView.solid(c);
      }
    }
    return FillView.solid(tpl.scheme.lookup('bg1') ?? 0xFFFFFFFF);
  }

  FillView? _fillOf(XmlElement? spPr, _Scheme scheme, String? Function(String) media, {int? phClr}) {
    if (spPr == null) return null;
    for (final k in spPr.childElements) {
      switch (k.name.local) {
        case 'noFill':
          return const FillView.none();
        case 'solidFill':
          final c = _colorFrom(k, scheme, phClr: phClr);
          return c == null ? null : FillView.solid(c);
        case 'gradFill':
          final stops = <int>[];
          for (final gs in _kids(_kid(k, 'gsLst'), 'gs')) {
            final c = _colorFrom(gs, scheme, phClr: phClr);
            if (c != null) stops.add(c);
          }
          if (stops.isEmpty) return null;
          final ang = (_num(_kid(k, 'lin'), 'ang') ?? 5400000) / 60000;
          return stops.length == 1 ? FillView.solid(stops.first) : FillView.gradient(stops, ang);
        case 'pattFill':
          final c = _colorFrom(_kid(k, 'fgClr'), scheme, phClr: phClr);
          return c == null ? null : FillView.solid(c);
        case 'blipFill':
          final rid = _kid(k, 'blip')?.attributes.where((a) => a.name.local == 'embed').map((a) => a.value).firstOrNull;
          final path = rid == null ? null : media(rid);
          return path == null ? null : FillView.image(path);
      }
    }
    return null;
  }

  // -------------------------------------------------------------- shape tree

  void _walk(
    XmlElement? tree,
    _Template tpl,
    String? Function(String) media,
    List<ShapeView> out,
    List<_GroupTx> groups,
    bool owner, {
    bool skipPlaceholders = false,
  }) {
    if (tree == null) return;
    for (var el in tree.childElements) {
      if (el.name.local == 'AlternateContent') {
        el = _kid(el, 'Fallback')?.childElements.firstOrNull ?? _kid(el, 'Choice')?.childElements.firstOrNull ?? el;
      }
      switch (el.name.local) {
        case 'sp':
          if (skipPlaceholders && _phOf(el) != null) continue;
          final v = _readSp(el, tpl, media, groups, owner);
          if (v != null) out.add(v);
        case 'cxnSp':
          final v = _readConnector(el, tpl, groups, owner);
          if (v != null) out.add(v);
        case 'pic':
          if (skipPlaceholders && _phOf(el) != null) continue;
          final v = _readPic(el, tpl, media, groups, owner);
          if (v != null) out.add(v);
        case 'graphicFrame':
          final v = _readFrame(el, tpl, groups, owner);
          if (v != null) out.add(v);
        case 'grpSp':
          final tx = _groupTx(el);
          _walk(el, tpl, media, out, [...groups, if (tx != null) tx], false, skipPlaceholders: skipPlaceholders);
      }
    }
  }

  _GroupTx? _groupTx(XmlElement grp) {
    final x = _path(grp, ['grpSpPr', 'xfrm']);
    if (x == null) return null;
    final off = _kid(x, 'off'), ext = _kid(x, 'ext'), chOff = _kid(x, 'chOff'), chExt = _kid(x, 'chExt');
    if (off == null || ext == null || chOff == null || chExt == null) return null;
    final cw = _num(chExt, 'cx') ?? 0, ch = _num(chExt, 'cy') ?? 0;
    return _GroupTx(
      _num(off, 'x') ?? 0,
      _num(off, 'y') ?? 0,
      cw == 0 ? 1 : (_num(ext, 'cx') ?? cw) / cw,
      ch == 0 ? 1 : (_num(ext, 'cy') ?? ch) / ch,
      _num(chOff, 'x') ?? 0,
      _num(chOff, 'y') ?? 0,
    );
  }

  Frame? _xfrm(XmlElement? x) {
    if (x == null) return null;
    final off = _kid(x, 'off'), ext = _kid(x, 'ext');
    if (off == null || ext == null) return null;
    return Frame(
      _num(off, 'x') ?? 0,
      _num(off, 'y') ?? 0,
      _num(ext, 'cx') ?? 0,
      _num(ext, 'cy') ?? 0,
      rot: (_num(x, 'rot') ?? 0) / 60000,
      flipH: _flag(x, 'flipH') ?? false,
      flipV: _flag(x, 'flipV') ?? false,
    );
  }

  Frame _mapGroups(Frame f, List<_GroupTx> groups) {
    var x = f.x, y = f.y, w = f.w, h = f.h;
    for (final g in groups.reversed) {
      x = g.offX + (x - g.chX) * g.sx;
      y = g.offY + (y - g.chY) * g.sy;
      w *= g.sx;
      h *= g.sy;
    }
    return f.copyWith(x: x, y: y, w: w, h: h);
  }

  Frame _inheritedFrame(XmlElement shape, XmlElement? own, _Template tpl, List<String> xfrmPath) {
    var frame = _xfrm(_path(shape, xfrmPath));
    if (frame != null) return frame;
    final ph = _phOf(shape);
    if (ph != null) {
      for (final doc in [tpl.layout, tpl.master]) {
        final src = _findPh(doc, ph);
        final f = src == null ? null : _xfrm(_path(src, ['spPr', 'xfrm']));
        if (f != null) return f;
      }
    }
    return const Frame(0, 0, 0, 0);
  }

  // ------------------------------------------------------------------- shapes

  ShapeView? _readSp(XmlElement sp, _Template tpl, String? Function(String) media, List<_GroupTx> groups, bool owner) {
    final cNvPr = _path(sp, ['nvSpPr', 'cNvPr']);
    final id = cNvPr?.getAttribute('id') ?? '0';
    final name = cNvPr?.getAttribute('name') ?? 'Shape';
    final ph = _phOf(sp);
    final spPr = _kid(sp, 'spPr');
    final style = _kid(sp, 'style');
    var frame = _inheritedFrame(sp, spPr, tpl, ['spPr', 'xfrm']);
    frame = _mapGroups(frame, groups);

    // Geometry, fill and line, from the shape, then its placeholder in the layout and master.
    final sources = <XmlElement?>[spPr];
    if (ph != null) {
      sources.add(_kid(_findPh(tpl.layout, ph), 'spPr'));
      sources.add(_kid(_findPh(tpl.master, ph), 'spPr'));
    }
    String geometry = 'rect';
    CustomPath? custom;
    double? adjust;
    for (final s in sources) {
      final prst = _kid(s, 'prstGeom');
      if (prst != null) {
        geometry = prst.getAttribute('prst') ?? 'rect';
        final gd = _path(prst, ['avLst', 'gd']);
        final fm = gd?.getAttribute('fmla') ?? '';
        final v = double.tryParse(fm.replaceFirst('val ', ''));
        if (v != null) adjust = v / 100000;
        break;
      }
      final cust = _kid(s, 'custGeom');
      if (cust != null) {
        geometry = 'custom';
        custom = _readCustom(cust);
        break;
      }
    }
    final phClr = _colorFrom(_kid(style, 'fillRef'), tpl.scheme);
    FillView fill = const FillView.none();
    var fillFound = false;
    for (final s in sources) {
      final f = _fillOf(s, tpl.scheme, media, phClr: phClr);
      if (f != null) {
        fill = f;
        fillFound = true;
        break;
      }
    }
    if (!fillFound && style != null) {
      final idx = int.tryParse(_kid(style, 'fillRef')?.getAttribute('idx') ?? '') ?? 0;
      if (idx > 0 && phClr != null) fill = FillView.solid(phClr);
    }
    LineView? line;
    for (final s in sources) {
      final ln = _kid(s, 'ln');
      if (ln == null) continue;
      line = _lineOf(ln, tpl.scheme, media, style);
      break;
    }
    line ??= _lineFromStyle(style, tpl.scheme);

    // Text.
    final body = _kid(sp, 'txBody');
    final paragraphs = body == null ? const <ParaView>[] : _readText(body, sp, ph, tpl, style, null);
    final box = _readBodyPr(body, ph, tpl);
    final kind = (geometry == 'line' || geometry == 'straightConnector1') && paragraphs.isEmpty ? ShapeKind.line : ShapeKind.text;
    return ShapeView(
      id: id,
      name: name,
      kind: kind,
      frame: frame,
      element: owner ? sp : null,
      editable: owner && groups.isEmpty,
      placeholder: ph != null,
      geometry: geometry,
      custom: custom,
      adjust: adjust,
      fill: fill,
      line: line,
      paragraphs: paragraphs,
      textBox: box,
    );
  }

  LineView? _lineOf(XmlElement ln, _Scheme scheme, String? Function(String) media, XmlElement? style) {
    if (_kid(ln, 'noFill') != null) return null;
    final lnRef = _kid(style, 'lnRef');
    final phClr = _colorFrom(lnRef, scheme);
    final fill = _kid(ln, 'solidFill');
    int? color = _colorFrom(fill, scheme, phClr: phClr);
    color ??= phClr ?? 0xFF000000;
    final w = (_num(ln, 'w') ?? 12700) / emuPerPt;
    final head = _kid(ln, 'headEnd')?.getAttribute('type'), tail = _kid(ln, 'tailEnd')?.getAttribute('type');
    return LineView(
      widthPt: w,
      color: color,
      dash: _kid(ln, 'prstDash')?.getAttribute('val'),
      headArrow: head != null && head != 'none',
      tailArrow: tail != null && tail != 'none',
    );
  }

  LineView? _lineFromStyle(XmlElement? style, _Scheme scheme) {
    final ref = _kid(style, 'lnRef');
    if (ref == null) return null;
    final idx = int.tryParse(ref.getAttribute('idx') ?? '') ?? 0;
    final c = _colorFrom(ref, scheme);
    if (idx == 0 || c == null) return null;
    return LineView(widthPt: idx * 0.75, color: c);
  }

  CustomPath? _readCustom(XmlElement cust) {
    final path = _path(cust, ['pathLst', 'path']);
    if (path == null) return null;
    final w = _num(path, 'w') ?? 0, h = _num(path, 'h') ?? 0;
    final cmds = <PathCmd>[];
    for (final c in path.childElements) {
      List<double> pts() => [
        for (final p in _kids(c, 'pt')) ...[_num(p, 'x') ?? 0, _num(p, 'y') ?? 0],
      ];
      switch (c.name.local) {
        case 'moveTo':
          cmds.add(PathCmd('m', pts()));
        case 'lnTo':
          cmds.add(PathCmd('l', pts()));
        case 'cubicBezTo':
          cmds.add(PathCmd('c', pts()));
        case 'quadBezTo':
          cmds.add(PathCmd('q', pts()));
        case 'close':
          cmds.add(const PathCmd('z'));
      }
    }
    if (cmds.isEmpty) return null;
    return CustomPath(w == 0 ? 1 : w, h == 0 ? 1 : h, cmds);
  }

  TextBox _readBodyPr(XmlElement? body, _Ph? ph, _Template tpl) {
    final chain = <XmlElement?>[
      if (ph != null) _kid(_kid(_findPh(tpl.master, ph), 'txBody'), 'bodyPr'),
      if (ph != null) _kid(_kid(_findPh(tpl.layout, ph), 'txBody'), 'bodyPr'),
      _kid(body, 'bodyPr'),
    ];
    var left = 91440.0, top = 45720.0, right = 91440.0, bottom = 45720.0;
    var anchor = 't';
    var wrap = true;
    var scale = 1.0;
    for (final b in chain) {
      if (b == null) continue;
      left = _num(b, 'lIns') ?? left;
      top = _num(b, 'tIns') ?? top;
      right = _num(b, 'rIns') ?? right;
      bottom = _num(b, 'bIns') ?? bottom;
      anchor = b.getAttribute('anchor') ?? anchor;
      if (b.getAttribute('wrap') != null) wrap = b.getAttribute('wrap') != 'none';
      final fit = _kid(b, 'normAutofit');
      if (fit != null) scale = (_num(fit, 'fontScale') ?? 100000) / 100000;
    }
    return TextBox(left: left, top: top, right: right, bottom: bottom, anchor: anchor, wrap: wrap, fontScale: scale);
  }

  /// The paragraphs of a text body, with sizes, colours and bullets worked out.
  List<ParaView> _readText(XmlElement body, XmlElement shape, _Ph? ph, _Template tpl, XmlElement? style, _Props? base) {
    final scheme = tpl.scheme;
    final phLayout = ph == null ? null : _findPh(tpl.layout, ph);
    final phMaster = ph == null ? null : _findPh(tpl.master, ph);
    final styleKind = ph == null
        ? 'otherStyle'
        : (ph.type == 'title' ? 'titleStyle' : (ph.type == 'body' || ph.type == 'obj' || ph.type == 'subTitle' ? 'bodyStyle' : 'otherStyle'));
    final txStyles = _kid(tpl.master?.rootElement, 'txStyles');
    final fontRefColor = _colorFrom(_kid(style, 'fontRef'), scheme, phClr: null);

    _Props levelProps(int level) {
      final p = base?.clone() ?? _Props();
      final tag = 'lvl${level + 1}pPr';
      p.applyPara(_kid(_defaultTextStyle, tag), scheme);
      if (ph != null) p.applyPara(_kid(_kid(txStyles, styleKind), tag), scheme);
      if (fontRefColor != null && ph == null) p.color = fontRefColor;
      p.applyPara(_kid(_kid(_kid(phMaster, 'txBody'), 'lstStyle'), tag), scheme);
      p.applyPara(_kid(_kid(_kid(phLayout, 'txBody'), 'lstStyle'), tag), scheme);
      p.applyPara(_kid(_kid(body, 'lstStyle'), tag), scheme);
      return p;
    }

    final fontScale = _readBodyPr(body, ph, tpl).fontScale;
    final out = <ParaView>[];
    final counters = <int, int>{};
    for (final p in _kids(body, 'p')) {
      final pPr = _kid(p, 'pPr');
      final level = int.tryParse(pPr?.getAttribute('lvl') ?? '') ?? 0;
      final props = levelProps(level.clamp(0, 8));
      props.applyPara(pPr, scheme);
      final runs = <RunView>[];
      for (final r in p.childElements) {
        final kind = r.name.local;
        if (kind != 'r' && kind != 'br' && kind != 'fld') continue;
        final run = props.clone()..applyRun(_kid(r, 'rPr'), scheme);
        final text = kind == 'br' ? '\n' : (_kid(r, 't')?.innerText ?? '');
        runs.add(
          RunView(
            text: text,
            sizePt: (run.sz ?? 18) * fontScale,
            bold: run.b ?? false,
            italic: run.i ?? false,
            underline: run.u ?? false,
            strike: run.strike ?? false,
            color: run.color ?? (scheme.lookup('tx1') ?? 0xFF000000),
            font: run.font,
          ),
        );
      }
      final endProps = props.clone()..applyRun(_kid(p, 'endParaRPr'), scheme);
      final size = (props.sz ?? 18) * fontScale;
      final hasBullet = props.buNone != true && (props.bullet != null || props.autoNum) && runs.any((r) => r.text.isNotEmpty);
      String? bullet;
      var autoNumber = false;
      if (hasBullet) {
        counters.removeWhere((k, _) => k > level);
        if (props.autoNum) {
          autoNumber = true;
          counters[level] = (counters[level] ?? 0) + 1;
          bullet = '${counters[level]}.';
        } else {
          bullet = props.bullet;
          counters.remove(level);
        }
      } else if (runs.any((r) => r.text.isNotEmpty)) {
        counters.removeWhere((k, _) => k >= level);
      }
      out.add(
        ParaView(
          runs: runs,
          align: props.algn ?? 'l',
          level: level,
          bullet: bullet,
          autoNumber: autoNumber,
          marL: props.marL ?? 0,
          indent: props.indent ?? 0,
          lineSpacing: props.lnSpc ?? 1.0,
          spaceBefore: props.spcBef ?? ((props.spcBefPct ?? 0) * size),
          spaceAfter: props.spcAft ?? ((props.spcAftPct ?? 0) * size),
          endSizePt: (endProps.sz ?? props.sz ?? 18) * fontScale,
        ),
      );
    }
    return out;
  }

  ShapeView? _readConnector(XmlElement cxn, _Template tpl, List<_GroupTx> groups, bool owner) {
    final cNvPr = _path(cxn, ['nvCxnSpPr', 'cNvPr']);
    final frame = _xfrm(_path(cxn, ['spPr', 'xfrm']));
    if (frame == null) return null;
    final spPr = _kid(cxn, 'spPr');
    final style = _kid(cxn, 'style');
    final ln = _kid(spPr, 'ln');
    final line = ln != null ? _lineOf(ln, tpl.scheme, (_) => null, style) : _lineFromStyle(style, tpl.scheme);
    final prst = _kid(spPr, 'prstGeom')?.getAttribute('prst') ?? 'line';
    return ShapeView(
      id: cNvPr?.getAttribute('id') ?? '0',
      name: cNvPr?.getAttribute('name') ?? 'Line',
      kind: ShapeKind.line,
      frame: _mapGroups(frame, groups),
      element: owner ? cxn : null,
      editable: owner && groups.isEmpty,
      geometry: prst,
      line: line ?? const LineView(widthPt: 1, color: 0xFF000000),
    );
  }

  ShapeView? _readPic(XmlElement pic, _Template tpl, String? Function(String) media, List<_GroupTx> groups, bool owner) {
    final cNvPr = _path(pic, ['nvPicPr', 'cNvPr']);
    final blip = _path(pic, ['blipFill', 'blip']);
    final rid = blip?.attributes.where((a) => a.name.local == 'embed').map((a) => a.value).firstOrNull;
    final path = rid == null ? null : media(rid);
    final frame = _inheritedFrame(pic, null, tpl, ['spPr', 'xfrm']);
    final src = _path(pic, ['blipFill', 'srcRect']);
    List<double>? crop;
    if (src != null) {
      crop = [(_num(src, 'l') ?? 0) / 100000, (_num(src, 't') ?? 0) / 100000, (_num(src, 'r') ?? 0) / 100000, (_num(src, 'b') ?? 0) / 100000];
    }
    final spPr = _kid(pic, 'spPr');
    final ln = _kid(spPr, 'ln');
    return ShapeView(
      id: cNvPr?.getAttribute('id') ?? '0',
      name: cNvPr?.getAttribute('name') ?? 'Picture',
      kind: ShapeKind.picture,
      frame: _mapGroups(frame, groups),
      element: owner ? pic : null,
      editable: owner && groups.isEmpty,
      placeholder: _phOf(pic) != null,
      geometry: _kid(spPr, 'prstGeom')?.getAttribute('prst') ?? 'rect',
      media: path,
      crop: crop,
      line: ln == null ? null : _lineOf(ln, tpl.scheme, (_) => null, null),
    );
  }

  ShapeView? _readFrame(XmlElement gf, _Template tpl, List<_GroupTx> groups, bool owner) {
    final cNvPr = _path(gf, ['nvGraphicFramePr', 'cNvPr']);
    final frame = _xfrm(_kid(gf, 'xfrm')) ?? _inheritedFrame(gf, null, tpl, ['xfrm']);
    final data = _path(gf, ['graphic', 'graphicData']);
    final uri = data?.getAttribute('uri') ?? '';
    final base = (
      id: cNvPr?.getAttribute('id') ?? '0',
      name: cNvPr?.getAttribute('name') ?? 'Content',
      frame: _mapGroups(frame, groups),
      element: owner ? gf : null,
      editable: owner && groups.isEmpty,
    );
    if (uri.endsWith('/table')) {
      final tbl = _kid(data, 'tbl');
      if (tbl != null) {
        return ShapeView(
          id: base.id,
          name: base.name,
          kind: ShapeKind.table,
          frame: base.frame,
          element: base.element,
          editable: base.editable,
          table: _readTable(tbl, tpl),
        );
      }
    }
    final kind = uri.endsWith('/chart') ? ShapeKind.chart : (uri.contains('diagram') ? ShapeKind.diagram : ShapeKind.other);
    final label = switch (kind) {
      ShapeKind.chart => 'Chart',
      ShapeKind.diagram => 'SmartArt graphic',
      _ => 'Content that cannot be shown here',
    };
    return ShapeView(id: base.id, name: base.name, kind: kind, frame: base.frame, element: base.element, editable: base.editable, label: label);
  }

  TableData _readTable(XmlElement tbl, _Template tpl) {
    final scheme = tpl.scheme;
    final props = _kid(tbl, 'tblPr');
    final firstRow = _flag(props, 'firstRow') ?? false;
    final banded = _flag(props, 'bandRow') ?? false;
    final accent = scheme.lookup('accent1') ?? 0xFF4472C4;
    final colWidths = [for (final c in _kids(_kid(tbl, 'tblGrid'), 'gridCol')) _num(c, 'w') ?? 0];
    final rowHeights = <double>[];
    final rows = <List<TableCellView>>[];
    var r = 0;
    for (final tr in _kids(tbl, 'tr')) {
      rowHeights.add(_num(tr, 'h') ?? 370840);
      final cells = <TableCellView>[];
      for (final tc in _kids(tr, 'tc')) {
        final tcPr = _kid(tc, 'tcPr');
        var fill = _colorFrom(_kid(tcPr, 'solidFill'), scheme);
        final header = firstRow && r == 0;
        if (fill == null && _kid(tcPr, 'noFill') == null) {
          if (header) {
            fill = accent;
          } else if (banded) {
            fill = _mix(accent, 0xFFFFFFFF, (r - (firstRow ? 1 : 0)).isEven ? 0.6 : 0.8, 255);
          } else {
            fill = _mix(accent, 0xFFFFFFFF, 0.8, 255);
          }
        }
        final base = _Props();
        if (header) {
          base.b = true;
          base.color = 0xFFFFFFFF;
        } else {
          base.color = scheme.lookup('tx1') ?? 0xFF000000;
        }
        final body = _kid(tc, 'txBody');
        final paras = body == null ? const <ParaView>[] : _readText(body, tc, null, tpl, null, base);
        cells.add(
          TableCellView(
            paragraphs: paras,
            fill: fill,
            gridSpan: int.tryParse(tc.getAttribute('gridSpan') ?? '') ?? 1,
            rowSpan: int.tryParse(tc.getAttribute('rowSpan') ?? '') ?? 1,
            merged: _flag(tc, 'hMerge') == true || _flag(tc, 'vMerge') == true,
            anchor: tcPr?.getAttribute('anchor') ?? 't',
          ),
        );
      }
      rows.add(cells);
      r++;
    }
    return TableData(colWidths: colWidths, rowHeights: rowHeights, rows: rows);
  }
}

class _GroupTx {
  const _GroupTx(this.offX, this.offY, this.sx, this.sy, this.chX, this.chY);
  final double offX, offY, sx, sy, chX, chY;
}

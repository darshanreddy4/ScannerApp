import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

/// What a Word file looks like, read out of its XML: pages, paragraphs with their look, tables with shaded cells,
/// pictures. Everything is in points. Pure Dart, so it can be built in an isolate.

class DxBorder {
  const DxBorder(this.widthPt, this.color);
  final double widthPt;
  final int color;
  static const none = DxBorder(0, 0);
  bool get isNone => widthPt <= 0;
}

class DxBorders {
  const DxBorders({this.top, this.left, this.bottom, this.right, this.insideH, this.insideV});
  final DxBorder? top, left, bottom, right, insideH, insideV;
}

class DxRunFmt {
  const DxRunFmt({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.caps = false,
    this.color,
    this.highlight,
    this.sizePt = 10,
    this.spacingPt = 0,
    this.font,
    this.vert = 0,
  });
  final bool bold, italic, underline, strike, caps;

  /// ARGB, or null for "automatic" (black, or white on a dark fill).
  final int? color;
  final int? highlight;
  final double sizePt;
  final double spacingPt;
  final String? font;

  /// 1 for superscript, -1 for subscript.
  final int vert;
}

class DxTab {
  const DxTab(this.posPt, this.align);
  final double posPt;
  final String align;
}

class DxParaFmt {
  const DxParaFmt({
    this.align = 'left',
    this.beforePt = 0,
    this.afterPt = 0,
    this.lineMult = 1,
    this.lineExactPt,
    this.lineAtLeastPt,
    this.leftPt = 0,
    this.rightPt = 0,
    this.firstLinePt = 0,
    this.hangingPt = 0,
    this.top,
    this.bottom,
    this.left,
    this.right,
    this.topSpace = 0,
    this.bottomSpace = 0,
    this.leftSpace = 0,
    this.rightSpace = 0,
    this.fill,
    this.tabs = const [],
    this.bidi = false,
    this.keepNext = false,
    this.pageBreakBefore = false,
    this.contextual = false,
    this.styleId,
  });
  final String align;
  final double beforePt, afterPt, lineMult;
  final double? lineExactPt, lineAtLeastPt;
  final double leftPt, rightPt, firstLinePt, hangingPt;
  final DxBorder? top, bottom, left, right;
  final double topSpace, bottomSpace, leftSpace, rightSpace;
  final int? fill;
  final List<DxTab> tabs;
  final bool bidi, keepNext, pageBreakBefore, contextual;
  final String? styleId;
}

class DxAnchor {
  const DxAnchor({required this.hFrom, required this.vFrom, this.hOff = 0, this.vOff = 0, this.hAlign, this.vAlign, this.behind = false});
  final String hFrom, vFrom;
  final double hOff, vOff;
  final String? hAlign, vAlign;
  final bool behind;
}

/// A picture, or a plain coloured rectangle or ellipse, with its size and (when it floats) where it sits.
class DxImage {
  const DxImage({this.bytes, required this.w, required this.h, this.anchor, this.fill, this.ellipse = false});
  final Uint8List? bytes;
  final double w, h;
  final DxAnchor? anchor;
  final int? fill;
  final bool ellipse;
}

class DxRun {
  const DxRun.text(this.text, this.fmt) : kind = 't', image = null;
  const DxRun.tab(this.fmt) : kind = 'tab', text = '\t', image = null;
  const DxRun.lineBreak(this.fmt) : kind = 'br', text = '\n', image = null;
  const DxRun.pageBreak(this.fmt) : kind = 'pb', text = '', image = null;
  const DxRun.image(this.image, this.fmt) : kind = 'img', text = '';
  final String kind;
  final String text;
  final DxRunFmt fmt;
  final DxImage? image;
}

sealed class DxBlock {
  const DxBlock();
}

class DxPara extends DxBlock {
  const DxPara({required this.runs, required this.fmt, required this.markFmt, this.label, this.labelFmt, this.labelLeftPt = 0});
  final List<DxRun> runs;
  final DxParaFmt fmt;

  /// The look of an empty paragraph's line.
  final DxRunFmt markFmt;

  /// The bullet or number in front, when the paragraph is in a list.
  final String? label;
  final DxRunFmt? labelFmt;

  /// Where the label starts, from the left edge of the text area.
  final double labelLeftPt;

  String get text {
    final b = StringBuffer();
    for (final r in runs) {
      if (r.kind == 't' || r.kind == 'tab' || r.kind == 'br') b.write(r.kind == 'tab' ? ' ' : r.text);
    }
    return b.toString();
  }
}

class DxCell {
  const DxCell({
    required this.blocks,
    required this.widthPt,
    this.span = 1,
    this.fill,
    this.borders,
    this.marL,
    this.marR,
    this.marT,
    this.marB,
    this.vAlign = 'top',
  });
  final List<DxBlock> blocks;
  final double widthPt;
  final int span;
  final int? fill;
  final DxBorders? borders;
  final double? marL, marR, marT, marB;
  final String vAlign;
}

class DxRow {
  const DxRow({required this.cells, this.heightPt, this.exact = false});
  final List<DxCell> cells;
  final double? heightPt;
  final bool exact;
}

class DxTable extends DxBlock {
  const DxTable({
    required this.grid,
    required this.rows,
    required this.borders,
    required this.marL,
    required this.marR,
    required this.marT,
    required this.marB,
    this.indentPt = 0,
    this.align = 'left',
  });
  final List<double> grid;
  final List<DxRow> rows;
  final DxBorders borders;
  final double marL, marR, marT, marB;
  final double indentPt;
  final String align;
}

class DxDocument {
  DxDocument({
    required this.pageW,
    required this.pageH,
    required this.mL,
    required this.mR,
    required this.mT,
    required this.mB,
    required this.blocks,
    required this.textLength,
    required this.imageCount,
  });
  final double pageW, pageH, mL, mR, mT, mB;
  final List<DxBlock> blocks;
  final int textLength;
  final int imageCount;
}

// ------------------------------------------------------------------------------------------------ helpers

extension _X on XmlElement {
  XmlElement? child(String n) {
    for (final c in children) {
      if (c is XmlElement && c.name.local == n) return c;
    }
    return null;
  }

  Iterable<XmlElement> kids([String? n]) => children.whereType<XmlElement>().where((e) => n == null || e.name.local == n);

  String? a(String n) {
    for (final at in attributes) {
      if (at.name.local == n) return at.value;
    }
    return null;
  }

  String? get val => a('val');
}

double? _twips(String? v) {
  final n = double.tryParse(v ?? '');
  return n == null ? null : n / 20;
}

int? _hex(String? v) {
  if (v == null || v.length != 6) return null;
  final n = int.tryParse(v, radix: 16);
  return n == null ? null : 0xFF000000 | n;
}

bool _on(XmlElement? e) {
  if (e == null) return false;
  final v = e.val?.toLowerCase();
  return v == null || !(v == '0' || v == 'false' || v == 'off' || v == 'none');
}

const _highlights = {
  'yellow': 0xFFFFFF00,
  'green': 0xFF00FF00,
  'cyan': 0xFF00FFFF,
  'magenta': 0xFFFF00FF,
  'blue': 0xFF0000FF,
  'red': 0xFFFF0000,
  'darkBlue': 0xFF000080,
  'darkCyan': 0xFF008080,
  'darkGreen': 0xFF008000,
  'darkMagenta': 0xFF800080,
  'darkRed': 0xFF800000,
  'darkYellow': 0xFF808000,
  'darkGray': 0xFF808080,
  'lightGray': 0xFFC0C0C0,
  'black': 0xFF000000,
  'white': 0xFFFFFFFF,
};

DxBorder? _border(XmlElement? e) {
  if (e == null) return null;
  final v = e.val;
  if (v == null || v == 'nil' || v == 'none') return DxBorder.none;
  final sz = double.tryParse(e.a('sz') ?? '') ?? 4;
  return DxBorder((sz / 8).clamp(0.25, 12), _hex(e.a('color')) ?? 0xFF000000);
}

DxBorders _borders(XmlElement? e) => e == null
    ? const DxBorders()
    : DxBorders(
        top: _border(e.child('top')),
        left: _border(e.child('left') ?? e.child('start')),
        bottom: _border(e.child('bottom')),
        right: _border(e.child('right') ?? e.child('end')),
        insideH: _border(e.child('insideH')),
        insideV: _border(e.child('insideV')),
      );

// ------------------------------------------------------------------------------------------------ run and paragraph looks

class _RB {
  bool bold = false, italic = false, underline = false, strike = false, caps = false;
  int? color, highlight;
  double sizePt = 10, spacingPt = 0;
  String? font;
  int vert = 0;

  _RB copy() => _RB()
    ..bold = bold
    ..italic = italic
    ..underline = underline
    ..strike = strike
    ..caps = caps
    ..color = color
    ..highlight = highlight
    ..sizePt = sizePt
    ..spacingPt = spacingPt
    ..font = font
    ..vert = vert;

  void apply(XmlElement? rPr) {
    if (rPr == null) return;
    for (final e in rPr.kids()) {
      switch (e.name.local) {
        case 'b':
          bold = _on(e);
        case 'i':
          italic = _on(e);
        case 'u':
          underline = e.val != null && e.val != 'none';
        case 'strike' || 'dstrike':
          strike = _on(e);
        case 'caps' || 'smallCaps':
          caps = _on(e);
        case 'color':
          final v = e.val;
          color = v == null || v == 'auto' ? null : (_hex(v) ?? color);
        case 'highlight':
          highlight = _highlights[e.val];
        case 'shd':
          final f = _hex(e.a('fill'));
          if (f != null) highlight = f;
        case 'sz':
          final n = double.tryParse(e.val ?? '');
          if (n != null && n > 0) sizePt = n / 2;
        case 'spacing':
          spacingPt = _twips(e.val) ?? spacingPt;
        case 'rFonts':
          final f = e.a('ascii') ?? e.a('hAnsi');
          if (f != null && f.isNotEmpty) font = f;
        case 'vertAlign':
          vert = e.val == 'superscript' ? 1 : (e.val == 'subscript' ? -1 : 0);
      }
    }
  }

  DxRunFmt build() => DxRunFmt(
    bold: bold,
    italic: italic,
    underline: underline,
    strike: strike,
    caps: caps,
    color: color,
    highlight: highlight,
    sizePt: sizePt,
    spacingPt: spacingPt,
    font: font,
    vert: vert,
  );
}

class _PB {
  String align = 'left';
  double before = 0, after = 0, lineMult = 1, left = 0, right = 0, firstLine = 0, hanging = 0;
  double? lineExact, lineAtLeast;
  DxBorder? top, bottom, leftB, rightB;
  double topSpace = 0, bottomSpace = 0, leftSpace = 0, rightSpace = 0;
  int? fill;
  List<DxTab> tabs = [];
  bool bidi = false, keepNext = false, pageBreakBefore = false, contextual = false;
  int? numId, ilvl;

  void apply(XmlElement? pPr, {bool indentOnly = false}) {
    if (pPr == null) return;
    for (final e in pPr.kids()) {
      final n = e.name.local;
      if (indentOnly && n != 'ind') continue;
      switch (n) {
        case 'jc':
          align = e.val ?? align;
        case 'spacing':
          before = _twips(e.a('before')) ?? before;
          after = _twips(e.a('after')) ?? after;
          final line = double.tryParse(e.a('line') ?? '');
          if (line != null) {
            final rule = e.a('lineRule') ?? 'auto';
            if (rule == 'auto') {
              lineMult = line / 240;
              lineExact = null;
              lineAtLeast = null;
            } else if (rule == 'exact') {
              lineExact = line / 20;
              lineAtLeast = null;
            } else {
              lineAtLeast = line / 20;
              lineExact = null;
            }
          }
        case 'ind':
          left = _twips(e.a('left') ?? e.a('start')) ?? left;
          right = _twips(e.a('right') ?? e.a('end')) ?? right;
          final fl = _twips(e.a('firstLine'));
          final h = _twips(e.a('hanging'));
          if (fl != null) {
            firstLine = fl;
            hanging = 0;
          }
          if (h != null) {
            hanging = h;
            firstLine = 0;
          }
        case 'pBdr':
          final t = e.child('top'), b = e.child('bottom'), l = e.child('left') ?? e.child('start'), r = e.child('right') ?? e.child('end');
          if (t != null) {
            top = _border(t);
            topSpace = double.tryParse(t.a('space') ?? '') ?? 0;
          }
          if (b != null) {
            bottom = _border(b);
            bottomSpace = double.tryParse(b.a('space') ?? '') ?? 0;
          }
          if (l != null) {
            leftB = _border(l);
            leftSpace = double.tryParse(l.a('space') ?? '') ?? 0;
          }
          if (r != null) {
            rightB = _border(r);
            rightSpace = double.tryParse(r.a('space') ?? '') ?? 0;
          }
        case 'shd':
          final f = _hex(e.a('fill'));
          if (f != null) fill = f;
        case 'tabs':
          for (final t in e.kids('tab')) {
            final pos = _twips(t.a('pos'));
            if (pos == null) continue;
            tabs.removeWhere((x) => (x.posPt - pos).abs() < 0.1);
            if (t.val != 'clear') tabs.add(DxTab(pos, t.val ?? 'left'));
          }
          tabs.sort((a, b) => a.posPt.compareTo(b.posPt));
        case 'bidi':
          bidi = _on(e);
        case 'keepNext':
          keepNext = _on(e);
        case 'pageBreakBefore':
          pageBreakBefore = _on(e);
        case 'contextualSpacing':
          contextual = _on(e);
        case 'numPr':
          final id = int.tryParse(e.child('numId')?.val ?? '');
          final lv = int.tryParse(e.child('ilvl')?.val ?? '');
          if (id != null) numId = id;
          if (lv != null) ilvl = lv;
      }
    }
  }

  DxParaFmt build(String? styleId) => DxParaFmt(
    align: align,
    beforePt: before,
    afterPt: after,
    lineMult: lineMult,
    lineExactPt: lineExact,
    lineAtLeastPt: lineAtLeast,
    leftPt: left,
    rightPt: right,
    firstLinePt: firstLine,
    hangingPt: hanging,
    top: top,
    bottom: bottom,
    left: leftB,
    right: rightB,
    topSpace: topSpace,
    bottomSpace: bottomSpace,
    leftSpace: leftSpace,
    rightSpace: rightSpace,
    fill: fill,
    tabs: List.of(tabs),
    bidi: bidi,
    keepNext: keepNext,
    pageBreakBefore: pageBreakBefore,
    contextual: contextual,
    styleId: styleId,
  );
}

class _Style {
  _Style(this.id, this.type, this.basedOn, this.pPr, this.rPr, this.tblPr);
  final String id, type;
  final String? basedOn;
  final XmlElement? pPr, rPr, tblPr;
}

class _Lvl {
  _Lvl(this.fmt, this.text, this.start, this.left, this.hanging, this.rPr);
  final String fmt, text;
  final int start;
  final double? left, hanging;
  final XmlElement? rPr;
}

class _Ctx {
  XmlElement? defRPr, defPPr;
  final styles = <String, _Style>{};
  String? defaultParaStyle;
  final numToAbstract = <int, int>{};
  final abstractLvls = <int, Map<int, _Lvl>>{};
  final counters = <int, List<int>>{};
  final rels = <String, String>{};
  Archive? archive;
  int textLength = 0;
  int imageCount = 0;

  List<_Style> chain(String? id) {
    final out = <_Style>[];
    final seen = <String>{};
    var cur = id == null ? null : styles[id];
    while (cur != null && seen.add(cur.id)) {
      out.insert(0, cur);
      cur = cur.basedOn == null ? null : styles[cur.basedOn];
    }
    return out;
  }
}

// ------------------------------------------------------------------------------------------------ reading

/// Reads a .docx into [DxDocument]. Throws when the file is not a Word package.
DxDocument readDocxLayout(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final docEntry = archive.findFile('word/document.xml');
  if (docEntry == null) throw const FormatException('no document.xml');
  final ctx = _Ctx()..archive = archive;
  XmlDocument load(String name) => XmlDocument.parse(utf8.decode(archive.findFile(name)!.readBytes()!, allowMalformed: true));

  if (archive.findFile('word/_rels/document.xml.rels') != null) {
    for (final r in load('word/_rels/document.xml.rels').descendants.whereType<XmlElement>().where((e) => e.name.local == 'Relationship')) {
      final id = r.getAttribute('Id'), target = r.getAttribute('Target');
      if (id != null && target != null) ctx.rels[id] = target;
    }
  }
  if (archive.findFile('word/styles.xml') != null) _readStyles(load('word/styles.xml').rootElement, ctx);
  if (archive.findFile('word/numbering.xml') != null) _readNumbering(load('word/numbering.xml').rootElement, ctx);

  final doc = XmlDocument.parse(utf8.decode(docEntry.readBytes()!, allowMalformed: true));
  final body = doc.rootElement.child('body');
  if (body == null) throw const FormatException('no body');

  var pageW = 595.3, pageH = 841.9, mL = 72.0, mR = 72.0, mT = 72.0, mB = 72.0;
  final sect = body.child('sectPr');
  if (sect != null) {
    final sz = sect.child('pgSz');
    pageW = _twips(sz?.a('w')) ?? pageW;
    pageH = _twips(sz?.a('h')) ?? pageH;
    final mar = sect.child('pgMar');
    mT = _twips(mar?.a('top')) ?? mT;
    mB = _twips(mar?.a('bottom')) ?? mB;
    mL = _twips(mar?.a('left')) ?? mL;
    mR = _twips(mar?.a('right')) ?? mR;
  }
  final blocks = _blocks(body, ctx, dark: false);
  return DxDocument(pageW: pageW, pageH: pageH, mL: mL, mR: mR, mT: mT, mB: mB, blocks: blocks, textLength: ctx.textLength, imageCount: ctx.imageCount);
}

void _readStyles(XmlElement root, _Ctx ctx) {
  final defaults = root.child('docDefaults');
  ctx.defRPr = defaults?.child('rPrDefault')?.child('rPr');
  ctx.defPPr = defaults?.child('pPrDefault')?.child('pPr');
  for (final s in root.kids('style')) {
    final id = s.a('styleId');
    if (id == null) continue;
    final type = s.a('type') ?? 'paragraph';
    ctx.styles[id] = _Style(id, type, s.child('basedOn')?.val, s.child('pPr'), s.child('rPr'), s.child('tblPr'));
    if (type == 'paragraph' && s.a('default') == '1') ctx.defaultParaStyle = id;
  }
}

void _readNumbering(XmlElement root, _Ctx ctx) {
  for (final a in root.kids('abstractNum')) {
    final id = int.tryParse(a.a('abstractNumId') ?? '');
    if (id == null) continue;
    final lvls = <int, _Lvl>{};
    for (final l in a.kids('lvl')) {
      final i = int.tryParse(l.a('ilvl') ?? '');
      if (i == null) continue;
      final ind = l.child('pPr')?.child('ind');
      lvls[i] = _Lvl(
        l.child('numFmt')?.val ?? 'decimal',
        l.child('lvlText')?.val ?? '',
        int.tryParse(l.child('start')?.val ?? '') ?? 1,
        _twips(ind?.a('left') ?? ind?.a('start')),
        _twips(ind?.a('hanging')),
        l.child('rPr'),
      );
    }
    ctx.abstractLvls[id] = lvls;
  }
  for (final n in root.kids('num')) {
    final id = int.tryParse(n.a('numId') ?? ''), abs = int.tryParse(n.child('abstractNumId')?.val ?? '');
    if (id != null && abs != null) ctx.numToAbstract[id] = abs;
  }
}

List<DxBlock> _blocks(XmlElement parent, _Ctx ctx, {required bool dark}) {
  final out = <DxBlock>[];
  for (final c in parent.kids()) {
    switch (c.name.local) {
      case 'p':
        final extra = <DxBlock>[];
        out.add(_para(c, ctx, extra, dark: dark));
        out.addAll(extra);
      case 'tbl':
        out.add(_table(c, ctx));
      case 'sdt':
        final content = c.child('sdtContent');
        if (content != null) out.addAll(_blocks(content, ctx, dark: dark));
      case 'ins' || 'customXml' || 'smartTag':
        out.addAll(_blocks(c, ctx, dark: dark));
    }
  }
  return out;
}

String _alpha(int n, bool upper) {
  var s = '';
  var x = n;
  while (x > 0) {
    x--;
    s = String.fromCharCode(97 + x % 26) + s;
    x ~/= 26;
  }
  return upper ? s.toUpperCase() : s;
}

String _roman(int n, bool upper) {
  const t = [
    (1000, 'm'),
    (900, 'cm'),
    (500, 'd'),
    (400, 'cd'),
    (100, 'c'),
    (90, 'xc'),
    (50, 'l'),
    (40, 'xl'),
    (10, 'x'),
    (9, 'ix'),
    (5, 'v'),
    (4, 'iv'),
    (1, 'i'),
  ];
  var x = n;
  final b = StringBuffer();
  for (final (v, s) in t) {
    while (x >= v) {
      b.write(s);
      x -= v;
    }
  }
  return upper ? b.toString().toUpperCase() : b.toString();
}

String _formatNumber(int n, String fmt) => switch (fmt) {
  'lowerLetter' => _alpha(n, false),
  'upperLetter' => _alpha(n, true),
  'lowerRoman' => _roman(n, false),
  'upperRoman' => _roman(n, true),
  'decimalZero' => n.toString().padLeft(2, '0'),
  _ => '$n',
};

String _bulletOf(String text) {
  if (text.isEmpty) return '•';
  final c = text.runes.first;
  if (c >= 0xF000 && c <= 0xF0FF) return c == 0xF0A7 ? '▪' : '•';
  if (text == 'o') return '◦';
  return text;
}

DxPara _para(XmlElement p, _Ctx ctx, List<DxBlock> extra, {required bool dark}) {
  final pPr = p.child('pPr');
  final styleId = pPr?.child('pStyle')?.val ?? ctx.defaultParaStyle;
  final chain = ctx.chain(styleId);

  final pb = _PB()..apply(ctx.defPPr);
  final rb = _RB()..apply(ctx.defRPr);
  for (final s in chain) {
    pb.apply(s.pPr);
    rb.apply(s.rPr);
  }
  // A list's indent sits between the style's and the paragraph's own.
  final direct = _PB()..apply(pPr);
  final numId = direct.numId ?? pb.numId;
  final ilvl = direct.ilvl ?? pb.ilvl ?? 0;
  String? label;
  DxRunFmt? labelFmt;
  double labelLeft = 0;
  if (numId != null && numId != 0) {
    final abs = ctx.numToAbstract[numId];
    final lvls = abs == null ? null : ctx.abstractLvls[abs];
    final lvl = lvls?[ilvl];
    if (lvl != null) {
      if (lvl.left != null) {
        pb.left = lvl.left!;
        pb.hanging = lvl.hanging ?? 0;
        pb.firstLine = 0;
      } else {
        pb.left = 18.0 * (ilvl + 1);
        pb.hanging = 18;
      }
      final counts = ctx.counters.putIfAbsent(numId, () => List.filled(10, 0));
      if (lvl.fmt == 'bullet') {
        label = _bulletOf(lvl.text);
      } else {
        counts[ilvl] = counts[ilvl] == 0 ? lvl.start : counts[ilvl] + 1;
        for (var i = ilvl + 1; i < counts.length; i++) {
          counts[i] = 0;
        }
        label = lvl.text.replaceAllMapped(RegExp(r'%(\d)'), (m) {
          final at = int.parse(m.group(1)!) - 1;
          final other = lvls?[at];
          final n = counts[at] == 0 ? (other?.start ?? 1) : counts[at];
          return _formatNumber(n, other?.fmt ?? 'decimal');
        });
      }
      final lb = rb.copy()..apply(lvl.rPr);
      labelFmt = lb.build();
    }
  }
  pb.apply(pPr);
  if (label != null) labelLeft = pb.left - pb.hanging;

  final fmt = pb.build(styleId);
  final markRb = rb.copy()..apply(pPr?.child('rPr'));
  final markFmt = markRb.build();
  final runs = <DxRun>[];

  void runs0(XmlElement parent, {required bool hyperlink}) {
    for (final c in parent.kids()) {
      switch (c.name.local) {
        case 'r':
          _run(c, ctx, rb, runs, extra, dark: dark, hyperlink: hyperlink);
        case 'hyperlink' || 'fldSimple' || 'ins' || 'smartTag' || 'customXml':
          runs0(c, hyperlink: hyperlink || c.name.local == 'hyperlink');
        case 'sdt':
          final content = c.child('sdtContent');
          if (content != null) runs0(content, hyperlink: hyperlink);
        case 'AlternateContent':
          final choice = c.child('Choice');
          if (choice != null) runs0(choice, hyperlink: hyperlink);
      }
    }
  }

  runs0(p, hyperlink: false);
  return DxPara(runs: runs, fmt: fmt, markFmt: markFmt, label: label, labelFmt: labelFmt, labelLeftPt: labelLeft);
}

void _run(XmlElement r, _Ctx ctx, _RB base, List<DxRun> runs, List<DxBlock> extra, {required bool dark, required bool hyperlink}) {
  final rPr = r.child('rPr');
  final b = base.copy();
  final rs = rPr?.child('rStyle')?.val;
  if (rs != null) {
    for (final s in ctx.chain(rs)) {
      b.apply(s.rPr);
    }
  } else if (hyperlink && ctx.styles.containsKey('Hyperlink')) {
    b.apply(ctx.styles['Hyperlink']!.rPr);
  }
  b.apply(rPr);
  final fmt = b.build();
  for (final c in r.kids()) {
    switch (c.name.local) {
      case 't':
        final t = c.innerText;
        if (t.isNotEmpty) {
          ctx.textLength += t.length;
          runs.add(DxRun.text(t, fmt));
        }
      case 'tab':
        runs.add(DxRun.tab(fmt));
      case 'br':
        runs.add(c.a('type') == 'page' ? DxRun.pageBreak(fmt) : DxRun.lineBreak(fmt));
      case 'cr':
        runs.add(DxRun.lineBreak(fmt));
      case 'noBreakHyphen':
        runs.add(DxRun.text('-', fmt));
      case 'drawing':
        _drawing(c, ctx, fmt, runs, extra, dark: dark);
      case 'pict' || 'object':
        _pict(c, ctx, fmt, runs, extra, dark: dark);
      case 'AlternateContent':
        final choice = c.child('Choice');
        if (choice != null) {
          // Only the first choice; the fallback shows the same thing again.
          for (final d in choice.kids('drawing')) {
            _drawing(d, ctx, fmt, runs, extra, dark: dark);
          }
        }
    }
  }
}

Uint8List? _media(_Ctx ctx, String? rid) {
  final target = rid == null ? null : ctx.rels[rid];
  if (target == null) return null;
  final path = target.startsWith('/') ? target.substring(1) : p.posix.normalize(p.posix.join('word', target));
  final lower = path.toLowerCase();
  if (lower.endsWith('.emf') || lower.endsWith('.wmf') || lower.endsWith('.svg')) return null;
  return ctx.archive?.findFile(path)?.readBytes();
}

double _emu(String? v) => (double.tryParse(v ?? '') ?? 0) / 12700;

void _drawing(XmlElement d, _Ctx ctx, DxRunFmt fmt, List<DxRun> runs, List<DxBlock> extra, {required bool dark}) {
  final host = d.child('inline') ?? d.child('anchor');
  if (host == null) return;
  final anchored = host.name.local == 'anchor';
  final ext = host.child('extent');
  final w = _emu(ext?.a('cx')), h = _emu(ext?.a('cy'));
  DxAnchor? anchor;
  if (anchored) {
    XmlElement? pos(String n) => host.child(n);
    final ph = pos('positionH'), pv = pos('positionV');
    anchor = DxAnchor(
      hFrom: ph?.a('relativeFrom') ?? 'column',
      vFrom: pv?.a('relativeFrom') ?? 'paragraph',
      hOff: _emu(ph?.child('posOffset')?.innerText),
      vOff: _emu(pv?.child('posOffset')?.innerText),
      hAlign: ph?.child('align')?.innerText,
      vAlign: pv?.child('align')?.innerText,
      behind: host.a('behindDoc') == '1',
    );
  }

  // Text boxes keep their words: the paragraphs inside are laid out in the flow.
  for (final box in host.descendants.whereType<XmlElement>().where((e) => e.name.local == 'txbxContent')) {
    if (box.ancestors.whereType<XmlElement>().any((a) => a.name.local == 'txbxContent')) continue;
    extra.addAll(_blocks(box, ctx, dark: dark));
  }

  final blip = host.descendants.whereType<XmlElement>().where((e) => e.name.local == 'blip').firstOrNull;
  if (blip != null) {
    final bytes = _media(ctx, blip.a('embed'));
    if (bytes != null && w > 0 && h > 0) {
      ctx.imageCount++;
      runs.add(DxRun.image(DxImage(bytes: bytes, w: w, h: h, anchor: anchor), fmt));
    }
    return;
  }
  // A plain filled shape, such as a coloured bar behind the text.
  final wsp = host.descendants.whereType<XmlElement>().where((e) => e.name.local == 'wsp').firstOrNull;
  final spPr = wsp?.child('spPr');
  final fill = spPr?.child('solidFill')?.child('srgbClr')?.val;
  if (anchor != null && fill != null && w > 0 && h > 0) {
    final geom = spPr?.child('prstGeom')?.a('prst');
    runs.add(DxRun.image(DxImage(w: w, h: h, anchor: anchor, fill: _hex(fill), ellipse: geom == 'ellipse'), fmt));
  }
}

void _pict(XmlElement pict, _Ctx ctx, DxRunFmt fmt, List<DxRun> runs, List<DxBlock> extra, {required bool dark}) {
  for (final box in pict.descendants.whereType<XmlElement>().where((e) => e.name.local == 'txbxContent')) {
    if (box.ancestors.whereType<XmlElement>().any((a) => a.name.local == 'txbxContent')) continue;
    extra.addAll(_blocks(box, ctx, dark: dark));
  }
  final img = pict.descendants.whereType<XmlElement>().where((e) => e.name.local == 'imagedata').firstOrNull;
  if (img == null) return;
  final bytes = _media(ctx, img.a('id'));
  if (bytes == null) return;
  final shape = img.parent as XmlElement?;
  final style = shape?.getAttribute('style') ?? '';
  double? size(String key) {
    final m = RegExp('$key:([0-9.]+)(pt|in|px)?').firstMatch(style);
    if (m == null) return null;
    final n = double.tryParse(m.group(1)!);
    if (n == null) return null;
    return switch (m.group(2)) {
      'in' => n * 72,
      'px' => n * 0.75,
      _ => n,
    };
  }

  final w = size('width'), h = size('height');
  if (w != null && h != null && w > 0 && h > 0) {
    ctx.imageCount++;
    runs.add(DxRun.image(DxImage(bytes: bytes, w: w, h: h), fmt));
  }
}

DxTable _table(XmlElement t, _Ctx ctx) {
  final tblPr = t.child('tblPr');
  // The table's style gives borders and cell margins unless the table says otherwise.
  DxBorders borders = const DxBorders();
  double marL = 5.4, marR = 5.4, marT = 0, marB = 0;
  void takeLook(XmlElement? pr) {
    if (pr == null) return;
    final b = pr.child('tblBorders');
    if (b != null) {
      final nb = _borders(b);
      borders = DxBorders(
        top: nb.top ?? borders.top,
        left: nb.left ?? borders.left,
        bottom: nb.bottom ?? borders.bottom,
        right: nb.right ?? borders.right,
        insideH: nb.insideH ?? borders.insideH,
        insideV: nb.insideV ?? borders.insideV,
      );
    }
    final m = pr.child('tblCellMar');
    if (m != null) {
      marL = _twips(m.child('left')?.a('w') ?? m.child('start')?.a('w')) ?? marL;
      marR = _twips(m.child('right')?.a('w') ?? m.child('end')?.a('w')) ?? marR;
      marT = _twips(m.child('top')?.a('w')) ?? marT;
      marB = _twips(m.child('bottom')?.a('w')) ?? marB;
    }
  }

  for (final s in ctx.chain(tblPr?.child('tblStyle')?.val)) {
    takeLook(s.tblPr);
  }
  takeLook(tblPr);

  final grid = <double>[for (final g in t.child('tblGrid')?.kids('gridCol') ?? const <XmlElement>[]) _twips(g.a('w')) ?? 0];
  final indent = _twips(tblPr?.child('tblInd')?.a('w')) ?? 0;
  final align = tblPr?.child('jc')?.val ?? 'left';

  final rows = <DxRow>[];
  for (final tr in t.kids('tr')) {
    final trPr = tr.child('trPr');
    final h = trPr?.child('trHeight');
    final cells = <DxCell>[];
    var col = 0;
    for (final tc in tr.kids('tc')) {
      final pr = tc.child('tcPr');
      final span = int.tryParse(pr?.child('gridSpan')?.val ?? '') ?? 1;
      var width = 0.0;
      for (var i = 0; i < span; i++) {
        if (col + i < grid.length) width += grid[col + i];
      }
      if (width <= 0) width = _twips(pr?.child('tcW')?.a('w')) ?? 0;
      final fill = _hex(pr?.child('shd')?.a('fill'));
      final mar = pr?.child('tcMar');
      final dark = fill != null && _luma(fill) < 0.45;
      var content = _blocks(tc, ctx, dark: dark);
      if (pr?.child('vMerge') != null && pr!.child('vMerge')!.val != 'restart') {
        content = [];
      }
      cells.add(
        DxCell(
          blocks: content,
          widthPt: width,
          span: span,
          fill: fill,
          borders: pr?.child('tcBorders') == null ? null : _borders(pr!.child('tcBorders')),
          marL: _twips(mar?.child('left')?.a('w') ?? mar?.child('start')?.a('w')),
          marR: _twips(mar?.child('right')?.a('w') ?? mar?.child('end')?.a('w')),
          marT: _twips(mar?.child('top')?.a('w')),
          marB: _twips(mar?.child('bottom')?.a('w')),
          vAlign: pr?.child('vAlign')?.val ?? 'top',
        ),
      );
      col += span;
    }
    rows.add(DxRow(cells: cells, heightPt: _twips(h?.a('val')), exact: h?.a('hRule') == 'exact'));
  }
  if (grid.isEmpty && rows.isNotEmpty) {
    for (final c in rows.first.cells) {
      grid.add(c.widthPt);
    }
  }
  return DxTable(grid: grid, rows: rows, borders: borders, marL: marL, marR: marR, marT: marT, marB: marB, indentPt: indent, align: align);
}

double _luma(int argb) {
  final r = (argb >> 16) & 0xFF, g = (argb >> 8) & 0xFF, b = argb & 0xFF;
  return (0.299 * r + 0.587 * g + 0.114 * b) / 255;
}

/// How light a colour is, from 0 (black) to 1 (white).
double colorLuma(int argb) => _luma(argb);

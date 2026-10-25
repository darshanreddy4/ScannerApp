import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

class DocxFormatException implements Exception {
  const DocxFormatException(this.message);
  final String message;
}

const _wNs = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

// ------------------------------------------------------------------ what the editor shows

/// A stretch of text that is shown in one look.
class RunSpan {
  const RunSpan(this.text, {this.bold = false, this.italic = false, this.underline = false, this.strike = false, this.color, this.sizePt});
  final String text;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strike;

  /// ARGB, or null for the default colour.
  final int? color;
  final double? sizePt;
}

sealed class DocBlock {
  const DocBlock();
}

class ParaBlock extends DocBlock {
  const ParaBlock({
    required this.index,
    required this.text,
    required this.spans,
    required this.align,
    required this.headingLevel,
    required this.listLabel,
    required this.indentPt,
    required this.images,
  });

  /// Position of the paragraph among all paragraphs of the document, in reading order.
  final int index;
  final String text;
  final List<RunSpan> spans;

  /// left, center, right or both (justified).
  final String align;
  final int? headingLevel;
  final String? listLabel;
  final double indentPt;

  /// Names of the pictures inside this paragraph, for [DocxDocument.imageBytes].
  final List<String> images;
}

class TableBlock extends DocBlock {
  const TableBlock(this.rows);

  /// Rows of cells, each cell holding blocks.
  final List<List<List<DocBlock>>> rows;
}

/// The look shared by everything in a selection; null where the selection is mixed.
class FormatState {
  const FormatState({this.bold, this.italic, this.underline, this.strike, this.sizePt, this.color, this.align = 'left'});
  final bool? bold;
  final bool? italic;
  final bool? underline;
  final bool? strike;
  final double? sizePt;
  final int? color;
  final String align;
}

/// A change to the look of text. Null leaves a setting as it is.
class FormatChange {
  const FormatChange({this.bold, this.italic, this.underline, this.strike, this.sizePt, this.color, this.clearColor = false});
  final bool? bold;
  final bool? italic;
  final bool? underline;
  final bool? strike;
  final double? sizePt;

  /// RGB (the alpha is ignored).
  final int? color;
  final bool clearColor;
}

class DocMatch {
  const DocMatch(this.paragraph, this.start, this.end);
  final int paragraph;
  final int start;
  final int end;
}

// ------------------------------------------------------------------ styles

class _Fmt {
  bool bold = false;
  bool italic = false;
  bool underline = false;
  bool strike = false;
  int? color;
  double? size;

  _Fmt copy() => _Fmt()
    ..bold = bold
    ..italic = italic
    ..underline = underline
    ..strike = strike
    ..color = color
    ..size = size;
}

class _StyleDef {
  _StyleDef({required this.id, required this.type, this.basedOn, this.rPr, this.pPr, this.isDefault = false});
  final String id;
  final String type;
  final String? basedOn;
  final XmlElement? rPr;
  final XmlElement? pPr;
  final bool isDefault;
}

// Order of the children of rPr and pPr that matter to Word.
const _rPrOrder = [
  'rStyle', 'rFonts', 'b', 'bCs', 'i', 'iCs', 'caps', 'smallCaps', 'strike', 'dstrike', 'outline', 'shadow', 'emboss', 'imprint', 'noProof', 'snapToGrid', //
  'vanish', 'webHidden', 'color', 'spacing', 'w', 'kern', 'position', 'sz', 'szCs', 'highlight', 'u', 'effect', 'bdr', 'shd', 'fitText', 'vertAlign', 'rtl',
  'cs', 'em', 'lang', 'eastAsianLayout', 'specVanish', 'oMath',
];
const _pPrAfterJc = ['textDirection', 'textAlignment', 'textboxTightWrap', 'outlineLvl', 'divId', 'cnfStyle', 'rPr', 'sectPr', 'pPrChange'];

// Children of a run that carry its text.
const _textKids = {'t', 'tab', 'cr', 'noBreakHyphen', 'lastRenderedPageBreak', 'softHyphen'};

/// A Word file whose text can be changed. Everything else in the file (pictures, styles, tables, headers) is written back untouched.
class DocxDocument {
  DocxDocument._(this._archive, this._doc, this._prefix) {
    _refresh();
  }

  final Archive _archive;
  XmlDocument _doc;
  final String? _prefix;

  final List<String> _undo = [];
  final List<String> _redo = [];
  static const _maxHistory = 40;

  late List<XmlElement> _paras;
  Map<String, _StyleDef>? _styles;
  XmlElement? _docDefaults;
  Map<String, String>? _rels;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// Reads a .docx. Throws [DocxFormatException] for anything else (older .doc files included).
  static DocxDocument open(Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const DocxFormatException('This file is not a valid .docx document. Older .doc files are not supported.');
    }
    final entry = archive.findFile('word/document.xml');
    if (entry == null) throw const DocxFormatException('This file is not a valid .docx document.');
    try {
      final doc = XmlDocument.parse(utf8.decode(entry.readBytes()!, allowMalformed: true));
      return DocxDocument._(archive, doc, doc.rootElement.name.prefix);
    } on XmlException {
      throw const DocxFormatException('The text of this document could not be read.');
    }
  }

  /// The file with the changes, as bytes.
  Uint8List save() {
    final out = Archive();
    final xml = utf8.encode(_doc.toXmlString());
    for (final f in _archive.files) {
      if (!f.isFile) continue;
      out.addFile(ArchiveFile.bytes(f.name, f.name == 'word/document.xml' ? xml : f.readBytes()!));
    }
    return Uint8List.fromList(ZipEncoder().encode(out));
  }

  // ------------------------------------------------------------------ structure

  XmlName _n(String local) => XmlName.parts(local, prefix: _prefix);

  static bool _is(XmlNode n, String local) =>
      n is XmlElement && n.name.local == local && (n.name.namespaceUri == _wNs || n.name.prefix == 'w' || n.name.namespaceUri == null);

  XmlElement? get _body {
    for (final c in _doc.rootElement.childElements) {
      if (_is(c, 'body')) return c;
    }
    return null;
  }

  void _refresh() {
    _paras = [];
    final body = _body;
    if (body != null) _collect(body, _paras);
  }

  /// Paragraphs in reading order, going into tables and content controls.
  void _collect(XmlElement parent, List<XmlElement> out) {
    for (final c in parent.childElements) {
      if (_is(c, 'p')) {
        out.add(c);
      } else if (_is(c, 'tbl')) {
        for (final tr in c.childElements.where((e) => _is(e, 'tr'))) {
          for (final tc in tr.childElements.where((e) => _is(e, 'tc'))) {
            _collect(tc, out);
          }
        }
      } else if (_is(c, 'sdt')) {
        for (final content in c.childElements.where((e) => _is(e, 'sdtContent'))) {
          _collect(content, out);
        }
      }
    }
  }

  int get paragraphCount => _paras.length;

  List<XmlElement> _runsOf(XmlElement p) {
    final runs = <XmlElement>[];
    void walk(XmlElement e) {
      for (final c in e.childElements) {
        if (_is(c, 'r')) {
          runs.add(c);
        } else if (_is(c, 'hyperlink') || _is(c, 'ins') || _is(c, 'smartTag') || _is(c, 'fldSimple') || _is(c, 'sdtContent') || _is(c, 'moveTo')) {
          walk(c);
        } else if (_is(c, 'sdt')) {
          for (final content in c.childElements.where((x) => _is(x, 'sdtContent'))) {
            walk(content);
          }
        }
      }
    }

    walk(p);
    return runs;
  }

  String _runText(XmlElement run) {
    final b = StringBuffer();
    for (final c in run.childElements) {
      if (_is(c, 't')) {
        b.write(c.innerText);
      } else if (_is(c, 'tab')) {
        b.write('\t');
      } else if (_is(c, 'cr') || (_is(c, 'br') && !_isPageBreak(c))) {
        b.write('\n');
      } else if (_is(c, 'noBreakHyphen')) {
        b.write('-');
      }
    }
    return b.toString();
  }

  bool _isPageBreak(XmlElement br) {
    final type = _attr(br, 'type');
    return type == 'page' || type == 'column';
  }

  /// A run that is only text, so it can be split without losing anything else it holds.
  bool _isPureText(XmlElement run) => run.childElements.every((c) => _is(c, 'rPr') || _textKids.contains(c.name.local) || (_is(c, 'br') && !_isPageBreak(c)));

  String _attr(XmlElement e, String local) {
    for (final a in e.attributes) {
      if (a.name.local == local) return a.value;
    }
    return '';
  }

  void _setAttr(XmlElement e, String local, String value) {
    e.attributes.removeWhere((a) => a.name.local == local);
    e.attributes.add(XmlAttribute(XmlName.parts(local, prefix: _prefix), value));
  }

  XmlElement? _child(XmlElement e, String local) {
    for (final c in e.childElements) {
      if (_is(c, local)) return c;
    }
    return null;
  }

  String paragraphText(int index) => _runsOf(_paras[index]).map(_runText).join();

  // ------------------------------------------------------------------ reading styles

  void _loadStyles() {
    if (_styles != null) return;
    final styles = <String, _StyleDef>{};
    final entry = _archive.findFile('word/styles.xml');
    if (entry != null) {
      try {
        final doc = XmlDocument.parse(utf8.decode(entry.readBytes()!, allowMalformed: true));
        for (final c in doc.rootElement.childElements) {
          if (_is(c, 'docDefaults')) {
            _docDefaults = _child(_child(c, 'rPrDefault') ?? c, 'rPr');
          } else if (_is(c, 'style')) {
            final id = _attr(c, 'styleId');
            if (id.isEmpty) continue;
            styles[id] = _StyleDef(
              id: id,
              type: _attr(c, 'type'),
              basedOn: _child(c, 'basedOn') == null ? null : _attr(_child(c, 'basedOn')!, 'val'),
              rPr: _child(c, 'rPr'),
              pPr: _child(c, 'pPr'),
              isDefault: _attr(c, 'default') == '1' || _attr(c, 'default') == 'true',
            );
          }
        }
      } catch (_) {
        // Without styles the text is shown plainly.
      }
    }
    _styles = styles;
  }

  List<_StyleDef> _chain(String? id) {
    final out = <_StyleDef>[];
    final seen = <String>{};
    var cur = id == null ? null : _styles![id];
    while (cur != null && seen.add(cur.id)) {
      out.insert(0, cur);
      cur = cur.basedOn == null ? null : _styles![cur.basedOn!];
    }
    return out;
  }

  bool _on(XmlElement e) {
    final v = _attr(e, 'val').toLowerCase();
    return v.isEmpty || (v != '0' && v != 'false' && v != 'off' && v != 'none');
  }

  void _applyRPr(_Fmt f, XmlElement? rPr) {
    if (rPr == null) return;
    for (final c in rPr.childElements) {
      switch (c.name.local) {
        case 'b':
          f.bold = _on(c);
        case 'i':
          f.italic = _on(c);
        case 'u':
          f.underline = _on(c);
        case 'strike':
          f.strike = _on(c);
        case 'color':
          final v = _attr(c, 'val');
          f.color = RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(v) ? 0xFF000000 | int.parse(v, radix: 16) : null;
        case 'sz':
          final v = double.tryParse(_attr(c, 'val'));
          if (v != null) f.size = v / 2;
      }
    }
  }

  _Fmt _paragraphBase(XmlElement p) {
    _loadStyles();
    final f = _Fmt();
    _applyRPr(f, _docDefaults);
    final pPr = _child(p, 'pPr');
    final styleId = pPr == null ? null : (_child(pPr, 'pStyle') == null ? null : _attr(_child(pPr, 'pStyle')!, 'val'));
    final defaultPara = _styles!.values.where((s) => s.type == 'paragraph' && s.isDefault).firstOrNull;
    for (final s in [..._chain(defaultPara?.id), if (styleId != null && styleId != defaultPara?.id) ..._chain(styleId)]) {
      _applyRPr(f, s.rPr);
    }
    return f;
  }

  _Fmt _runFormat(_Fmt base, XmlElement run) {
    final f = base.copy();
    final rPr = _child(run, 'rPr');
    if (rPr != null) {
      final rStyle = _child(rPr, 'rStyle');
      if (rStyle != null) {
        for (final s in _chain(_attr(rStyle, 'val'))) {
          _applyRPr(f, s.rPr);
        }
      }
      _applyRPr(f, rPr);
    }
    return f;
  }

  String _alignOf(XmlElement p) {
    _loadStyles();
    var jc = 'left';
    final pPr = _child(p, 'pPr');
    final styleId = pPr == null ? null : (_child(pPr, 'pStyle') == null ? null : _attr(_child(pPr, 'pStyle')!, 'val'));
    for (final s in _chain(styleId)) {
      final v = s.pPr == null ? null : _child(s.pPr!, 'jc');
      if (v != null) jc = _attr(v, 'val');
    }
    final direct = pPr == null ? null : _child(pPr, 'jc');
    if (direct != null) jc = _attr(direct, 'val');
    return switch (jc) {
      'center' => 'center',
      'right' || 'end' => 'right',
      'both' || 'distribute' => 'both',
      _ => 'left',
    };
  }

  // ------------------------------------------------------------------ the picture of the document

  /// The document as blocks to draw: paragraphs and tables.
  List<DocBlock> view() {
    _loadStyles();
    final counters = <String, List<int>>{};
    final indexOf = {for (var i = 0; i < _paras.length; i++) _paras[i]: i};
    final body = _body;
    if (body == null) return const [];
    return _blocksOf(body, indexOf, counters);
  }

  List<DocBlock> _blocksOf(XmlElement parent, Map<XmlElement, int> indexOf, Map<String, List<int>> counters) {
    final out = <DocBlock>[];
    for (final c in parent.childElements) {
      if (_is(c, 'p')) {
        out.add(_paraBlock(c, indexOf[c] ?? -1, counters));
      } else if (_is(c, 'tbl')) {
        final rows = <List<List<DocBlock>>>[];
        for (final tr in c.childElements.where((e) => _is(e, 'tr'))) {
          rows.add([for (final tc in tr.childElements.where((e) => _is(e, 'tc'))) _blocksOf(tc, indexOf, counters)]);
        }
        out.add(TableBlock(rows));
      } else if (_is(c, 'sdt')) {
        for (final content in c.childElements.where((e) => _is(e, 'sdtContent'))) {
          out.addAll(_blocksOf(content, indexOf, counters));
        }
      }
    }
    return out;
  }

  ParaBlock _paraBlock(XmlElement p, int index, Map<String, List<int>> counters) {
    final base = _paragraphBase(p);
    final spans = <RunSpan>[];
    final text = StringBuffer();
    final images = <String>[];
    for (final r in _runsOf(p)) {
      final t = _runText(r);
      final f = _runFormat(base, r);
      if (t.isNotEmpty) {
        text.write(t);
        spans.add(RunSpan(t, bold: f.bold, italic: f.italic, underline: f.underline, strike: f.strike, color: f.color, sizePt: f.size));
      }
      for (final blip in r.descendantElements.where((e) => e.name.local == 'blip')) {
        final id = blip.attributes.where((a) => a.name.local == 'embed').map((a) => a.value).firstOrNull;
        final target = id == null ? null : _relTargets()[id];
        if (target != null) images.add(target);
      }
    }
    final pPr = _child(p, 'pPr');
    final styleId = pPr == null || _child(pPr, 'pStyle') == null ? '' : _attr(_child(pPr, 'pStyle')!, 'val');
    int? heading;
    final h = RegExp(r'^[Hh]eading\s*(\d)$').firstMatch(styleId);
    if (h != null) heading = int.parse(h.group(1)!);
    if (styleId == 'Title') heading = 0;
    var indent = 0.0;
    final ind = pPr == null ? null : _child(pPr, 'ind');
    if (ind != null) {
      indent = (double.tryParse(_attr(ind, 'left')) ?? double.tryParse(_attr(ind, 'start')) ?? 0) / 20;
    }
    return ParaBlock(
      index: index,
      text: text.toString(),
      spans: spans,
      align: _alignOf(p),
      headingLevel: heading,
      listLabel: _listLabel(p, counters),
      indentPt: indent,
      images: images,
    );
  }

  Map<String, String> _relTargets() {
    final cached = _rels;
    if (cached != null) return cached;
    final map = <String, String>{};
    final entry = _archive.findFile('word/_rels/document.xml.rels');
    if (entry != null) {
      try {
        final doc = XmlDocument.parse(utf8.decode(entry.readBytes()!, allowMalformed: true));
        for (final r in doc.rootElement.childElements) {
          final id = r.getAttribute('Id'), target = r.getAttribute('Target');
          if (id != null && target != null && r.getAttribute('Type')?.endsWith('/image') == true) {
            map[id] = target.startsWith('/') ? target.substring(1) : 'word/$target';
          }
        }
      } catch (_) {
        // No pictures are shown.
      }
    }
    return _rels = map;
  }

  /// The bytes of a PNG or JPEG picture of the document, or null for other kinds.
  Uint8List? imageBytes(String part) {
    final lower = part.toLowerCase();
    if (!(lower.endsWith('.png') || lower.endsWith('.jpg') || lower.endsWith('.jpeg'))) return null;
    final normalized = part.replaceAll('word/../', '');
    return _archive.findFile(normalized)?.readBytes();
  }

  // Numbers and bullets of lists.
  XmlDocument? _numberingDoc;
  var _numberingLoaded = false;

  String? _listLabel(XmlElement p, Map<String, List<int>> counters) {
    final pPr = _child(p, 'pPr');
    var numPr = pPr == null ? null : _child(pPr, 'numPr');
    if (numPr == null) {
      // List styles such as "List Bullet" carry their numbering in the style.
      final styleId = pPr == null || _child(pPr, 'pStyle') == null ? null : _attr(_child(pPr, 'pStyle')!, 'val');
      for (final style in _chain(styleId).reversed) {
        final found = style.pPr == null ? null : _child(style.pPr!, 'numPr');
        if (found != null) {
          numPr = found;
          break;
        }
      }
    }
    if (numPr == null) return null;
    final numId = _child(numPr, 'numId') == null ? '' : _attr(_child(numPr, 'numId')!, 'val');
    if (numId.isEmpty || numId == '0') return null;
    final level = int.tryParse(_child(numPr, 'ilvl') == null ? '0' : _attr(_child(numPr, 'ilvl')!, 'val')) ?? 0;
    if (!_numberingLoaded) {
      _numberingLoaded = true;
      final entry = _archive.findFile('word/numbering.xml');
      if (entry != null) {
        try {
          _numberingDoc = XmlDocument.parse(utf8.decode(entry.readBytes()!, allowMalformed: true));
        } catch (_) {
          _numberingDoc = null;
        }
      }
    }
    final root = _numberingDoc?.rootElement;
    if (root == null) return '\u2022';
    final num = root.childElements.where((e) => _is(e, 'num') && _attr(e, 'numId') == numId).firstOrNull;
    final abstractId = num == null ? null : (_child(num, 'abstractNumId') == null ? null : _attr(_child(num, 'abstractNumId')!, 'val'));
    final abstract = abstractId == null ? null : root.childElements.where((e) => _is(e, 'abstractNum') && _attr(e, 'abstractNumId') == abstractId).firstOrNull;
    XmlElement? lvlOf(int l) => abstract?.childElements.where((e) => _is(e, 'lvl') && _attr(e, 'ilvl') == '$l').firstOrNull;
    final lvl = lvlOf(level);
    final fmt = lvl == null || _child(lvl, 'numFmt') == null ? 'bullet' : _attr(_child(lvl, 'numFmt')!, 'val');
    if (fmt == 'bullet' || fmt == 'none') return '\u2022';
    final counter = counters.putIfAbsent(numId, () => List.filled(10, 0));
    counter[level]++;
    for (var i = level + 1; i < counter.length; i++) {
      counter[i] = 0;
    }
    String format(int n, String f) => switch (f) {
      'lowerLetter' => String.fromCharCode(96 + ((n - 1) % 26) + 1),
      'upperLetter' => String.fromCharCode(64 + ((n - 1) % 26) + 1),
      'lowerRoman' => _roman(n).toLowerCase(),
      'upperRoman' => _roman(n),
      _ => '$n',
    };
    final start = lvl == null || _child(lvl, 'start') == null ? 1 : (int.tryParse(_attr(_child(lvl, 'start')!, 'val')) ?? 1);
    final text = lvl == null || _child(lvl, 'lvlText') == null ? '%${level + 1}.' : _attr(_child(lvl, 'lvlText')!, 'val');
    return text.replaceAllMapped(RegExp(r'%(\d)'), (m) {
      final l = int.parse(m.group(1)!) - 1;
      final lf = l == level ? fmt : (lvlOf(l) == null || _child(lvlOf(l)!, 'numFmt') == null ? 'decimal' : _attr(_child(lvlOf(l)!, 'numFmt')!, 'val'));
      return format(counter[l] + (start - 1), lf);
    });
  }

  static String _roman(int n) {
    const map = [
      (1000, 'M'),
      (900, 'CM'),
      (500, 'D'),
      (400, 'CD'),
      (100, 'C'),
      (90, 'XC'),
      (50, 'L'),
      (40, 'XL'),
      (10, 'X'),
      (9, 'IX'),
      (5, 'V'),
      (4, 'IV'),
      (1, 'I'),
    ];
    var out = '';
    for (final (v, s) in map) {
      while (n >= v) {
        out += s;
        n -= v;
      }
    }
    return out;
  }

  /// The look at a place in a paragraph: shared settings of the text from [start] to [end], or of the whole paragraph when the two are equal.
  FormatState formatOf(int index, int start, int end) {
    final p = _paras[index];
    final base = _paragraphBase(p);
    final infos = _runInfos(p);
    final total = infos.isEmpty ? 0 : infos.last.end;
    var s = start, e = end;
    if (s == e) {
      s = 0;
      e = total;
    }
    final formats = <_Fmt>[];
    for (final r in infos) {
      if (r.text.isEmpty) continue;
      final overlaps = e > s ? (r.start < e && r.end > s) : false;
      if (overlaps) formats.add(_runFormat(base, r.run));
    }
    if (formats.isEmpty && infos.isNotEmpty) formats.add(_runFormat(base, infos.first.run));
    if (formats.isEmpty) formats.add(base);
    bool? same(bool Function(_Fmt) get) => formats.every((f) => get(f) == get(formats.first)) ? get(formats.first) : null;
    final sizes = formats.map((f) => f.size).toSet();
    final colors = formats.map((f) => f.color).toSet();
    return FormatState(
      bold: same((f) => f.bold),
      italic: same((f) => f.italic),
      underline: same((f) => f.underline),
      strike: same((f) => f.strike),
      sizePt: sizes.length == 1 ? sizes.first : null,
      color: colors.length == 1 ? colors.first : null,
      align: _alignOf(p),
    );
  }

  // ------------------------------------------------------------------ editing

  void _checkpoint() {
    _undo.add(_doc.toXmlString());
    if (_undo.length > _maxHistory) _undo.removeAt(0);
    _redo.clear();
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(_doc.toXmlString());
    _doc = XmlDocument.parse(_undo.removeLast());
    _refresh();
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(_doc.toXmlString());
    _doc = XmlDocument.parse(_redo.removeLast());
    _refresh();
  }

  List<({XmlElement run, int start, int end, String text})> _runInfos(XmlElement p) {
    final out = <({XmlElement run, int start, int end, String text})>[];
    var at = 0;
    for (final r in _runsOf(p)) {
      final t = _runText(r);
      out.add((run: r, start: at, end: at + t.length, text: t));
      at += t.length;
    }
    return out;
  }

  /// Puts [text] into the paragraph, changing only the part that differs so the look of the rest is kept.
  void setParagraphText(int index, String text) {
    final old = paragraphText(index);
    if (old == text) return;
    var prefix = 0;
    final limit = math.min(old.length, text.length);
    while (prefix < limit && old.codeUnitAt(prefix) == text.codeUnitAt(prefix)) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < limit - prefix && old.codeUnitAt(old.length - 1 - suffix) == text.codeUnitAt(text.length - 1 - suffix)) {
      suffix++;
    }
    _checkpoint();
    _splice(_paras[index], prefix, old.length - suffix, text.substring(prefix, text.length - suffix));
  }

  void _splice(XmlElement p, int start, int end, String insert) {
    final infos = _runInfos(p);
    final total = infos.isEmpty ? 0 : infos.last.end;
    start = start.clamp(0, total);
    end = end.clamp(start, total);
    var inserted = false;
    for (final info in infos) {
      final overlaps = end > start && info.start < end && info.end > start;
      if (!overlaps) continue;
      final from = math.max(start - info.start, 0), to = math.min(end - info.start, info.text.length);
      final text = info.text.substring(0, from) + (inserted ? '' : insert) + info.text.substring(to);
      inserted = true;
      _writeRunText(info.run, text);
    }
    if (inserted || insert.isEmpty) return;
    ({XmlElement run, int start, int end, String text})? target;
    for (final info in infos) {
      if (info.start < start && start <= info.end) target = info;
    }
    target ??= infos.where((i) => i.start == start).firstOrNull;
    if (target != null) {
      final at = start - target.start;
      _writeRunText(target.run, target.text.substring(0, at) + insert + target.text.substring(at));
      return;
    }
    // A paragraph without any text: the new text takes the look of the paragraph mark.
    final run = XmlElement(_n('r'));
    final markProps = _child(_child(p, 'pPr') ?? p, 'rPr');
    if (markProps != null && _child(p, 'pPr') != null) run.children.add(markProps.copy());
    p.children.add(run);
    _writeRunText(run, insert);
  }

  /// Replaces the text of a run, keeping its look and anything that is not text (such as a picture).
  void _writeRunText(XmlElement run, String text) {
    var at = -1;
    final remove = <XmlNode>[];
    for (var i = 0; i < run.children.length; i++) {
      final c = run.children[i];
      if (c is XmlElement && (_textKids.contains(c.name.local) || (_is(c, 'br') && !_isPageBreak(c)))) {
        if (at < 0) at = i;
        remove.add(c);
      }
    }
    for (final c in remove) {
      c.remove();
    }
    final hasOther = run.childElements.any((c) => !_is(c, 'rPr'));
    if (text.isEmpty && !hasOther) {
      run.remove();
      return;
    }
    final nodes = <XmlNode>[];
    final buffer = StringBuffer();
    void flush() {
      if (buffer.isEmpty) return;
      nodes.add(XmlElement(_n('t'), [XmlAttribute(XmlName.parts('space', prefix: 'xml'), 'preserve')], [XmlText(buffer.toString())]));
      buffer.clear();
    }

    for (final ch in text.split('')) {
      if (ch == '\t') {
        flush();
        nodes.add(XmlElement(_n('tab')));
      } else if (ch == '\n') {
        flush();
        nodes.add(XmlElement(_n('br')));
      } else {
        buffer.write(ch);
      }
    }
    flush();
    run.children.insertAll(at < 0 ? run.children.length : at, nodes);
  }

  // region looks

  void _splitAt(XmlElement p, int offset) {
    for (final info in _runInfos(p)) {
      if (info.start < offset && offset < info.end && _isPureText(info.run)) {
        final copy = info.run.copy();
        info.run.parent!.children.insert(info.run.parent!.children.indexOf(info.run) + 1, copy);
        _writeRunText(info.run, info.text.substring(0, offset - info.start));
        _writeRunText(copy, info.text.substring(offset - info.start));
        return;
      }
    }
  }

  /// Changes the look of the text from [start] to [end] of a paragraph, or of the whole paragraph when they are equal.
  void formatRange(int index, int start, int end, FormatChange change) {
    final p = _paras[index];
    _checkpoint();
    final total = paragraphText(index).length;
    if (start == end) {
      start = 0;
      end = total;
    }
    start = start.clamp(0, total);
    end = end.clamp(start, total);
    _splitAt(p, end);
    _splitAt(p, start);
    for (final info in _runInfos(p)) {
      final overlaps = end > start && info.start < end && info.end > start;
      if (overlaps) _applyChange(info.run, change);
    }
    // An empty paragraph keeps the look for what is typed into it.
    if (total == 0) {
      final pPr = _child(p, 'pPr');
      if (pPr != null) _applyChangeToProps(_ensureChild(pPr, 'rPr', _pPrAfterRPr), change);
    }
  }

  static const _pPrAfterRPr = ['sectPr', 'pPrChange'];

  XmlElement _ensureChild(XmlElement parent, String local, List<String> before) {
    final existing = _child(parent, local);
    if (existing != null) return existing;
    final created = XmlElement(_n(local));
    final at = parent.children.indexWhere((c) => c is XmlElement && before.contains(c.name.local));
    parent.children.insert(at < 0 ? parent.children.length : at, created);
    return created;
  }

  void _applyChange(XmlElement run, FormatChange change) {
    var rPr = _child(run, 'rPr');
    if (rPr == null) {
      rPr = XmlElement(_n('rPr'));
      run.children.insert(0, rPr);
    }
    _applyChangeToProps(rPr, change);
  }

  void _putRProp(XmlElement rPr, String local, XmlElement? element, {List<String> alsoRemove = const []}) {
    for (final name in [local, ...alsoRemove]) {
      rPr.children.removeWhere((c) => c is XmlElement && c.name.local == name);
    }
    if (element == null) return;
    final rank = _rPrOrder.indexOf(local);
    final at = rPr.children.indexWhere((c) => c is XmlElement && _rPrOrder.indexOf(c.name.local) > rank);
    rPr.children.insert(at < 0 ? rPr.children.length : at, element);
  }

  XmlElement _flag(String local, [String? val]) {
    final e = XmlElement(_n(local));
    if (val != null) _setAttr(e, 'val', val);
    return e;
  }

  void _applyChangeToProps(XmlElement rPr, FormatChange c) {
    if (c.bold != null) _putRProp(rPr, 'b', c.bold! ? _flag('b') : _flag('b', '0'), alsoRemove: const ['bCs']);
    if (c.italic != null) _putRProp(rPr, 'i', c.italic! ? _flag('i') : _flag('i', '0'), alsoRemove: const ['iCs']);
    if (c.underline != null) _putRProp(rPr, 'u', _flag('u', c.underline! ? 'single' : 'none'));
    if (c.strike != null) _putRProp(rPr, 'strike', c.strike! ? _flag('strike') : _flag('strike', '0'));
    if (c.clearColor) _putRProp(rPr, 'color', null);
    if (c.color != null) _putRProp(rPr, 'color', _flag('color', (c.color! & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()));
    if (c.sizePt != null) {
      final half = (c.sizePt! * 2).round().clamp(2, 1638).toString();
      _putRProp(rPr, 'sz', _flag('sz', half), alsoRemove: const ['szCs']);
      _putRProp(rPr, 'szCs', _flag('szCs', half));
    }
  }

  /// left, center, right or both.
  void setAlign(int index, String align) {
    final p = _paras[index];
    _checkpoint();
    var pPr = _child(p, 'pPr');
    if (pPr == null) {
      pPr = XmlElement(_n('pPr'));
      p.children.insert(0, pPr);
    }
    pPr.children.removeWhere((c) => c is XmlElement && c.name.local == 'jc');
    final jc = _flag('jc', align == 'both' ? 'both' : align);
    final at = pPr.children.indexWhere((c) => c is XmlElement && _pPrAfterJc.contains(c.name.local));
    pPr.children.insert(at < 0 ? pPr.children.length : at, jc);
  }

  // endregion

  /// Adds an empty paragraph after paragraph [index], with the same layout and text look. Returns its index.
  int insertParagraphAfter(int index, {String text = ''}) {
    final p = _paras[index];
    _checkpoint();
    final created = XmlElement(_n('p'));
    final pPr = _child(p, 'pPr');
    if (pPr != null) {
      final copy = pPr.copy();
      copy.children.removeWhere((c) => c is XmlElement && (c.name.local == 'sectPr' || c.name.local == 'pPrChange'));
      created.children.add(copy);
    }
    final runs = _runsOf(p);
    if (text.isNotEmpty) {
      final run = XmlElement(_n('r'));
      final props = runs.isEmpty ? null : _child(runs.last, 'rPr');
      if (props != null) run.children.add(props.copy());
      created.children.add(run);
      _writeRunText(run, text);
    }
    p.parent!.children.insert(p.parent!.children.indexOf(p) + 1, created);
    _refresh();
    return _paras.indexOf(created);
  }

  /// Removes a paragraph. A table cell or a section break needs one, so then it is only emptied.
  void deleteParagraph(int index) {
    final p = _paras[index];
    _checkpoint();
    final parent = p.parent;
    final pPr = _child(p, 'pPr');
    final keeps =
        (parent != null && _is(parent, 'tc') && parent.childElements.where((e) => _is(e, 'p')).length == 1) || (pPr != null && _child(pPr, 'sectPr') != null);
    if (keeps) {
      for (final r in _runsOf(p).toList()) {
        if (_isPureText(r)) {
          r.remove();
        } else {
          _writeRunText(r, '');
        }
      }
    } else {
      p.remove();
    }
    _refresh();
  }

  // ------------------------------------------------------------------ search

  List<DocMatch> findAll(String query, {bool matchCase = false}) {
    if (query.isEmpty) return const [];
    final q = matchCase ? query : query.toLowerCase();
    final out = <DocMatch>[];
    for (var i = 0; i < _paras.length; i++) {
      final text = paragraphText(i);
      final hay = matchCase ? text : text.toLowerCase();
      if (hay.length != text.length) continue;
      var from = 0;
      while (true) {
        final at = hay.indexOf(q, from);
        if (at < 0) break;
        out.add(DocMatch(i, at, at + q.length));
        from = at + math.max(q.length, 1);
      }
    }
    return out;
  }

  /// Replaces every match; returns how many were replaced.
  int replaceAll(String query, String replacement, {bool matchCase = false}) {
    final matches = findAll(query, matchCase: matchCase);
    if (matches.isEmpty) return 0;
    _checkpoint();
    for (final m in matches.reversed) {
      _splice(_paras[m.paragraph], m.start, m.end, replacement);
    }
    return matches.length;
  }
}

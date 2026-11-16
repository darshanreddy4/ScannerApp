import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import 'docx_builder.dart';

class DocxFormatException implements Exception {
  const DocxFormatException(this.message);
  final String message;
}

const _wNs = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

// ------------------------------------------------------------------ what the editor shows

/// A stretch of text that is shown in one look.
class RunSpan {
  const RunSpan(this.text, {this.bold = false, this.italic = false, this.underline = false, this.strike = false, this.color, this.sizePt, this.font});
  final String text;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strike;

  /// ARGB, or null for the default colour.
  final int? color;
  final double? sizePt;

  /// Font family named in the file, or null when it comes from a theme.
  final String? font;
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
  const FormatState({this.bold, this.italic, this.underline, this.strike, this.sizePt, this.color, this.font, this.align = 'left'});
  final bool? bold;
  final bool? italic;
  final bool? underline;
  final bool? strike;
  final double? sizePt;
  final int? color;
  final String? font;
  final String align;
}

/// A change to the look of text. Null leaves a setting as it is.
class FormatChange {
  const FormatChange({this.bold, this.italic, this.underline, this.strike, this.sizePt, this.color, this.clearColor = false, this.font});
  final bool? bold;
  final bool? italic;
  final bool? underline;
  final bool? strike;
  final double? sizePt;

  /// A font family name to apply.
  final String? font;

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
  String? font;

  _Fmt copy() => _Fmt()
    ..bold = bold
    ..italic = italic
    ..underline = underline
    ..strike = strike
    ..color = color
    ..size = size
    ..font = font;
}

class _StyleDef {
  _StyleDef({required this.id, required this.type, this.name, this.basedOn, this.rPr, this.pPr, this.isDefault = false});
  final String id;
  final String type;
  final String? name;
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
const _pPrOrder = [
  'pStyle', 'keepNext', 'keepLines', 'pageBreakBefore', 'framePr', 'widowControl', 'numPr', 'suppressLineNumbers', 'pBdr', 'shd', 'tabs', //
  'suppressAutoHyphens', 'kinsoku', 'wordWrap', 'overflowPunct', 'topLinePunct', 'autoSpaceDE', 'autoSpaceDN', 'bidi', 'adjustRightInd', 'snapToGrid',
  'spacing', 'ind', 'contextualSpacing', 'mirrorIndents', 'suppressOverlap', 'jc', ..._pPrAfterJc,
];

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

  // Parts that this class may change besides the body; they are written back only when touched.
  XmlDocument? _stylesDoc;
  var _stylesTouched = false;
  var _numberingTouched = false;

  // Parts added or rewritten by the editor (pictures, headers, footers), with the relationships and content types they need.
  final Map<String, List<int>> _newFiles = {};
  final List<({String id, String type, String target})> _newRels = [];
  final List<({String part, String contentType})> _newOverrides = [];
  final Set<String> _newExtensions = {};
  static const _imageTypes = {'png': 'image/png', 'jpg': 'image/jpeg', 'jpeg': 'image/jpeg'};

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
    final replaced = <String, List<int>>{'word/document.xml': utf8.encode(_doc.toXmlString())};
    final newParts = <({String name, String contentType, String relType, String id})>[];
    const wordType = 'application/vnd.openxmlformats-officedocument.wordprocessingml';
    const relBase = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
    final styles = _stylesDoc;
    if (_stylesTouched && styles != null) {
      replaced['word/styles.xml'] = utf8.encode(styles.toXmlString());
      if (_archive.findFile('word/styles.xml') == null) {
        newParts.add((name: 'word/styles.xml', contentType: '$wordType.styles+xml', relType: '$relBase/styles', id: 'rIdDlStyles'));
      }
    }
    final numbering = _numberingDoc;
    if (_numberingTouched && numbering != null) {
      replaced['word/numbering.xml'] = utf8.encode(numbering.toXmlString());
      if (_archive.findFile('word/numbering.xml') == null) {
        newParts.add((name: 'word/numbering.xml', contentType: '$wordType.numbering+xml', relType: '$relBase/numbering', id: 'rIdDlNumbering'));
      }
    }
    if (newParts.isNotEmpty || _newRels.isNotEmpty) {
      final types = _archive.findFile('[Content_Types].xml');
      if (types != null) {
        var s = utf8.decode(types.readBytes()!, allowMalformed: true);
        final add = StringBuffer(newParts.map((p) => '<Override PartName="/${p.name}" ContentType="${p.contentType}"/>').join());
        for (final o in _newOverrides) {
          add.write('<Override PartName="/${o.part}" ContentType="${o.contentType}"/>');
        }
        for (final ext in _newExtensions) {
          if (!s.toLowerCase().contains('extension="$ext"')) add.write('<Default Extension="$ext" ContentType="${_imageTypes[ext]}"/>');
        }
        final at = s.lastIndexOf('</Types>');
        if (at >= 0) replaced['[Content_Types].xml'] = utf8.encode(s.substring(0, at) + add.toString() + s.substring(at));
      }
      final add = StringBuffer(newParts.map((p) => '<Relationship Id="${p.id}" Type="${p.relType}" Target="${p.name.split('/').last}"/>').join());
      for (final r in _newRels) {
        add.write('<Relationship Id="${r.id}" Type="${r.type}" Target="${r.target}"/>');
      }
      final rels = _archive.findFile('word/_rels/document.xml.rels');
      if (rels != null) {
        final s = utf8.decode(rels.readBytes()!, allowMalformed: true);
        final at = s.lastIndexOf('</Relationships>');
        if (at >= 0) replaced['word/_rels/document.xml.rels'] = utf8.encode(s.substring(0, at) + add.toString() + s.substring(at));
      } else {
        replaced['word/_rels/document.xml.rels'] = utf8.encode(
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">$add</Relationships>',
        );
      }
    }
    replaced.addAll(_newFiles);
    final out = Archive();
    final written = <String>{};
    for (final f in _archive.files) {
      if (!f.isFile) continue;
      out.addFile(ArchiveFile.bytes(f.name, replaced[f.name] ?? f.readBytes()!));
      written.add(f.name);
    }
    for (final e in replaced.entries) {
      if (!written.contains(e.key)) out.addFile(ArchiveFile.bytes(e.key, e.value));
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
    if (entry != null || _stylesDoc != null) {
      try {
        final doc = _stylesDoc ?? XmlDocument.parse(utf8.decode(entry!.readBytes()!, allowMalformed: true));
        for (final c in doc.rootElement.childElements) {
          if (_is(c, 'docDefaults')) {
            _docDefaults = _child(_child(c, 'rPrDefault') ?? c, 'rPr');
          } else if (_is(c, 'style')) {
            final id = _attr(c, 'styleId');
            if (id.isEmpty) continue;
            styles[id] = _StyleDef(
              id: id,
              type: _attr(c, 'type'),
              name: _child(c, 'name') == null ? null : _attr(_child(c, 'name')!, 'val'),
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
        case 'rFonts':
          final named = _attr(c, 'ascii').isNotEmpty ? _attr(c, 'ascii') : _attr(c, 'hAnsi');
          // A theme attribute wins over the name in Word, and the theme is not read here.
          final themed = _attr(c, 'asciiTheme').isNotEmpty || _attr(c, 'hAnsiTheme').isNotEmpty;
          if (themed) {
            f.font = null;
          } else if (named.isNotEmpty) {
            f.font = named;
          }
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
        spans.add(RunSpan(t, bold: f.bold, italic: f.italic, underline: f.underline, strike: f.strike, color: f.color, sizePt: f.size, font: f.font));
      }
      for (final blip in r.descendantElements.where((e) => e.name.local == 'blip')) {
        final id = blip.attributes.where((a) => a.name.local == 'embed').map((a) => a.value).firstOrNull;
        final target = id == null ? null : _relTargets()[id];
        if (target != null) images.add(target);
      }
    }
    final pPr = _child(p, 'pPr');
    final styleId = pPr == null || _child(pPr, 'pStyle') == null ? '' : _attr(_child(pPr, 'pStyle')!, 'val');
    final heading = _headingLevel(styleId);
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
    final added = _newFiles[normalized];
    if (added != null) return Uint8List.fromList(added);
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
    _loadNumbering();
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
    final fonts = formats.map((f) => f.font).toSet();
    return FormatState(
      bold: same((f) => f.bold),
      italic: same((f) => f.italic),
      underline: same((f) => f.underline),
      strike: same((f) => f.strike),
      sizePt: sizes.length == 1 ? sizes.first : null,
      color: colors.length == 1 ? colors.first : null,
      font: fonts.length == 1 ? fonts.first : null,
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
    final font = c.font;
    if (font != null && font.isNotEmpty) {
      final e = _flag('rFonts');
      for (final a in const ['ascii', 'hAnsi', 'cs', 'eastAsia']) {
        _setAttr(e, a, font);
      }
      _putRProp(rPr, 'rFonts', e);
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

  // region styles and lists

  void _loadNumbering() {
    if (_numberingLoaded) return;
    _numberingLoaded = true;
    final entry = _archive.findFile('word/numbering.xml');
    if (entry == null) return;
    try {
      _numberingDoc = XmlDocument.parse(utf8.decode(entry.readBytes()!, allowMalformed: true));
    } catch (_) {
      _numberingDoc = null;
    }
  }

  XmlElement _fragment(String xml) => XmlDocument.parse('<w:r xmlns:w="$docxMainNs">$xml</w:r>').rootElement.childElements.first.copy();

  XmlElement _pPrOf(XmlElement p) {
    final existing = _child(p, 'pPr');
    if (existing != null) return existing;
    final created = XmlElement(_n('pPr'));
    p.children.insert(0, created);
    return created;
  }

  void _putPProp(XmlElement pPr, String local, XmlElement? element) {
    pPr.children.removeWhere((c) => c is XmlElement && c.name.local == local);
    if (element == null) return;
    final rank = _pPrOrder.indexOf(local);
    final at = pPr.children.indexWhere((c) => c is XmlElement && _pPrOrder.indexOf(c.name.local) > rank);
    pPr.children.insert(at < 0 ? pPr.children.length : at, element);
  }

  String _styleIdOf(XmlElement p) {
    final pPr = _child(p, 'pPr');
    final s = pPr == null ? null : _child(pPr, 'pStyle');
    return s == null ? '' : _attr(s, 'val');
  }

  /// 0 for a title, 1 to 9 for headings, null for anything else.
  int? _headingLevel(String styleId) {
    if (styleId.isEmpty) return null;
    final name = (_styles?[styleId]?.name ?? '').toLowerCase();
    final h = RegExp(r'^heading\s*(\d)$').firstMatch(name) ?? RegExp(r'^heading\s*(\d)$', caseSensitive: false).firstMatch(styleId);
    if (h != null) return int.parse(h.group(1)!);
    if (styleId == 'Title' || name == 'title') return 0;
    return null;
  }

  /// The paragraph look of paragraph [index], or null for a style of the file's own that has no button.
  DocStyle? styleOf(int index) {
    _loadStyles();
    final id = _styleIdOf(_paras[index]);
    if (id.isEmpty) return DocStyle.normal;
    final level = _headingLevel(id);
    if (level != null) {
      return switch (level) {
        0 => DocStyle.title,
        1 => DocStyle.heading1,
        2 => DocStyle.heading2,
        3 => DocStyle.heading3,
        _ => null,
      };
    }
    final def = _styles![id];
    return def != null && def.type == 'paragraph' && def.isDefault ? DocStyle.normal : null;
  }

  XmlDocument _stylesDocument() {
    final existing = _stylesDoc;
    if (existing != null) return existing;
    final entry = _archive.findFile('word/styles.xml');
    return _stylesDoc = XmlDocument.parse(entry == null ? emptyStylesXml() : utf8.decode(entry.readBytes()!, allowMalformed: true));
  }

  /// The id of the style the file already has for [style], or a new one added to its styles.
  String _styleIdFor(DocStyle style) {
    _loadStyles();
    if (_styles!.containsKey(style.id)) return style.id;
    final name = switch (style) {
      DocStyle.title => 'title',
      DocStyle.heading1 => 'heading 1',
      DocStyle.heading2 => 'heading 2',
      DocStyle.heading3 => 'heading 3',
      DocStyle.normal => 'normal',
    };
    for (final s in _styles!.values) {
      if (s.type == 'paragraph' && (s.name ?? '').toLowerCase() == name) return s.id;
    }
    final xml = docxStyleXml(style.id);
    if (xml == null) return style.id;
    _stylesDocument().rootElement.children.add(_fragment(xml));
    _stylesTouched = true;
    _styles = null;
    return style.id;
  }

  /// Gives paragraph [index] one of the looks for titles and headings, or the plain look.
  void setStyle(int index, DocStyle style) {
    final p = _paras[index];
    final id = style == DocStyle.normal ? null : _styleIdFor(style);
    _checkpoint();
    final pPr = _pPrOf(p);
    _putPProp(pPr, 'pStyle', id == null ? null : _flag('pStyle', id));
    if (id != null) _putPProp(pPr, 'numPr', null);
  }

  XmlElement _numberingRoot() {
    _loadNumbering();
    if (_numberingDoc == null) {
      if (_archive.findFile('word/numbering.xml') != null) throw const DocxFormatException('The lists of this document could not be read.');
      _numberingDoc = XmlDocument.parse(emptyNumberingXml());
    }
    _numberingTouched = true;
    return _numberingDoc!.rootElement;
  }

  XmlElement? _abstractOf(XmlElement root, String numId) {
    final num = root.childElements.where((e) => _is(e, 'num') && _attr(e, 'numId') == numId).firstOrNull;
    final link = num == null ? null : _child(num, 'abstractNumId');
    if (link == null) return null;
    final id = _attr(link, 'val');
    return root.childElements.where((e) => _is(e, 'abstractNum') && _attr(e, 'abstractNumId') == id).firstOrNull;
  }

  bool _isBulletList(XmlElement? abstract) {
    final lvl = abstract?.childElements.where((e) => _is(e, 'lvl') && _attr(e, 'ilvl') == '0').firstOrNull;
    final fmt = lvl == null || _child(lvl, 'numFmt') == null ? 'bullet' : _attr(_child(lvl, 'numFmt')!, 'val');
    return fmt == 'bullet' || fmt == 'none';
  }

  ({String numId, DocList kind})? _listOf(XmlElement p) {
    _loadStyles();
    final pPr = _child(p, 'pPr');
    var numPr = pPr == null ? null : _child(pPr, 'numPr');
    if (numPr == null) {
      for (final style in _chain(_styleIdOf(p)).reversed) {
        final found = style.pPr == null ? null : _child(style.pPr!, 'numPr');
        if (found != null) {
          numPr = found;
          break;
        }
      }
    }
    final idElement = numPr == null ? null : _child(numPr, 'numId');
    final numId = idElement == null ? '' : _attr(idElement, 'val');
    if (numId.isEmpty || numId == '0') return null;
    _loadNumbering();
    final root = _numberingDoc?.rootElement;
    if (root == null) return (numId: numId, kind: DocList.bullet);
    return (numId: numId, kind: _isBulletList(_abstractOf(root, numId)) ? DocList.bullet : DocList.number);
  }

  /// Whether paragraph [index] is a bullet item, a numbered item or neither.
  DocList listKindOf(int index) => _listOf(_paras[index])?.kind ?? DocList.none;

  String _numIdFor(DocList kind, int index) {
    final root = _numberingRoot();
    if (kind == DocList.number && index > 0) {
      final above = _listOf(_paras[index - 1]);
      if (above != null && above.kind == DocList.number) return above.numId;
    }
    final nums = root.childElements.where((e) => _is(e, 'num')).toList();
    if (kind == DocList.bullet) {
      for (final n in nums) {
        if (_isBulletList(_abstractOf(root, _attr(n, 'numId')))) return _attr(n, 'numId');
      }
    }
    int maxOf(Iterable<XmlElement> list, String attr) => list.fold<int>(0, (m, e) => math.max(m, int.tryParse(_attr(e, attr)) ?? 0));
    final abstracts = root.childElements.where((e) => _is(e, 'abstractNum')).toList();
    XmlElement? reuse;
    for (final a in abstracts) {
      if (_isBulletList(a) == (kind == DocList.bullet)) {
        reuse = a;
        break;
      }
    }
    final int abstractId;
    if (reuse != null) {
      abstractId = int.tryParse(_attr(reuse, 'abstractNumId')) ?? 0;
    } else {
      abstractId = maxOf(abstracts, 'abstractNumId') + 1;
      final firstNum = root.children.indexWhere((c) => c is XmlElement && _is(c, 'num'));
      root.children.insert(firstNum < 0 ? root.children.length : firstNum, _fragment(docxAbstractNumXml(kind, abstractId)));
    }
    final numId = maxOf(nums, 'numId') + 1;
    root.children.add(_fragment(docxNumXml(numId, abstractId, restart: kind == DocList.number)));
    return '$numId';
  }

  /// Turns paragraph [index] into a bullet item or a numbered item, or takes it out of a list.
  void setList(int index, DocList kind) {
    final p = _paras[index];
    final current = _listOf(p);
    final numId = kind == DocList.none ? null : _numIdFor(kind, index);
    _checkpoint();
    final pPr = _pPrOf(p);
    XmlElement numPr(String id) => XmlElement(_n('numPr'))..children.addAll([_flag('ilvl', '0'), _flag('numId', id)]);
    if (numId != null) {
      final style = styleOf(index);
      if (style != null && style != DocStyle.normal) _putPProp(pPr, 'pStyle', null);
      _putPProp(pPr, 'numPr', numPr(numId));
    } else if (current != null) {
      _putPProp(pPr, 'numPr', numPr('0'));
    }
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

  // ------------------------------------------------------------------ pictures

  static const _wpNs = 'http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing';
  static const _aNs = 'http://schemas.openxmlformats.org/drawingml/2006/main';
  static const _picNs = 'http://schemas.openxmlformats.org/drawingml/2006/picture';
  static const _rNs = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
  var _addedCount = 0;

  XmlElement _parseWithNamespaces(String xml) => XmlDocument.parse(
    xml.replaceFirstMapped(RegExp(r'^<([\w:]+)'), (m) => '<${m[1]} xmlns:w="$_wNs" xmlns:r="$_rNs" xmlns:wp="$_wpNs" xmlns:a="$_aNs" xmlns:pic="$_picNs"'),
  ).rootElement.copy();

  /// Adds a picture, centred in a paragraph of its own, after paragraph [index]. Only PNG and JPEG are accepted. A picture wider than
  /// [maxWidthPt] is made to fit. Returns the index of the new paragraph.
  int insertPictureAfter(int index, Uint8List bytes, {required String extension, required int pixelWidth, required int pixelHeight, double maxWidthPt = 400}) {
    final ext = extension.toLowerCase().replaceFirst('.', '') == 'jpeg' ? 'jpg' : extension.toLowerCase().replaceFirst('.', '');
    if (!_imageTypes.containsKey(ext)) throw ArgumentError('Only PNG and JPEG pictures can be added.');
    if (pixelWidth <= 0 || pixelHeight <= 0) throw ArgumentError('The picture has no size.');
    final anchor = _paras[index];
    _checkpoint();
    String part;
    do {
      _addedCount++;
      part = 'word/media/dlpic$_addedCount.$ext';
    } while (_newFiles.containsKey(part) || _archive.findFile(part) != null);
    final id = 'rIdDlPic$_addedCount';
    final widthPt = math.min(pixelWidth * 0.75, maxWidthPt);
    final heightPt = widthPt * pixelHeight / pixelWidth;
    final cx = (widthPt * 12700).round(), cy = (heightPt * 12700).round();
    var docPrId = 0;
    for (final e in _doc.descendantElements.where((e) => e.name.local == 'docPr')) {
      docPrId = math.max(docPrId, int.tryParse(e.getAttribute('id') ?? '') ?? 0);
    }
    docPrId++;
    final para = _parseWithNamespaces(
      '<w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0">'
      '<wp:extent cx="$cx" cy="$cy"/><wp:docPr id="$docPrId" name="Picture $docPrId"/>'
      '<wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect="1"/></wp:cNvGraphicFramePr>'
      '<a:graphic><a:graphicData uri="$_picNs"><pic:pic><pic:nvPicPr><pic:cNvPr id="0" name="${part.split('/').last}"/><pic:cNvPicPr/></pic:nvPicPr>'
      '<pic:blipFill><a:blip r:embed="$id"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
      '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$cx" cy="$cy"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>'
      '</pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>',
    );
    _newFiles[part] = bytes;
    _newRels.add((id: id, type: '$_rNs/image', target: 'media/${part.split('/').last}'));
    _newExtensions.add(ext);
    _relTargets()[id] = part;
    anchor.parent!.children.insert(anchor.parent!.children.indexOf(anchor) + 1, para);
    _refresh();
    return _paras.indexWhere((p) => identical(p, para));
  }

  // ------------------------------------------------------------------ header and footer

  /// Every relationship of the document: id to (type, part path).
  Map<String, ({String type, String part})> _allRelationships() {
    final out = <String, ({String type, String part})>{};
    final entry = _archive.findFile('word/_rels/document.xml.rels');
    if (entry != null) {
      try {
        final doc = XmlDocument.parse(utf8.decode(entry.readBytes()!, allowMalformed: true));
        for (final r in doc.rootElement.childElements) {
          final id = r.getAttribute('Id'), target = r.getAttribute('Target'), type = r.getAttribute('Type');
          if (id != null && target != null && type != null && r.getAttribute('TargetMode') != 'External') {
            out[id] = (type: type, part: target.startsWith('/') ? target.substring(1) : 'word/$target');
          }
        }
      } catch (_) {
        // No header or footer is found.
      }
    }
    for (final r in _newRels) {
      out[r.id] = (type: r.type, part: 'word/${r.target}');
    }
    return out;
  }

  XmlElement? get _sectPr {
    final body = _body;
    if (body == null) return null;
    return body.childElements.where((e) => _is(e, 'sectPr')).lastOrNull;
  }

  /// The part of the header or footer shown on every page, or null when the document has none.
  String? _hfPart(String kind) {
    final sect = _sectPr;
    if (sect == null) return null;
    final rels = _allRelationships();
    for (final ref in sect.childElements.where((e) => _is(e, '${kind}Reference'))) {
      if (_attr(ref, 'type') != 'default') continue;
      final id = ref.attributes.where((a) => a.name.local == 'id').map((a) => a.value).firstOrNull;
      final part = id == null ? null : rels[id]?.part;
      if (part != null) return part;
    }
    return null;
  }

  XmlDocument? _hfDocument(String? part) {
    if (part == null) return null;
    final bytes = _newFiles[part] ?? _archive.findFile(part)?.readBytes();
    if (bytes == null) return null;
    try {
      return XmlDocument.parse(utf8.decode(bytes, allowMalformed: true));
    } catch (_) {
      return null;
    }
  }

  static bool _hasPageField(XmlElement p) =>
      p.descendantElements.any((e) => (e.name.local == 'fldSimple' && (e.getAttribute('w:instr') ?? e.getAttribute('instr') ?? '').toUpperCase().contains('PAGE')) ||
          (e.name.local == 'instrText' && e.innerText.toUpperCase().contains('PAGE')));

  /// The text of the header and the footer that every page shows, and whether the footer or header numbers the pages.
  ({String header, String footer, bool pageNumbers}) headerFooter() {
    var numbers = false;
    String read(String kind) {
      final doc = _hfDocument(_hfPart(kind));
      if (doc == null) return '';
      final lines = <String>[];
      for (final p in doc.rootElement.descendantElements.where((e) => _is(e, 'p'))) {
        if (_hasPageField(p)) {
          numbers = true;
          continue;
        }
        final text = p.descendantElements.where((e) => e.name.local == 't').map((e) => e.innerText).join();
        if (text.trim().isNotEmpty) lines.add(text);
      }
      return lines.join('\n');
    }

    final header = read('header'), footer = read('footer');
    return (header: header, footer: footer, pageNumbers: numbers);
  }

  /// Sets the text at the top and bottom of every page, and page numbers in the footer. Text and numbers are centred.
  /// A header or footer that has no text and no numbers is left as it is when the document had none.
  void setHeaderFooter({required String header, required String footer, required bool pageNumbers, String pageWord = 'Page', String ofWord = 'of'}) {
    String esc(String s) => XmlText(s).toXmlString();
    String line(String text) =>
        '<w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:t xml:space="preserve">${esc(text)}</w:t></w:r></w:p>';
    String lines(String text) => [for (final l in text.split('\n')) if (l.trim().isNotEmpty) line(l.trim())].join();
    final numberLine = '<w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:t xml:space="preserve">${esc('$pageWord ')}</w:t></w:r>'
        '<w:fldSimple w:instr=" PAGE "><w:r><w:t>1</w:t></w:r></w:fldSimple>'
        '<w:r><w:t xml:space="preserve">${esc(' $ofWord ')}</w:t></w:r><w:fldSimple w:instr=" NUMPAGES "><w:r><w:t>1</w:t></w:r></w:fldSimple></w:p>';

    void write(String kind, String paragraphs) {
      var part = _hfPart(kind);
      if (part == null && paragraphs.isEmpty) return;
      final tag = kind == 'header' ? 'hdr' : 'ftr';
      final xml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:$tag xmlns:w="$_wNs" xmlns:r="$_rNs">${paragraphs.isEmpty ? '<w:p/>' : paragraphs}</w:$tag>';
      if (part == null) {
        var n = 0;
        do {
          n++;
          part = 'word/$kind$n.xml';
        } while (_newFiles.containsKey(part) || _archive.findFile(part) != null);
        final id = 'rIdDl${kind == 'header' ? 'Header' : 'Footer'}$n';
        _newRels.add((id: id, type: '$_rNs/$kind', target: '$kind$n.xml'));
        _newOverrides.add((part: part, contentType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.$kind+xml'));
        var sect = _sectPr;
        if (sect == null) {
          sect = XmlElement(_n('sectPr'));
          _body!.children.add(sect);
        }
        sect.children.insert(0, _parseWithNamespaces('<w:${kind}Reference w:type="default" r:id="$id"/>'));
      }
      _newFiles[part] = utf8.encode(xml);
    }

    write('header', lines(header));
    write('footer', lines(footer) + (pageNumbers ? numberLine : ''));
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

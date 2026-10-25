import 'dart:math' as math;
import 'dart:typed_data';

import 'package:xml/xml.dart';

import '../domain/slide_model.dart';
import 'pptx_package.dart';
import 'pptx_template.dart';
import 'slide_reader.dart';

const _nsDecl =
    'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"';

XmlElement _fragment(String xml) => XmlDocument.parse('<root $_nsDecl>$xml</root>').rootElement.childElements.first.copy();

String _esc(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
String _hex(int argb) => (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

Iterable<XmlElement> _kids(XmlElement? e, String name) => e == null ? const [] : e.childElements.where((c) => c.name.local == name);

class _Snapshot {
  _Snapshot(this.order, this.xml, this.rels);
  final List<SlidePart> order;
  final Map<SlidePart, String> xml;
  final Map<SlidePart, List<Rel>> rels;
}

/// Changes a [PptxDeck] and remembers each change so it can be undone.
class DeckEditor {
  DeckEditor(this.deck) : reader = SlideReader(deck);

  final PptxDeck deck;
  final SlideReader reader;
  final List<_Snapshot> _undo = [];
  final List<_Snapshot> _redo = [];
  static const _maxHistory = 30;

  bool modified = false;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  SlideView view(SlidePart slide) => reader.read(slide);

  // ------------------------------------------------------------------- history

  _Snapshot _capture(Iterable<SlidePart> touched) =>
      _Snapshot(List.of(deck.slides), {for (final s in touched) s: s.snapshot()}, {for (final s in touched) s: List.of(s.rels)});

  void _restore(_Snapshot st) {
    deck.slides
      ..clear()
      ..addAll(st.order);
    st.xml.forEach((slide, xml) {
      slide.doc = XmlDocument.parse(xml);
      slide.dirty = true;
    });
    st.rels.forEach((slide, rels) => slide.rels = rels);
  }

  void _checkpoint(Iterable<SlidePart> touched) {
    _undo.add(_capture(touched));
    if (_undo.length > _maxHistory) _undo.removeAt(0);
    _redo.clear();
    modified = true;
  }

  void undo() {
    if (_undo.isEmpty) return;
    final st = _undo.removeLast();
    _redo.add(_capture(st.xml.keys));
    _restore(st);
    modified = true;
  }

  void redo() {
    if (_redo.isEmpty) return;
    final st = _redo.removeLast();
    _undo.add(_capture(st.xml.keys));
    _restore(st);
    modified = true;
  }

  // ----------------------------------------------------------------- finding

  XmlElement? _find(SlidePart slide, String id) {
    for (final el in slide.spTree.childElements) {
      final holder = _cNvPr(el);
      if (holder?.getAttribute('id') == id) return el;
    }
    return null;
  }

  XmlElement? _cNvPr(XmlElement shape) {
    for (final k in shape.childElements) {
      if (k.name.local.startsWith('nv')) {
        final c = k.childElements.where((e) => e.name.local == 'cNvPr').firstOrNull;
        if (c != null) return c;
      }
    }
    return null;
  }

  int _nextId(SlidePart slide) {
    var m = 1;
    for (final e in slide.doc.descendants.whereType<XmlElement>()) {
      if (e.name.local == 'cNvPr') m = math.max(m, int.tryParse(e.getAttribute('id') ?? '') ?? 0);
    }
    return m + 1;
  }

  void _touch(SlidePart slide) => slide.dirty = true;

  ShapeView? shapeOf(SlidePart slide, String id) {
    for (final s in view(slide).shapes) {
      if (s.id == id && s.element != null) return s;
    }
    return null;
  }

  // ------------------------------------------------------------------- text

  /// Replaces the text of a shape. Each line becomes a paragraph that keeps the look of the paragraph it replaces.
  void setText(SlidePart slide, String id, String text) {
    final sp = _find(slide, id);
    if (sp == null) return;
    _checkpoint([slide]);
    var body = _kids(sp, 'txBody').firstOrNull;
    if (body == null) {
      body = _fragment('<p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:endParaRPr lang="en-US"/></a:p></p:txBody>');
      sp.children.add(body);
    }
    final paras = _kids(body, 'p').toList();
    final lines = text.split('\n');
    XmlElement templatePara(int i) => paras.isEmpty ? _fragment('<a:p/>') : paras[math.min(i, paras.length - 1)];
    for (final p in paras) {
      p.remove();
    }
    for (var i = 0; i < lines.length; i++) {
      final src = templatePara(i);
      final p = _fragment('<a:p/>');
      final pPr = _kids(src, 'pPr').firstOrNull;
      if (pPr != null) p.children.add(pPr.copy());
      final firstRun = _kids(src, 'r').firstOrNull;
      final rPr = firstRun == null ? null : _kids(firstRun, 'rPr').firstOrNull;
      final end = _kids(src, 'endParaRPr').firstOrNull;
      if (lines[i].isNotEmpty) {
        final r = _fragment('<a:r><a:t/></a:r>');
        if (rPr != null) r.children.insert(0, rPr.copy());
        r.childElements.firstWhere((e) => e.name.local == 't').innerText = lines[i];
        p.children.add(r);
      }
      final endCopy = end?.copy() ?? (rPr == null ? null : _toEnd(rPr));
      if (endCopy != null) p.children.add(endCopy);
      body.children.add(p);
    }
    _touch(slide);
  }

  XmlElement _toEnd(XmlElement rPr) {
    final e = rPr.copy();
    return XmlElement(XmlName('a:endParaRPr'), e.attributes.map((a) => a.copy()), e.children.map((c) => c.copy()));
  }

  /// Changes the look of all text of a shape. Values that are null stay as they are.
  void styleText(SlidePart slide, String id, {double? sizePt, double? sizeDelta, bool? bold, bool? italic, bool? underline, int? color, String? align}) {
    final sp = _find(slide, id);
    final shape = shapeOf(slide, id);
    if (sp == null || shape == null) return;
    _checkpoint([slide]);
    final body = _kids(sp, 'txBody').firstOrNull;
    if (body == null) return;
    var pi = 0;
    for (final p in _kids(body, 'p')) {
      final resolved = pi < shape.paragraphs.length ? shape.paragraphs[pi] : null;
      pi++;
      if (align != null) {
        var pPr = _kids(p, 'pPr').firstOrNull;
        if (pPr == null) {
          pPr = _fragment('<a:pPr/>');
          p.children.insert(0, pPr);
        }
        pPr.setAttribute('algn', align);
      }
      for (final r in p.childElements.where((e) => const {'r', 'fld'}.contains(e.name.local))) {
        final runIndex = resolved == null ? -1 : _runIndex(p, r);
        final current = resolved != null && runIndex >= 0 && runIndex < resolved.runs.length ? resolved.runs[runIndex] : null;
        var rPr = _kids(r, 'rPr').firstOrNull;
        if (rPr == null) {
          rPr = _fragment('<a:rPr lang="en-US"/>');
          r.children.insert(0, rPr);
        }
        _applyRun(rPr, current, sizePt: sizePt, sizeDelta: sizeDelta, bold: bold, italic: italic, underline: underline, color: color);
      }
      final end = _kids(p, 'endParaRPr').firstOrNull;
      if (end != null && (sizePt != null || sizeDelta != null)) {
        final base = resolved?.endSizePt ?? 18;
        end.setAttribute('sz', ((sizePt ?? math.max(6, base + sizeDelta!)) * 100).round().toString());
      }
    }
    _touch(slide);
  }

  /// Position of run [r] among the runs and line breaks of [p], matching the order of the resolved runs.
  int _runIndex(XmlElement p, XmlElement r) {
    var i = 0;
    for (final c in p.childElements) {
      if (c == r) return i;
      if (const {'r', 'br', 'fld'}.contains(c.name.local)) i++;
    }
    return -1;
  }

  void _applyRun(XmlElement rPr, RunView? current, {double? sizePt, double? sizeDelta, bool? bold, bool? italic, bool? underline, int? color}) {
    if (sizePt != null) {
      rPr.setAttribute('sz', (sizePt * 100).round().toString());
    } else if (sizeDelta != null) {
      final base = current?.sizePt ?? 18;
      rPr.setAttribute('sz', (math.max(6, base + sizeDelta) * 100).round().toString());
    }
    if (bold != null) rPr.setAttribute('b', bold ? '1' : '0');
    if (italic != null) rPr.setAttribute('i', italic ? '1' : '0');
    if (underline != null) rPr.setAttribute('u', underline ? 'sng' : 'none');
    if (color != null) {
      for (final f in _kids(rPr, 'solidFill').toList()) {
        f.remove();
      }
      for (final f in _kids(rPr, 'noFill').toList()) {
        f.remove();
      }
      // Fill goes before the font elements, as the schema asks.
      final fill = _fragment('<a:solidFill><a:srgbClr val="${_hex(color)}"/></a:solidFill>');
      final at = rPr.children.indexWhere(
        (c) => c is XmlElement && const {'latin', 'ea', 'cs', 'sym', 'hlinkClick', 'hlinkMouseOver', 'rtl', 'extLst'}.contains(c.name.local),
      );
      at < 0 ? rPr.children.add(fill) : rPr.children.insert(at, fill);
    }
  }

  // ------------------------------------------------------------------ geometry

  /// Moves or resizes a shape. Shapes that took their place from the layout get their own position.
  void setFrame(SlidePart slide, String id, Frame frame, {bool checkpoint = true}) {
    final el = _find(slide, id);
    if (el == null) return;
    if (checkpoint) _checkpoint([slide]);
    final isFrame = el.name.local == 'graphicFrame';
    XmlElement? holder = isFrame ? el : _kids(el, 'spPr').firstOrNull;
    if (holder == null) {
      holder = _fragment('<p:spPr/>');
      el.children.add(holder);
    }
    var x = _kids(holder, 'xfrm').firstOrNull;
    if (x == null) {
      x = _fragment(isFrame ? '<p:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/></p:xfrm>' : '<a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/></a:xfrm>');
      // The position comes first in the shape properties, and after the properties in a frame.
      if (isFrame) {
        final at = holder.children.indexWhere((c) => c is XmlElement && c.name.local == 'graphic');
        at < 0 ? holder.children.add(x) : holder.children.insert(at, x);
      } else {
        holder.children.insert(0, x);
      }
    }
    final off = _kids(x, 'off').first, ext = _kids(x, 'ext').first;
    off.setAttribute('x', frame.x.round().toString());
    off.setAttribute('y', frame.y.round().toString());
    ext.setAttribute('cx', math.max(0, frame.w).round().toString());
    ext.setAttribute('cy', math.max(0, frame.h).round().toString());
    if (frame.rot != 0) {
      x.setAttribute('rot', (frame.rot * 60000).round().toString());
    } else {
      x.removeAttribute('rot');
    }
    _touch(slide);
  }

  /// Sets the fill colour of a shape, or removes the fill when [color] is null.
  void setFill(SlidePart slide, String id, int? color) {
    final el = _find(slide, id);
    if (el == null) return;
    final spPr = _kids(el, 'spPr').firstOrNull;
    if (spPr == null) return;
    _checkpoint([slide]);
    for (final n in ['noFill', 'solidFill', 'gradFill', 'blipFill', 'pattFill', 'grpFill']) {
      for (final f in _kids(spPr, n).toList()) {
        f.remove();
      }
    }
    final fill = _fragment(color == null ? '<a:noFill/>' : '<a:solidFill><a:srgbClr val="${_hex(color)}"/></a:solidFill>');
    final at = spPr.children.indexWhere((c) => c is XmlElement && const {'ln', 'effectLst', 'effectDag', 'scene3d', 'sp3d', 'extLst'}.contains(c.name.local));
    at < 0 ? spPr.children.add(fill) : spPr.children.insert(at, fill);
    _touch(slide);
  }

  void setOutline(SlidePart slide, String id, int? color, {double widthPt = 1.5}) {
    final el = _find(slide, id);
    final spPr = el == null ? null : _kids(el, 'spPr').firstOrNull;
    if (el == null || spPr == null) return;
    _checkpoint([slide]);
    for (final f in _kids(spPr, 'ln').toList()) {
      f.remove();
    }
    final ln = _fragment(
      color == null ? '<a:ln><a:noFill/></a:ln>' : '<a:ln w="${(widthPt * 12700).round()}"><a:solidFill><a:srgbClr val="${_hex(color)}"/></a:solidFill></a:ln>',
    );
    final at = spPr.children.indexWhere((c) => c is XmlElement && const {'effectLst', 'effectDag', 'scene3d', 'sp3d', 'extLst'}.contains(c.name.local));
    at < 0 ? spPr.children.add(ln) : spPr.children.insert(at, ln);
    _touch(slide);
  }

  void delete(SlidePart slide, String id) {
    final el = _find(slide, id);
    if (el == null) return;
    _checkpoint([slide]);
    el.remove();
    _touch(slide);
  }

  /// Returns the id of the copy.
  String? duplicate(SlidePart slide, String id) {
    final el = _find(slide, id);
    if (el == null) return null;
    _checkpoint([slide]);
    final copy = el.copy();
    final newId = _nextId(slide);
    final holder = _cNvPr(copy);
    holder?.setAttribute('id', '$newId');
    holder?.setAttribute('name', '${holder.getAttribute('name') ?? 'Shape'} copy');
    el.parent!.children.insert(el.parent!.children.indexOf(el) + 1, copy);
    // A copy of a placeholder would still be one; make it an ordinary shape.
    for (final ph in copy.descendants.whereType<XmlElement>().where((e) => e.name.local == 'ph').toList()) {
      ph.remove();
    }
    final shape = shapeOf(slide, '$newId');
    if (shape != null) {
      setFrame(slide, '$newId', shape.frame.copyWith(x: shape.frame.x + 228600, y: shape.frame.y + 228600), checkpoint: false);
    }
    _touch(slide);
    return '$newId';
  }

  /// Moves a shape in the stacking order: [toFront] / [toBack], or one step with [delta].
  void reorder(SlidePart slide, String id, {bool? toFront, int delta = 0}) {
    final el = _find(slide, id);
    final parent = el?.parent;
    if (el == null || parent == null) return;
    _checkpoint([slide]);
    final shapes = parent.children.whereType<XmlElement>().where((e) => const {'sp', 'pic', 'graphicFrame', 'grpSp', 'cxnSp'}.contains(e.name.local)).toList();
    final i = shapes.indexOf(el);
    int target;
    if (toFront == true) {
      target = shapes.length - 1;
    } else if (toFront == false) {
      target = 0;
    } else {
      target = (i + delta).clamp(0, shapes.length - 1);
    }
    if (target == i) return;
    el.remove();
    final others = parent.children.whereType<XmlElement>().where((e) => const {'sp', 'pic', 'graphicFrame', 'grpSp', 'cxnSp'}.contains(e.name.local)).toList();
    if (target >= others.length) {
      parent.children.insert(parent.children.indexOf(others.last) + 1, el);
    } else {
      parent.children.insert(parent.children.indexOf(others[target]), el);
    }
    _touch(slide);
  }

  // ------------------------------------------------------------------- adding

  String addTextBox(SlidePart slide, String text, {double? x, double? y, double? w, double? h, double sizePt = 24, int? color}) {
    _checkpoint([slide]);
    final id = _nextId(slide);
    final bw = w ?? deck.width * 0.5, bh = h ?? sizePt * 12700 * 2.2;
    final bx = x ?? (deck.width - bw) / 2, by = y ?? (deck.height - bh) / 2;
    final paras = text
        .split('\n')
        .map(
          (l) =>
              '<a:p><a:r><a:rPr lang="en-US" sz="${(sizePt * 100).round()}" dirty="0">${color == null ? '' : '<a:solidFill><a:srgbClr val="${_hex(color)}"/></a:solidFill>'}</a:rPr><a:t>${_esc(l)}</a:t></a:r></a:p>',
        )
        .join();
    final el = _fragment(
      '<p:sp><p:nvSpPr><p:cNvPr id="$id" name="TextBox $id"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x="${bx.round()}" y="${by.round()}"/><a:ext cx="${bw.round()}" cy="${bh.round()}"/></a:xfrm>'
      '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/></p:spPr><p:txBody><a:bodyPr wrap="square" rtlCol="0"><a:spAutoFit/></a:bodyPr><a:lstStyle/>$paras</p:txBody></p:sp>',
    );
    slide.spTree.children.add(el);
    _touch(slide);
    return '$id';
  }

  String addShape(SlidePart slide, String preset, {int color = 0xFF4472C4, double? w, double? h}) {
    _checkpoint([slide]);
    final id = _nextId(slide);
    final sw = w ?? deck.width * 0.25, sh = h ?? (preset == 'line' ? 0 : deck.height * 0.25);
    final bx = (deck.width - sw) / 2, by = (deck.height - sh) / 2;
    final isLine = preset == 'line' || preset == 'straightConnector1';
    final el = isLine
        ? _fragment(
            '<p:cxnSp><p:nvCxnSpPr><p:cNvPr id="$id" name="Line $id"/><p:cNvCxnSpPr/><p:nvPr/></p:nvCxnSpPr><p:spPr><a:xfrm><a:off x="${bx.round()}" y="${by.round()}"/><a:ext cx="${sw.round()}" cy="0"/></a:xfrm>'
            '<a:prstGeom prst="line"><a:avLst/></a:prstGeom><a:ln w="28575"><a:solidFill><a:srgbClr val="${_hex(color)}"/></a:solidFill></a:ln></p:spPr></p:cxnSp>',
          )
        : _fragment(
            '<p:sp><p:nvSpPr><p:cNvPr id="$id" name="Shape $id"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x="${bx.round()}" y="${by.round()}"/><a:ext cx="${sw.round()}" cy="${sh.round()}"/></a:xfrm>'
            '<a:prstGeom prst="${_esc(preset)}"><a:avLst/></a:prstGeom><a:solidFill><a:srgbClr val="${_hex(color)}"/></a:solidFill><a:ln><a:noFill/></a:ln></p:spPr>'
            '<p:txBody><a:bodyPr rtlCol="0" anchor="ctr"/><a:lstStyle/><a:p><a:pPr algn="ctr"/><a:endParaRPr lang="en-US" dirty="0"/></a:p></p:txBody></p:sp>',
          );
    slide.spTree.children.add(el);
    _touch(slide);
    return '$id';
  }

  String _nextMediaPath(String ext) {
    var i = 1;
    while (deck.files.containsKey('ppt/media/image$i.$ext')) {
      i++;
    }
    return 'ppt/media/image$i.$ext';
  }

  /// Puts a picture on the slide, fitted inside the area given and centred. [ext] is png or jpeg.
  String addPicture(SlidePart slide, Uint8List bytes, String ext, int pixelWidth, int pixelHeight, {double? areaW, double? areaH}) {
    _checkpoint([slide]);
    final id = _nextId(slide);
    final path = _nextMediaPath(ext);
    deck.files[path] = bytes;
    var n = 1;
    while (slide.rels.any((r) => r.id == 'rId$n')) {
      n++;
    }
    final rid = 'rId$n';
    slide.rels = [...slide.rels, Rel(rid, 'image', path)];
    slide.relsDirty = true;
    final aw = areaW ?? deck.width * 0.8, ah = areaH ?? deck.height * 0.8;
    final ratio = pixelWidth / math.max(1, pixelHeight);
    var w = aw, h = aw / ratio;
    if (h > ah) {
      h = ah;
      w = ah * ratio;
    }
    final el = _fragment(
      '<p:pic><p:nvPicPr><p:cNvPr id="$id" name="Picture $id"/><p:cNvPicPr><a:picLocks noChangeAspect="1"/></p:cNvPicPr><p:nvPr/></p:nvPicPr><p:blipFill><a:blip r:embed="$rid"/><a:stretch><a:fillRect/></a:stretch></p:blipFill>'
      '<p:spPr><a:xfrm><a:off x="${((deck.width - w) / 2).round()}" y="${((deck.height - h) / 2).round()}"/><a:ext cx="${w.round()}" cy="${h.round()}"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr></p:pic>',
    );
    slide.spTree.children.add(el);
    _touch(slide);
    return '$id';
  }

  void setBackground(SlidePart slide, int? color) {
    _checkpoint([slide]);
    final cSld = slide.doc.rootElement.childElements.firstWhere((e) => e.name.local == 'cSld');
    for (final b in _kids(cSld, 'bg').toList()) {
      b.remove();
    }
    if (color != null) {
      cSld.children.insert(0, _fragment('<p:bg><p:bgPr><a:solidFill><a:srgbClr val="${_hex(color)}"/></a:solidFill><a:effectLst/></p:bgPr></p:bg>'));
    }
    _touch(slide);
  }

  // -------------------------------------------------------------------- slides

  String _freshSlidePath() {
    var i = 1;
    bool taken(String p) => deck.files.containsKey(p) || deck.slides.any((s) => s.path == p);
    while (taken('ppt/slides/slide$i.xml')) {
      i++;
    }
    return 'ppt/slides/slide$i.xml';
  }

  /// The layout whose name or type matches [kind] ("blank" or "obj" for title and content), or any layout.
  String _layoutFor(String kind, SlidePart? like) {
    String? best;
    for (final k in deck.files.keys) {
      if (!k.startsWith('ppt/slideLayouts/') || !k.endsWith('.xml')) continue;
      final doc = deck.parse(k);
      final type = doc.rootElement.getAttribute('type');
      if (type == kind) {
        best = k;
        break;
      }
    }
    return best ?? like?.layoutPath ?? deck.layoutFallback;
  }

  SlidePart addSlide({bool blank = false, int? after}) {
    _checkpoint(const []);
    final layoutKind = blank ? 'blank' : 'obj';
    final layout = _layoutFor(layoutKind, null);
    final part = SlidePart(path: _freshSlidePath(), deck: deck)
      ..doc = XmlDocument.parse(newSlideXml(withPlaceholders: !blank))
      ..rels = [Rel('rId1', 'slideLayout', layout)]
      ..dirty = true
      ..relsDirty = true
      ..isNew = true;
    final at = (after ?? deck.slides.length - 1) + 1;
    deck.slides.insert(at.clamp(0, deck.slides.length), part);
    deck.structureChanged = true;
    return part;
  }

  SlidePart duplicateSlide(int index) {
    _checkpoint(const []);
    final src = deck.slides[index];
    final part = SlidePart(path: _freshSlidePath(), deck: deck)
      ..doc = XmlDocument.parse(src.snapshot())
      ..rels = [
        for (final r in src.rels)
          if (r.type != 'notesSlide') r,
      ]
      ..dirty = true
      ..relsDirty = true
      ..isNew = true;
    deck.slides.insert(index + 1, part);
    deck.structureChanged = true;
    return part;
  }

  /// Returns false when it is the only slide.
  bool deleteSlide(int index) {
    if (deck.slides.length <= 1) return false;
    _checkpoint(const []);
    deck.slides.removeAt(index);
    deck.structureChanged = true;
    return true;
  }

  void moveSlide(int from, int to) {
    if (from == to || from < 0 || to < 0 || from >= deck.slides.length || to >= deck.slides.length) return;
    _checkpoint(const []);
    deck.slides.insert(to, deck.slides.removeAt(from));
    deck.structureChanged = true;
  }

  /// Slide titles or the first text on each slide, for the outline and for search.
  List<int> findText(String query) {
    if (query.isEmpty) return const [];
    final q = query.toLowerCase();
    final hits = <int>[];
    for (var i = 0; i < deck.slides.length; i++) {
      final text = view(deck.slides[i]).shapes.map((s) => s.plainText).join('\n').toLowerCase();
      if (text.contains(q)) hits.add(i);
    }
    return hits;
  }

  /// Plain text of everything on a slide.
  String slideText(SlidePart slide) => view(slide).shapes.where((s) => s.plainText.isNotEmpty).map((s) => s.plainText).join('\n');
}

/// Reads the bytes of a JPEG or PNG file's size without decoding it.
({int width, int height, String ext})? imageInfo(Uint8List b) {
  if (b.length > 24 && b[0] == 0x89 && b[1] == 0x50) {
    final bd = ByteData.sublistView(b);
    return (width: bd.getUint32(16), height: bd.getUint32(20), ext: 'png');
  }
  if (b.length > 4 && b[0] == 0xFF && b[1] == 0xD8) {
    var i = 2;
    final bd = ByteData.sublistView(b);
    while (i + 9 < b.length) {
      if (b[i] != 0xFF) {
        i++;
        continue;
      }
      final marker = b[i + 1];
      if (marker >= 0xC0 && marker <= 0xCF && marker != 0xC4 && marker != 0xC8 && marker != 0xCC) {
        return (width: bd.getUint16(i + 7), height: bd.getUint16(i + 5), ext: 'jpeg');
      }
      i += 2 + bd.getUint16(i + 2);
    }
  }
  return null;
}

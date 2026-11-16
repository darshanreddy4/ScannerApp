import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import 'pptx_package.dart';

const _slideContentType = 'application/vnd.openxmlformats-officedocument.presentationml.slide+xml';
const _relNs = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _mediaTypes = {'png': 'image/png', 'jpeg': 'image/jpeg', 'jpg': 'image/jpeg', 'gif': 'image/gif', 'bmp': 'image/bmp', 'webp': 'image/webp'};

String _relative(String from, String target) {
  final fromParts = from.split('/')..removeLast();
  final toParts = target.split('/');
  var i = 0;
  while (i < fromParts.length && i < toParts.length - 1 && fromParts[i] == toParts[i]) {
    i++;
  }
  return [...List.filled(fromParts.length - i, '..'), ...toParts.sublist(i)].join('/');
}

String _relsXml(String part, List<Rel> rels) {
  final b = StringBuffer(
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">',
  );
  for (final r in rels) {
    final target = r.external ? r.target : _relative(part, r.target);
    b.write(
      '<Relationship Id="${r.id}" Type="${r.fullType}" Target="${const HtmlEscape(HtmlEscapeMode.attribute).convert(target)}"${r.external ? ' TargetMode="External"' : ''}/>',
    );
  }
  b.write('</Relationships>');
  return b.toString();
}

/// Writes the presentation as .pptx. Parts the app did not change are copied from the original file unchanged.
Uint8List writePptx(PptxDeck deck) {
  final files = Map<String, Uint8List>.of(deck.files);
  Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));
  XmlDocument parse(String name) => XmlDocument.parse(utf8.decode(files[name]!, allowMalformed: true));
  void put(String name, XmlDocument d) => files[name] = bytes(d.toXmlString());

  final keep = {for (final s in deck.slides) s.path};

  _writeNotes(deck, files);

  // Slides that changed, and new ones.
  for (final s in deck.slides) {
    if (s.dirty || s.isNew) files[s.path] = bytes(s.doc.toXmlString());
    if (s.relsDirty || s.isNew) files[relsPathOf(s.path)] = bytes(_relsXml(s.path, s.rels));
  }

  if (deck.structureChanged || deck.slides.any((s) => s.isNew)) {
    final pres = parse('ppt/presentation.xml');
    final presRels = deck.readRels('ppt/presentation.xml').toList();
    final ct = parse('[Content_Types].xml');

    // Slides that are gone: their parts, relationships and notes pages.
    final oldPaths = deck.readRels('ppt/presentation.xml').where((r) => r.type == 'slide').map((r) => r.target).toList();
    for (final path in oldPaths) {
      if (keep.contains(path)) continue;
      final rels = files.containsKey(relsPathOf(path)) ? deck.readRels(path) : const <Rel>[];
      for (final r in rels.where((r) => r.type == 'notesSlide')) {
        files.remove(r.target);
        files.remove(relsPathOf(r.target));
        ct.rootElement.children.removeWhere((c) => c is XmlElement && c.getAttribute('PartName') == '/${r.target}');
      }
      files.remove(path);
      files.remove(relsPathOf(path));
      ct.rootElement.children.removeWhere((c) => c is XmlElement && c.getAttribute('PartName') == '/$path');
      presRels.removeWhere((r) => r.target == path);
    }

    var maxId = 255;
    for (final s in deck.slides) {
      if (s.slideId != null && s.slideId! > maxId) maxId = s.slideId!;
    }
    var n = 1;
    String freshRid() {
      while (presRels.any((r) => r.id == 'rId$n')) {
        n++;
      }
      return 'rId${n++}';
    }

    final list = pres.rootElement.childElements.where((e) => e.name.local == 'sldIdLst').firstOrNull ?? XmlElement(XmlName('p:sldIdLst'));
    if (list.parent == null) {
      final at = pres.rootElement.children.indexWhere((c) => c is XmlElement && const {'sldSz', 'notesSz'}.contains(c.name.local));
      at < 0 ? pres.rootElement.children.add(list) : pres.rootElement.children.insert(at, list);
    }
    if (pres.rootElement.getAttribute('xmlns:r') == null) pres.rootElement.setAttribute('xmlns:r', _relNs);
    list.children.clear();
    for (final s in deck.slides) {
      var rid = s.rid;
      final existing = rid != null && presRels.any((r) => r.id == rid && r.target == s.path);
      if (!existing) {
        rid = freshRid();
        presRels.add(Rel(rid, 'slide', s.path));
        s.rid = rid;
        ct.rootElement.children.add(
          XmlElement(XmlName('Override'), [XmlAttribute(XmlName('PartName'), '/${s.path}'), XmlAttribute(XmlName('ContentType'), _slideContentType)]),
        );
      }
      s.slideId ??= ++maxId;
      list.children.add(XmlElement(XmlName('p:sldId'), [XmlAttribute(XmlName('id'), '${s.slideId}'), XmlAttribute(XmlName('r:id'), rid)]));
    }

    // Slide sections list slide numbers; after a change they would point at the wrong slides.
    for (final ext
        in pres.rootElement.descendants
            .whereType<XmlElement>()
            .where((e) => e.name.local == 'ext' && (e.getAttribute('uri') ?? '').toUpperCase() == '{521415D9-36F7-43E2-AB2F-B90AF26B5E84}')
            .toList()) {
      ext.remove();
    }
    put('ppt/presentation.xml', pres);
    files['ppt/_rels/presentation.xml.rels'] = bytes(_relsXml('ppt/presentation.xml', presRels));
    put('[Content_Types].xml', ct);
  }

  // Picture types the content list does not know yet.
  final extensions = {
    for (final k in files.keys)
      if (k.startsWith('ppt/media/') && k.contains('.')) k.substring(k.lastIndexOf('.') + 1).toLowerCase(),
  };
  final ct = parse('[Content_Types].xml');
  var ctChanged = false;
  final known = {for (final e in ct.rootElement.childElements.where((e) => e.name.local == 'Default')) (e.getAttribute('Extension') ?? '').toLowerCase()};
  for (final e in extensions) {
    if (known.contains(e) || !_mediaTypes.containsKey(e)) continue;
    ct.rootElement.children.insert(
      0,
      XmlElement(XmlName('Default'), [XmlAttribute(XmlName('Extension'), e), XmlAttribute(XmlName('ContentType'), _mediaTypes[e]!)]),
    );
    ctChanged = true;
  }
  if (ctChanged) put('[Content_Types].xml', ct);

  final out = Archive();
  final names = files.keys.toList()..sort((a, b) => a == '[Content_Types].xml' ? -1 : (b == '[Content_Types].xml' ? 1 : 0));
  for (final n in names) {
    out.addFile(ArchiveFile.bytes(n, files[n]!));
  }
  return Uint8List.fromList(ZipEncoder().encode(out));
}

// ------------------------------------------------------------------ speaker notes

const _pNs = 'http://schemas.openxmlformats.org/presentationml/2006/main';
const _aNs = 'http://schemas.openxmlformats.org/drawingml/2006/main';
const _notesMasterType = 'application/vnd.openxmlformats-officedocument.presentationml.notesMaster+xml';
const _notesSlideType = 'application/vnd.openxmlformats-officedocument.presentationml.notesSlide+xml';
const _themeType = 'application/vnd.openxmlformats-officedocument.theme+xml';

String _paragraphs(String text) {
  final lines = text.isEmpty ? [''] : text.split('\n');
  return [
    for (final l in lines)
      l.isEmpty ? '<a:p><a:endParaRPr lang="en-US"/></a:p>' : '<a:p><a:r><a:rPr lang="en-US" dirty="0"/><a:t>${XmlText(l).toXmlString()}</a:t></a:r></a:p>',
  ].join();
}

String _freshPart(Map<String, Uint8List> files, String folder, String stem) {
  var i = 1;
  while (files.containsKey('$folder/$stem$i.xml')) {
    i++;
  }
  return '$folder/$stem$i.xml';
}

/// Writes the speaker notes that were changed in the app: into the notes page the slide already has, or into a new one.
void _writeNotes(PptxDeck deck, Map<String, Uint8List> files) {
  final changed = [
    for (final s in deck.slides)
      if (s.notesDirty) s,
  ];
  if (changed.isEmpty) return;
  Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));
  XmlDocument parse(String name) => XmlDocument.parse(utf8.decode(files[name]!, allowMalformed: true));

  String? master;
  XmlDocument? ct;
  void override(String part, String type) {
    ct ??= parse('[Content_Types].xml');
    ct!.rootElement.children.add(XmlElement(XmlName('Override'), [XmlAttribute(XmlName('PartName'), '/$part'), XmlAttribute(XmlName('ContentType'), type)]));
  }

  String ensureMaster() {
    final existing = deck.readRels('ppt/presentation.xml').where((r) => r.type == 'notesMaster' && files.containsKey(r.target)).firstOrNull;
    if (existing != null) return existing.target;
    final themeSource = files.keys.where((k) => RegExp(r'^ppt/theme/theme\d+\.xml$').hasMatch(k)).firstOrNull;
    if (themeSource == null) throw StateError('The presentation has no theme to base the notes on');
    final masterPath = _freshPart(files, 'ppt/notesMasters', 'notesMaster');
    final themePath = _freshPart(files, 'ppt/theme', 'theme');
    files[themePath] = files[themeSource]!;
    override(themePath, _themeType);
    files[masterPath] = bytes(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><p:notesMaster xmlns:a="$_aNs" xmlns:r="$_relNs" xmlns:p="$_pNs"><p:cSld><p:bg><p:bgRef idx="1001"><a:schemeClr val="bg1"/></p:bgRef></p:bg>'
      '<p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>'
      '<p:sp><p:nvSpPr><p:cNvPr id="2" name="Slide Image Placeholder 1"/><p:cNvSpPr><a:spLocks noGrp="1" noRot="1" noChangeAspect="1"/></p:cNvSpPr><p:nvPr><p:ph type="sldImg" idx="2"/></p:nvPr></p:nvSpPr>'
      '<p:spPr><a:xfrm><a:off x="685800" y="1143000"/><a:ext cx="5486400" cy="3086100"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/><a:ln w="12700"><a:solidFill><a:prstClr val="black"/></a:solidFill></a:ln></p:spPr></p:sp>'
      '<p:sp><p:nvSpPr><p:cNvPr id="3" name="Notes Placeholder 2"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr><p:ph type="body" sz="quarter" idx="3"/></p:nvPr></p:nvSpPr>'
      '<p:spPr><a:xfrm><a:off x="685800" y="4400550"/><a:ext cx="5486400" cy="3600450"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr>'
      '<p:txBody><a:bodyPr vert="horz" lIns="91440" tIns="45720" rIns="91440" bIns="45720" rtlCol="0"/><a:lstStyle/><a:p><a:pPr lvl="0"/><a:r><a:rPr lang="en-US"/><a:t>Click to edit Master text styles</a:t></a:r></a:p></p:txBody></p:sp>'
      '</p:spTree></p:cSld><p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>'
      '<p:notesStyle><a:lvl1pPr marL="0" algn="l" defTabSz="914400" rtl="0" eaLnBrk="1" latinLnBrk="0" hangingPunct="1"><a:defRPr sz="1200" kern="1200"><a:solidFill><a:schemeClr val="tx1"/></a:solidFill><a:latin typeface="+mn-lt"/><a:ea typeface="+mn-ea"/><a:cs typeface="+mn-cs"/></a:defRPr></a:lvl1pPr></p:notesStyle></p:notesMaster>',
    );
    files[relsPathOf(masterPath)] = bytes(_relsXml(masterPath, [Rel('rId1', 'theme', themePath)]));
    override(masterPath, _notesMasterType);

    final presRels = deck.readRels('ppt/presentation.xml').toList();
    var n = 1;
    while (presRels.any((r) => r.id == 'rId$n')) {
      n++;
    }
    presRels.add(Rel('rId$n', 'notesMaster', masterPath));
    deck.setRels('ppt/presentation.xml', presRels);
    files['ppt/_rels/presentation.xml.rels'] = bytes(_relsXml('ppt/presentation.xml', presRels));

    final pres = parse('ppt/presentation.xml');
    final root = pres.rootElement;
    if (root.getAttribute('xmlns:r') == null) root.setAttribute('xmlns:r', _relNs);
    if (!root.childElements.any((e) => e.name.local == 'notesMasterIdLst')) {
      final list = XmlDocument.parse('<p:notesMasterIdLst xmlns:p="$_pNs" xmlns:r="$_relNs"><p:notesMasterId r:id="rId$n"/></p:notesMasterIdLst>').rootElement.copy();
      final at = root.children.indexWhere((c) => c is XmlElement && const {'handoutMasterIdLst', 'sldIdLst', 'sldSz', 'notesSz'}.contains(c.name.local));
      at < 0 ? root.children.add(list) : root.children.insert(at, list);
    }
    files['ppt/presentation.xml'] = bytes(pres.toXmlString());
    return masterPath;
  }

  for (final s in changed) {
    final text = s.notesText ?? '';
    final rel = s.relOfType('notesSlide');
    if (rel != null && files.containsKey(rel.target)) {
      final doc = parse(rel.target);
      for (final sp in doc.descendants.whereType<XmlElement>().where((e) => e.name.local == 'sp')) {
        final ph = sp.descendants.whereType<XmlElement>().where((e) => e.name.local == 'ph').firstOrNull;
        final body = sp.childElements.where((e) => e.name.local == 'txBody').firstOrNull;
        if (ph == null || ph.getAttribute('type') != 'body' || body == null) continue;
        body.children.removeWhere((c) => c is XmlElement && c.name.local == 'p');
        final fresh = XmlDocument.parse('<root xmlns:a="$_aNs">${_paragraphs(text)}</root>').rootElement.children.map((c) => c.copy()).toList();
        body.children.addAll(fresh);
        break;
      }
      files[rel.target] = bytes(doc.toXmlString());
    } else if (text.trim().isNotEmpty) {
      master ??= ensureMaster();
      final notesPath = _freshPart(files, 'ppt/notesSlides', 'notesSlide');
      files[notesPath] = bytes(
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><p:notes xmlns:a="$_aNs" xmlns:r="$_relNs" xmlns:p="$_pNs"><p:cSld><p:spTree>'
        '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>'
        '<p:sp><p:nvSpPr><p:cNvPr id="2" name="Slide Image Placeholder 1"/><p:cNvSpPr><a:spLocks noGrp="1" noRot="1" noChangeAspect="1"/></p:cNvSpPr><p:nvPr><p:ph type="sldImg"/></p:nvPr></p:nvSpPr><p:spPr/></p:sp>'
        '<p:sp><p:nvSpPr><p:cNvPr id="3" name="Notes Placeholder 2"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr><p:ph type="body" idx="1"/></p:nvPr></p:nvSpPr><p:spPr/>'
        '<p:txBody><a:bodyPr/><a:lstStyle/>${_paragraphs(text)}</p:txBody></p:sp></p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:notes>',
      );
      files[relsPathOf(notesPath)] = bytes(_relsXml(notesPath, [Rel('rId1', 'notesMaster', master), Rel('rId2', 'slide', s.path)]));
      override(notesPath, _notesSlideType);
      var n = 1;
      while (s.rels.any((r) => r.id == 'rId$n')) {
        n++;
      }
      s.rels = [...s.rels, Rel('rId$n', 'notesSlide', notesPath)];
      s.relsDirty = true;
    }
    s.notesDirty = false;
  }
  final types = ct;
  if (types != null) files['[Content_Types].xml'] = bytes(types.toXmlString());

  // The deck keeps what was added, so saving again changes these parts instead of adding them a second time.
  for (final e in files.entries) {
    if (!identical(deck.files[e.key], e.value)) {
      deck.files[e.key] = e.value;
      deck.forget(e.key);
    }
  }
}

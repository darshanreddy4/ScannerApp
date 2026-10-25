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

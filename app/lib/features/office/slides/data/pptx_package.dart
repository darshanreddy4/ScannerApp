import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

class PptxFormatException implements Exception {
  const PptxFormatException(this.message);
  final String message;
}

/// A relationship of a part: where it points and what kind of thing it is.
class Rel {
  const Rel(this.id, this.type, this.target, {this.external = false, String? fullType})
    : fullType = fullType ?? 'http://schemas.openxmlformats.org/officeDocument/2006/relationships/$type';
  final String id;

  /// The complete relationship type address, written back as it was read.
  final String fullType;

  /// The last word of the relationship type, such as "image" or "slideLayout".
  final String type;

  /// Path inside the file, or the address when [external].
  final String target;
  final bool external;
}

String resolvePart(String base, String target) {
  if (target.startsWith('/')) return target.substring(1);
  final parts = base.split('/')..removeLast();
  for (final seg in target.split('/')) {
    if (seg == '..') {
      if (parts.isNotEmpty) parts.removeLast();
    } else if (seg != '.' && seg.isNotEmpty) {
      parts.add(seg);
    }
  }
  return parts.join('/');
}

String relsPathOf(String part) {
  final i = part.lastIndexOf('/');
  return '${part.substring(0, i + 1)}_rels/${part.substring(i + 1)}.rels';
}

/// One slide of a presentation. Its XML is read when first needed and changed in place by edits.
class SlidePart {
  SlidePart({required this.path, this.slideId, this.rid, required this.deck});

  String path;
  int? slideId;
  String? rid;
  final PptxDeck deck;
  XmlDocument? _doc;
  List<Rel>? _rels;

  /// Needs to be written again.
  bool dirty = false;

  /// The relationships changed (a picture was added) and are written again.
  bool relsDirty = false;

  /// Created in the app, so it has no part in the file yet.
  bool isNew = false;

  XmlDocument get doc => _doc ??= deck.parse(path);
  set doc(XmlDocument d) => _doc = d;
  bool get loaded => _doc != null;

  List<Rel> get rels => _rels ??= deck.readRels(path);
  set rels(List<Rel> r) => _rels = r;

  Rel? relById(String id) {
    for (final r in rels) {
      if (r.id == id) return r;
    }
    return null;
  }

  Rel? relOfType(String type) {
    for (final r in rels) {
      if (r.type == type) return r;
    }
    return null;
  }

  String? get layoutPath => relOfType('slideLayout')?.target;

  XmlElement get spTree => doc.rootElement.childElements.firstWhere((e) => e.name.local == 'cSld').childElements.firstWhere((e) => e.name.local == 'spTree');

  /// A copy of the part with no shared state, used for undo.
  String snapshot() => doc.toXmlString();
}

/// A .pptx file opened for viewing and editing. Parts that are not changed are written back untouched.
class PptxDeck {
  PptxDeck._(this.files);

  /// Every part of the package by path.
  final Map<String, Uint8List> files;
  final Map<String, XmlDocument> _parsed = {};
  final Map<String, List<Rel>> _relCache = {};
  late final List<SlidePart> slides;
  late final XmlDocument presentation;
  late double width;
  late double height;

  /// Slides were added, removed or reordered.
  bool structureChanged = false;

  static Future<PptxDeck> open(Uint8List bytes) async {
    final Map<String, Uint8List> files;
    try {
      files = await Isolate.run(() => _unzip(bytes));
    } catch (_) {
      throw const PptxFormatException('This file is not a valid .pptx presentation. Older .ppt files are not supported.');
    }
    return PptxDeck.fromFiles(files);
  }

  static Map<String, Uint8List> _unzip(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    return {
      for (final f in archive.files)
        if (f.isFile) f.name: Uint8List.fromList(f.readBytes()!),
    };
  }

  factory PptxDeck.fromFiles(Map<String, Uint8List> files) {
    final deck = PptxDeck._(files);
    if (!files.containsKey('ppt/presentation.xml')) throw const PptxFormatException('This file is not a valid .pptx presentation.');
    try {
      deck.presentation = deck.parse('ppt/presentation.xml');
      final root = deck.presentation.rootElement;
      final size = root.childElements.where((e) => e.name.local == 'sldSz').firstOrNull;
      deck.width = double.tryParse(size?.getAttribute('cx') ?? '') ?? 9144000;
      deck.height = double.tryParse(size?.getAttribute('cy') ?? '') ?? 6858000;
      final rels = deck.readRels('ppt/presentation.xml');
      final list = root.childElements.where((e) => e.name.local == 'sldIdLst').firstOrNull;
      final slides = <SlidePart>[];
      for (final s in list?.childElements ?? const <XmlElement>[]) {
        final rid = s.attributes.where((a) => a.name.local == 'id' && a.name.prefix != null).map((a) => a.value).firstOrNull;
        final rel = rels.where((r) => r.id == rid).firstOrNull;
        if (rel == null || !files.containsKey(rel.target)) continue;
        slides.add(SlidePart(path: rel.target, slideId: int.tryParse(s.getAttribute('id') ?? ''), rid: rid, deck: deck));
      }
      deck.slides = slides;
    } on XmlException {
      throw const PptxFormatException('This presentation file is damaged.');
    }
    if (deck.slides.isEmpty) throw const PptxFormatException('This presentation has no slides.');
    return deck;
  }

  XmlDocument parse(String path) {
    final cached = _parsed[path];
    if (cached != null) return cached;
    final bytes = files[path];
    if (bytes == null) throw PptxFormatException('Missing part $path');
    final doc = XmlDocument.parse(utf8.decode(bytes, allowMalformed: true));
    _parsed[path] = doc;
    return doc;
  }

  XmlDocument? parseOrNull(String? path) => path != null && files.containsKey(path) ? parse(path) : null;

  /// Forgets a parsed part so it is read again from the bytes.
  void forget(String path) => _parsed.remove(path);

  List<Rel> readRels(String part) {
    final cached = _relCache[part];
    if (cached != null) return cached;
    final path = relsPathOf(part);
    final bytes = files[path];
    final out = <Rel>[];
    if (bytes != null) {
      final doc = XmlDocument.parse(utf8.decode(bytes, allowMalformed: true));
      for (final r in doc.rootElement.childElements) {
        final id = r.getAttribute('Id'), type = r.getAttribute('Type'), target = r.getAttribute('Target');
        if (id == null || type == null || target == null) continue;
        final external = r.getAttribute('TargetMode') == 'External';
        out.add(Rel(id, type.substring(type.lastIndexOf('/') + 1), external ? target : resolvePart(part, target), external: external, fullType: type));
      }
    }
    _relCache[part] = out;
    return out;
  }

  void setRels(String part, List<Rel> rels) => _relCache[part] = rels;

  String get layoutFallback {
    for (final k in files.keys) {
      if (k.startsWith('ppt/slideLayouts/') && k.endsWith('.xml')) return k;
    }
    throw const PptxFormatException('This presentation has no slide layouts.');
  }
}

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../../../core/error/failures.dart';

/// Ordered content of a Word file: either a run of text or an extracted image file.
class DocxBlock {
  const DocxBlock.text(this.value) : isImage = false;
  const DocxBlock.image(this.value) : isImage = true;

  final bool isImage;

  /// Text for text blocks, file path for image blocks.
  final String value;
}

/// Reads `.docx` content in document order. Pure Dart so it can run in an isolate.
List<DocxBlock> parseDocx({required String path, required String outDir, required String prefix}) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(File(path).readAsBytesSync());
  } catch (_) {
    throw const ImportFailure('This file is not a valid .docx document. Older .doc files are not supported.');
  }

  final docEntry = archive.findFile('word/document.xml');
  if (docEntry == null) {
    throw const ImportFailure('This file is not a valid .docx document.');
  }

  final relTargets = <String, String>{};
  final relsEntry = archive.findFile('word/_rels/document.xml.rels');
  if (relsEntry != null) {
    final rels = XmlDocument.parse(utf8.decode(relsEntry.readBytes()!, allowMalformed: true));
    for (final r in rels.descendants.whereType<XmlElement>().where((e) => e.name.local == 'Relationship')) {
      final id = r.getAttribute('Id');
      final target = r.getAttribute('Target');
      if (id != null && target != null) relTargets[id] = target;
    }
  }

  final doc = XmlDocument.parse(utf8.decode(docEntry.readBytes()!, allowMalformed: true));
  final blocks = <DocxBlock>[];
  final paragraphs = <String>[];
  final current = StringBuffer();
  var inParagraph = false;
  var imageCount = 0;

  void endParagraph() {
    if (inParagraph) paragraphs.add(current.toString());
    current.clear();
    inParagraph = false;
  }

  void flushText() {
    endParagraph();
    final text = paragraphs.join('\n').trim();
    paragraphs.clear();
    if (text.isNotEmpty) blocks.add(DocxBlock.text(text));
  }

  for (final e in doc.descendants.whereType<XmlElement>()) {
    switch (e.name.local) {
      case 'p':
        endParagraph();
        inParagraph = true;
      case 't':
        current.write(e.innerText);
      case 'tab':
        current.write('    ');
      case 'br':
        current.write('\n');
      case 'blip':
        final embed = e.attributes.where((a) => a.name.local == 'embed').map((a) => a.value).firstOrNull;
        final target = embed == null ? null : relTargets[embed];
        final entry = target == null ? null : archive.findFile(p.posix.normalize(p.posix.join('word', target)));
        if (entry == null) break;
        final bytes = entry.readBytes();
        if (bytes == null) break;
        final file = _writeImage(bytes, p.extension(target!).toLowerCase(), outDir, '$prefix-img${++imageCount}');
        if (file != null) {
          flushText();
          blocks.add(DocxBlock.image(file));
        }
    }
  }
  flushText();
  return blocks;
}

/// Keeps JPEG/PNG as they are and converts other raster formats; vector formats (EMF/WMF) are skipped.
String? _writeImage(Uint8List bytes, String ext, String outDir, String name) {
  if (ext == '.jpg' || ext == '.jpeg' || ext == '.png') {
    final f = File(p.join(outDir, '$name$ext'))..writeAsBytesSync(bytes, flush: true);
    return f.path;
  }
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final f = File(p.join(outDir, '$name.png'))..writeAsBytesSync(img.encodePng(decoded), flush: true);
  return f.path;
}

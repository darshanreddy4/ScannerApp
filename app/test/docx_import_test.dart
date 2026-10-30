import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:doculoom/core/error/failures.dart';
import 'package:doculoom/features/export/data/document_builders.dart';
import 'package:doculoom/features/export/domain/entities/export_options.dart';
import 'package:doculoom/features/importer/data/docx_parser.dart';

String _docxWithText(String dir, List<String> paragraphs) {
  final body = paragraphs.map((t) => '<w:p><w:r><w:t>$t</w:t></w:r></w:p>').join();
  final xml =
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>$body</w:body></w:document>';
  final archive = Archive()..addFile(ArchiveFile.bytes('word/document.xml', utf8.encode(xml)));
  final path = '$dir/text.docx';
  File(path).writeAsBytesSync(ZipEncoder().encode(archive));
  return path;
}

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('doculoom_docx'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('extracts images from a DOCX produced by the exporter, in order', () {
    final pages = <PageSource>[];
    for (var i = 0; i < 3; i++) {
      final image = img.Image(width: 60, height: 80)..clear(img.ColorRgb8(10 * i, 20, 30));
      final f = File('${tmp.path}/p$i.jpg')..writeAsBytesSync(img.encodeJpg(image));
      pages.add(PageSource(path: f.path, width: 60, height: 80));
    }
    final docx = '${tmp.path}/scan.docx';
    buildDocx(pages, ExportQuality.high, docx);

    final out = Directory('${tmp.path}/out')..createSync();
    final blocks = parseDocx(path: docx, outDir: out.path, prefix: 't');

    expect(blocks.length, 3);
    expect(blocks.every((b) => b.isImage), isTrue);
    expect(blocks.map((b) => File(b.value).existsSync()).every((e) => e), isTrue);
    expect(blocks.first.value, endsWith('t-img1.jpg'));
  });

  test('collects text paragraphs from a text-only DOCX', () {
    final path = _docxWithText(tmp.path, ['Hello', 'World', 'नमस्ते']);
    final blocks = parseDocx(path: path, outDir: tmp.path, prefix: 't');

    expect(blocks.length, 1);
    expect(blocks.single.isImage, isFalse);
    expect(blocks.single.value, 'Hello\nWorld\nनमस्ते');
  });

  test('rejects files that are not DOCX packages', () {
    final bad = File('${tmp.path}/bad.docx')..writeAsStringSync('not a zip');
    expect(() => parseDocx(path: bad.path, outDir: tmp.path, prefix: 't'), throwsA(isA<ImportFailure>()));
  });

  test('rejects a zip that has no word/document.xml', () {
    final archive = Archive()..addFile(ArchiveFile.bytes('readme.txt', utf8.encode('hi')));
    final f = File('${tmp.path}/other.docx')..writeAsBytesSync(ZipEncoder().encode(archive));
    expect(() => parseDocx(path: f.path, outDir: tmp.path, prefix: 't'), throwsA(isA<ImportFailure>()));
  });
}

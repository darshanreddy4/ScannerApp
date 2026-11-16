import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';
import 'package:doculoom/features/text_edit/docx/doc_template_store.dart';
import 'package:doculoom/features/text_edit/docx/doc_templates.dart';
import 'package:doculoom/features/text_edit/docx/docx_builder.dart';
import 'package:doculoom/features/text_edit/docx/docx_document.dart';
import 'package:doculoom/features/text_edit/docx/docx_edit_cubit.dart';
import 'package:doculoom/features/text_edit/docx/new_document_sheet.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

List<ParaBlock> paragraphs(DocxDocument d) {
  final out = <ParaBlock>[];
  void walk(List<DocBlock> blocks) {
    for (final b in blocks) {
      switch (b) {
        case ParaBlock():
          out.add(b);
        case TableBlock():
          for (final row in b.rows) {
            for (final cell in row) {
              walk(cell);
            }
          }
      }
    }
  }

  walk(d.view());
  return out;
}

/// A Word file with a body and nothing else: no styles, no numbering.
Uint8List bareDocx(List<String> texts) {
  final body = texts.map((t) => '<w:p><w:r><w:t>$t</w:t></w:r></w:p>').join();
  final archive = Archive()
    ..addFile(
      ArchiveFile.bytes(
        '[Content_Types].xml',
        utf8.encode(
          '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
          '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
          '<Default Extension="xml" ContentType="application/xml"/>'
          '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>',
        ),
      ),
    )
    ..addFile(
      ArchiveFile.bytes(
        '_rels/.rels',
        utf8.encode(
          '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>',
        ),
      ),
    )
    ..addFile(
      ArchiveFile.bytes(
        'word/_rels/document.xml.rels',
        utf8.encode('<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"></Relationships>'),
      ),
    )
    ..addFile(
      ArchiveFile.bytes('word/document.xml', utf8.encode('<?xml version="1.0" encoding="UTF-8"?><w:document xmlns:w="$_w"><w:body>$body</w:body></w:document>')),
    );
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

String part(Uint8List bytes, String name) => utf8.decode(ZipDecoder().decodeBytes(bytes).findFile(name)!.readBytes()!);

void main() {
  group('new documents from templates', () {
    test('every template makes a file the editor opens and that saves again', () {
      expect(docTemplates.map((t) => t.id).toSet().length, docTemplates.length, reason: 'ids are unique');
      for (final t in docTemplates) {
        final bytes = buildDocx(t.build());
        final doc = DocxDocument.open(bytes);
        expect(doc.paragraphCount, greaterThan(0), reason: t.id);
        final again = DocxDocument.open(doc.save());
        expect(paragraphs(again).map((q) => q.text), paragraphs(doc).map((q) => q.text), reason: t.id);
        // Every part of the package is well formed.
        final archive = ZipDecoder().decodeBytes(bytes);
        for (final f in archive.files.where((f) => f.isFile)) {
          expect(() => XmlDocument.parse(utf8.decode(f.readBytes()!)), returnsNormally, reason: '${t.id}: ${f.name}');
        }
      }
    });

    test('titles, headings, bullets, numbers and tables come through', () {
      final doc = DocxDocument.open(buildDocx(docTemplateById('meeting_minutes')!.build()));
      final all = paragraphs(doc);
      expect(all.first.text, 'Meeting minutes');
      expect(all.first.headingLevel, 0);
      expect(all.firstWhere((q) => q.text == 'Agenda').headingLevel, 1);
      expect(all.firstWhere((q) => q.text == '[Decision]').listLabel, '\u2022');
      expect(doc.view().whereType<TableBlock>().length, 2);
      expect(doc.view().whereType<TableBlock>().last.rows.first.map((c) => (c.single as ParaBlock).text), ['Task', 'Owner', 'Due date']);
    });

    test('each numbered list starts again at 1', () {
      final doc = DocxDocument.open(
        buildDocx([
          DocPara('One', list: DocList.number),
          DocPara('Two', list: DocList.number),
          DocPara('Break'),
          DocPara('Again', list: DocList.number),
          DocPara('Again two', list: DocList.number),
        ]),
      );
      final labels = paragraphs(doc).map((q) => q.listLabel).toList();
      expect(labels, ['1.', '2.', null, '1.', '2.']);
    });

    test('a file that ends in a table still ends in a paragraph, and text with markup characters is escaped', () {
      final bytes = buildDocx([
        DocPara('A & B < C > D'),
        const DocTable([
          ['x', 'y'],
        ]),
      ]);
      final doc = DocxDocument.open(bytes);
      expect(paragraphs(doc).first.text, 'A & B < C > D');
      expect(part(bytes, 'word/document.xml'), contains('<w:p/><w:sectPr>'));
    });

    test('the page is A4, or Letter on request', () {
      expect(part(buildDocx(const []), 'word/document.xml'), contains('w:w="11906"'));
      expect(part(buildDocx(const [], letter: true), 'word/document.xml'), contains('w:w="12240"'));
    });
  });

  group('styles and lists in an open document', () {
    test('a heading uses the style the file already has', () {
      final d = DocxDocument.open(File('test/fixtures/text_edit/sample.docx').readAsBytesSync());
      final i = paragraphs(d).firstWhere((q) => q.text.startsWith('The quick')).index;
      expect(d.styleOf(i), DocStyle.normal);
      d.setStyle(i, DocStyle.heading2);
      expect(paragraphs(d).firstWhere((q) => q.index == i).headingLevel, 2);
      expect(d.styleOf(i), DocStyle.heading2);
      d.setStyle(i, DocStyle.normal);
      expect(paragraphs(d).firstWhere((q) => q.index == i).headingLevel, isNull);
      d.undo();
      expect(d.styleOf(i), DocStyle.heading2);
    });

    test('lists reuse the numbering of the file and continue the list above', () {
      final d = DocxDocument.open(File('test/fixtures/text_edit/sample.docx').readAsBytesSync());
      final steps = paragraphs(d).firstWhere((q) => q.text.startsWith('Step two')).index;
      expect(d.listKindOf(steps), DocList.number);
      d.setList(steps, DocList.none);
      expect(d.listKindOf(steps), DocList.none);
      expect(paragraphs(d).firstWhere((q) => q.index == steps).listLabel, isNull);
      d.setList(steps, DocList.number);
      expect(paragraphs(d).firstWhere((q) => q.index == steps).listLabel, '2.');
    });

    test('a file without styles or numbering gets them, and keeps them when saved', () {
      final d = DocxDocument.open(bareDocx(['Heading text', 'First', 'Second', 'Third']));
      d.setStyle(0, DocStyle.heading1);
      d.setList(1, DocList.bullet);
      d.setList(2, DocList.number);
      d.setList(3, DocList.number);
      final saved = d.save();
      final archive = ZipDecoder().decodeBytes(saved);
      expect(archive.findFile('word/styles.xml'), isNotNull);
      expect(archive.findFile('word/numbering.xml'), isNotNull);
      expect(part(saved, '[Content_Types].xml'), allOf(contains('/word/styles.xml'), contains('/word/numbering.xml')));
      expect(part(saved, 'word/_rels/document.xml.rels'), allOf(contains('styles.xml'), contains('numbering.xml')));
      for (final f in archive.files.where((f) => f.isFile)) {
        expect(() => XmlDocument.parse(utf8.decode(f.readBytes()!)), returnsNormally, reason: f.name);
      }

      final again = DocxDocument.open(saved);
      final all = paragraphs(again);
      expect(all[0].headingLevel, 1);
      expect(all[1].listLabel, '\u2022');
      expect(all[2].listLabel, '1.');
      expect(all[3].listLabel, '2.');
      expect(again.listKindOf(1), DocList.bullet);
      expect(again.listKindOf(2), DocList.number);
    });

    test('paragraph settings are written in the order Word expects', () {
      final d = DocxDocument.open(bareDocx(['Item']));
      d.setAlign(0, 'center');
      d.setList(0, DocList.bullet);
      d.setStyle(0, DocStyle.title);
      d.setList(0, DocList.number);
      final doc = XmlDocument.parse(part(d.save(), 'word/document.xml'));
      final pPr = doc.findAllElements('pPr', namespaceUri: _w).first;
      expect(pPr.childElements.map((e) => e.name.local).toList(), ['numPr', 'jc'], reason: 'a list takes the heading look away; style comes first when present');
      d.setStyle(0, DocStyle.heading1);
      final again = XmlDocument.parse(part(d.save(), 'word/document.xml')).findAllElements('pPr', namespaceUri: _w).first;
      expect(again.childElements.map((e) => e.name.local).toList(), ['pStyle', 'jc']);
    });

    test('a heading is not also a list item, and switching a list off leaves the text alone', () {
      final d = DocxDocument.open(bareDocx(['Item']));
      d.setList(0, DocList.bullet);
      d.setStyle(0, DocStyle.heading2);
      expect(d.listKindOf(0), DocList.none);
      d.setList(0, DocList.bullet);
      expect(d.styleOf(0), DocStyle.normal);
      d.setList(0, DocList.none);
      expect(d.listKindOf(0), DocList.none);
      expect(d.paragraphText(0), 'Item');
    });
  });

  group('saving and starting new documents', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('sv_newdoc'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('a new document is saved under its own name, an opened one as a copy', () async {
      final fresh = Directory(p.join(dir.path, newDocsFolder))..createSync();
      final a = File(p.join(fresh.path, 'Resume.docx'))..writeAsBytesSync(buildDocx(docTemplateById('resume')!.build()));
      final b = File(p.join(dir.path, 'Notes.docx'))..writeAsBytesSync(buildDocx(docTemplateById('blank')!.build()));
      final c1 = DocxEditCubit(workDir: () async => dir);
      await c1.open(a.path);
      expect(c1.fileName, 'Resume.docx');
      expect(p.basename((await c1.export())!), 'Resume.docx');
      final c2 = DocxEditCubit(workDir: () async => dir);
      await c2.open(b.path);
      expect(c2.fileName, 'Notes_edited.docx');
      expect(p.basename((await c2.export())!), 'Notes_edited.docx');
      await c1.close();
      await c2.close();
    });

    test('my templates are saved, listed and removed', () async {
      final store = DocTemplateStore(dir: () async => Directory(p.join(dir.path, 'mine')));
      expect(await store.list(), isEmpty);
      final src = File(p.join(dir.path, 'src.docx'))..writeAsBytesSync(buildDocx(docTemplateById('report')!.build()));
      final saved = await store.save(src.path, 'Weekly: report?');
      expect(p.basename(saved.path), 'Weekly_ report_.docx');
      expect((await store.list()).map((f) => p.basename(f.path)), ['Weekly_ report_.docx']);
      await store.save(src.path, 'Weekly: report?');
      expect(await store.list(), hasLength(1), reason: 'the same name replaces the template');
      await store.delete(saved);
      expect(await store.list(), isEmpty);
      expect(DocTemplateStore.cleanName('   '), 'Template');
    });

    testWidgets('the picker lists templates and opens the new file in the editor', (tester) async {
      String? opened;
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, _) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => startNewDocument(context, tempDir: () async => dir, store: DocTemplateStore(dir: () async => Directory(p.join(dir.path, 'mine')))),
                  child: const Text('start'),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/docx-edit',
            builder: (_, state) {
              opened = state.extra as String;
              return const Scaffold(body: Text('editor'));
            },
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.tap(find.text('start'));
      await tester.pumpAndSettle();
      expect(find.text('Blank document'), findsOneWidget);
      expect(find.text('Assignment'), findsOneWidget);
      expect(find.text('Resume'), findsOneWidget);
      expect(find.text('MY TEMPLATES'), findsNothing);
      await tester.ensureVisible(find.byKey(const ValueKey('template-resume')));
      await tester.tap(find.byKey(const ValueKey('template-resume')));
      await tester.pump();
      // The file is written with real IO, which needs real time between the steps of the fake clock.
      for (var i = 0; i < 20 && opened == null; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(find.text('editor'), findsOneWidget);
      expect(opened, p.join(dir.path, newDocsFolder, 'Resume.docx'));
      final doc = DocxDocument.open(File(opened!).readAsBytesSync());
      expect(paragraphs(doc).first.text, '[Your name]');
    });
  });
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';
import 'package:doculoom/core/theme/app_theme.dart';
import 'package:doculoom/features/office/slides/data/deck_editor.dart';
import 'package:doculoom/features/office/slides/data/pptx_package.dart';
import 'package:doculoom/features/office/slides/data/pptx_template.dart';
import 'package:doculoom/features/office/slides/data/pptx_writer.dart';
import 'package:doculoom/features/office/slides/presentation/slides_page.dart';

DeckEditor deckOf(int slides) {
  final e = DeckEditor(PptxDeck.fromFiles(newPresentationFiles()));
  for (var i = 1; i < slides; i++) {
    e.addSlide();
  }
  return e;
}

Map<String, String> partsOf(Uint8List pptx) => {
  for (final f in ZipDecoder().decodeBytes(pptx).files)
    if (f.isFile) f.name: utf8.decode(f.readBytes()!, allowMalformed: true),
};

Iterable<String> named(Map<String, String> parts, String prefix) => parts.keys.where((k) => k.startsWith(prefix) && !k.contains('_rels'));

Future<DeckEditor> reopen(Uint8List bytes) async => DeckEditor(await PptxDeck.open(bytes));

void main() {
  group('speaker notes in the file', () {
    test('a slide has no notes until some are written, and none are added for empty notes', () {
      final e = deckOf(2);
      expect(e.notesOf(e.deck.slides.first), '');
      e.modified = false;
      e.setNotes(e.deck.slides.first, '  \n');
      expect(e.modified, isFalse, reason: 'nothing changed');
      expect(named(partsOf(writePptx(e.deck)), 'ppt/notesSlides/'), isEmpty);
    });

    test('notes are written with their own notes page and notes master, and read back', () async {
      final e = deckOf(2);
      e.setNotes(e.deck.slides[1], 'Say hello & welcome\n\nThen show the <chart>');
      final bytes = writePptx(e.deck);
      final parts = partsOf(bytes);

      expect(named(parts, 'ppt/notesSlides/'), ['ppt/notesSlides/notesSlide1.xml']);
      expect(named(parts, 'ppt/notesMasters/'), ['ppt/notesMasters/notesMaster1.xml']);
      for (final entry in parts.entries.where((e) => e.key.endsWith('.xml') || e.key.endsWith('.rels'))) {
        expect(() => XmlDocument.parse(entry.value), returnsNormally, reason: entry.key);
      }
      final types = parts['[Content_Types].xml']!;
      expect(types, allOf(contains('/ppt/notesSlides/notesSlide1.xml'), contains('/ppt/notesMasters/notesMaster1.xml'), contains('presentationml.notesSlide+xml'), contains('presentationml.notesMaster+xml')));
      expect(parts['ppt/_rels/presentation.xml.rels'], contains('notesMaster'));
      final pres = XmlDocument.parse(parts['ppt/presentation.xml']!).rootElement.childElements.map((c) => c.name.local).toList();
      expect(pres, containsAllInOrder(['sldMasterIdLst', 'notesMasterIdLst', 'sldIdLst', 'sldSz', 'notesSz']));
      expect(parts['ppt/slides/_rels/slide2.xml.rels'], contains('notesSlide1.xml'));
      expect(parts['ppt/slides/_rels/slide1.xml.rels'], isNot(contains('notesSlide')));
      expect(parts['ppt/notesSlides/_rels/notesSlide1.xml.rels'], allOf(contains('../slides/slide2.xml'), contains('../notesMasters/notesMaster1.xml')));
      expect(parts['ppt/notesMasters/_rels/notesMaster1.xml.rels'], contains('../theme/theme'));

      final again = await reopen(bytes);
      expect(again.notesOf(again.deck.slides[0]), '');
      expect(again.notesOf(again.deck.slides[1]), 'Say hello & welcome\n\nThen show the <chart>');
    });

    test('saving twice, or changing the notes later, changes the same parts', () async {
      final e = deckOf(2);
      e.setNotes(e.deck.slides[0], 'first');
      writePptx(e.deck);
      e.setNotes(e.deck.slides[0], 'second');
      e.setNotes(e.deck.slides[1], 'other slide');
      final bytes = writePptx(e.deck);
      final parts = partsOf(bytes);
      expect(named(parts, 'ppt/notesSlides/'), hasLength(2));
      expect(named(parts, 'ppt/notesMasters/'), hasLength(1), reason: 'one master for all notes');
      expect(named(parts, 'ppt/theme/'), hasLength(2), reason: 'the deck theme and the notes theme');
      expect(RegExp('notesMasterId ').allMatches(parts['ppt/presentation.xml']!), hasLength(1));

      final again = await reopen(bytes);
      expect([for (final s in again.deck.slides) again.notesOf(s)], ['second', 'other slide']);
      again.setNotes(again.deck.slides[0], 'third');
      final changed = partsOf(writePptx(again.deck));
      expect(named(changed, 'ppt/notesSlides/'), hasLength(2), reason: 'the notes page that was there is changed, not added to');
      expect((await reopen(writePptx(again.deck))).notesOf(again.deck.slides[0]), 'third');
    });

    test('undo and redo bring the old notes back', () {
      final e = deckOf(1);
      final s = e.deck.slides.first;
      e.setNotes(s, 'one');
      e.setNotes(s, 'two');
      e.undo();
      expect(e.notesOf(s), 'one');
      e.undo();
      expect(e.notesOf(s), '');
      e.redo();
      expect(e.notesOf(s), 'one');
    });

    test('a copy of a slide has its own notes page, and a deleted slide takes its notes with it', () async {
      final e = deckOf(2);
      e.setNotes(e.deck.slides[0], 'speak slowly');
      final copy = e.duplicateSlide(0);
      expect(e.notesOf(copy), 'speak slowly');
      e.setNotes(copy, 'speak slowly, then pause');
      final bytes = writePptx(e.deck);
      expect(named(partsOf(bytes), 'ppt/notesSlides/'), hasLength(2));
      final again = await reopen(bytes);
      expect([for (final s in again.deck.slides) again.notesOf(s)], ['speak slowly', 'speak slowly, then pause', '']);

      again.deleteSlide(0);
      final afterDelete = partsOf(writePptx(again.deck));
      expect(named(afterDelete, 'ppt/notesSlides/'), hasLength(1));
      expect((await reopen(writePptx(again.deck))).notesOf(again.deck.slides.first), 'speak slowly, then pause');
    });

    test('notes made by other programs are read, one line per paragraph', () async {
      final e = deckOf(1);
      e.setNotes(e.deck.slides.first, 'a');
      final parts = partsOf(writePptx(e.deck));
      final edited = parts['ppt/notesSlides/notesSlide1.xml']!.replaceFirst(
        RegExp(r'<a:p>.*</a:p>'),
        '<a:p><a:r><a:t>Line </a:t></a:r><a:r><a:t>one</a:t></a:r></a:p><a:p><a:r><a:t>Line two</a:t></a:r></a:p><a:p><a:endParaRPr lang="en-US"/></a:p>',
      );
      final out = Archive();
      for (final f in ZipDecoder().decodeBytes(writePptx(e.deck)).files) {
        out.addFile(ArchiveFile.bytes(f.name, f.name == 'ppt/notesSlides/notesSlide1.xml' ? utf8.encode(edited) : f.readBytes()!));
      }
      final again = await reopen(Uint8List.fromList(ZipEncoder().encode(out)));
      expect(again.notesOf(again.deck.slides.first), 'Line one\nLine two');
    });
  });

  group('notes on screen', () {
    Widget host() => MaterialApp(theme: AppTheme.light(), home: const SlidesPage());

    testWidgets('the notes dialog sets the notes of the slide and the slide show can show them', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 860));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(host());
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('stool_notes')));
      await tester.tap(find.byKey(const ValueKey('stool_notes')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('slide_text_field')), 'Remember to smile');
      await tester.tap(find.byKey(const ValueKey('slide_text_ok')));
      await tester.pumpAndSettle();
      expect(find.textContaining('*'), findsOneWidget, reason: 'the notes count as a change');

      await tester.tap(find.byKey(const ValueKey('slides_play')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('show_notes_panel')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('show_notes')));
      await tester.pump();
      expect(find.text('Remember to smile'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('show_notes')));
      await tester.pump();
      expect(find.byKey(const ValueKey('show_notes_panel')), findsNothing);
    });
  });
}

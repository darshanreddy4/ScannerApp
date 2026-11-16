import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';
import 'package:doculoom/features/office/slides/data/deck_builder.dart';
import 'package:doculoom/features/office/slides/data/deck_editor.dart';
import 'package:doculoom/features/office/slides/data/pptx_package.dart';
import 'package:doculoom/features/office/slides/data/pptx_template.dart';
import 'package:doculoom/features/office/slides/data/pptx_writer.dart';
import 'package:doculoom/features/office/slides/domain/slide_presets.dart';
import 'package:doculoom/features/office/slides/domain/slide_themes.dart';
import 'package:doculoom/features/office/slides/presentation/new_presentation_sheet.dart';
import 'package:doculoom/features/text_edit/docx/doc_template_store.dart';

List<String> texts(DeckEditor e, int slide) => e.view(e.deck.slides[slide]).shapes.map((s) => s.plainText).where((t) => t.isNotEmpty).toList();

void main() {
  group('themes and layouts of a new presentation', () {
    test('every theme makes a package that opens, and the package parts are well formed', () {
      for (final t in deckThemes) {
        final files = newPresentationFiles(theme: t);
        for (final e in files.entries) {
          expect(() => XmlDocument.parse(utf8.decode(e.value)), returnsNormally, reason: '${t.id}: ${e.key}');
        }
        final deck = PptxDeck.fromFiles(files);
        expect(deck.slides, hasLength(1), reason: t.id);
        final layouts = files.keys.where((k) => RegExp(r'^ppt/slideLayouts/slideLayout\d+\.xml$').hasMatch(k)).toList();
        expect(layouts, hasLength(deckLayouts.length));
        expect(utf8.decode(files['[Content_Types].xml']!), contains('slideLayout${deckLayouts.length}.xml'));
      }
      expect(deckThemes.map((t) => t.id).toSet().length, deckThemes.length);
      for (final t in deckThemes) {
        expect(t.accents, hasLength(6));
        for (final c in [t.background, t.text, t.title, t.soft, ...t.accents]) {
          expect(RegExp(r'^[0-9A-F]{6}$').hasMatch(c), isTrue, reason: '${t.id} $c');
        }
      }
    });

    test('the theme colours reach the slide: title colour, bullets, and a dark background', () {
      final light = DeckEditor(PptxDeck.fromFiles(newPresentationFiles(theme: deckThemeById('forest'))));
      final title = light.view(light.deck.slides.first).shapes.firstWhere((s) => s.canHaveText);
      light.setText(light.deck.slides.first, title.id, 'Hello');
      final again = light.view(light.deck.slides.first).shapes.firstWhere((s) => s.plainText == 'Hello');
      expect(again.paragraphs.first.runs.first.color, 0xFF1E5631, reason: 'titles take the theme title colour');

      final dark = DeckEditor(PptxDeck.fromFiles(newPresentationFiles(theme: deckThemeById('midnight'))));
      final background = dark.view(dark.deck.slides.first).background;
      expect(background.color, 0xFF0F172A);
      dark.setText(dark.deck.slides.first, title.id, 'Hello');
      final body = dark.view(dark.deck.slides.first).shapes.where((s) => s.canHaveText).last;
      dark.setText(dark.deck.slides.first, body.id, 'Body text');
      final bodyAgain = dark.view(dark.deck.slides.first).shapes.firstWhere((s) => s.plainText == 'Body text');
      expect(bodyAgain.paragraphs.first.runs.first.color, 0xFFF1F5F9, reason: 'light text on a dark slide');
    });

    test('a slide takes the text boxes of the layout chosen for it', () {
      final e = DeckEditor(PptxDeck.fromFiles(newPresentationFiles()));
      int boxes(String layout) {
        final s = e.addSlide(layout: layout);
        return s.spTree.childElements.where((el) => el.descendants.whereType<XmlElement>().any((x) => x.name.local == 'ph')).length;
      }

      expect(boxes('obj'), 2);
      expect(boxes('title'), 2);
      expect(boxes('secHead'), 2);
      expect(boxes('twoObj'), 3);
      expect(boxes('titleOnly'), 1);
      expect(boxes('blank'), 0);
      expect(e.deck.slides, hasLength(7));
      final ids = e.deck.slides.last.spTree.descendants.whereType<XmlElement>().where((x) => x.name.local == 'cNvPr').map((x) => x.getAttribute('id')).toList();
      expect(ids.toSet().length, ids.length, reason: 'shape ids are unique');
    });

    test('the title slide layout puts a centred title above a subtitle, and the two-content layout puts two boxes side by side', () {
      final e = DeckEditor(PptxDeck.fromFiles(newPresentationFiles()));
      final t = e.addSlide(layout: 'title');
      e.fillPlaceholders(t, ['Big title', 'Small line']);
      final boxes = e.view(t).shapes.where((s) => s.plainText.isNotEmpty).toList();
      expect(boxes.map((s) => s.plainText), ['Big title', 'Small line']);
      expect(boxes.first.frame.y, lessThan(boxes.last.frame.y));
      expect(boxes.first.paragraphs.first.align, 'ctr');
      final two = e.addSlide(layout: 'twoObj');
      e.fillPlaceholders(two, ['T', 'Left', 'Right']);
      final cols = e.view(two).shapes.where((s) => s.plainText == 'Left' || s.plainText == 'Right').toList();
      expect(cols, hasLength(2));
      expect(cols.firstWhere((s) => s.plainText == 'Left').frame.x, lessThan(cols.firstWhere((s) => s.plainText == 'Right').frame.x));
    });

    test('adding a slide to an existing file uses what its layouts offer, and the old behaviour stays', () {
      final e = DeckEditor(PptxDeck.fromFiles(newPresentationFiles()));
      e.addSlide();
      e.addSlide(blank: true);
      expect(e.deck.slides, hasLength(3));
      expect(e.view(e.deck.slides[1]).shapes.where((s) => s.canHaveText), hasLength(2));
      expect(e.view(e.deck.slides[2]).shapes.where((s) => s.canHaveText), isEmpty);
    });
  });

  group('starter presentations', () {
    test('each starter builds a deck with its slides and text, and survives a save and reopen', () async {
      expect(deckPresets.map((d) => d.id).toSet().length, deckPresets.length);
      for (final d in deckPresets) {
        expect(deckThemes.map((t) => t.id), contains(d.themeId), reason: d.id);
        final deck = buildPresetDeck(d);
        expect(deck.slides, hasLength(d.slides.length), reason: d.id);
        final editor = DeckEditor(deck);
        for (var i = 0; i < d.slides.length; i++) {
          final shown = texts(editor, i);
          expect(shown.first, d.slides[i].texts.first, reason: '${d.id} slide ${i + 1} title');
          expect(shown, hasLength(d.slides[i].texts.where((t) => t.isNotEmpty).length), reason: '${d.id} slide ${i + 1}');
        }
        final reopened = await PptxDeck.open(writePptx(deck));
        expect(reopened.slides, hasLength(d.slides.length), reason: d.id);
        final again = DeckEditor(reopened);
        expect(texts(again, 0).first, d.slides.first.texts.first, reason: d.id);
      }
    });

    test('a starter starts with nothing to undo', () {
      final deck = buildPresetDeck(deckPresets.first);
      final e = DeckEditor(deck);
      expect(e.canUndo, isFalse);
    });

    test('the saved file is a complete package: the layouts, theme and content list are all there', () {
      final bytes = writePptx(buildPresetDeck(deckPresetById('team_update')!));
      final names = ZipDecoder().decodeBytes(bytes).files.where((f) => f.isFile).map((f) => f.name).toSet();
      expect(names, containsAll(['[Content_Types].xml', 'ppt/presentation.xml', 'ppt/theme/theme1.xml', 'ppt/slideMasters/slideMaster1.xml']));
      expect(names.where((n) => n.startsWith('ppt/slideLayouts/') && n.endsWith('.xml') && !n.contains('_rels')), hasLength(deckLayouts.length));
      expect(names.where((n) => RegExp(r'^ppt/slides/slide\d+\.xml$').hasMatch(n)), hasLength(deckPresetById('team_update')!.slides.length));
    });
  });

  group('picking a starter', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('sv_decks'));
    tearDown(() => dir.deleteSync(recursive: true));

    Future<Object?> pick(WidgetTester tester, String key, {DocTemplateStore? store}) async {
      Object? opened;
      var route = '';
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, _) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => startNewPresentation(context, tempDir: () async => dir, store: store ?? DocTemplateStore.decks(dir: () async => Directory(p.join(dir.path, 'mine')))),
                  child: const Text('start'),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/slides',
            builder: (_, state) {
              opened = state.extra;
              route = '/slides';
              return const Scaffold(body: Text('editor'));
            },
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.tap(find.text('start'));
      await tester.pumpAndSettle();
      // The list of saved templates is read with real IO.
      for (var i = 0; i < 20 && find.byKey(ValueKey(key)).evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
      await tester.ensureVisible(find.byKey(ValueKey(key)));
      await tester.tap(find.byKey(ValueKey(key)));
      for (var i = 0; i < 20 && route.isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      return opened;
    }

    testWidgets('a starter is handed to the editor', (tester) async {
      final opened = await pick(tester, 'deck-business_pitch');
      expect(opened, isA<DeckPreset>());
      expect((opened! as DeckPreset).id, 'business_pitch');
    });

    testWidgets('the blank choice opens an empty presentation', (tester) async {
      final opened = await pick(tester, 'deck-blank');
      expect(opened, isNull);
      expect(find.text('editor'), findsOneWidget);
    });

    testWidgets('a saved template is copied and opened by its file', (tester) async {
      final store = DocTemplateStore.decks(dir: () async => Directory(p.join(dir.path, 'mine')));
      final src = File(p.join(dir.path, 'src.pptx'))..writeAsBytesSync(writePptx(buildPresetDeck(deckPresets.first)));
      await tester.runAsync(() => store.save(src.path, 'My pitch'));
      final opened = await pick(tester, 'mine-My pitch', store: store);
      expect(opened, p.join(dir.path, newDecksFolder, 'My pitch.pptx'));
      expect(File(opened! as String).existsSync(), isTrue);
      final deck = await tester.runAsync(() => PptxDeck.open(File(opened as String).readAsBytesSync()));
      expect(deck!.slides, hasLength(deckPresets.first.slides.length));
    });

    test('presentation templates are kept apart from Word templates', () async {
      final decks = DocTemplateStore.decks(dir: () async => Directory(p.join(dir.path, 'decks')));
      final words = DocTemplateStore(dir: () async => Directory(p.join(dir.path, 'decks')));
      final src = File(p.join(dir.path, 'a.pptx'))..writeAsBytesSync([1, 2, 3]);
      await decks.save(src.path, 'Deck');
      expect((await decks.list()).map((f) => p.basename(f.path)), ['Deck.pptx']);
      expect(await words.list(), isEmpty, reason: 'a Word list only shows .docx files');
    });
  });
}

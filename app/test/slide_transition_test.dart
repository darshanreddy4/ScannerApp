import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:doculoom/features/office/slides/data/deck_editor.dart';
import 'package:doculoom/features/office/slides/data/pptx_package.dart';
import 'package:doculoom/features/office/slides/data/pptx_template.dart';
import 'package:doculoom/features/office/slides/data/pptx_writer.dart';
import 'package:doculoom/core/theme/app_theme.dart';
import 'package:doculoom/features/office/slides/presentation/slides_page.dart';
import 'package:xml/xml.dart';

DeckEditor deckOf(int slides) {
  final e = DeckEditor(PptxDeck.fromFiles(newPresentationFiles()));
  for (var i = 1; i < slides; i++) {
    e.addSlide();
  }
  return e;
}

String slideXml(List<int> pptx, int n) => utf8.decode(ZipDecoder().decodeBytes(pptx).findFile('ppt/slides/slide$n.xml')!.readBytes()!);

void main() {
  group('how a slide appears', () {
    test('a slide has no effect until one is set, and each effect reads back', () {
      final e = deckOf(2);
      final s = e.deck.slides.first;
      expect(e.transitionOf(s), 'none');
      for (final k in DeckEditor.transitionKinds) {
        e.setTransition(s, k);
        expect(e.transitionOf(s), k);
      }
    });

    test('the effect is written in the right place and survives saving', () async {
      final e = deckOf(2);
      e.setTransition(e.deck.slides[1], 'push');
      final bytes = writePptx(e.deck);
      final xml = slideXml(bytes, 2);
      expect(xml, contains('<p:transition spd="med"><p:push dir="l"/></p:transition>'));
      expect(XmlDocument.parse(xml).rootElement.childElements.map((c) => c.name.local).toList(), containsAllInOrder(['cSld', 'transition']));
      expect(slideXml(bytes, 1), isNot(contains('p:transition')));

      final again = DeckEditor(await PptxDeck.open(bytes));
      expect([for (final s in again.deck.slides) again.transitionOf(s)], ['none', 'push']);
    });

    test('an effect goes before the slide timing, and setting it again replaces it', () {
      final e = deckOf(1);
      final s = e.deck.slides.first;
      s.doc.rootElement.children.add(XmlDocument.parse('<p:timing xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"/>').rootElement.copy());
      e.setTransition(s, 'fade');
      e.setTransition(s, 'wipe');
      final names = s.doc.rootElement.childElements.map((c) => c.name.local).toList();
      expect(names.where((n) => n == 'transition'), hasLength(1));
      expect(names.indexOf('transition'), lessThan(names.indexOf('timing')));
      expect(e.transitionOf(s), 'wipe');
      e.setTransition(s, 'none');
      expect(s.doc.rootElement.childElements.any((c) => c.name.local == 'transition'), isFalse);
      expect(names, contains('timing'));
    });

    test('an effect from another program is recognised, and replaced even when wrapped as Office writes it', () {
      final e = deckOf(1);
      final s = e.deck.slides.first;
      s.doc.rootElement.children.add(
        XmlDocument.parse(
          '<mc:AlternateContent xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">'
          '<mc:Choice Requires="p14"><p:transition spd="slow"><p:checker/></p:transition></mc:Choice>'
          '<mc:Fallback><p:transition spd="slow"><p:checker/></p:transition></mc:Fallback></mc:AlternateContent>',
        ).rootElement.copy(),
      );
      expect(e.transitionOf(s), 'other');
      e.setTransition(s, 'fade');
      expect(e.transitionOf(s), 'fade');
      expect(s.doc.toXmlString(), isNot(contains('AlternateContent')));
      expect(s.doc.toXmlString(), isNot(contains('checker')));
    });

    test('one effect can be given to every slide at once, and undo takes it back from all', () {
      final e = deckOf(3);
      e.setTransition(e.deck.slides[1], 'cover', all: true);
      expect([for (final s in e.deck.slides) e.transitionOf(s)], ['cover', 'cover', 'cover']);
      e.undo();
      expect([for (final s in e.deck.slides) e.transitionOf(s)], ['none', 'none', 'none']);
      e.setTransition(e.deck.slides.first, 'sparkle');
      expect(e.transitionOf(e.deck.slides.first), 'none', reason: 'an unknown effect is ignored');
    });
  });

  group('in the slide show', () {
    Widget host() => MaterialApp(theme: AppTheme.light(), home: const SlidesPage());

    testWidgets('the effect chosen in the editor is what the show uses, and the sheet marks the current one', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 860));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(host());
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('stool_newslide')));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('thumb_0')));
      await tester.pump();

      await tester.ensureVisible(find.byKey(const ValueKey('stool_transition')));
      await tester.tap(find.byKey(const ValueKey('stool_transition')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('transition_all')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('transition_fade')));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const ValueKey('stool_transition')));
      await tester.tap(find.byKey(const ValueKey('stool_transition')));
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('transition_fade'))).selected, isTrue);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('slides_play')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('canvas_0')).evaluate().isNotEmpty || find.byType(AnimatedSwitcher).evaluate().isNotEmpty, isTrue);
      await tester.tap(find.byKey(const ValueKey('slide_show')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.descendant(of: find.byType(AnimatedSwitcher), matching: find.byType(FadeTransition)), findsWidgets, reason: 'the change is fading');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('slide_show')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('slide_show')), findsNothing, reason: 'a tap on the last slide ends the show');
    });

    testWidgets('a swipe to the left moves on and a swipe to the right goes back', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 860));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(host());
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('stool_newslide')));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('thumb_0')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('slides_play')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey(0)), findsOneWidget);
      await tester.fling(find.byKey(const ValueKey('slide_show')), const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey(1)), findsOneWidget);
      await tester.fling(find.byKey(const ValueKey('slide_show')), const Offset(300, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey(0)), findsOneWidget);
      await tester.fling(find.byKey(const ValueKey('slide_show')), const Offset(300, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey(0)), findsOneWidget, reason: 'there is nothing before the first slide');
      await tester.tap(find.byKey(const ValueKey('show_close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('slide_show')), findsNothing);
    });
  });
}

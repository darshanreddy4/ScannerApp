import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:doculoom/core/theme/app_theme.dart';
import 'package:doculoom/features/cv/domain/cv.dart';
import 'package:doculoom/features/cv/presentation/cv_design_picker.dart';

void main() {
  group('the catalogue', () {
    test('there are at least 20 designs in two groups, each with a name and a hint', () {
      expect(cvDesigns.length, greaterThanOrEqualTo(20));
      expect(cvDesigns.where((d) => d.group == CvGroup.plain).length, greaterThanOrEqualTo(10));
      expect(cvDesigns.where((d) => d.group == CvGroup.colourful).length, greaterThanOrEqualTo(10));
      expect(cvDesigns.map((d) => d.id).toSet().length, cvDesigns.length);
      expect(cvDesigns.map((d) => d.name).toSet().length, cvDesigns.length);
      for (final d in cvDesigns) {
        expect(d.name.trim(), isNotEmpty);
        expect(d.hint.trim(), endsWith('.'), reason: d.id);
      }
    });

    test('the three older layouts are still there under their ids', () {
      expect(cvTemplates.keys, containsAll(['europe', 'classic', 'modern']));
    });

    test('every design is the right mix: plain ones with colour or none, colourful ones with colour', () {
      for (final d in cvDesigns.where((d) => d.group == CvGroup.colourful)) {
        expect(d.mono, isFalse, reason: d.id);
      }
      expect(cvDesigns.where((d) => d.mono).map((d) => d.id), containsAll(['ats', 'us', 'german', 'academic', 'minimal']));
      expect(cvDesigns.where((d) => !d.personal).map((d) => d.id), containsAll(['ats', 'us', 'uk']));
      expect(cvDesigns.where((d) => !d.hasPhoto).map((d) => d.id), containsAll(['ats', 'us', 'uk', 'academic']));
      expect(cvDesigns.where((d) => d.isSidebar).length, greaterThanOrEqualTo(4));
    });

    test('an unknown id gives the European design, and each id is kept when saved', () {
      expect(cvDesignOf('zzz').id, 'europe');
      for (final d in cvDesigns) {
        expect(CvData.fromJson(CvData(template: d.id).toJson()).template, d.id);
      }
    });

    test('black and white designs ignore the colour, the others use it', () {
      expect(effectiveAccent(cvDesignOf('ats'), 0xFFB91C1C), 0xFF111827);
      expect(effectiveAccent(cvDesignOf('banner'), 0xFFB91C1C), 0xFFB91C1C);
    });

    test('lighter and darker shades of a colour, and the levels of languages', () {
      expect(tintOf(0xFF000000, 0.5), 0xFF808080);
      expect(tintOf(0xFFFFFFFF, 0.5), 0xFFFFFFFF);
      expect(tintOf(0xFF1D4ED8, 0), 0xFF1D4ED8);
      expect(shadeOf(0xFFFFFFFF, 0.5), 0xFF808080);
      expect(shadeOf(0xFF1D4ED8, 1), 0xFF000000);
      expect(levelFraction('A1'), closeTo(1 / 6, 1e-9));
      expect(levelFraction('C2'), 1);
      expect(levelFraction('Native'), 1);
      expect(cvAccents.length, greaterThanOrEqualTo(10));
      expect(cvAccents.toSet().length, cvAccents.length);
    });
  });

  group('the gallery', () {
    Future<void> show(
      WidgetTester tester, {
      String selected = 'europe',
      int accent = defaultCvAccent,
      void Function(String)? onDesign,
      void Function(int)? onAccent,
      double width = 400,
    }) async {
      tester.view.physicalSize = Size(width * 3, 4000 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: CvDesignPicker(selected: selected, accent: accent, onDesign: onDesign ?? (_) {}, onAccent: onAccent ?? (_) {}),
            ),
          ),
        ),
      );
    }

    testWidgets('shows every design in two groups with its name, and the colours', (tester) async {
      await show(tester);
      expect(find.text('Plain and professional'), findsOneWidget);
      expect(find.text('Colourful'), findsWidgets);
      for (final d in cvDesigns) {
        expect(find.byKey(ValueKey('template-${d.id}')), findsOneWidget, reason: d.id);
        expect(find.text(d.name), findsOneWidget, reason: d.id);
      }
      for (final c in cvAccents) {
        expect(find.byKey(ValueKey('accent-$c')), findsOneWidget);
      }
    });

    testWidgets('choosing a design and a colour tells the page', (tester) async {
      String? design;
      int? colour;
      await show(tester, onDesign: (d) => design = d, onAccent: (c) => colour = c);
      await tester.tap(find.byKey(const ValueKey('template-timeline')));
      await tester.tap(find.byKey(ValueKey('accent-${cvAccents[2]}')));
      expect(design, 'timeline');
      expect(colour, cvAccents[2]);
    });

    testWidgets('the chosen design is described, and its habits are said', (tester) async {
      await show(tester, selected: 'us');
      final hint = tester.widget<Container>(find.byKey(const ValueKey('design-hint')));
      expect(hint, isNotNull);
      expect(find.textContaining('US resume'), findsWidgets);
      expect(find.textContaining('The birth date and nationality are left out.'), findsOneWidget);
    });

    testWidgets('a black and white design offers no colours and says why', (tester) async {
      await show(tester, selected: 'ats');
      expect(find.byKey(const ValueKey('mono-note')), findsOneWidget);
      expect(find.byKey(ValueKey('accent-${cvAccents.first}')), findsNothing);
      await show(tester, selected: 'banner');
      expect(find.byKey(const ValueKey('mono-note')), findsNothing);
      expect(find.byKey(ValueKey('accent-${cvAccents.first}')), findsOneWidget);
    });

    testWidgets('every design is drawn small in every colour without errors', (tester) async {
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final c in [cvAccents.first, cvAccents[3], cvAccents.last]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Wrap(
                children: [for (final d in cvDesigns) CvThumb(design: d, accent: c)],
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
      }
    });

    for (final w in [320.0, 900.0]) {
      testWidgets('fits a ${w.toInt()} px wide screen', (tester) async {
        await show(tester, width: w, selected: 'creative');
        expect(tester.takeException(), isNull);
      });
    }
  });
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scanvault/core/theme/app_theme.dart';
import 'package:scanvault/features/office/slides/presentation/slides_page.dart';

Widget host(String? path) => MaterialApp(
  theme: AppTheme.light(),
  home: SlidesPage(path: path),
);

Future<void> waitFor(WidgetTester tester, Finder f) async {
  for (var i = 0; i < 60 && f.evaluate().isEmpty; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }
}

void main() {
  testWidgets('opens a deck, selects a shape, edits its text and slides can be added and undone', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 860));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(host(File('test/fixtures/office/deck.pptx').absolute.path));
    await waitFor(tester, find.byKey(const ValueKey('thumb_2')));
    expect(find.byKey(const ValueKey('thumb_0')), findsOneWidget);
    expect(find.byKey(const ValueKey('thumb_2')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('thumb_1')));
    await tester.pump();
    // Tap the body placeholder (centre of the slide area, where the bullets are).
    final canvas = find.byKey(const ValueKey('canvas_1'));
    final rect = tester.getRect(canvas);
    await tester.tapAt(Offset(rect.left + rect.width * 0.3, rect.top + rect.height * 0.3));
    await tester.pump();
    expect(find.byKey(const ValueKey('stool_edit')), findsOneWidget, reason: 'a text shape is selected');
    await tester.tap(find.byKey(const ValueKey('stool_edit')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('slide_text_field')), 'Changed text');
    await tester.tap(find.byKey(const ValueKey('slide_text_ok')));
    await tester.pumpAndSettle();
    expect(find.text('Changed text'), findsNothing, reason: 'slides are drawn, not text widgets');

    expect(find.textContaining('*'), findsOneWidget, reason: 'the title shows unsaved changes');
    await tester.tap(find.byKey(const ValueKey('stool_done')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('stool_newslide')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('thumb_3')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('slides_undo')));
    await tester.pump();
    expect(find.byKey(const ValueKey('thumb_3')), findsNothing);
  });

  testWidgets('a new presentation starts with one slide; leaving with changes asks first', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 860));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(host(null));
    await tester.pump();
    expect(find.byKey(const ValueKey('thumb_0')), findsOneWidget);
    expect(find.byKey(const ValueKey('thumb_1')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('stool_addtext')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('slide_text_field')), 'Hello');
    await tester.tap(find.byKey(const ValueKey('slide_text_ok')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('slides_back')));
    await tester.pumpAndSettle();
    expect(find.text('Leave without saving?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('slides_undo')), findsOneWidget);
  });

  testWidgets('the slide show pages through slides', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 860));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(host(File('test/fixtures/office/deck.pptx').absolute.path));
    await waitFor(tester, find.byKey(const ValueKey('thumb_2')));
    await tester.tap(find.byKey(const ValueKey('slides_play')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('slide_show')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('slide_show')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('show_close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('slide_show')), findsNothing);
  });

  testWidgets('a file that is not a presentation shows a clear message', (tester) async {
    final dir = Directory.systemTemp.createTempSync('bad_pptx');
    final bad = File('${dir.path}/bad.pptx')..writeAsBytesSync([1, 2, 3]);
    await tester.pumpWidget(host(bad.path));
    await waitFor(tester, find.text('Go back'));
    expect(find.textContaining('not a valid .pptx'), findsOneWidget);
    dir.deleteSync(recursive: true);
  });
}

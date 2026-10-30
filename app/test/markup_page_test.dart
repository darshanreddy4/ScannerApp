import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:doculoom/core/theme/app_theme.dart';
import 'package:doculoom/features/markup/data/stamp_store.dart';
import 'package:doculoom/features/markup/domain/stamps.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:doculoom/features/markup/domain/markup.dart';
import 'package:doculoom/features/markup/markup_paint.dart';
import 'package:doculoom/features/markup/presentation/markup_canvas.dart';
import 'package:doculoom/features/markup/presentation/markup_cubit.dart';
import 'package:doculoom/features/markup/presentation/markup_page.dart';

void main() {
  List<MarkupItem>? result;
  var popped = false;

  Uint8List pagePicture() => Uint8List.fromList(img.encodeJpg(img.Image(width: 60, height: 80, numChannels: 3), quality: 50));

  Future<MarkupCubit> open(WidgetTester tester, {double width = 400, double height = 800}) async {
    tester.view.physicalSize = Size(width * 3, height * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    result = null;
    popped = false;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await context.push<List<MarkupItem>>('/markup', extra: MarkupArgs(width: 600, height: 800, previewBytes: pagePicture()));
                  popped = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/markup',
          builder: (_, state) => MarkupPage(args: state.extra! as MarkupArgs),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(theme: AppTheme.light(), routerConfig: router));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    return tester.element(find.byType(MarkupCanvas)).read<MarkupCubit>();
  }

  Finder canvas() => find.byKey(const ValueKey('markup-canvas'));

  Future<void> drag(WidgetTester tester, Offset from, Offset by, {int pointer = 1}) async {
    final g = await tester.startGesture(from, pointer: pointer);
    for (var i = 1; i <= 6; i++) {
      await g.moveBy(by / 6);
    }
    await g.up();
    await tester.pump();
  }

  Offset at(WidgetTester tester, double fx, double fy) {
    final r = tester.getRect(canvas());
    return Offset(r.left + r.width * fx, r.top + r.height * fy);
  }

  Future<void> tool(WidgetTester tester, MarkupTool t) async {
    final f = find.byKey(ValueKey('tool-${t.name}'));
    final strip = find.descendant(of: find.byType(Scaffold), matching: find.byType(Scrollable)).first;
    // The strip scrolls sideways and builds only the tools that are near the screen.
    for (final delta in [300.0, -300.0]) {
      if (f.evaluate().isNotEmpty) break;
      try {
        await tester.scrollUntilVisible(f, delta, scrollable: strip, maxScrolls: 20);
      } on StateError {
        // Wrong direction: the strip is already at that end.
      }
    }
    // Built does not mean on screen: slide the strip until the tool is inside it.
    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    for (var i = 0; i < 30; i++) {
      final x = tester.getCenter(f).dx;
      if (x > 80 && x < width - 24) break;
      await tester.drag(strip, Offset(x <= 80 ? 120 : -120, 0));
      await tester.pump();
    }
    await tester.tap(f);
    await tester.pump();
  }

  testWidgets('shows every tool and starts with the pen', (tester) async {
    final cubit = await open(tester);
    expect(cubit.state.tool, MarkupTool.pen);
    for (final t in [
      MarkupTool.pen,
      MarkupTool.pencil,
      MarkupTool.highlighter,
      MarkupTool.eraser,
      MarkupTool.line,
      MarkupTool.arrow,
      MarkupTool.rectangle,
      MarkupTool.ellipse,
      MarkupTool.redact,
      MarkupTool.sticker,
      MarkupTool.stamp,
      MarkupTool.text,
    ]) {
      await tool(tester, t);
    }
    expect(tester.widget<IconButton>(find.byKey(const ValueKey('undo'))).onPressed, isNull);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
  });

  testWidgets('Cancel and Done show their full words on a narrow phone', (tester) async {
    await open(tester);
    expect(tester.getSize(find.text('Cancel')).width, greaterThanOrEqualTo(80));
    expect(tester.getSize(find.text('Done')).width, greaterThanOrEqualTo(55));
    expect(tester.takeException(), isNull);
  });

  testWidgets('drawing with a finger adds a mark, undo and redo move through it', (tester) async {
    final cubit = await open(tester);
    await drag(tester, at(tester, 0.2, 0.3), const Offset(120, 40));
    expect(cubit.state.items.single, isA<MarkupStroke>());
    expect(tester.widget<IconButton>(find.byKey(const ValueKey('undo'))).onPressed, isNotNull);
    await tester.tap(find.byKey(const ValueKey('undo')));
    await tester.pump();
    expect(cubit.state.items, isEmpty);
    await tester.tap(find.byKey(const ValueKey('redo')));
    await tester.pump();
    expect(cubit.state.items.length, 1);
  });

  testWidgets('a highlighter stroke is wide and see-through', (tester) async {
    final cubit = await open(tester);
    await tool(tester, MarkupTool.highlighter);
    await drag(tester, at(tester, 0.2, 0.5), const Offset(120, 0));
    final s = cubit.state.items.single as MarkupStroke;
    expect(s.kind, PenKind.highlighter);
    expect((s.color >> 24) & 0xFF, lessThan(150));
    expect(s.width, greaterThan(0.02));
  });

  testWidgets('shapes: square, circle, arrow and line are drawn by dragging', (tester) async {
    final cubit = await open(tester);
    var y = 0.15;
    for (final t in [MarkupTool.rectangle, MarkupTool.ellipse, MarkupTool.arrow, MarkupTool.line]) {
      await tool(tester, t);
      await drag(tester, at(tester, 0.2, y), const Offset(100, 30));
      y += 0.2;
    }
    expect([for (final i in cubit.state.items) (i as MarkupShape).kind], [ShapeKind.rectangle, ShapeKind.ellipse, ShapeKind.arrow, ShapeKind.line]);
  });

  testWidgets('the fill option appears for square and circle only', (tester) async {
    await open(tester);
    await tool(tester, MarkupTool.line);
    expect(find.byKey(const ValueKey('fill-chip')), findsNothing);
    await tool(tester, MarkupTool.ellipse);
    expect(find.byKey(const ValueKey('fill-chip')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('fill-chip')));
    await tester.pump();
    expect(tester.element(canvas()).read<MarkupCubit>().state.filled, isTrue);
  });

  testWidgets('the thickness slider changes the pen width', (tester) async {
    final cubit = await open(tester);
    final before = cubit.state.widthOf(MarkupTool.pen);
    await tester.drag(find.byKey(const ValueKey('thickness-slider')), const Offset(200, 0));
    await tester.pump();
    expect(cubit.state.widthOf(MarkupTool.pen), greaterThan(before));
  });

  testWidgets('emoji: choose one, tap the page to place it, then adjust or delete it', (tester) async {
    final cubit = await open(tester);
    await tool(tester, MarkupTool.sticker);
    await tester.tap(find.byKey(const ValueKey('emoji-button')));
    await tester.pumpAndSettle();
    expect(find.text('Choose an emoji'), findsOneWidget);
    await tester.tap(find.text('👍'));
    await tester.pumpAndSettle();
    expect(cubit.state.emoji, '👍');
    await tester.tapAt(at(tester, 0.5, 0.5));
    await tester.pump();
    final s = cubit.state.items.single as MarkupSticker;
    expect(s.text, '👍');
    expect(cubit.state.tool, MarkupTool.select);
    expect(cubit.state.selectedId, s.id);
    expect(find.byKey(const ValueKey('sticker-size')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('delete-selected')));
    await tester.pump();
    expect(cubit.state.items, isEmpty);
  });

  testWidgets('text: tap the page, type words, and they appear as a mark that can be edited, resized and deleted', (tester) async {
    final cubit = await open(tester);
    await tool(tester, MarkupTool.text);
    await tester.tapAt(at(tester, 0.4, 0.3));
    await tester.pumpAndSettle();
    expect(find.text('Add text'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('markup-text-save')));
    await tester.pumpAndSettle();
    expect(cubit.state.items, isEmpty, reason: 'empty text adds nothing');

    await tester.tapAt(at(tester, 0.4, 0.3));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('markup-text-field')), 'Paid in full');
    await tester.tap(find.byKey(const ValueKey('markup-text-save')));
    await tester.pumpAndSettle();
    final t = cubit.state.items.single as MarkupText;
    expect(t.text, 'Paid in full');
    expect(t.center.dx, closeTo(0.4, 0.02));
    expect(cubit.state.tool, MarkupTool.select);
    expect(cubit.state.selectedId, t.id);

    await tester.tap(find.byKey(const ValueKey('bold-chip')));
    await tester.pump();
    expect((cubit.state.items.single as MarkupText).bold, isTrue);
    cubit.setTextSize(0.1);
    expect((cubit.state.items.single as MarkupText).size, closeTo(0.1, 1e-9));

    await tester.tap(find.byKey(const ValueKey('edit-text')));
    await tester.pumpAndSettle();
    expect(find.text('Edit text'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('markup-text-field')), 'Paid');
    await tester.tap(find.byKey(const ValueKey('markup-text-save')));
    await tester.pumpAndSettle();
    expect((cubit.state.items.single as MarkupText).text, 'Paid');

    cubit.undo();
    expect((cubit.state.items.single as MarkupText).text, 'Paid in full');

    await tester.tap(find.byKey(const ValueKey('delete-selected')));
    await tester.pump();
    expect(cubit.state.items, isEmpty);
  });

  testWidgets('text: tapping existing text with the Text tool edits it instead of adding another', (tester) async {
    final cubit = await open(tester);
    cubit.addText(const Offset(0.5, 0.5), 'Hello');
    await tool(tester, MarkupTool.text);
    await tester.tapAt(at(tester, 0.5, 0.5));
    await tester.pumpAndSettle();
    expect(find.text('Edit text'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('markup-text-field')), 'Bye');
    await tester.tap(find.byKey(const ValueKey('markup-text-save')));
    await tester.pumpAndSettle();
    expect(cubit.state.items, hasLength(1));
    expect((cubit.state.items.single as MarkupText).text, 'Bye');
  });

  testWidgets('text colour follows the colour chosen, and the saved page has the text drawn on it', (tester) async {
    final cubit = await open(tester);
    cubit.setColor(0x1E88E5);
    cubit.addText(const Offset(0.5, 0.5), 'Blue');
    final t = cubit.state.items.single as MarkupText;
    expect(t.color, 0xFF1E88E5);
    cubit.setColor(0xE53935);
    expect((cubit.state.items.single as MarkupText).color, 0xFFE53935, reason: 'the selected text takes the new colour');

    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(const Rect.fromLTWH(0, 0, 300, 400), Paint()..color = Colors.white);
      paintMarkup(canvas, const Size(300, 400), cubit.state.items);
      final image = await recorder.endRecording().toImage(300, 400);
      final data = (await image.toByteData())!;
      var red = 0;
      for (var i = 0; i < data.lengthInBytes; i += 4) {
        if (data.getUint8(i) > 200 && data.getUint8(i + 1) < 100 && data.getUint8(i + 2) < 100) red++;
      }
      expect(red, greaterThan(50), reason: 'red text pixels are on the page');
    });
  });

  testWidgets('the Hide tool covers an area in solid black whatever colour or see-through setting is chosen', (tester) async {
    final cubit = await open(tester);
    cubit.setColor(0xE53935);
    cubit.setOpacity(0.2);
    await tool(tester, MarkupTool.redact);
    expect(find.textContaining('solid black'), findsOneWidget);
    expect(find.byKey(const ValueKey('thickness-slider')), findsNothing, reason: 'nothing to adjust');
    await drag(tester, at(tester, 0.2, 0.3), const Offset(120, 80));

    final box = cubit.state.items.single as MarkupShape;
    expect(box.redact, isTrue);
    expect(box.color, 0xFF000000);
    expect(box.filled, isTrue);

    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(const Rect.fromLTWH(0, 0, 300, 400), Paint()..color = Colors.white);
      paintMarkup(canvas, const Size(300, 400), [
        const MarkupShape(
          id: 1,
          kind: ShapeKind.rectangle,
          from: Offset(0.2, 0.2),
          to: Offset(0.8, 0.5),
          color: 0xFF000000,
          width: 0.001,
          filled: true,
          redact: true,
        ),
      ]);
      final image = await recorder.endRecording().toImage(300, 400);
      final data = (await image.toByteData())!;
      int px(int x, int y) => data.getUint32((y * 300 + x) * 4);
      // Every pixel from edge to edge inside the box is pure black, including the very first and last.
      for (final (x, y) in [(60, 80), (61, 81), (239, 199), (150, 140), (60, 199), (239, 80)]) {
        expect(data.getUint8((y * 300 + x) * 4), 0, reason: 'red channel at $x,$y');
        expect(data.getUint8((y * 300 + x) * 4 + 1), 0);
        expect(data.getUint8((y * 300 + x) * 4 + 2), 0);
        expect(data.getUint8((y * 300 + x) * 4 + 3), 255, reason: 'fully opaque at $x,$y');
      }
      expect(px(20, 20), isNot(0xFF000000), reason: 'outside the box stays white');
    });
  });

  testWidgets('a black box cannot be made see-through or coloured afterwards, but can be moved and removed', (tester) async {
    final cubit = await open(tester);
    await tool(tester, MarkupTool.redact);
    await drag(tester, at(tester, 0.2, 0.3), const Offset(120, 80));
    await tool(tester, MarkupTool.select);
    await drag(tester, at(tester, 0.3, 0.35), const Offset(40, 20));
    expect(cubit.state.selectedId, isNotNull);
    expect(find.textContaining('Black box'), findsOneWidget);
    expect(find.byKey(const ValueKey('thickness-slider')), findsNothing);

    cubit.setColor(0x1E88E5);
    cubit.setOpacity(0.1);
    cubit.setFilled(false);
    final box = cubit.state.items.single as MarkupShape;
    expect(box.color, 0xFF000000);
    expect(box.filled, isTrue);
    expect(box.redact, isTrue);

    await tester.tap(find.byKey(const ValueKey('delete-selected')));
    await tester.pump();
    expect(cubit.state.items, isEmpty);
  });

  testWidgets('a tiny accidental touch with the Hide tool leaves no box', (tester) async {
    final cubit = await open(tester);
    await tool(tester, MarkupTool.redact);
    await drag(tester, at(tester, 0.5, 0.5), const Offset(2, 1));
    expect(cubit.state.items, isEmpty);
  });

  test('text marks: size, touching, moving, scaling and turning', () {
    const page = Size(600, 800);
    const t = MarkupText(id: 1, text: 'Line one\nLine two', center: Offset(0.5, 0.5), size: 0.05, color: 0xFF000000);
    final box = MarkupGeometry.bounds(t, page);
    expect(box.center.dx, closeTo(300, 0.5));
    expect(box.center.dy, closeTo(400, 0.5));
    expect(box.height, greaterThan(2 * 0.05 * 600), reason: 'two lines are taller than one');
    expect(MarkupGeometry.hit(t, const Offset(0.5, 0.5), page), isTrue);
    expect(MarkupGeometry.hit(t, const Offset(0.5, 0.9), page), isFalse);
    expect(MarkupGeometry.hit(t, const Offset(0.02, 0.5), page), isFalse);

    final moved = MarkupGeometry.transform(t, page, delta: const Offset(0.1, 0)) as MarkupText;
    expect(moved.center.dx, closeTo(0.6, 1e-9));
    final big = MarkupGeometry.transform(t, page, scale: 100) as MarkupText;
    expect(big.size, MarkupText.maxSize);
    final turned = MarkupGeometry.transform(t, page, rotation: 1.5708) as MarkupText;
    expect(MarkupGeometry.bounds(turned, page).height, greaterThan(box.height), reason: 'a turned wide text is taller');
  });

  testWidgets('any emoji can be typed in', (tester) async {
    final cubit = await open(tester);
    await tool(tester, MarkupTool.sticker);
    await tester.tap(find.byKey(const ValueKey('emoji-button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('custom-emoji')), '🦄');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(cubit.state.emoji, '🦄');
  });

  testWidgets('a placed sticker can be dragged to a new spot', (tester) async {
    final cubit = await open(tester);
    await tool(tester, MarkupTool.sticker);
    await tester.tapAt(at(tester, 0.3, 0.3));
    await tester.pump();
    final before = (cubit.state.items.single as MarkupSticker).center;
    await drag(tester, at(tester, 0.3, 0.3), const Offset(90, 60));
    final after = (cubit.state.items.single as MarkupSticker).center;
    expect(after.dx, greaterThan(before.dx));
    expect(after.dy, greaterThan(before.dy));
    await tester.tap(find.byKey(const ValueKey('undo')));
    await tester.pump();
    expect((cubit.state.items.single as MarkupSticker).center, before);
  });

  testWidgets('the eraser removes the mark it touches', (tester) async {
    final cubit = await open(tester);
    await drag(tester, at(tester, 0.2, 0.3), const Offset(150, 0));
    await drag(tester, at(tester, 0.2, 0.7), const Offset(150, 0));
    await tool(tester, MarkupTool.eraser);
    await drag(tester, at(tester, 0.3, 0.25), const Offset(0, 60));
    expect(cubit.state.items.length, 1);
  });

  testWidgets('the zoom tool does not draw', (tester) async {
    final cubit = await open(tester);
    await tool(tester, MarkupTool.hand);
    await drag(tester, at(tester, 0.3, 0.3), const Offset(80, 80));
    expect(cubit.state.items, isEmpty);
    expect(find.textContaining('Pinch to zoom'), findsOneWidget);
  });

  testWidgets('a second finger drops the line instead of drawing a stray mark', (tester) async {
    final cubit = await open(tester);
    final g1 = await tester.startGesture(at(tester, 0.2, 0.3), pointer: 1);
    await g1.moveBy(const Offset(30, 0));
    final g2 = await tester.startGesture(at(tester, 0.6, 0.6), pointer: 2);
    await g1.moveBy(const Offset(30, 0));
    await g2.up();
    await g1.up();
    await tester.pump();
    expect(cubit.state.items, isEmpty);
  });

  testWidgets('colour sheet: grid, ring and opacity', (tester) async {
    final cubit = await open(tester);
    await tester.tap(find.byKey(const ValueKey('color-button')));
    await tester.pumpAndSettle();
    expect(find.text('Grid'), findsOneWidget);
    expect(find.text('Ring'), findsOneWidget);
    // Pick a swatch from the quick row: the green one.
    final before = cubit.state.color;
    await tester.tap(find.byKey(const ValueKey('swatch-43a047')));
    await tester.pump();
    expect(cubit.state.color, 0x43A047);
    expect(cubit.state.color, isNot(before));
    await tester.tap(find.text('Ring'));
    await tester.pumpAndSettle();
    final ring = find.byKey(const ValueKey('ring-picker'));
    expect(ring, findsOneWidget);
    final c = tester.getCenter(ring);
    final side = tester.getSize(ring).width;
    final colorBefore = cubit.state.color;
    await tester.tapAt(c + Offset(side / 2 - side * 0.055, 0));
    await tester.pump();
    expect(cubit.state.color, isNot(colorBefore), reason: 'tapping the ring changes the hue');
    await tester.drag(find.byKey(const ValueKey('opacity-slider')), const Offset(-200, 0));
    await tester.pump();
    expect(cubit.state.opacityOf(MarkupTool.pen), lessThan(1));
  });

  testWidgets('the colour chosen is used for the next line', (tester) async {
    final cubit = await open(tester);
    cubit.setColor(0x1E88E5);
    await drag(tester, at(tester, 0.2, 0.3), const Offset(100, 0));
    expect((cubit.state.items.single as MarkupStroke).color & 0xFFFFFF, 0x1E88E5);
  });

  testWidgets('Done hands the marks back; with no marks it hands back nothing', (tester) async {
    final cubit = await open(tester);
    await drag(tester, at(tester, 0.2, 0.3), const Offset(100, 0));
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(popped, isTrue);
    expect(result!.length, 1);
    expect(cubit.state.items.length, 1);

    await open(tester);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });

  testWidgets('Cancel asks before throwing marks away', (tester) async {
    await open(tester);
    await drag(tester, at(tester, 0.2, 0.3), const Offset(100, 0));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Discard your markup?'), findsOneWidget);
    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();
    expect(popped, isFalse);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(popped, isTrue);
    expect(result, isNull);
  });

  testWidgets('Cancel with nothing drawn leaves at once', (tester) async {
    await open(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(popped, isTrue);
  });

  for (final size in [const Size(320, 568), const Size(400, 800), const Size(900, 600)]) {
    testWidgets('fits a ${size.width.toInt()} x ${size.height.toInt()} screen with every control', (tester) async {
      final cubit = await open(tester, width: size.width, height: size.height);
      for (final t in MarkupTool.values) {
        await tool(tester, t);
        expect(tester.takeException(), isNull, reason: t.name);
      }
      cubit.selectTool(MarkupTool.pen);
      await tester.pump();
      await drag(tester, at(tester, 0.3, 0.3), const Offset(40, 20));
      expect(cubit.state.items, isNotEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('stamp: choose a ready-made one, tap the page, and it is placed as a framed, tilted stamp', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final cubit = await open(tester);
    await tool(tester, MarkupTool.stamp);
    expect(find.text('Tap the page to place'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('stamp-button')));
    await tester.pumpAndSettle();
    expect(find.text('Choose a stamp'), findsOneWidget);
    await tester.tap(find.text('APPROVED', findRichText: true).first);
    await tester.pumpAndSettle();
    expect(cubit.state.stamp, const Stamp('APPROVED', stampGreen));
    await tester.tapAt(at(tester, 0.5, 0.5));
    await tester.pump();
    final item = cubit.state.items.single as MarkupText;
    expect(item.text, 'APPROVED');
    expect(item.framed, isTrue);
    expect(item.bold, isTrue);
    expect(item.rotation, isNot(0));
    expect(item.color, stampGreen);
    expect(cubit.state.tool, MarkupTool.select);
    await tester.tap(find.byKey(const ValueKey('delete-selected')));
    await tester.pump();
    expect(cubit.state.items, isEmpty);
  });

  testWidgets('stamp: make your own, with a clear message first, and it is kept in My stamps', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final cubit = await open(tester);
    await tool(tester, MarkupTool.stamp);
    await tester.tap(find.byKey(const ValueKey('stamp-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('make-stamp')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('stamp-use')));
    await tester.pumpAndSettle();
    expect(find.text('Type the words for the stamp.'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('stamp-text')), 'my seal');
    await tester.tap(find.byKey(const ValueKey('stamp-color-blue')));
    await tester.tap(find.byKey(const ValueKey('stamp-date')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('stamp-preview')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('stamp-use')));
    await tester.pumpAndSettle();
    expect(cubit.state.stamp, const Stamp('MY SEAL\n{date}', stampBlue));
    expect(await const StampStore().load(), [const Stamp('MY SEAL\n{date}', stampBlue)]);
  });

  testWidgets('stamp: the sheet and the options fit a narrow phone', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await open(tester, width: 320, height: 640);
    await tool(tester, MarkupTool.stamp);
    await tester.tap(find.byKey(const ValueKey('stamp-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('make-stamp')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

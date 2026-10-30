import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:doculoom/features/markup/domain/markup.dart';
import 'package:doculoom/features/markup/presentation/markup_cubit.dart';

void main() {
  const page = Size(1000, 1400);
  late MarkupCubit c;

  setUp(() => c = MarkupCubit(page: page));
  tearDown(() => c.close());

  void drawLine(Offset a, Offset b, {int steps = 5}) {
    c.pointerDown(a);
    for (var i = 1; i <= steps; i++) {
      c.pointerMove(Offset.lerp(a, b, i / steps)!);
    }
    c.pointerUp();
  }

  group('freehand tools', () {
    test('a pen stroke becomes an item with the chosen colour and width', () {
      c.setColor(0x1E88E5);
      c.setWidth(0.01);
      drawLine(const Offset(0.1, 0.1), const Offset(0.5, 0.4));
      final s = c.state.items.single as MarkupStroke;
      expect(s.kind, PenKind.pen);
      expect(s.color, 0xFF1E88E5);
      expect(s.width, 0.01);
      expect(s.points.length, greaterThan(2));
      expect(c.state.draft, isNull);
      expect(c.state.canUndo, isTrue);
    });

    test('tiny jitters are not recorded as new points', () {
      c.pointerDown(const Offset(0.5, 0.5));
      c.pointerMove(const Offset(0.5001, 0.5));
      c.pointerMove(const Offset(0.5002, 0.5001));
      c.pointerUp();
      expect((c.state.items.single as MarkupStroke).points.length, 1, reason: 'a tap leaves a dot');
    });

    test('the highlighter is see-through by default and keeps its own opacity', () {
      c.selectTool(MarkupTool.highlighter);
      drawLine(const Offset(0.1, 0.1), const Offset(0.8, 0.1));
      final s = c.state.items.single as MarkupStroke;
      expect(s.kind, PenKind.highlighter);
      expect((s.color >> 24) & 0xFF, closeTo(0.4 * 255, 1));
      expect(s.width, 0.03);
      c.selectTool(MarkupTool.pen);
      drawLine(const Offset(0.1, 0.2), const Offset(0.8, 0.2));
      expect(((c.state.items.last as MarkupStroke).color >> 24) & 0xFF, 255, reason: 'the pen stays solid');
    });

    test('opacity and width are remembered per tool', () {
      c.selectTool(MarkupTool.pencil);
      c.setOpacity(0.5);
      c.setWidth(0.02);
      c.selectTool(MarkupTool.pen);
      expect(c.state.opacityOf(MarkupTool.pen), 1);
      expect(c.state.widthOf(MarkupTool.pen), 0.005);
      c.selectTool(MarkupTool.pencil);
      expect(c.state.opacityOf(MarkupTool.pencil), 0.5);
      expect(c.state.widthOf(MarkupTool.pencil), 0.02);
    });

    test('a second finger drops the line being drawn', () {
      c.pointerDown(const Offset(0.2, 0.2));
      c.pointerMove(const Offset(0.4, 0.4));
      c.cancelDraft();
      c.pointerUp();
      expect(c.state.items, isEmpty);
    });
  });

  group('shapes', () {
    test('a square is created by dragging and follows the finger while drawing', () {
      c.selectTool(MarkupTool.rectangle);
      c.pointerDown(const Offset(0.2, 0.2));
      c.pointerMove(const Offset(0.6, 0.5));
      expect((c.state.draft as MarkupShape).to, const Offset(0.6, 0.5));
      expect(c.state.items, isEmpty);
      c.pointerUp();
      final s = c.state.items.single as MarkupShape;
      expect((s.kind, s.from, s.to), (ShapeKind.rectangle, const Offset(0.2, 0.2), const Offset(0.6, 0.5)));
    });

    test('every shape kind has a tool', () {
      for (final t in [MarkupTool.line, MarkupTool.arrow, MarkupTool.rectangle, MarkupTool.ellipse]) {
        c.selectTool(t);
        drawLine(const Offset(0.1, 0.1), const Offset(0.5, 0.5), steps: 1);
        expect((c.state.items.last as MarkupShape).kind, t.shapeKind);
      }
      expect(c.state.items.length, 4);
    });

    test('a tap without dragging does not leave an invisible shape', () {
      c.selectTool(MarkupTool.ellipse);
      c.pointerDown(const Offset(0.5, 0.5));
      c.pointerUp();
      expect(c.state.items, isEmpty);
    });

    test('fill is kept with the shape', () {
      c.setFilled(true);
      c.selectTool(MarkupTool.ellipse);
      drawLine(const Offset(0.2, 0.2), const Offset(0.6, 0.6), steps: 1);
      expect((c.state.items.single as MarkupShape).filled, isTrue);
    });
  });

  group('emoji', () {
    test('a tap places the chosen emoji and selects it for adjusting', () {
      c.setEmoji('⭐');
      c.selectTool(MarkupTool.sticker);
      c.pointerDown(const Offset(0.4, 0.3));
      c.pointerUp();
      final s = c.state.items.single as MarkupSticker;
      expect((s.text, s.center), ('⭐', const Offset(0.4, 0.3)));
      expect(c.state.selectedId, s.id);
      expect(c.state.tool, MarkupTool.select);
    });

    test('blank text is ignored', () {
      c.setEmoji('   ');
      expect(c.state.emoji, '✅');
    });

    test('the selected sticker can be changed to another emoji', () {
      c.selectTool(MarkupTool.sticker);
      c.pointerDown(const Offset(0.5, 0.5));
      c.pointerUp();
      c.setEmoji('👍');
      expect((c.state.items.single as MarkupSticker).text, '👍');
    });
  });

  group('eraser', () {
    test('removes only the marks it touches, as one step', () {
      drawLine(const Offset(0.1, 0.1), const Offset(0.5, 0.1));
      drawLine(const Offset(0.1, 0.5), const Offset(0.5, 0.5));
      drawLine(const Offset(0.1, 0.9), const Offset(0.5, 0.9));
      c.selectTool(MarkupTool.eraser);
      c.pointerDown(const Offset(0.3, 0.1));
      c.pointerMove(const Offset(0.3, 0.5));
      c.pointerUp();
      expect(c.state.items.length, 1);
      expect((c.state.items.single as MarkupStroke).points.first.dy, closeTo(0.9, 1e-9));
      c.undo();
      expect(c.state.items.length, 3, reason: 'one Undo brings both back');
    });

    test('touching empty paper changes nothing and adds no history step', () {
      drawLine(const Offset(0.1, 0.1), const Offset(0.5, 0.1));
      final steps = c.state.undoDepth;
      c.selectTool(MarkupTool.eraser);
      c.pointerDown(const Offset(0.9, 0.9));
      c.pointerUp();
      expect(c.state.items.length, 1);
      expect(c.state.undoDepth, steps);
    });
  });

  group('moving and resizing', () {
    void place() {
      c.selectTool(MarkupTool.sticker);
      c.pointerDown(const Offset(0.5, 0.5));
      c.pointerUp();
    }

    test('dragging the selected item moves it as one undo step', () {
      place();
      final steps = c.state.undoDepth;
      c.pointerDown(const Offset(0.5, 0.5));
      c.transformSelected(delta: const Offset(0.05, 0));
      c.transformSelected(delta: const Offset(0.05, 0.1));
      c.endTransform();
      expect((c.state.items.single as MarkupSticker).center.dx, closeTo(0.6, 1e-9));
      expect(c.state.undoDepth, steps + 1);
      c.undo();
      expect((c.state.items.single as MarkupSticker).center, const Offset(0.5, 0.5));
    });

    test('pinching scales and turns a sticker', () {
      place();
      c.pointerDown(const Offset(0.5, 0.5));
      c.transformSelected(scale: 2, rotation: 0.3);
      c.endTransform();
      final s = c.state.items.single as MarkupSticker;
      expect(s.size, closeTo(0.24, 1e-9));
      expect(s.rotation, closeTo(0.3, 1e-9));
    });

    test('touching empty paper deselects, touching an item selects it', () {
      drawLine(const Offset(0.2, 0.2), const Offset(0.6, 0.2));
      final id = c.state.items.single.id;
      c.selectTool(MarkupTool.select);
      c.pointerDown(const Offset(0.4, 0.2));
      expect(c.state.selectedId, id);
      c.endTransform();
      c.pointerDown(const Offset(0.4, 0.8));
      expect(c.state.selectedId, isNull);
    });

    test('colour changes restyle the selected item, one step each', () {
      drawLine(const Offset(0.2, 0.2), const Offset(0.6, 0.2));
      c.selectTool(MarkupTool.select);
      c.pointerDown(const Offset(0.4, 0.2));
      c.endTransform();
      final steps = c.state.undoDepth;
      c.setColor(0x43A047);
      c.setColor(0x8E24AA);
      expect((c.state.items.single as MarkupStroke).color, 0xFF8E24AA);
      expect(c.state.undoDepth, steps + 2);
      c.undo();
      expect((c.state.items.single as MarkupStroke).color, 0xFF43A047);
    });

    test('a slider drag restyles as a single step', () {
      drawLine(const Offset(0.2, 0.2), const Offset(0.6, 0.2));
      c.selectTool(MarkupTool.select);
      c.pointerDown(const Offset(0.4, 0.2));
      c.endTransform();
      final steps = c.state.undoDepth;
      for (final w in [0.006, 0.008, 0.012, 0.02]) {
        c.setWidth(w);
      }
      c.endStyleChange();
      expect((c.state.items.single as MarkupStroke).width, 0.02);
      expect(c.state.undoDepth, steps + 1);
    });

    test('the selected sticker can be resized directly and deleted', () {
      place();
      c.resizeSelectedSticker(0.3);
      expect((c.state.items.single as MarkupSticker).size, 0.3);
      c.deleteSelected();
      expect(c.state.items, isEmpty);
      expect(c.state.selectedId, isNull);
      c.undo();
      expect(c.state.items.length, 1);
    });
  });

  group('history', () {
    test('undo and redo walk through the marks', () {
      drawLine(const Offset(0.1, 0.1), const Offset(0.5, 0.1));
      drawLine(const Offset(0.1, 0.2), const Offset(0.5, 0.2));
      expect(c.state.items.length, 2);
      c.undo();
      expect(c.state.items.length, 1);
      expect(c.state.canRedo, isTrue);
      c.undo();
      expect(c.state.items, isEmpty);
      expect(c.state.canUndo, isFalse);
      c.redo();
      c.redo();
      expect(c.state.items.length, 2);
      expect(c.state.canRedo, isFalse);
    });

    test('drawing after an undo clears what could be redone', () {
      drawLine(const Offset(0.1, 0.1), const Offset(0.5, 0.1));
      c.undo();
      drawLine(const Offset(0.1, 0.2), const Offset(0.5, 0.2));
      expect(c.state.canRedo, isFalse);
    });

    test('clear removes everything and can be undone', () {
      drawLine(const Offset(0.1, 0.1), const Offset(0.5, 0.1));
      drawLine(const Offset(0.1, 0.2), const Offset(0.5, 0.2));
      c.clearAll();
      expect(c.state.items, isEmpty);
      c.undo();
      expect(c.state.items.length, 2);
    });

    test('ids stay unique after undo and new marks', () {
      drawLine(const Offset(0.1, 0.1), const Offset(0.5, 0.1));
      c.undo();
      drawLine(const Offset(0.1, 0.2), const Offset(0.5, 0.2));
      drawLine(const Offset(0.1, 0.3), const Offset(0.5, 0.3));
      expect(c.state.items.map((e) => e.id).toSet().length, 2);
    });

    test('the hand tool draws nothing', () {
      c.selectTool(MarkupTool.hand);
      c.pointerDown(const Offset(0.3, 0.3));
      c.pointerMove(const Offset(0.6, 0.6));
      c.pointerUp();
      expect(c.state.items, isEmpty);
    });
  });
}

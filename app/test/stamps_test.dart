import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:doculoom/features/markup/data/stamp_store.dart';
import 'package:doculoom/features/markup/domain/markup.dart';
import 'package:doculoom/features/markup/domain/stamps.dart';
import 'package:doculoom/features/markup/presentation/markup_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('stamp text', () {
    test('words are tidied to capitals, blank lines dropped', () {
      expect(stampText('  paid \n\n in full '), 'PAID\nIN FULL');
    });

    test('the date goes on the last line when asked', () {
      expect(stampText('paid', withDate: true), 'PAID\n{date}');
    });

    test('empty words, too many lines and long lines are explained', () {
      expect(stampProblem('  \n '), 'Type the words for the stamp.');
      expect(stampProblem('a\nb\nc\nd'), 'A stamp has up to 3 lines.');
      expect(stampProblem('x' * 25), 'Each line of a stamp has up to 24 characters.');
      expect(stampProblem('x' * 24), isNull);
      expect(stampProblem('a\nb\nc'), isNull);
    });

    test('three lines leave no room for the date', () {
      expect(stampProblem('a\nb\nc', withDate: true), 'With the date, a stamp has up to 2 lines of words.');
      expect(stampProblem('a\nb', withDate: true), isNull);
    });

    test('the date is filled in', () {
      expect(const Stamp('PAID\n{date}', stampGreen).resolve('05 JAN 2026'), 'PAID\n05 JAN 2026');
      expect(const Stamp('PAID', stampGreen).hasDate, isFalse);
    });

    test('a longer stamp gets smaller letters, within sensible bounds', () {
      const s = Stamp('X', stampRed);
      expect(s.fontSize('PAID'), greaterThan(s.fontSize('ANY OTHER PURPOSE ONLY')));
      expect(s.fontSize('A'), lessThanOrEqualTo(0.09));
      expect(s.fontSize('X' * 200), greaterThanOrEqualTo(0.03));
    });
  });

  group('library', () {
    test('every ready-made stamp is within the limits and in a known colour', () {
      for (final g in stampLibrary) {
        expect(g.stamps, isNotEmpty, reason: g.title);
        for (final s in g.stamps) {
          expect(stampProblem(s.text.replaceAll('{date}', 'D'), withDate: false), isNull, reason: s.text);
          expect(stampColors, contains(s.color), reason: s.text);
        }
      }
    });

    test('the group for the region comes right after the everyday stamps', () {
      expect(orderedStampGroups('india').map((g) => g.title).take(2), ['Everyday', 'For India']);
      expect(orderedStampGroups('usa').map((g) => g.title).take(2), ['Everyday', 'For the United States']);
      expect(orderedStampGroups('auto').first.title, 'Everyday');
      expect(orderedStampGroups('india').length, stampLibrary.length);
    });

    test('a stamp is saved and read back as it was', () {
      const s = Stamp('PAID\n{date}', stampGreen);
      expect(Stamp.fromJson(s.toJson()), s);
      expect(Stamp.fromJson({'text': '', 'color': 1}), isNull);
      expect(Stamp.fromJson('x'), isNull);
    });
  });

  group('my stamps', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));
    const a = Stamp('A', stampRed);
    const b = Stamp('B', stampBlue);

    test('newest first, no duplicates, and removable', () async {
      const store = StampStore();
      await store.add(a);
      await store.add(b);
      await store.add(a);
      expect(await store.load(), [a, b]);
      expect(await store.remove(a), [b]);
      await store.clear();
      expect(await store.load(), isEmpty);
    });

    test('only the newest 20 are kept', () async {
      const store = StampStore();
      for (var i = 0; i < 25; i++) {
        await store.add(Stamp('S$i', stampRed));
      }
      final all = await store.load();
      expect(all.length, maxCustomStamps);
      expect(all.first.text, 'S24');
    });

    test('damaged saved data is ignored', () async {
      SharedPreferences.setMockInitialValues({'custom_stamps': 'not json'});
      expect(await const StampStore().load(), isEmpty);
    });
  });

  group('placing a stamp', () {
    const page = Size(1000, 1400);
    late MarkupCubit c;
    setUp(() => c = MarkupCubit(page: page, now: () => DateTime(2026, 1, 5)));
    tearDown(() => c.close());

    test('the stamp tool starts with a ready stamp and places it where tapped', () {
      c.selectTool(MarkupTool.stamp);
      expect(c.state.stamp, isNotNull);
      c.pointerDown(const Offset(0.5, 0.4));
      c.pointerUp();
      final t = c.state.items.single as MarkupText;
      expect(t.framed, isTrue);
      expect(t.center, const Offset(0.5, 0.4));
      expect(c.state.selectedId, t.id);
      expect(c.state.tool, MarkupTool.select);
    });

    test('the date is the day it is placed', () {
      c.selectTool(MarkupTool.stamp);
      c.selectStamp(const Stamp('PAID\n{date}', stampGreen));
      c.pointerDown(const Offset(0.5, 0.5));
      c.pointerUp();
      final t = c.state.items.single as MarkupText;
      expect(t.text, startsWith('PAID\n5 '));
      expect(t.text, contains('2026'));
      expect(t.text, isNot(contains('{date}')));
    });

    test('placing is one undo step and the frame adds room around the words', () {
      c.selectTool(MarkupTool.stamp);
      c.pointerDown(const Offset(0.5, 0.5));
      c.pointerUp();
      final t = c.state.items.single as MarkupText;
      final plain = MarkupText(id: 99, text: t.text, center: t.center, size: t.size, color: t.color, bold: true, rotation: t.rotation);
      expect(MarkupGeometry.bounds(t, page).width, greaterThan(MarkupGeometry.bounds(plain, page).width));
      c.undo();
      expect(c.state.items, isEmpty);
    });
  });
}

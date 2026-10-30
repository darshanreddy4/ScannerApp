import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/widgets.dart' as pw;
import 'package:doculoom/features/pdf_compare/data/compare_pdf_reader.dart';
import 'package:doculoom/features/pdf_compare/domain/page_diff.dart';
import 'package:doculoom/features/pdf_compare/domain/sequence_diff.dart';
import 'package:doculoom/features/pdf_compare/domain/text_compare.dart';

List<int> ints(String s) => s.isEmpty ? [] : s.split('').map((c) => c.codeUnitAt(0)).toList();

/// Applies [ops] to [a] and checks the result is [b], and that the ops walk both sequences from start to end.
String replay(String a, String b, List<DiffOp> ops) {
  final out = StringBuffer();
  var ai = 0, bi = 0;
  for (final op in ops) {
    switch (op.kind) {
      case DiffKind.equal:
        expect(op.aIndex, ai);
        expect(op.bIndex, bi);
        out.write(a[ai]);
        ai++;
        bi++;
      case DiffKind.delete:
        expect(op.aIndex, ai);
        ai++;
      case DiffKind.insert:
        expect(op.bIndex, bi);
        out.write(b[bi]);
        bi++;
    }
  }
  expect(ai, a.length);
  expect(bi, b.length);
  return out.toString();
}

int edits(List<DiffOp> ops) => ops.where((o) => o.kind != DiffKind.equal).length;

PageWords page(String text, {double top = 0.1}) {
  final words = <PageWord>[];
  var x = 0.05;
  for (final w in text.split(' ')) {
    words.add(PageWord(w, TextRect(x, top, x + w.length * 0.01, top + 0.02)));
    x += w.length * 0.01 + 0.01;
  }
  return PageWords(words: words);
}

void main() {
  group('the shortest edit script', () {
    final cases = [
      ('', ''),
      ('abc', 'abc'),
      ('', 'abc'),
      ('abc', ''),
      ('abc', 'abd'),
      ('abcabba', 'cbabac'),
      ('kitten', 'sitting'),
      ('the quick brown fox', 'the slow brown dog'),
      ('aaaa', 'aa'),
      ('abcdefgh', 'efghabcd'),
    ];
    for (final (a, b) in cases) {
      test('"$a" to "$b" replays to the target', () {
        final ops = diffSequences(ints(a), ints(b));
        expect(replay(a, b, ops), b);
      });
    }

    test('the number of edits is the smallest', () {
      expect(edits(diffSequences(ints('abcabba'), ints('cbabac'))), 5);
      expect(edits(diffSequences(ints('kitten'), ints('sitting'))), 5);
      expect(edits(diffSequences(ints('abc'), ints('abc'))), 0);
    });

    test('random pairs always replay correctly', () {
      final rnd = math.Random(7);
      for (var i = 0; i < 300; i++) {
        String make() => String.fromCharCodes(List.generate(rnd.nextInt(14), (_) => 97 + rnd.nextInt(4)));
        final a = make(), b = make();
        expect(replay(a, b, diffSequences(ints(a), ints(b))), b, reason: '$a -> $b');
      }
    });

    test('texts that have almost nothing in common give up instead of taking forever', () {
      final a = List.generate(4000, (i) => i), b = List.generate(4000, (i) => i + 100000);
      expect(() => diffSequences(a, b), throwsA(isA<TooDifferent>()));
    });

    test('long texts with a few changes are quick', () {
      final a = List.generate(30000, (i) => i % 977);
      final b = [...a]
        ..[100] = -1
        ..removeAt(15000)
        ..insert(20000, -2);
      final sw = Stopwatch()..start();
      final ops = diffSequences(a, b);
      expect(edits(ops), 4);
      expect(sw.elapsedMilliseconds, lessThan(2000));
    });
  });

  group('comparing the text of two PDFs', () {
    test('the same text has no changes', () {
      final c = compareText([page('The quick brown fox.')], [page('The quick brown fox.')]);
      expect(c.identical, isTrue);
      expect(c.changes, isEmpty);
    });

    test('a changed word shows as removed and added, with the words around it', () {
      final c = compareText([page('Pay the invoice within thirty days of receipt please')], [page('Pay the invoice within fourteen days of receipt please')]);
      expect(c.changes.length, 1);
      final ch = c.changes.single;
      expect(ch.kind, ChangeKind.changed);
      expect(ch.plain, 'Pay the invoice within [-thirty-] {+fourteen+} days of receipt please');
      expect((c.removedWords, c.addedWords), (1, 1));
      expect(ch.originalPage, 0);
      expect(ch.revisedPage, 0);
    });

    test('an added and a removed sentence', () {
      final a = page('One two three four five six seven eight nine ten eleven twelve thirteen fourteen');
      final addedOnly = compareText([a], [page('One two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen')]);
      expect(addedOnly.changes.single.kind, ChangeKind.added);
      expect(addedOnly.changes.single.addedWords, 2);
      final removedOnly = compareText([a], [page('One two three four five six seven eight nine ten eleven twelve')]);
      expect(removedOnly.changes.single.kind, ChangeKind.removed);
      expect(removedOnly.changes.single.removedWords, 2);
    });

    test('changes close together are one, far apart are two', () {
      final base = 'a1 a2 a3 a4 a5 a6 a7 a8 a9 b1 b2 b3 b4 b5 b6 b7 b8 b9';
      final near = compareText([page(base)], [page(base.replaceFirst('a5', 'X5').replaceFirst('a7', 'X7'))]);
      expect(near.changes.length, 1);
      final far = compareText([page(base)], [page(base.replaceFirst('a2', 'X2').replaceFirst('b8', 'X8'))]);
      expect(far.changes.length, 2);
      expect(far.changes.first.cutBefore, isFalse);
      expect(far.changes.first.cutAfter, isTrue);
      expect(far.changes.last.cutBefore, isTrue);
      expect(far.changes.last.cutAfter, isFalse);
    });

    test('a paragraph moved to the next page is not a change, and an inserted page does not shift the rest', () {
      final a = [page('alpha beta gamma delta'), page('epsilon zeta eta theta'), page('iota kappa lambda mu')];
      final b = [page('alpha beta gamma delta epsilon'), page('zeta eta theta'), page('iota kappa lambda mu')];
      expect(compareText(a, b).identical, isTrue);
      final inserted = [a[0], page('A completely new page'), a[1], a[2]];
      final c = compareText(a, inserted);
      expect(c.changes.length, 1);
      expect(c.changes.single.kind, ChangeKind.added);
      expect(c.changes.single.revisedPage, 1);
      expect(c.removedWords, 0);
    });

    test('the place of the changed words is kept, one box for a line', () {
      final c = compareText([page('Total due thirty five dollars today')], [page('Total due forty two dollars today')]);
      final ch = c.changes.single;
      expect(ch.originalBoxes.length, 1);
      expect(ch.revisedBoxes.length, 1);
      expect(ch.originalBoxes.single.page, 0);
      expect(ch.originalBoxes.single.rect.top, 0.1);
      expect(ch.revisedBoxes.single.rect.left, lessThan(ch.revisedBoxes.single.rect.right));
    });

    test('words are split from the text with the box of their letters', () {
      final rects = List<TextRect?>.generate(11, (i) => i == 5 ? null : TextRect(i * 0.1, 0, i * 0.1 + 0.1, 0.1));
      final words = wordsOfText('Hello world', rects);
      expect(words.map((w) => w.text), ['Hello', 'world']);
      expect(words.first.box!.left, 0);
      expect(words.first.box!.right, closeTo(0.5, 1e-9));
      expect(words.last.box!.left, closeTo(0.6, 1e-9));
      expect(wordsOfText('  \n ', const []), isEmpty);
    });

    test('a text that shares almost nothing is reported as too different', () {
      final a = [
        PageWords(words: [for (var i = 0; i < 4000; i++) PageWord('a$i', null)]),
      ];
      final b = [
        PageWords(words: [for (var i = 0; i < 4000; i++) PageWord('b$i', null)]),
      ];
      final c = compareText(a, b);
      expect(c.tooDifferent, isTrue);
      expect(c.identical, isFalse);
    });

    test('nothing to compare on either side', () {
      expect(compareText(const [], const []).identical, isTrue);
      final onlyB = compareText(const [], [page('new words here')]);
      expect(onlyB.changes.single.kind, ChangeKind.added);
    });
  });

  group('comparing how two pages look', () {
    Uint8List pageImage({List<(int, int, int, int)> ink = const [], int w = 600, int h = 800}) {
      final image = img.Image(width: w, height: h);
      img.fill(image, color: img.ColorRgb8(255, 255, 255));
      for (final (x, y, rw, rh) in ink) {
        img.fillRect(image, x1: x, y1: y, x2: x + rw, y2: y + rh, color: img.ColorRgb8(0, 0, 0));
      }
      return Uint8List.fromList(img.encodePng(image));
    }

    const lines = [(60, 100, 400, 12), (60, 130, 380, 12), (60, 160, 420, 12), (60, 190, 300, 12)];

    test('the same page is the same', () {
      final d = diffPageImages(pageImage(ink: lines), pageImage(ink: lines));
      expect(d.same, isTrue);
      expect(d.similarity, 1.0);
    });

    test('a new line of text is found where it is', () {
      final d = diffPageImages(pageImage(ink: lines), pageImage(ink: [...lines, (60, 500, 350, 12)]));
      expect(d.regions.length, 1);
      final r = d.regions.single;
      expect(r.top, closeTo(500 / 800, 0.03));
      expect(r.bottom, closeTo(512 / 800, 0.03));
      expect(r.left, closeTo(60 / 600, 0.03));
      expect(r.right, closeTo(410 / 600, 0.03));
      expect(d.similarity, lessThan(1));
    });

    test('two separate changes are two boxes', () {
      final d = diffPageImages(pageImage(ink: lines), pageImage(ink: [...lines, (60, 400, 200, 12), (60, 700, 200, 12)]));
      expect(d.regions.length, 2);
    });

    test('a removed line is found too', () {
      final d = diffPageImages(pageImage(ink: lines), pageImage(ink: lines.take(3).toList()));
      expect(d.regions.length, 1);
      expect(d.regions.single.top, closeTo(190 / 800, 0.03));
    });

    test('pages of another shape are noted', () {
      final d = diffPageImages(pageImage(ink: lines), pageImage(ink: lines, w: 800, h: 600));
      expect(d.sizeChanged, isTrue);
      expect(d.same, isFalse);
    });

    test('a picture that cannot be opened counts as no difference', () {
      expect(diffPageImages(Uint8List.fromList([1, 2, 3]), pageImage()).same, isTrue);
    });
  });

  group('reading a real PDF', () {
    Future<Uint8List> make(List<String> pages) async {
      final doc = pw.Document();
      for (final t in pages) {
        doc.addPage(pw.Page(build: (_) => pw.Text(t, style: const pw.TextStyle(fontSize: 14))));
      }
      return doc.save();
    }

    test('the words of every page come out in order, with a box each', () async {
      final words = readPdfWords(await make(['Pay within thirty days', 'Second page here']));
      expect(words.length, 2);
      expect(words[0].words.map((w) => w.text), ['Pay', 'within', 'thirty', 'days']);
      expect(words[1].words.map((w) => w.text), ['Second', 'page', 'here']);
      expect(words[0].words.every((w) => w.box != null), isTrue);
      expect(words[0].words.first.box!.left, lessThan(words[0].words.last.box!.left));
    });

    test('two versions of a PDF give the changed word and its place', () async {
      final a = readPdfWords(await make(['Pay within thirty days of receipt']));
      final b = readPdfWords(await make(['Pay within fourteen days of receipt']));
      final c = compareText(a, b);
      expect(c.changes.single.plain, 'Pay within [-thirty-] {+fourteen+} days of receipt');
      expect(c.changes.single.originalBoxes.single.rect.top, closeTo(c.changes.single.revisedBoxes.single.rect.top, 0.01));
      expect(compareText(a, a).identical, isTrue);
    });

    test('a page that is only a picture has no words', () async {
      final doc = pw.Document();
      doc.addPage(pw.Page(build: (_) => pw.SizedBox()));
      expect(readPdfWords(await doc.save()).single.isEmpty, isTrue);
    });
  });
}

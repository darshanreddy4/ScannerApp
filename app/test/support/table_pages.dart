import 'dart:math' as math;

import 'package:doculoom/features/ocr/domain/ocr_models.dart';

/// Builds the words a text reader would find on a page that holds a table, for the table tests.
const _rowHeight = 30.0;

/// A page of 1000 x 1400 with the given cells: each cell is (text, left, row index, jitter). Words are 14 px a letter wide with 10 px between.
OcrPageResult page(
  List<(String, double, int)> cells, {
  double tilt = 0,
  double wordGap = 10,
  double jitter = 0,
  bool oneLinePerRow = false,
  bool withWords = true,
}) {
  final lines = <OcrLine>[];
  final byRow = <int, List<OcrLine>>{};
  var n = 0;
  for (final (text, left, row) in cells) {
    var x = left;
    final y = 100 + row * 60.0 + (n++ % 2 == 0 ? jitter : -jitter);
    final words = <OcrWord>[];
    for (final w in text.split(' ')) {
      final width = w.length * 14.0;
      words.add(OcrWord(text: w, left: x, top: y, right: x + width, bottom: y + _rowHeight));
      x += width + wordGap;
    }
    final line = OcrLine(text: text, left: left, top: y, right: x - wordGap, bottom: y + _rowHeight, words: withWords ? words : const [], angle: tilt);
    byRow.putIfAbsent(row, () => []).add(line);
    lines.add(line);
  }
  var out = lines;
  if (tilt != 0) {
    // Turn every position about the centre of the page, the way a tilted photo shows them.
    OcrWord turn(OcrWord w) {
      final cx = (w.left + w.right) / 2 - 500, cy = (w.top + w.bottom) / 2 - 700;
      final nx = cx * math.cos(-tilt) + cy * math.sin(-tilt) + 500, ny = -cx * math.sin(-tilt) + cy * math.cos(-tilt) + 700;
      final hw = (w.right - w.left) / 2;
      return OcrWord(text: w.text, left: nx - hw, top: ny - _rowHeight / 2, right: nx + hw, bottom: ny + _rowHeight / 2);
    }

    out = [
      for (final l in lines)
        OcrLine(text: l.text, left: l.left, top: l.top, right: l.right, bottom: l.bottom, words: [for (final w in l.words) turn(w)], angle: tilt),
    ];
  }
  if (oneLinePerRow) {
    final merged = <OcrLine>[];
    for (final row in byRow.keys.toList()..sort()) {
      final members = [
        for (final l in out)
          if (byRow[row]!.any((b) => b.text == l.text && b.left == l.left)) l,
      ];
      merged.add(
        OcrLine(
          text: members.map((l) => l.text).join('   '),
          left: members.first.left,
          top: members.first.top,
          right: members.last.right,
          bottom: members.first.bottom,
          words: [for (final l in members) ...l.words],
        ),
      );
    }
    out = merged;
  }
  return OcrPageResult(width: 1000, height: 1400, blocks: [OcrBlock(lines: out)]);
}

List<(String, double, int)> grid(List<List<String>> rows, List<double> columnLeft) => [
  for (var r = 0; r < rows.length; r++)
    for (var c = 0; c < rows[r].length; c++)
      if (rows[r][c].isNotEmpty) (rows[r][c], columnLeft[c], r),
];

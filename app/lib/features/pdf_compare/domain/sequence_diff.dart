enum DiffKind { equal, delete, insert }

/// One step of the way from sequence a to sequence b: keep an item, remove an item of a, or add an item of b.
class DiffOp {
  const DiffOp(this.kind, {this.aIndex = -1, this.bIndex = -1});
  final DiffKind kind;

  /// The item of a that is kept or removed; -1 for an addition.
  final int aIndex;

  /// The item of b that is kept or added; -1 for a removal.
  final int bIndex;
}

/// Thrown by [diffSequences] when the two sequences differ in more than [maxEdits] places.
class TooDifferent implements Exception {
  const TooDifferent();
}

/// The shortest list of removals and additions that turns [a] into [b] (Myers' algorithm), with the unchanged items in between.
/// Items are compared by value. Throws [TooDifferent] when more than [maxEdits] changes would be needed.
List<DiffOp> diffSequences(List<int> a, List<int> b, {int maxEdits = 1500}) {
  var start = 0;
  while (start < a.length && start < b.length && a[start] == b[start]) {
    start++;
  }
  var endA = a.length, endB = b.length;
  while (endA > start && endB > start && a[endA - 1] == b[endB - 1]) {
    endA--;
    endB--;
  }
  final ops = <DiffOp>[for (var i = 0; i < start; i++) DiffOp(DiffKind.equal, aIndex: i, bIndex: i)];
  final n = endA - start, m = endB - start;
  if (n == 0) {
    for (var j = 0; j < m; j++) {
      ops.add(DiffOp(DiffKind.insert, bIndex: start + j));
    }
  } else if (m == 0) {
    for (var i = 0; i < n; i++) {
      ops.add(DiffOp(DiffKind.delete, aIndex: start + i));
    }
  } else {
    ops.addAll(_myers(a, b, start, n, m, maxEdits));
  }
  for (var i = 0; i < a.length - endA; i++) {
    ops.add(DiffOp(DiffKind.equal, aIndex: endA + i, bIndex: endB + i));
  }
  return ops;
}

List<DiffOp> _myers(List<int> a, List<int> b, int start, int n, int m, int maxEdits) {
  final limit = n + m < maxEdits ? n + m : maxEdits;
  final offset = limit + 1;
  final v = List<int>.filled(2 * limit + 3, 0);
  // The furthest points reached by each number of edits, only the part that was in use, to walk back from the end.
  final trace = <({List<int> values, int base})>[];
  var found = -1;
  for (var d = 0; d <= limit && found < 0; d++) {
    final base = offset - d - 1;
    trace.add((values: v.sublist(base, offset + d + 2), base: base));
    for (var k = -d; k <= d; k += 2) {
      int x;
      if (k == -d || (k != d && v[k - 1 + offset] < v[k + 1 + offset])) {
        x = v[k + 1 + offset];
      } else {
        x = v[k - 1 + offset] + 1;
      }
      var y = x - k;
      while (x < n && y < m && a[start + x] == b[start + y]) {
        x++;
        y++;
      }
      v[k + offset] = x;
      if (x >= n && y >= m) {
        found = d;
        break;
      }
    }
  }
  if (found < 0) throw const TooDifferent();

  final back = <DiffOp>[];
  var x = n, y = m;
  for (var d = found; d > 0; d--) {
    final t = trace[d];
    int at(int k) => t.values[k + offset - t.base];
    final k = x - y;
    final prevK = (k == -d || (k != d && at(k - 1) < at(k + 1))) ? k + 1 : k - 1;
    final prevX = at(prevK);
    final prevY = prevX - prevK;
    while (x > prevX && y > prevY) {
      back.add(DiffOp(DiffKind.equal, aIndex: start + x - 1, bIndex: start + y - 1));
      x--;
      y--;
    }
    if (x == prevX) {
      back.add(DiffOp(DiffKind.insert, bIndex: start + y - 1));
      y--;
    } else {
      back.add(DiffOp(DiffKind.delete, aIndex: start + x - 1));
      x--;
    }
  }
  while (x > 0 && y > 0) {
    back.add(DiffOp(DiffKind.equal, aIndex: start + x - 1, bIndex: start + y - 1));
    x--;
    y--;
  }
  return back.reversed.toList();
}

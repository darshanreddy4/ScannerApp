import 'dart:math' as math;

class SheetSlot {
  const SheetSlot(this.xMm, this.yMm);
  final double xMm;
  final double yMm;
}

/// Where copies of a photo go on a sheet of paper, in millimetres. The paper may be turned to fit more.
class SheetLayout {
  const SheetLayout({
    required this.paperWidthMm,
    required this.paperHeightMm,
    required this.photoWidthMm,
    required this.photoHeightMm,
    required this.columns,
    required this.rows,
    required this.slots,
    required this.turned,
  });

  final double paperWidthMm;
  final double paperHeightMm;
  final double photoWidthMm;
  final double photoHeightMm;
  final int columns;
  final int rows;
  final List<SheetSlot> slots;

  /// True when the paper is used sideways to fit more copies.
  final bool turned;

  int get capacity => columns * rows;

  /// Fits as many copies as possible, centred, trying the paper both ways. [copies] limits how many are placed.
  static SheetLayout fit({
    required double paperWidthMm,
    required double paperHeightMm,
    required double photoWidthMm,
    required double photoHeightMm,
    double marginMm = 5,
    double gapMm = 2,
    int? copies,
  }) {
    final upright = _grid(paperWidthMm, paperHeightMm, photoWidthMm, photoHeightMm, marginMm, gapMm);
    final sideways = _grid(paperHeightMm, paperWidthMm, photoWidthMm, photoHeightMm, marginMm, gapMm);
    final turned = sideways.$1 * sideways.$2 > upright.$1 * upright.$2;
    final pw = turned ? paperHeightMm : paperWidthMm;
    final ph = turned ? paperWidthMm : paperHeightMm;
    final cols = turned ? sideways.$1 : upright.$1;
    final rows = turned ? sideways.$2 : upright.$2;

    final shown = copies == null ? cols * rows : math.min(copies, cols * rows);
    // Keep the used block centred even when fewer copies than the grid holds are printed.
    final usedRows = shown == 0 ? 0 : (shown / math.max(cols, 1)).ceil();
    final usedCols = shown == 0 ? 0 : math.min(cols, shown);
    final blockW = usedCols * photoWidthMm + math.max(0, usedCols - 1) * gapMm;
    final blockH = usedRows * photoHeightMm + math.max(0, usedRows - 1) * gapMm;
    final x0 = (pw - blockW) / 2;
    final y0 = (ph - blockH) / 2;

    final slots = <SheetSlot>[];
    for (var i = 0; i < shown; i++) {
      final c = i % math.max(cols, 1), r = i ~/ math.max(cols, 1);
      slots.add(SheetSlot(x0 + c * (photoWidthMm + gapMm), y0 + r * (photoHeightMm + gapMm)));
    }
    return SheetLayout(
      paperWidthMm: pw,
      paperHeightMm: ph,
      photoWidthMm: photoWidthMm,
      photoHeightMm: photoHeightMm,
      columns: cols,
      rows: rows,
      slots: slots,
      turned: turned,
    );
  }

  static (int, int) _grid(double pw, double ph, double w, double h, double margin, double gap) {
    final usableW = pw - 2 * margin, usableH = ph - 2 * margin;
    final cols = usableW < w ? 0 : ((usableW + gap) / (w + gap)).floor();
    final rows = usableH < h ? 0 : ((usableH + gap) / (h + gap)).floor();
    return (cols, rows);
  }
}

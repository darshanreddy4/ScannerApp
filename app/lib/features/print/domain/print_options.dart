import 'package:equatable/equatable.dart';

enum PaperSize {
  a4('A4', 210, 297),
  a3('A3', 297, 420),
  a5('A5', 148, 210),
  letter('Letter', 215.9, 279.4),
  legal('Legal', 215.9, 355.6),
  photo('Photo 4 x 6 in', 101.6, 152.4);

  const PaperSize(this.label, this.widthMm, this.heightMm);
  final String label;
  final double widthMm;
  final double heightMm;
}

enum PrintOrientation {
  auto('Auto'),
  portrait('Portrait'),
  landscape('Landscape');

  const PrintOrientation(this.label);
  final String label;
}

enum PrintMargin {
  none('None', 0),
  small('Small', 8),
  normal('Normal', 15);

  const PrintMargin(this.label, this.mm);
  final String label;
  final double mm;
}

/// Ready-made settings for common jobs.
enum PrintPreset {
  document('Document'),
  photo('Photo'),
  eco('Eco draft');

  const PrintPreset(this.label);
  final String label;
}

class PrintOptions extends Equatable {
  const PrintOptions({
    this.paper = PaperSize.a4,
    this.orientation = PrintOrientation.auto,
    this.color = true,
    this.copies = 1,
    this.pagesPerSheet = 1,
    this.fill = false,
    this.margin = PrintMargin.normal,
    this.pageRange = '',
  });

  final PaperSize paper;
  final PrintOrientation orientation;

  /// False prints in black and white (greyscale), which saves colour ink or toner.
  final bool color;
  final int copies;

  /// 1, 2 or 4 document pages on each sheet.
  final int pagesPerSheet;

  /// Fill the page (may crop the edges) instead of fitting the whole page inside.
  final bool fill;
  final PrintMargin margin;

  /// Empty means all pages. Otherwise something like `1-3, 5`.
  final String pageRange;

  static PrintOptions preset(PrintPreset p) => switch (p) {
    PrintPreset.document => const PrintOptions(),
    PrintPreset.photo => const PrintOptions(paper: PaperSize.photo, fill: true, margin: PrintMargin.none),
    PrintPreset.eco => const PrintOptions(color: false, pagesPerSheet: 2, margin: PrintMargin.small),
  };

  PrintOptions copyWith({
    PaperSize? paper,
    PrintOrientation? orientation,
    bool? color,
    int? copies,
    int? pagesPerSheet,
    bool? fill,
    PrintMargin? margin,
    String? pageRange,
  }) => PrintOptions(
    paper: paper ?? this.paper,
    orientation: orientation ?? this.orientation,
    color: color ?? this.color,
    copies: copies ?? this.copies,
    pagesPerSheet: pagesPerSheet ?? this.pagesPerSheet,
    fill: fill ?? this.fill,
    margin: margin ?? this.margin,
    pageRange: pageRange ?? this.pageRange,
  );

  @override
  List<Object?> get props => [paper, orientation, color, copies, pagesPerSheet, fill, margin, pageRange];
}

abstract final class PageRange {
  /// Parses `1-3, 5, 8-` style input into zero-based page indexes in the order written (no duplicates).
  /// Returns null when the text is invalid or refers to pages that do not exist. Empty text means all pages.
  static List<int>? parse(String text, int total) {
    final input = text.trim();
    if (input.isEmpty) return [for (var i = 0; i < total; i++) i];

    final out = <int>[];
    for (final raw in input.split(',')) {
      final part = raw.trim();
      if (part.isEmpty) return null;
      final m = RegExp(r'^(\d+)(?:\s*-\s*(\d*))?$').firstMatch(part);
      if (m == null) return null;
      final from = int.parse(m[1]!);
      final dash = part.contains('-');
      final to = dash ? (m[2]!.isEmpty ? total : int.parse(m[2]!)) : from;
      if (from < 1 || to < from || to > total) return null;
      for (var n = from; n <= to; n++) {
        if (!out.contains(n - 1)) out.add(n - 1);
      }
    }
    return out;
  }
}

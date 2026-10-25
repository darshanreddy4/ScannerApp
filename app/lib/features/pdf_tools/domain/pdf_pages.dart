import '../../../core/error/result.dart';

/// Reads page ranges typed by people, such as "1-3, 5, 8-".
class RangeParse {
  const RangeParse({this.groups = const [], this.error});

  /// One list of zero-based page numbers per comma separated part, in the order typed.
  final List<List<int>> groups;
  final String? error;

  bool get ok => error == null && groups.isNotEmpty;

  /// All pages of all parts, in the order typed, without repeats.
  List<int> get pages {
    final seen = <int>{};
    return [
      for (final g in groups)
        for (final p in g)
          if (seen.add(p)) p,
    ];
  }
}

abstract final class PageRanges {
  static RangeParse parse(String text, int pageCount) {
    final cleaned = text.trim();
    if (cleaned.isEmpty) return const RangeParse(error: 'Type the pages, for example 1-3, 5.');
    final groups = <List<int>>[];
    for (final raw in cleaned.split(RegExp(r'[,;]'))) {
      final part = raw.replaceAll(RegExp(r'\s+'), '');
      if (part.isEmpty) continue;
      final match = RegExp(r'^(\d+)(?:(-|–)(\d*))?$').firstMatch(part);
      if (match == null) return RangeParse(error: '"${raw.trim()}" is not a page or a range. Use numbers such as 2 or 4-7.');
      final from = int.parse(match.group(1)!);
      final hasDash = match.group(2) != null;
      final toText = match.group(3) ?? '';
      final to = !hasDash ? from : (toText.isEmpty ? pageCount : int.parse(toText));
      if (from < 1 || to < 1) return const RangeParse(error: 'Pages start at 1.');
      if (from > pageCount) return RangeParse(error: 'Page $from does not exist. This PDF has $pageCount ${pageCount == 1 ? 'page' : 'pages'}.');
      if (to > pageCount) return RangeParse(error: 'Page $to does not exist. This PDF has $pageCount ${pageCount == 1 ? 'page' : 'pages'}.');
      if (to < from) return RangeParse(error: '$from-$to goes backwards. Write the smaller page first.');
      groups.add([for (var i = from; i <= to; i++) i - 1]);
    }
    if (groups.isEmpty) return const RangeParse(error: 'Type the pages, for example 1-3, 5.');
    return RangeParse(groups: groups);
  }

  /// Short text for file names and summaries, such as "1-3_5_8-10".
  static String label(List<int> pages, {String separator = '_'}) {
    if (pages.isEmpty) return '';
    final parts = <String>[];
    var start = pages.first, prev = pages.first;
    void flush() => parts.add(start == prev ? '${start + 1}' : '${start + 1}-${prev + 1}');
    for (final p in pages.skip(1)) {
      if (p == prev + 1) {
        prev = p;
        continue;
      }
      flush();
      start = prev = p;
    }
    flush();
    return parts.join(separator);
  }

  static List<List<int>> splitEach(int pageCount) => [
    for (var i = 0; i < pageCount; i++) [i],
  ];

  static List<List<int>> splitEvery(int size, int pageCount) {
    final n = size < 1 ? 1 : size;
    return [
      for (var start = 0; start < pageCount; start += n) [for (var i = start; i < start + n && i < pageCount; i++) i],
    ];
  }
}

enum PageNumberStyle {
  none('No numbers'),
  plain('1, 2, 3'),
  pageOf('Page 1 of 5'),
  slash('1 / 5');

  const PageNumberStyle(this.label);
  final String label;

  String text(int number, int total) => switch (this) {
    PageNumberStyle.none => '',
    PageNumberStyle.plain => '$number',
    PageNumberStyle.pageOf => 'Page $number of $total',
    PageNumberStyle.slash => '$number / $total',
  };
}

enum NumberPosition {
  bottomRight('Bottom right'),
  bottomCenter('Bottom centre'),
  bottomLeft('Bottom left');

  const NumberPosition(this.label);
  final String label;
}

/// Numbers, a header and a footer printed on the pages of the result.
class PageMarks {
  const PageMarks({
    this.numbers = PageNumberStyle.none,
    this.position = NumberPosition.bottomRight,
    this.header = '',
    this.footer = '',
    this.skipFirst = false,
  });

  final PageNumberStyle numbers;
  final NumberPosition position;
  final String header;
  final String footer;

  /// Leave the first page clean, for a cover page.
  final bool skipFirst;

  bool get isEmpty => numbers == PageNumberStyle.none && header.trim().isEmpty && footer.trim().isEmpty;

  PageMarks copyWith({PageNumberStyle? numbers, NumberPosition? position, String? header, String? footer, bool? skipFirst}) => PageMarks(
    numbers: numbers ?? this.numbers,
    position: position ?? this.position,
    header: header ?? this.header,
    footer: footer ?? this.footer,
    skipFirst: skipFirst ?? this.skipFirst,
  );

  @override
  bool operator ==(Object other) =>
      other is PageMarks &&
      other.numbers == numbers &&
      other.position == position &&
      other.header == header &&
      other.footer == footer &&
      other.skipFirst == skipFirst;

  @override
  int get hashCode => Object.hash(numbers, position, header, footer, skipFirst);
}

/// A PDF that was opened for editing: one picture per page.
class OpenedPdf {
  const OpenedPdf({required this.name, required this.pages});
  final String name;
  final List<String> pages;
}

/// One file to create: which pages go in, in this order.
class PartRequest {
  const PartRequest({required this.fileName, required this.pages});
  final String fileName;
  final List<int> pages;
}

class PdfPart {
  const PdfPart({required this.path, required this.name, required this.pages, required this.bytes});
  final String path;
  final String name;
  final int pages;
  final int bytes;
}

abstract interface class PdfPageService {
  /// Reads the PDF into page pictures.
  Future<Result<OpenedPdf>> open(String path);

  /// Creates one PDF per request. [rotations] holds quarter turns clockwise (0 to 3) by page index.
  Future<Result<List<PdfPart>>> build({
    required OpenedPdf source,
    required List<PartRequest> parts,
    required Map<int, int> rotations,
    required PageMarks marks,
    required String outputDir,
    void Function(int done, int total)? onProgress,
  });
}

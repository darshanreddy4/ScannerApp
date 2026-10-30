import 'package:equatable/equatable.dart';

/// Writing systems the on-device engine can read. Arabic is not offered: Google's on-device models do not support it.
enum OcrScript {
  latin('Latin', 'English, Spanish, French, German, Italian, Portuguese and other Latin-script languages'),
  devanagari('Devanagari', 'Hindi, Marathi, Nepali, Sanskrit');

  const OcrScript(this.label, this.languages);
  final String label;
  final String languages;
}

/// One word of a line with its box in image pixels.
class OcrWord extends Equatable {
  const OcrWord({required this.text, required this.left, required this.top, required this.right, required this.bottom});
  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;

  @override
  List<Object?> get props => [text, left, top, right, bottom];
}

/// One line of recognised text with its box in image pixels.
class OcrLine extends Equatable {
  const OcrLine({required this.text, required this.left, required this.top, required this.right, required this.bottom, this.words = const [], this.angle = 0});
  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;

  /// The words of the line, when the engine tells them apart; empty otherwise.
  final List<OcrWord> words;

  /// How much the line is turned, in radians clockwise (0 for a level line).
  final double angle;

  double get width => right - left;
  double get height => bottom - top;

  @override
  List<Object?> get props => [text, left, top, right, bottom, words, angle];
}

/// A group of lines the engine considers one paragraph or region.
class OcrBlock extends Equatable {
  const OcrBlock({required this.lines});
  final List<OcrLine> lines;

  @override
  List<Object?> get props => [lines];
}

class OcrPageResult extends Equatable {
  const OcrPageResult({required this.width, required this.height, required this.blocks});
  final double width;
  final double height;
  final List<OcrBlock> blocks;

  String get plainText => blocks.map((b) => b.lines.map((l) => l.text).join('\n')).join('\n\n');

  @override
  List<Object?> get props => [width, height, blocks];
}

/// Recognised text for one page of a saved document, ready to show and search.
class PageText extends Equatable {
  const PageText({required this.position, required this.script, required this.markdown, required this.plain, this.edited = false});

  /// Zero-based page number.
  final int position;
  final OcrScript script;

  /// Structure and formulas as Markdown, with formulas written as `$...$` and `$$...$$`.
  final String markdown;

  /// The engine's text without formatting, used for search.
  final String plain;

  /// True once the person corrected the text by hand.
  final bool edited;

  PageText copyWith({String? markdown, bool? edited}) =>
      PageText(position: position, script: script, markdown: markdown ?? this.markdown, plain: plain, edited: edited ?? this.edited);

  @override
  List<Object?> get props => [position, script, markdown, plain, edited];
}

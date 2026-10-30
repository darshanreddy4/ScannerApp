import 'translation_service.dart';

/// A passage to translate and what follows it in the text: a space, a line break or a blank line.
class TranslationPart {
  const TranslationPart(this.text, this.after);
  final String text;
  final String after;
}

class TranslationCancelled implements Exception {
  const TranslationCancelled();
}

final _endsSentence = RegExp(r'[.!?:;\u0964\u2026]["\u201D\u2019)\]]*$');
final _sentenceBreak = RegExp(r'(?<=[.!?\u0964\u2026])\s+(?=\S)');
final _hasLetters = RegExp(r'\p{L}', unicode: true);

/// Cuts text into passages the translator can take: lines cut by the width of a page are joined into one sentence,
/// each passage has at most [maxLength] characters and ends at a sentence where it can. Paragraphs and headings stay apart.
List<TranslationPart> splitForTranslation(String text, {int maxLength = 900}) {
  final cleaned = text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll('\u00AD', '')
      .replaceAll(RegExp(r'[ \t\u00A0]+'), ' ')
      .replaceAllMapped(RegExp(r'(\p{L})-\n\s*(\p{Ll})', unicode: true), (m) => '${m[1]}${m[2]}');

  final paragraphs = [
    for (final p in cleaned.split(RegExp(r'\n\s*\n')))
      if (p.trim().isNotEmpty) p,
  ];
  final out = <TranslationPart>[];
  for (var pi = 0; pi < paragraphs.length; pi++) {
    final units = <String>[];
    var buffer = '';
    for (final raw in paragraphs[pi].split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (buffer.isEmpty) {
        buffer = line;
      } else if (!_endsSentence.hasMatch(buffer) && RegExp(r'^\p{Ll}', unicode: true).hasMatch(line)) {
        buffer = '$buffer $line';
      } else {
        units.add(buffer);
        buffer = line;
      }
    }
    if (buffer.isNotEmpty) units.add(buffer);

    for (var ui = 0; ui < units.length; ui++) {
      final pieces = _pack(units[ui], maxLength);
      final lastUnit = ui == units.length - 1;
      final lastParagraph = pi == paragraphs.length - 1;
      for (var k = 0; k < pieces.length; k++) {
        final lastPiece = k == pieces.length - 1;
        final after = !lastPiece ? ' ' : (!lastUnit ? '\n' : (lastParagraph ? '' : '\n\n'));
        out.add(TranslationPart(pieces[k], after));
      }
    }
  }
  return out;
}

List<String> _pack(String unit, int max) {
  final pieces = <String>[];
  var current = '';
  for (final sentence in unit.split(_sentenceBreak)) {
    for (final part in _fit(sentence.trim(), max)) {
      if (current.isEmpty) {
        current = part;
      } else if (current.length + 1 + part.length <= max) {
        current = '$current $part';
      } else {
        pieces.add(current);
        current = part;
      }
    }
  }
  if (current.isNotEmpty) pieces.add(current);
  return pieces;
}

List<String> _fit(String s, int max) {
  if (s.isEmpty) return const [];
  if (s.length <= max) return [s];
  final out = <String>[];
  var rest = s;
  while (rest.length > max) {
    var cut = rest.lastIndexOf(RegExp(r'[,;:]\s'), max - 1);
    if (cut < max ~/ 3) cut = rest.lastIndexOf(' ', max);
    if (cut < max ~/ 3) cut = max;
    final end = cut >= max ? max : cut + 1;
    out.add(rest.substring(0, end).trim());
    rest = rest.substring(end).trim();
  }
  if (rest.isNotEmpty) out.add(rest);
  return out;
}

/// Translates text of any length passage by passage, keeping its paragraphs. Passages with no letters (numbers, dates) are kept as they are.
Future<String> translateLongText(
  TranslationService service,
  String text, {
  required String from,
  required String to,
  void Function(int done, int total)? onProgress,
  bool Function()? isCancelled,
}) async {
  final parts = splitForTranslation(text);
  final b = StringBuffer();
  for (var i = 0; i < parts.length; i++) {
    if (isCancelled?.call() ?? false) throw const TranslationCancelled();
    final part = parts[i];
    final translated = _hasLetters.hasMatch(part.text) ? (await service.translate(part.text, from: from, to: to)).trim() : part.text;
    if (isCancelled?.call() ?? false) throw const TranslationCancelled();
    b
      ..write(translated.isEmpty ? part.text : translated)
      ..write(part.after);
    onProgress?.call(i + 1, parts.length);
  }
  return b.toString().trim();
}

import '../../translate/domain/translation_languages.dart';

final _endsSentence = RegExp(r'[.!?:;\u0964\u2026]["\u201D\u2019)\]]*$');

/// Cuts text into pieces for a speech engine: wrapped lines are joined, each sentence stays whole, and pieces are short enough to start quickly.
List<String> splitForSpeech(String text, {int maxLength = 320}) {
  final cleaned = text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll('\u00AD', '')
      .replaceAll(RegExp(r'[ \t\u00A0]+'), ' ')
      // A word cut by a hyphen at the end of a line.
      .replaceAllMapped(RegExp(r'(\p{L})-\n\s*(\p{Ll})', unicode: true), (m) => '${m[1]}${m[2]}');

  final pieces = <String>[];
  for (final paragraph in cleaned.split(RegExp(r'\n\s*\n'))) {
    final units = <String>[];
    var buffer = '';
    final lines = [
      for (final l in paragraph.split('\n'))
        if (l.trim().isNotEmpty) l.trim(),
    ];
    for (final line in lines) {
      if (buffer.isEmpty) {
        buffer = line;
        continue;
      }
      // A line that stops without a full stop and goes on in lower case is one sentence cut by the width of the page.
      final open = !_endsSentence.hasMatch(buffer);
      final continues = RegExp(r'^\p{Ll}', unicode: true).hasMatch(line);
      if (open && continues) {
        buffer = '$buffer $line';
      } else {
        units.add(buffer);
        buffer = line;
      }
    }
    if (buffer.isNotEmpty) units.add(buffer);

    var current = '';
    void flush() {
      if (current.isNotEmpty) pieces.add(current);
      current = '';
    }

    for (final unit in units) {
      for (final sentence in unit.split(RegExp(r'(?<=[.!?\u0964\u2026])\s+(?=\S)'))) {
        for (final part in _fit(sentence.trim(), maxLength)) {
          if (current.isEmpty) {
            current = part;
          } else if (current.length + 1 + part.length <= maxLength) {
            current = '$current $part';
          } else {
            flush();
            current = part;
          }
        }
      }
      // A line that does not end like a sentence (a list item, a heading) is spoken on its own so the voice pauses after it.
      if (!_endsSentence.hasMatch(unit)) flush();
    }
    flush();
  }
  return [
    for (final p in pieces)
      if (RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(p)) p,
  ];
}

/// A sentence cut into parts of at most [max] characters, at a comma or a space.
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

/// The voice language to ask for: null lets the phone use its own language.
/// Text mostly in Devanagari or Arabic script is read with a voice for that script.
String? guessSpeechLanguage(String text) {
  var letters = 0, devanagari = 0, arabic = 0;
  for (final r in text.runes) {
    if (r >= 0x0900 && r <= 0x097F) {
      devanagari++;
      letters++;
    } else if ((r >= 0x0600 && r <= 0x06FF) || (r >= 0x0750 && r <= 0x077F)) {
      arabic++;
      letters++;
    } else if ((r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A) || (r >= 0xC0 && r <= 0x24F)) {
      letters++;
    }
  }
  if (letters == 0) return null;
  if (devanagari / letters >= 0.3) return 'hi-IN';
  if (arabic / letters >= 0.3) return 'ar';
  return null;
}

const _firstVoices = <(String?, String)>[
  (null, 'Automatic'),
  ('en', 'English'),
  ('hi-IN', 'Hindi'),
  ('es', 'Spanish'),
  ('fr', 'French'),
  ('de', 'German'),
  ('pt', 'Portuguese'),
  ('it', 'Italian'),
  ('ru', 'Russian'),
  ('tr', 'Turkish'),
  ('id', 'Indonesian'),
  ('ar', 'Arabic'),
];

/// Voices offered in the language list: the first entry (null) follows the text and the phone, then the common languages,
/// then every other language the translator knows, so a translation can be read in its own language.
final speechLanguages = <(String?, String)>[
  ..._firstVoices,
  for (final l in translationLanguages)
    if (l.code != 'hi' && !_firstVoices.any((v) => v.$1 == l.code)) (l.code, l.name),
];

/// The voice language for a translator language code ("hi" is asked for as Indian Hindi).
String speechVoiceFor(String translatorCode) => translatorCode == 'hi' ? 'hi-IN' : translatorCode;

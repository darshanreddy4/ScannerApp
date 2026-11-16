/// The colours a presentation theme gives to text, background, titles and shapes.
class DeckTheme {
  const DeckTheme({
    required this.id,
    required this.name,
    required this.background,
    required this.text,
    required this.title,
    required this.soft,
    required this.accents,
    this.dark = false,
  });

  final String id;
  final String name;

  /// Six hex colours without #, for accent 1 to 6; shapes and the bar at the top of each slide use the first.
  final List<String> accents;
  final String background;
  final String text;

  /// Colour of slide titles.
  final String title;

  /// A pale tone for panels.
  final String soft;

  /// Light text on a dark background.
  final bool dark;
}

const deckThemes = <DeckTheme>[
  DeckTheme(
    id: 'office',
    name: 'Classic blue',
    background: 'FFFFFF',
    text: '262626',
    title: '1F3864',
    soft: 'E7E6E6',
    accents: ['4472C4', 'ED7D31', 'A5A5A5', 'FFC000', '5B9BD5', '70AD47'],
  ),
  DeckTheme(
    id: 'ocean',
    name: 'Ocean',
    background: 'FFFFFF',
    text: '1B2A3A',
    title: '0B3C5D',
    soft: 'D9EAF3',
    accents: ['1C7ED6', '0FB9B1', '328CC1', 'F4A261', '5BC0EB', '2A9D8F'],
  ),
  DeckTheme(
    id: 'forest',
    name: 'Forest',
    background: 'FBFDF9',
    text: '1F2D24',
    title: '1E5631',
    soft: 'E3F0E6',
    accents: ['2E7D32', '8BC34A', '00897B', 'FBC02D', '6D4C41', '43A047'],
  ),
  DeckTheme(
    id: 'sunset',
    name: 'Sunset',
    background: 'FFFBF6',
    text: '3A2418',
    title: 'B23A0A',
    soft: 'FCE9DA',
    accents: ['F4511E', 'FFB300', 'E53935', '8E24AA', 'FB8C00', '6D4C41'],
  ),
  DeckTheme(
    id: 'berry',
    name: 'Berry',
    background: 'FFFFFF',
    text: '2B1B33',
    title: '6A1B9A',
    soft: 'F1E4F7',
    accents: ['8E24AA', 'D81B60', '5E35B1', 'F06292', '3949AB', '00ACC1'],
  ),
  DeckTheme(
    id: 'slate',
    name: 'Slate',
    background: 'FFFFFF',
    text: '212121',
    title: '37474F',
    soft: 'ECEFF1',
    accents: ['455A64', '607D8B', '26A69A', 'FFA000', '78909C', '90A4AE'],
  ),
  DeckTheme(
    id: 'classroom',
    name: 'Classroom',
    background: 'FFF9E8',
    text: '2D2A26',
    title: 'B3261E',
    soft: 'FDEBC8',
    accents: ['D84315', 'F9A825', '2E7D32', '1565C0', '6A1B9A', '00838F'],
  ),
  DeckTheme(
    id: 'midnight',
    name: 'Midnight',
    background: '0F172A',
    text: 'F1F5F9',
    title: '93C5FD',
    soft: '1E293B',
    dark: true,
    accents: ['38BDF8', 'A78BFA', 'F472B6', 'FBBF24', '34D399', 'FB7185'],
  ),
];

DeckTheme deckThemeById(String id) => deckThemes.firstWhere((t) => t.id == id, orElse: () => deckThemes.first);

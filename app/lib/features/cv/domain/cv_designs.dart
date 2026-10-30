/// Where the parts of a CV go.
enum CvLayout {
  /// Everything in one column under the header.
  single,

  /// A narrow column for personal details, languages and skills beside the main column.
  twoColumn,

  /// A full-height coloured column on the left or the right, holding the photo, contact details, languages and skills.
  sidebarLeft,
  sidebarRight,

  /// One column where dates and labels stand in a wide column on the left, as in a German Lebenslauf.
  table,
}

/// How the name and contact details are shown at the top.
enum CvHeader { plain, centered, band, banner, twoTone, bigName }

/// How the title of a section is drawn.
enum CvHeading { underline, caps, bar, pill, boxed, plain }

enum CvSkills { bullets, inline, chips }

enum CvEntries { dateLeft, inline, timeline }

enum CvPhoto { none, circle, rounded }

enum CvGroup { plain, colourful }

class CvDesign {
  const CvDesign({
    required this.id,
    required this.name,
    required this.hint,
    required this.group,
    required this.layout,
    required this.header,
    required this.heading,
    this.skills = CvSkills.bullets,
    this.entries = CvEntries.dateLeft,
    this.photo = CvPhoto.circle,
    this.levelBars = false,
    this.mono = false,
    this.personal = true,
    this.sidebar = CvSidebar.accent,
    this.pageTint = false,
    this.baseSize = 9.5,
    this.margin = 36,
    this.defaultAccent = 0xFF1D4ED8,
  });

  final String id;

  /// Shown in English; the screen translates it.
  final String name;
  final String hint;
  final CvGroup group;
  final CvLayout layout;
  final CvHeader header;
  final CvHeading heading;
  final CvSkills skills;
  final CvEntries entries;
  final CvPhoto photo;

  /// Language levels as bars instead of words.
  final bool levelBars;

  /// Black and white: the colour chosen does not change it.
  final bool mono;

  /// Whether the birth date and nationality are written, which US and UK CVs leave out.
  final bool personal;

  /// The look of the side column of a sidebar layout.
  final CvSidebar sidebar;

  /// The whole page in a very light shade of the colour.
  final bool pageTint;

  /// The size of body text in points.
  final double baseSize;

  /// Left and right margin in points.
  final double margin;
  final int defaultAccent;

  bool get isSidebar => layout == CvLayout.sidebarLeft || layout == CvLayout.sidebarRight;

  bool get hasPhoto => photo != CvPhoto.none;
}

enum CvSidebar { accent, dark, tint }

/// The colour a design really uses: black and white designs ignore the choice.
int effectiveAccent(CvDesign design, int chosen) => design.mono ? 0xFF111827 : chosen;

/// [color] mixed with white; [amount] 0 is the colour, 1 is white.
int tintOf(int color, double amount) {
  int mix(int c) => (c + (255 - c) * amount).round().clamp(0, 255);
  final r = mix((color >> 16) & 0xFF), g = mix((color >> 8) & 0xFF), b = mix(color & 0xFF);
  return 0xFF000000 | (r << 16) | (g << 8) | b;
}

/// [color] mixed with black; [amount] 0 is the colour, 1 is black.
int shadeOf(int color, double amount) {
  int mix(int c) => (c * (1 - amount)).round().clamp(0, 255);
  final r = mix((color >> 16) & 0xFF), g = mix((color >> 8) & 0xFF), b = mix(color & 0xFF);
  return 0xFF000000 | (r << 16) | (g << 8) | b;
}

/// How far a CEFR level fills a bar: A1 is a sixth, Native is full.
double levelFraction(String level) {
  final i = const ['A1', 'A2', 'B1', 'B2', 'C1', 'C2'].indexOf(level);
  return i < 0 ? 1 : (i + 1) / 6;
}

const cvDesigns = <CvDesign>[
  // Plain and professional
  CvDesign(
    id: 'classic',
    name: 'Classic',
    hint: 'Clean and safe for any job.',
    group: CvGroup.plain,
    layout: CvLayout.single,
    header: CvHeader.plain,
    heading: CvHeading.underline,
    skills: CvSkills.inline,
  ),
  CvDesign(
    id: 'ats',
    name: 'ATS plain',
    hint: 'Plain text layout that application-tracking software reads well. No photo, no colour.',
    group: CvGroup.plain,
    layout: CvLayout.single,
    header: CvHeader.plain,
    heading: CvHeading.caps,
    entries: CvEntries.inline,
    photo: CvPhoto.none,
    mono: true,
    personal: false,
  ),
  CvDesign(
    id: 'us',
    name: 'US resume',
    hint: 'One page, no photo and no birth date, which is what US employers expect.',
    group: CvGroup.plain,
    layout: CvLayout.single,
    header: CvHeader.centered,
    heading: CvHeading.underline,
    skills: CvSkills.inline,
    entries: CvEntries.inline,
    photo: CvPhoto.none,
    mono: true,
    personal: false,
    baseSize: 9.2,
    margin: 40,
  ),
  CvDesign(
    id: 'uk',
    name: 'UK CV',
    hint: 'Up to two pages with a profile first, no photo and no birth date.',
    group: CvGroup.plain,
    layout: CvLayout.single,
    header: CvHeader.plain,
    heading: CvHeading.bar,
    skills: CvSkills.inline,
    entries: CvEntries.inline,
    photo: CvPhoto.none,
    personal: false,
    defaultAccent: 0xFF334155,
  ),
  CvDesign(
    id: 'europe',
    name: 'European',
    hint: 'Two columns with a photo and personal details, close to the Europass layout.',
    group: CvGroup.plain,
    layout: CvLayout.twoColumn,
    header: CvHeader.plain,
    heading: CvHeading.underline,
  ),
  CvDesign(
    id: 'german',
    name: 'German tabular',
    hint: 'Dates on the left in a table, with a photo: the usual Lebenslauf.',
    group: CvGroup.plain,
    layout: CvLayout.table,
    header: CvHeader.plain,
    heading: CvHeading.plain,
    skills: CvSkills.inline,
    photo: CvPhoto.rounded,
    mono: true,
  ),
  CvDesign(
    id: 'academic',
    name: 'Academic',
    hint: 'Plain and long-form, for research and teaching posts.',
    group: CvGroup.plain,
    layout: CvLayout.single,
    header: CvHeader.plain,
    heading: CvHeading.caps,
    skills: CvSkills.inline,
    photo: CvPhoto.none,
    mono: true,
    baseSize: 10,
    margin: 44,
  ),
  CvDesign(
    id: 'executive',
    name: 'Executive',
    hint: 'A centred name and restrained colour for senior roles.',
    group: CvGroup.plain,
    layout: CvLayout.single,
    header: CvHeader.centered,
    heading: CvHeading.underline,
    skills: CvSkills.inline,
    entries: CvEntries.inline,
    photo: CvPhoto.none,
    defaultAccent: 0xFF1E293B,
  ),
  CvDesign(
    id: 'minimal',
    name: 'Minimal',
    hint: 'Light, airy and quiet.',
    group: CvGroup.plain,
    layout: CvLayout.single,
    header: CvHeader.plain,
    heading: CvHeading.plain,
    skills: CvSkills.inline,
    photo: CvPhoto.none,
    mono: true,
    margin: 48,
  ),
  CvDesign(
    id: 'compact',
    name: 'Compact one-pager',
    hint: 'Small type in two columns to fit everything on one page.',
    group: CvGroup.plain,
    layout: CvLayout.twoColumn,
    header: CvHeader.plain,
    heading: CvHeading.underline,
    baseSize: 8.6,
    margin: 28,
  ),
  CvDesign(
    id: 'india',
    name: 'Indian CV',
    hint: 'Photo, personal details and boxed headings, as in many Indian applications.',
    group: CvGroup.plain,
    layout: CvLayout.single,
    header: CvHeader.plain,
    heading: CvHeading.boxed,
    skills: CvSkills.bullets,
    entries: CvEntries.inline,
    photo: CvPhoto.rounded,
    defaultAccent: 0xFF0F766E,
  ),
  // Colourful
  CvDesign(
    id: 'modern',
    name: 'Modern band',
    hint: 'A coloured band with your name on top.',
    group: CvGroup.colourful,
    layout: CvLayout.twoColumn,
    header: CvHeader.band,
    heading: CvHeading.underline,
  ),
  CvDesign(
    id: 'sidebar_left',
    name: 'Colour sidebar',
    hint: 'A full-height colour column for contact details, languages and skills.',
    group: CvGroup.colourful,
    layout: CvLayout.sidebarLeft,
    header: CvHeader.plain,
    heading: CvHeading.underline,
    defaultAccent: 0xFF0F766E,
  ),
  CvDesign(
    id: 'sidebar_right',
    name: 'Sidebar on the right',
    hint: 'The same colour column, on the right.',
    group: CvGroup.colourful,
    layout: CvLayout.sidebarRight,
    header: CvHeader.plain,
    heading: CvHeading.underline,
    defaultAccent: 0xFF7C3AED,
  ),
  CvDesign(
    id: 'sidebar_dark',
    name: 'Dark sidebar',
    hint: 'A dark column with coloured headings.',
    group: CvGroup.colourful,
    layout: CvLayout.sidebarLeft,
    header: CvHeader.plain,
    heading: CvHeading.bar,
    sidebar: CvSidebar.dark,
    levelBars: true,
    skills: CvSkills.chips,
  ),
  CvDesign(
    id: 'banner',
    name: 'Bold banner',
    hint: 'A tall coloured banner with a large photo.',
    group: CvGroup.colourful,
    layout: CvLayout.single,
    header: CvHeader.banner,
    heading: CvHeading.bar,
    skills: CvSkills.chips,
    photo: CvPhoto.rounded,
    defaultAccent: 0xFFB91C1C,
  ),
  CvDesign(
    id: 'twotone',
    name: 'Two-tone header',
    hint: 'Two shades of your colour in the header.',
    group: CvGroup.colourful,
    layout: CvLayout.twoColumn,
    header: CvHeader.twoTone,
    heading: CvHeading.pill,
    defaultAccent: 0xFF0369A1,
  ),
  CvDesign(
    id: 'timeline',
    name: 'Timeline',
    hint: 'A line with dots down your work and study history.',
    group: CvGroup.colourful,
    layout: CvLayout.single,
    header: CvHeader.band,
    heading: CvHeading.bar,
    skills: CvSkills.chips,
    entries: CvEntries.timeline,
    defaultAccent: 0xFF15803D,
  ),
  CvDesign(
    id: 'chips',
    name: 'Skill tags',
    hint: 'Skills as coloured tags and pill headings.',
    group: CvGroup.colourful,
    layout: CvLayout.single,
    header: CvHeader.band,
    heading: CvHeading.pill,
    skills: CvSkills.chips,
    entries: CvEntries.inline,
    defaultAccent: 0xFFBE185D,
  ),
  CvDesign(
    id: 'infographic',
    name: 'Infographic',
    hint: 'Language levels as bars and skills as tags.',
    group: CvGroup.colourful,
    layout: CvLayout.twoColumn,
    header: CvHeader.bigName,
    heading: CvHeading.bar,
    skills: CvSkills.chips,
    levelBars: true,
    defaultAccent: 0xFFC2410C,
  ),
  CvDesign(
    id: 'creative',
    name: 'Creative',
    hint: 'A bold column and a timeline.',
    group: CvGroup.colourful,
    layout: CvLayout.sidebarLeft,
    header: CvHeader.plain,
    heading: CvHeading.bar,
    entries: CvEntries.timeline,
    levelBars: true,
    skills: CvSkills.chips,
    photo: CvPhoto.rounded,
    defaultAccent: 0xFF4338CA,
  ),
  CvDesign(
    id: 'tinted',
    name: 'Soft sidebar',
    hint: 'A pale tinted column that is light on ink.',
    group: CvGroup.colourful,
    layout: CvLayout.sidebarLeft,
    header: CvHeader.plain,
    heading: CvHeading.caps,
    sidebar: CvSidebar.tint,
    levelBars: true,
    defaultAccent: 0xFF0F766E,
  ),
  CvDesign(
    id: 'cards',
    name: 'Soft boxes',
    hint: 'Tinted heading boxes and skill tags.',
    group: CvGroup.colourful,
    layout: CvLayout.single,
    header: CvHeader.plain,
    heading: CvHeading.boxed,
    skills: CvSkills.chips,
    entries: CvEntries.inline,
    defaultAccent: 0xFF7C3AED,
  ),
  CvDesign(
    id: 'pastel',
    name: 'Pastel page',
    hint: 'A softly tinted page with pill headings.',
    group: CvGroup.colourful,
    layout: CvLayout.twoColumn,
    header: CvHeader.centered,
    heading: CvHeading.pill,
    skills: CvSkills.chips,
    pageTint: true,
    defaultAccent: 0xFFBE185D,
  ),
  CvDesign(
    id: 'bold',
    name: 'Big name',
    hint: 'A very large name with a thick colour bar.',
    group: CvGroup.colourful,
    layout: CvLayout.single,
    header: CvHeader.bigName,
    heading: CvHeading.caps,
    skills: CvSkills.inline,
    entries: CvEntries.inline,
    defaultAccent: 0xFF0369A1,
  ),
];

CvDesign cvDesignOf(String id) => cvDesigns.firstWhere((d) => d.id == id, orElse: () => cvDesigns.firstWhere((d) => d.id == 'europe'));

/// The ids and English names of the designs, in the order they are offered.
final Map<String, String> cvTemplates = {for (final d in cvDesigns) d.id: d.name};

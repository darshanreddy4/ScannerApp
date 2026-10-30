import 'cv_designs.dart';

export 'cv_designs.dart';

const defaultCvAccent = 0xFF1D4ED8;

/// The colours offered for headings and rules.
const cvAccents = [
  0xFF1D4ED8,
  0xFF0F766E,
  0xFF7C3AED,
  0xFFB91C1C,
  0xFF334155,
  0xFF0369A1,
  0xFF15803D,
  0xFFC2410C,
  0xFFBE185D,
  0xFF4338CA,
  0xFF92400E,
  0xFF0F172A,
];

/// One job or one course of study on a CV.
class CvEntry {
  const CvEntry({this.title = '', this.organisation = '', this.place = '', this.from = '', this.to = '', this.description = ''});
  final String title;
  final String organisation;
  final String place;

  /// Free text such as `03/2019`; kept as typed.
  final String from;
  final String to;
  final String description;

  bool get isEmpty => title.trim().isEmpty && organisation.trim().isEmpty && description.trim().isEmpty;

  Map<String, Object?> toJson() => {'title': title, 'organisation': organisation, 'place': place, 'from': from, 'to': to, 'description': description};

  static CvEntry fromJson(Object? o) {
    final j = o is Map ? o : const {};
    String s(String k) => j[k] is String ? j[k] as String : '';
    return CvEntry(title: s('title'), organisation: s('organisation'), place: s('place'), from: s('from'), to: s('to'), description: s('description'));
  }
}

/// The levels of the Common European Framework of Reference for Languages, plus a native speaker.
const cvLanguageLevels = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2', 'Native'];

class CvLanguage {
  const CvLanguage({required this.name, this.level = 'B2'});
  final String name;
  final String level;

  Map<String, Object?> toJson() => {'name': name, 'level': level};

  static CvLanguage fromJson(Object? o) {
    final j = o is Map ? o : const {};
    final level = j['level'];
    return CvLanguage(name: j['name'] is String ? j['name'] as String : '', level: level is String && cvLanguageLevels.contains(level) ? level : 'B2');
  }
}

class CvData {
  const CvData({
    this.name = '',
    this.headline = '',
    this.email = '',
    this.phone = '',
    this.address = '',
    this.website = '',
    this.birthDate = '',
    this.nationality = '',
    this.summary = '',
    this.work = const [],
    this.education = const [],
    this.skills = const [],
    this.languages = const [],
    this.language = 'en',
    this.template = 'europe',
    this.accent = defaultCvAccent,
  });

  final String name;

  /// The job title or the kind of work looked for.
  final String headline;
  final String email;
  final String phone;
  final String address;
  final String website;
  final String birthDate;
  final String nationality;
  final String summary;
  final List<CvEntry> work;
  final List<CvEntry> education;
  final List<String> skills;
  final List<CvLanguage> languages;

  /// The language the CV headings are written in.
  final String language;

  /// One of [cvTemplates].
  final String template;

  /// The colour of headings and rules, as 0xAARRGGBB.
  final int accent;

  Map<String, Object?> toJson() => {
    'name': name,
    'headline': headline,
    'email': email,
    'phone': phone,
    'address': address,
    'website': website,
    'birthDate': birthDate,
    'nationality': nationality,
    'summary': summary,
    'work': [for (final e in work) e.toJson()],
    'education': [for (final e in education) e.toJson()],
    'skills': skills,
    'languages': [for (final l in languages) l.toJson()],
    'language': language,
    'template': template,
    'accent': accent,
  };

  static CvData fromJson(Map<String, Object?> j) {
    String s(String k) => j[k] is String ? j[k]! as String : '';
    List<T> list<T>(String k, T Function(Object?) f) => j[k] is List ? [for (final e in j[k]! as List) f(e)] : <T>[];
    return CvData(
      name: s('name'),
      headline: s('headline'),
      email: s('email'),
      phone: s('phone'),
      address: s('address'),
      website: s('website'),
      birthDate: s('birthDate'),
      nationality: s('nationality'),
      summary: s('summary'),
      work: list('work', CvEntry.fromJson),
      education: list('education', CvEntry.fromJson),
      skills: [
        for (final x in (j['skills'] is List ? j['skills']! as List : const []))
          if (x is String) x,
      ],
      languages: list('languages', CvLanguage.fromJson),
      language: s('language').isEmpty ? 'en' : s('language'),
      template: cvTemplates.containsKey(s('template')) ? s('template') : 'europe',
      accent: j['accent'] is int && cvAccents.contains(j['accent']) ? j['accent']! as int : defaultCvAccent,
    );
  }
}

/// Skills typed as a list separated by commas, semicolons or line breaks.
List<String> splitSkills(String text) => [
  for (final s in text.split(RegExp(r'[,;\n]')))
    if (s.trim().isNotEmpty) s.trim(),
];

/// A problem found in what was typed: which field, and what to tell the person.
class CvIssue {
  const CvIssue(this.field, this.message);

  /// `name`, `email`, `phone`, `contact`, `website`, `birth`, `headline`, `summary`, `skills`, `work.0.title`, `education.1.from`, ...
  final String field;
  final String message;
}

/// A month and year, or a year alone, as written on a CV.
typedef CvDate = ({int year, int? month});

final _monthYear = RegExp(r'^(\d{1,2})\s*[/.\-]\s*(\d{4})$');
final _yearMonth = RegExp(r'^(\d{4})\s*[/.\-]\s*(\d{1,2})$');

/// Reads `03/2019`, `3.2019`, `2019-03` or `2019`; null when it is none of these or not plausible (years 1950 to 2100).
CvDate? parseCvDate(String text) {
  final t = text.trim();
  CvDate? d;
  var m = _monthYear.firstMatch(t);
  if (m != null) d = (year: int.parse(m[2]!), month: int.parse(m[1]!));
  m = _yearMonth.firstMatch(t);
  if (d == null && m != null) d = (year: int.parse(m[1]!), month: int.parse(m[2]!));
  if (d == null && RegExp(r'^\d{4}$').hasMatch(t)) d = (year: int.parse(t), month: null);
  if (d == null || d.year < 1950 || d.year > 2100) return null;
  if (d.month != null && (d.month! < 1 || d.month! > 12)) return null;
  return d;
}

/// `03/2019` or `2019`, the form the CV shows.
String formatCvDate(CvDate d) => d.month == null ? '${d.year}' : '${d.month.toString().padLeft(2, '0')}/${d.year}';

final _fullDate = RegExp(r'^(\d{1,2})\s*[/.\-]\s*(\d{1,2})\s*[/.\-]\s*(\d{4})$');
final _isoDate = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$');

/// Reads a day, month and year (`25/03/1990`, `25.3.1990` or `1990-03-25`); null when it is not a real date.
DateTime? parseCvBirthDate(String text) {
  final t = text.trim();
  int? y, mo, d;
  var m = _fullDate.firstMatch(t);
  if (m != null) {
    d = int.parse(m[1]!);
    mo = int.parse(m[2]!);
    y = int.parse(m[3]!);
  } else if ((m = _isoDate.firstMatch(t)) != null) {
    y = int.parse(m![1]!);
    mo = int.parse(m[2]!);
    d = int.parse(m[3]!);
  }
  if (y == null || mo == null || d == null) return null;
  final date = DateTime(y, mo, d);
  return date.year == y && date.month == mo && date.day == d ? date : null;
}

/// `25/03/1990`, the form the CV shows.
String formatCvBirthDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

final _emailRe = RegExp(r"^[A-Za-z0-9._%+\-']+@[A-Za-z0-9\-]+(\.[A-Za-z0-9\-]+)*\.[A-Za-z]{2,}$");
final _websiteRe = RegExp(r'^(https?://)?([A-Za-z0-9\-]+\.)+[A-Za-z]{2,}(:\d+)?(/\S*)?$', caseSensitive: false);

bool isCvEmail(String s) => _emailRe.hasMatch(s.trim());

/// Digits, spaces, dashes, dots and brackets, with an optional + at the start, and 6 to 15 digits.
bool isCvPhone(String s) {
  final t = s.trim();
  if (!RegExp(r'^\+?[\d\s().\-]+$').hasMatch(t)) return false;
  final digits = t.replaceAll(RegExp(r'\D'), '').length;
  return digits >= 6 && digits <= 15;
}

bool isCvWebsite(String s) => _websiteRe.hasMatch(s.trim());

/// Whether the PDF font (Roboto: Latin, Greek and Cyrillic letters) can print every character; false for Hindi, Kannada, Arabic, Chinese, emoji and the like.
bool isCvPrintable(String s) {
  for (final r in s.runes) {
    final ok =
        r < 0x250 || // Latin
        (r >= 0x1E00 && r <= 0x1EFF) || // Latin extended additional
        (r >= 0x370 && r <= 0x52F) || // Greek and Cyrillic
        (r >= 0x2000 && r <= 0x206F) || // punctuation
        (r >= 0x20A0 && r <= 0x20CF) || // currency
        r == 0x2116 ||
        r == 0x2122;
    if (!ok) return false;
  }
  return true;
}

const cvMaxSummary = 1200;
const cvMaxDescription = 600;

String? _longText(String s, int max) => s.trim().length > max ? 'The text is too long ({n} characters at most).' : null;

/// Everything wrong with what was typed, in the order it is shown. Empty when the CV can be made. [now] is for tests.
List<CvIssue> cvIssues(CvData d, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final issues = <CvIssue>[];
  void add(String field, String message) => issues.add(CvIssue(field, message));

  final name = d.name.trim();
  if (name.length < 2) {
    add('name', 'Enter your full name.');
  } else if (name.length > 80) {
    add('name', 'The name is too long (80 letters at most).');
  }
  if (d.email.trim().isEmpty && d.phone.trim().isEmpty) {
    add('contact', 'Enter an email address or a phone number.');
  }
  if (d.email.trim().isNotEmpty && !isCvEmail(d.email)) add('email', 'The email address is not valid. It looks like name@example.com.');
  if (d.phone.trim().isNotEmpty && !isCvPhone(d.phone)) {
    add('phone', 'The phone number is not valid. Use digits, with a + for the country, such as +49 170 1234567.');
  }
  if (d.website.trim().isNotEmpty && !isCvWebsite(d.website)) add('website', 'The website is not valid. It looks like www.example.com.');

  final birth = d.birthDate.trim();
  if (birth.isNotEmpty) {
    final b = parseCvBirthDate(birth);
    if (b == null) {
      add('birth', 'The date of birth is not a real date. Use DD/MM/YYYY, such as 25/03/1990.');
    } else if (b.isAfter(today)) {
      add('birth', 'The date of birth is in the future.');
    } else if (today.year - b.year < 14 || today.year - b.year > 100) {
      add('birth', 'Check the year of birth: the age must be between 14 and 100.');
    }
  }

  void text(String field, String s, int max) {
    final long = _longText(s, max);
    if (long != null) add(field, long);
  }

  text('headline', d.headline, 80);
  text('summary', d.summary, cvMaxSummary);
  text('skills', d.skills.join(', '), 400);

  final nowKey = today.year * 12 + today.month;
  void entries(String kind, List<CvEntry> list, String titleMessage, {required bool futureEnd}) {
    for (final (i, e) in list.indexed) {
      final used = !e.isEmpty || e.from.trim().isNotEmpty || e.to.trim().isNotEmpty || e.place.trim().isNotEmpty;
      if (!used) continue;
      final f = '$kind.$i';
      if (e.title.trim().isEmpty) add('$f.title', titleMessage);
      text('$f.description', e.description, cvMaxDescription);
      final from = e.from.trim().isEmpty ? null : parseCvDate(e.from);
      final to = e.to.trim().isEmpty ? null : parseCvDate(e.to);
      if (e.from.trim().isEmpty) {
        add('$f.from', 'Enter the start date, such as 03/2019.');
      } else if (from == null) {
        add('$f.from', 'The date is not valid. Use MM/YYYY, such as 03/2019, or just the year.');
      } else if (from.year * 12 + (from.month ?? 1) > nowKey) {
        add('$f.from', 'The start date is in the future.');
      }
      if (e.to.trim().isNotEmpty) {
        if (to == null) {
          add('$f.to', 'The date is not valid. Use MM/YYYY, such as 03/2019, or just the year.');
        } else {
          final end = to.year * 12 + (to.month ?? 12);
          if (from != null && end < from.year * 12 + (from.month ?? 1)) {
            add('$f.to', 'The end date is before the start date.');
          } else if (end > nowKey + (futureEnd ? 120 : 0) && !(to.month == null && to.year == today.year)) {
            add('$f.to', 'The end date is in the future.');
          }
        }
      }
    }
  }

  entries('work', d.work, 'Enter the job title.', futureEnd: false);
  entries('education', d.education, 'Enter the qualification or course.', futureEnd: true);

  if (d.work.every((e) => e.isEmpty) && d.education.every((e) => e.isEmpty) && d.summary.trim().isEmpty) {
    add('content', 'Add some work, education or a short profile.');
  }

  final printable = <String, String>{
    'name': d.name,
    'headline': d.headline,
    'email': d.email,
    'address': d.address,
    'website': d.website,
    'nationality': d.nationality,
    'summary': d.summary,
    'skills': d.skills.join(', '),
  };
  for (final (i, e) in d.work.indexed) {
    printable['work.$i.title'] = e.title;
    printable['work.$i.organisation'] = e.organisation;
    printable['work.$i.place'] = e.place;
    printable['work.$i.description'] = e.description;
  }
  for (final (i, e) in d.education.indexed) {
    printable['education.$i.title'] = e.title;
    printable['education.$i.organisation'] = e.organisation;
    printable['education.$i.place'] = e.place;
    printable['education.$i.description'] = e.description;
  }
  for (final (i, l) in d.languages.indexed) {
    printable['language.$i'] = l.name;
  }
  for (final e in printable.entries) {
    if (!isCvPrintable(e.value) && !issues.any((x) => x.field == e.key)) {
      add(e.key, 'Some characters cannot be printed in the PDF (for example Hindi, Kannada or emoji). Use Latin, Greek or Cyrillic letters.');
    }
  }
  return issues;
}

/// The first thing to fix, or null when the CV can be made.
String? cvProblem(CvData d) => cvIssues(d).firstOrNull?.message;

/// The same CV with dates written in one form (`03/2019`, `25/03/1990`) and spaces trimmed.
CvData tidyCv(CvData d) {
  String date(String s) {
    final x = parseCvDate(s);
    return x == null ? s.trim() : formatCvDate(x);
  }

  CvEntry entry(CvEntry e) => CvEntry(
    title: e.title.trim(),
    organisation: e.organisation.trim(),
    place: e.place.trim(),
    from: date(e.from),
    to: date(e.to),
    description: e.description.trim(),
  );

  final b = parseCvBirthDate(d.birthDate);
  return CvData(
    name: d.name.trim(),
    headline: d.headline.trim(),
    email: d.email.trim(),
    phone: d.phone.trim(),
    address: d.address.trim(),
    website: d.website.trim(),
    birthDate: b == null ? d.birthDate.trim() : formatCvBirthDate(b),
    nationality: d.nationality.trim(),
    summary: d.summary.trim(),
    work: [
      for (final e in d.work)
        if (!e.isEmpty) entry(e),
    ],
    education: [
      for (final e in d.education)
        if (!e.isEmpty) entry(e),
    ],
    skills: d.skills,
    languages: d.languages,
    language: d.language,
    template: d.template,
    accent: d.accent,
  );
}

/// The words on the CV, in the language it is written in.
class CvLabels {
  const CvLabels._(this._w);
  final Map<String, String> _w;

  static CvLabels of(String code) => CvLabels._(_all[code] ?? _all['en']!);

  String operator [](String key) => _w[key] ?? _all['en']![key] ?? key;

  static const supported = {
    'en': 'English',
    'de': 'Deutsch',
    'fr': 'Fran\u00E7ais',
    'es': 'Espa\u00F1ol',
    'it': 'Italiano',
    'nl': 'Nederlands',
    'pl': 'Polski',
  };

  static const _all = <String, Map<String, String>>{
    'en': {
      'cv': 'Curriculum vitae',
      'personal': 'Personal information',
      'profile': 'Profile',
      'work': 'Work experience',
      'education': 'Education and training',
      'languages': 'Language skills',
      'skills': 'Skills',
      'born': 'Date of birth',
      'nationality': 'Nationality',
      'present': 'present',
      'native': 'Mother tongue',
    },
    'de': {
      'cv': 'Lebenslauf',
      'personal': 'Pers\u00F6nliche Daten',
      'profile': 'Profil',
      'work': 'Berufserfahrung',
      'education': 'Ausbildung',
      'languages': 'Sprachkenntnisse',
      'skills': 'Kenntnisse',
      'born': 'Geburtsdatum',
      'nationality': 'Staatsangeh\u00F6rigkeit',
      'present': 'heute',
      'native': 'Muttersprache',
    },
    'fr': {
      'cv': 'Curriculum vitae',
      'personal': 'Informations personnelles',
      'profile': 'Profil',
      'work': 'Exp\u00E9rience professionnelle',
      'education': 'Formation',
      'languages': 'Comp\u00E9tences linguistiques',
      'skills': 'Comp\u00E9tences',
      'born': 'Date de naissance',
      'nationality': 'Nationalit\u00E9',
      'present': 'aujourd\'hui',
      'native': 'Langue maternelle',
    },
    'es': {
      'cv': 'Curr\u00EDculum vitae',
      'personal': 'Informaci\u00F3n personal',
      'profile': 'Perfil',
      'work': 'Experiencia laboral',
      'education': 'Educaci\u00F3n y formaci\u00F3n',
      'languages': 'Idiomas',
      'skills': 'Competencias',
      'born': 'Fecha de nacimiento',
      'nationality': 'Nacionalidad',
      'present': 'actualidad',
      'native': 'Lengua materna',
    },
    'it': {
      'cv': 'Curriculum vitae',
      'personal': 'Informazioni personali',
      'profile': 'Profilo',
      'work': 'Esperienza lavorativa',
      'education': 'Istruzione e formazione',
      'languages': 'Competenze linguistiche',
      'skills': 'Competenze',
      'born': 'Data di nascita',
      'nationality': 'Nazionalit\u00E0',
      'present': 'in corso',
      'native': 'Madrelingua',
    },
    'nl': {
      'cv': 'Curriculum vitae',
      'personal': 'Persoonlijke gegevens',
      'profile': 'Profiel',
      'work': 'Werkervaring',
      'education': 'Opleiding',
      'languages': 'Talenkennis',
      'skills': 'Vaardigheden',
      'born': 'Geboortedatum',
      'nationality': 'Nationaliteit',
      'present': 'heden',
      'native': 'Moedertaal',
    },
    'pl': {
      'cv': 'Curriculum vitae',
      'personal': 'Dane osobowe',
      'profile': 'Profil',
      'work': 'Do\u015Bwiadczenie zawodowe',
      'education': 'Edukacja i szkolenia',
      'languages': 'Znajomo\u015B\u0107 j\u0119zyk\u00F3w',
      'skills': 'Umiej\u0119tno\u015Bci',
      'born': 'Data urodzenia',
      'nationality': 'Narodowo\u015B\u0107',
      'present': 'obecnie',
      'native': 'J\u0119zyk ojczysty',
    },
  };
}

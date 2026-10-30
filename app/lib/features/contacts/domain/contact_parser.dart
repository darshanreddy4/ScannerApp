/// What could be read about a person from the text of a business card.
class ContactDraft {
  const ContactDraft({
    this.name = '',
    this.organization = '',
    this.title = '',
    this.phones = const [],
    this.emails = const [],
    this.websites = const [],
    this.address = '',
  });

  final String name;
  final String organization;
  final String title;
  final List<String> phones;
  final List<String> emails;
  final List<String> websites;
  final String address;

  bool get isEmpty => name.isEmpty && organization.isEmpty && title.isEmpty && phones.isEmpty && emails.isEmpty && websites.isEmpty && address.isEmpty;

  /// Worth saving: a number or email, or a name with something else on the card. A lone name is more likely ordinary text.
  bool get isUsable =>
      phones.isNotEmpty || emails.isNotEmpty || (name.isNotEmpty && (organization.isNotEmpty || title.isNotEmpty || websites.isNotEmpty || address.isNotEmpty));
}

final _email = RegExp(r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9\-]+(?:\.[A-Za-z0-9\-]+)*\.[A-Za-z]{2,}');
final _site = RegExp(
  r'(?:https?://)?(?:www\.)[A-Za-z0-9\-]+(?:\.[A-Za-z0-9\-]+)+(?:/[^\s,;]*)?|https?://[A-Za-z0-9\-]+(?:\.[A-Za-z0-9\-]+)+(?:/[^\s,;]*)?',
  caseSensitive: false,
);
final _bareSite = RegExp(
  r'\b[A-Za-z0-9\-]{2,}\.(?:com|net|org|io|co|in|info|biz|app|dev|ai|edu|gov|us|uk|de|fr|es|it|nl|ca|au|ae|sg|pk|bd|lk|np|za|br|mx|ru|jp|cn)(?:\.[a-z]{2})?\b(?:/[^\s,;]*)?',
  caseSensitive: false,
);
final _phone = RegExp(r'(?:\+|00)?\(?\d[\d\s().\-]{5,}\d');
final _label = RegExp(
  r'^\s*(?:(?:tel(?:ephone)?|phone|ph|mobile|mob|cell|call|whatsapp|direct|office|e-?mail|email|web(?:site)?|url|address|addr)\s*[:.\-|]|[tpmwea]\s*[:|])\s*',
  caseSensitive: false,
);
final _faxLine = RegExp(r'^\s*(?:fax\s*[:.\-|]|f\s*[:|])', caseSensitive: false);

const _titleWords = [
  'manager',
  'director',
  'engineer',
  'ceo',
  'cto',
  'cfo',
  'coo',
  'founder',
  'co-founder',
  'cofounder',
  'consultant',
  'developer',
  'designer',
  'president',
  'vice',
  'officer',
  'head of',
  'lead',
  'sales',
  'partner',
  'executive',
  'analyst',
  'architect',
  'specialist',
  'coordinator',
  'supervisor',
  'administrator',
  'accountant',
  'lawyer',
  'attorney',
  'advocate',
  'doctor',
  'dr.',
  'professor',
  'chairman',
  'owner',
  'proprietor',
  'representative',
  'associate',
  'assistant',
  'agent',
  'broker',
  'advisor',
  'adviser',
  'technician',
  'programmer',
  'marketing',
  'recruiter',
  'principal',
  'editor',
  'writer',
];
const _companyWords = [
  'inc',
  'llc',
  'ltd',
  'limited',
  'corp',
  'corporation',
  'gmbh',
  'pvt',
  'plc',
  'co.',
  'company',
  'group',
  'solutions',
  'technologies',
  'technology',
  'systems',
  'services',
  'consulting',
  'studio',
  'bank',
  'labs',
  'partners',
  'associates',
  'industries',
  'enterprises',
  'university',
  'school',
  'hospital',
  'clinic',
  'agency',
  'holdings',
  'ventures',
  'trading',
  'logistics',
  'realty',
  'foundation',
  'institute',
];
const _addressWords = [
  'street',
  'st.',
  'road',
  'rd.',
  'avenue',
  'ave',
  'lane',
  'floor',
  'suite',
  'block',
  'sector',
  'plot',
  'building',
  'tower',
  'plaza',
  'park',
  'nagar',
  'colony',
  'boulevard',
  'blvd',
  'drive',
  'p.o.',
  'box',
  'city',
];

bool _hasWord(String line, List<String> words) {
  final l = ' ${line.toLowerCase()} ';
  for (final w in words) {
    final pattern = RegExp('(?<![a-z])${RegExp.escape(w)}(?![a-z])');
    if (pattern.hasMatch(l)) return true;
  }
  return false;
}

bool _looksLikeName(String line) {
  if (line.length > 40 || RegExp(r'[0-9@/\\|_:;]').hasMatch(line)) return false;
  final tokens = line.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
  if (tokens.isEmpty || tokens.length > 4) return false;
  final word = RegExp(r"^\p{L}[\p{L}.'\-]*$", unicode: true);
  const particles = {
    'de',
    'da',
    'del',
    'della',
    'di',
    'van',
    'von',
    'der',
    'den',
    'bin',
    'binti',
    'al',
    'el',
    'la',
    'le',
    'du',
    'dos',
    'das',
    'ibn',
    'ter',
    'ten',
    'y',
    'e',
  };
  final capitalised = tokens.every(
    (t) => particles.contains(t.toLowerCase()) || t[0] != t[0].toLowerCase() || t[0] == t[0].toUpperCase() && t[0] == t[0].toLowerCase(),
  );
  return capitalised && tokens.every(word.hasMatch) && !_hasWord(line, _titleWords) && !_hasWord(line, _companyWords) && !_hasWord(line, _addressWords);
}

String _titleCase(String s) {
  if (s != s.toUpperCase() || !RegExp(r'\p{L}', unicode: true).hasMatch(s)) return s;
  return s.split(' ').map((w) => w.isEmpty ? w : '${w[0]}${w.substring(1).toLowerCase()}').join(' ');
}

String _digits(String s) => s.replaceAll(RegExp(r'\D'), '');

/// Reads names, numbers and addresses out of the text of a business card. It makes sensible guesses; the person checks them.
ContactDraft parseContactText(String text) {
  final emails = <String>[];
  final websites = <String>[];
  final phones = <String>[];
  final seenDigits = <String>{};
  final rest = <String>[];

  for (final raw in text.split(RegExp(r'[\r\n]+'))) {
    var line = raw.replaceAll(RegExp(r'[\u00A0\t]+'), ' ').replaceAll(RegExp(r' {2,}'), ' ').trim();
    if (line.isEmpty) continue;
    final isFax = _faxLine.hasMatch(line);
    line = line.replaceFirst(_label, '').trim();

    for (final m in _email.allMatches(line)) {
      final e = m.group(0)!.toLowerCase();
      if (!emails.contains(e)) emails.add(e);
    }
    line = line.replaceAll(_email, ' ').trim();

    for (final m in _site.allMatches(line)) {
      final w = _cleanSite(m.group(0)!);
      if (!websites.any((x) => x.toLowerCase() == w.toLowerCase())) websites.add(w);
    }
    line = line.replaceAll(_site, ' ').trim();
    for (final m in _bareSite.allMatches(line)) {
      final w = _cleanSite(m.group(0)!);
      if (!websites.any((x) => x.toLowerCase() == w.toLowerCase())) websites.add(w);
    }
    line = line.replaceAll(_bareSite, ' ').trim();

    final matches = _phone.allMatches(line).toList();
    var remaining = line;
    for (final m in matches) {
      final d = _digits(m.group(0)!);
      if (d.length < 7 || d.length > 15) continue;
      remaining = remaining.replaceFirst(m.group(0)!, ' ');
      if (isFax) continue;
      if (seenDigits.add(d)) phones.add(m.group(0)!.trim().replaceAll(RegExp(r'\s{2,}'), ' '));
    }
    remaining = remaining.replaceAll(RegExp(r'[|•·]+'), ' ').replaceAll(RegExp(r'\s{2,}'), ' ').trim();
    if (remaining.length >= 2 && !RegExp(r'^[\W_]+$').hasMatch(remaining)) rest.add(remaining);
  }

  final used = <int>{};
  String name = '';
  for (var i = 0; i < rest.length; i++) {
    if (_looksLikeName(rest[i])) {
      name = _titleCase(rest[i]);
      used.add(i);
      break;
    }
  }
  String title = '';
  for (var i = 0; i < rest.length; i++) {
    if (!used.contains(i) && _hasWord(rest[i], _titleWords) && !_hasWord(rest[i], _companyWords) && rest[i].length <= 60) {
      title = rest[i];
      used.add(i);
      break;
    }
  }
  String org = '';
  for (var i = 0; i < rest.length; i++) {
    if (!used.contains(i) && _hasWord(rest[i], _companyWords) && !RegExp(r'\d{3,}').hasMatch(rest[i])) {
      org = rest[i];
      used.add(i);
      break;
    }
  }
  final address = <String>[];
  for (var i = 0; i < rest.length; i++) {
    if (used.contains(i)) continue;
    final line = rest[i];
    if (RegExp(r'\d').hasMatch(line) || _hasWord(line, _addressWords)) {
      address.add(line);
      used.add(i);
    }
  }
  if (org.isEmpty) {
    for (var i = 0; i < rest.length; i++) {
      if (!used.contains(i) && rest[i].length <= 50) {
        org = rest[i];
        used.add(i);
        break;
      }
    }
  }
  return ContactDraft(name: name, organization: org, title: title, phones: phones, emails: emails, websites: websites, address: address.join(', '));
}

String _cleanSite(String raw) {
  var s = raw.trim().replaceAll(RegExp(r'[.,;:)\]]+$'), '');
  if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(s)) s = 'https://$s';
  return s;
}

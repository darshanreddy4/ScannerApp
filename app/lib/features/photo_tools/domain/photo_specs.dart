/// One official photo size, for example "Passport 35 x 45 mm".
class PhotoSpec {
  const PhotoSpec({
    required this.id,
    required this.name,
    required this.widthMm,
    required this.heightMm,
    this.headMinMm,
    this.headMaxMm,
    this.note,
    this.exactWidthPx,
    this.exactHeightPx,
  });

  final String id;
  final String name;
  final double widthMm;
  final double heightMm;

  /// Allowed height of the head, chin to crown, when the rules state it.
  final double? headMinMm;
  final double? headMaxMm;
  final String? note;

  /// Set for sizes given in pixels (online forms); the output then has exactly these pixels.
  final int? exactWidthPx;
  final int? exactHeightPx;

  double get aspect => widthMm / heightMm;

  int pixelWidth(int dpi) => exactWidthPx ?? (widthMm / 25.4 * dpi).round();
  int pixelHeight(int dpi) => exactHeightPx ?? (heightMm / 25.4 * dpi).round();

  /// Middle of the allowed head height, or the usual 75% of the photo when no rule is given.
  double get headTargetMm => headMinMm != null && headMaxMm != null ? (headMinMm! + headMaxMm!) / 2 : heightMm * 0.75;

  String get sizeLabel {
    if (exactWidthPx != null && exactHeightPx != null) return '$exactWidthPx x $exactHeightPx px';
    return '${_n(widthMm)} x ${_n(heightMm)} mm';
  }

  /// Inches shown next to millimetres for sizes that are defined in inches.
  String get sizeLabelFull {
    if (exactWidthPx != null) return sizeLabel;
    final w = widthMm / 25.4, h = heightMm / 25.4;
    return '${_n(widthMm)} x ${_n(heightMm)} mm (${w.toStringAsFixed(2)} x ${h.toStringAsFixed(2)} in)';
  }

  /// A size typed in by the person.
  factory PhotoSpec.custom({required double widthMm, required double heightMm, int? widthPx, int? heightPx}) =>
      PhotoSpec(id: 'custom', name: 'Custom size', widthMm: widthMm, heightMm: heightMm, exactWidthPx: widthPx, exactHeightPx: heightPx);

  static String _n(double v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
}

class PhotoCountry {
  const PhotoCountry({required this.code, required this.name, required this.specs});
  final String code;
  final String name;
  final List<PhotoSpec> specs;
}

/// Common photo sizes by country. Rules change, so the screen always tells people to check the issuing office.
abstract final class PhotoCatalog {
  // The ICAO standard used by most passports.
  static const _icao = PhotoSpec(id: 'icao', name: 'Passport', widthMm: 35, heightMm: 45, headMinMm: 32, headMaxMm: 36);

  static PhotoSpec _passport35x45({String id = 'passport', String name = 'Passport'}) =>
      PhotoSpec(id: id, name: name, widthMm: 35, heightMm: 45, headMinMm: 32, headMaxMm: 36);

  static PhotoSpec _square2in({String id = 'passport', String name = 'Passport and visa'}) =>
      PhotoSpec(id: id, name: name, widthMm: 51, heightMm: 51, headMinMm: 25, headMaxMm: 35, note: '2 x 2 inches');

  static final List<PhotoCountry> countries = List.unmodifiable(
    [
      PhotoCountry(
        code: 'IN',
        name: 'India',
        specs: [
          _passport35x45(),
          _square2in(id: 'visa', name: 'Visa and OCI'),
          const PhotoSpec(id: 'pan', name: 'PAN card', widthMm: 25, heightMm: 35),
          const PhotoSpec(id: 'stamp', name: 'Stamp size (forms)', widthMm: 20, heightMm: 25),
        ],
      ),
      PhotoCountry(
        code: 'US',
        name: 'United States',
        specs: [_square2in(name: 'Passport, visa and green card')],
      ),
      PhotoCountry(
        code: 'GB',
        name: 'United Kingdom',
        specs: [const PhotoSpec(id: 'passport', name: 'Passport and driving licence', widthMm: 35, heightMm: 45, headMinMm: 29, headMaxMm: 34)],
      ),
      PhotoCountry(
        code: 'CA',
        name: 'Canada',
        specs: [
          const PhotoSpec(id: 'passport', name: 'Passport', widthMm: 50, heightMm: 70, headMinMm: 31, headMaxMm: 36),
          const PhotoSpec(id: 'visa', name: 'Visa and permits', widthMm: 35, heightMm: 45, headMinMm: 31, headMaxMm: 36),
        ],
      ),
      PhotoCountry(code: 'AU', name: 'Australia', specs: [_passport35x45()]),
      PhotoCountry(code: 'NZ', name: 'New Zealand', specs: [_passport35x45()]),
      PhotoCountry(
        code: 'EU',
        name: 'European Union / Schengen visa',
        specs: [_passport35x45(id: 'visa', name: 'Visa and ID card')],
      ),
      PhotoCountry(code: 'DE', name: 'Germany', specs: [_passport35x45()]),
      PhotoCountry(code: 'FR', name: 'France', specs: [_passport35x45()]),
      PhotoCountry(code: 'IT', name: 'Italy', specs: [_passport35x45()]),
      PhotoCountry(code: 'ES', name: 'Spain', specs: [_passport35x45()]),
      PhotoCountry(code: 'NL', name: 'Netherlands', specs: [_passport35x45()]),
      PhotoCountry(code: 'IE', name: 'Ireland', specs: [_passport35x45()]),
      PhotoCountry(code: 'CH', name: 'Switzerland', specs: [_passport35x45()]),
      PhotoCountry(code: 'RU', name: 'Russia', specs: [_passport35x45()]),
      PhotoCountry(
        code: 'TR',
        name: 'Turkey',
        specs: [
          const PhotoSpec(id: 'passport', name: 'Passport', widthMm: 50, heightMm: 60),
          _passport35x45(id: 'visa', name: 'Visa'),
        ],
      ),
      PhotoCountry(
        code: 'CN',
        name: 'China',
        specs: [const PhotoSpec(id: 'passport', name: 'Passport and visa', widthMm: 33, heightMm: 48, headMinMm: 28, headMaxMm: 33)],
      ),
      PhotoCountry(
        code: 'JP',
        name: 'Japan',
        specs: [
          _passport35x45(),
          const PhotoSpec(id: 'visa', name: 'Visa', widthMm: 45, heightMm: 45),
        ],
      ),
      PhotoCountry(code: 'KR', name: 'South Korea', specs: [_passport35x45()]),
      PhotoCountry(code: 'SG', name: 'Singapore', specs: [_passport35x45()]),
      PhotoCountry(
        code: 'MY',
        name: 'Malaysia',
        specs: [const PhotoSpec(id: 'passport', name: 'Passport and visa', widthMm: 35, heightMm: 50)],
      ),
      PhotoCountry(
        code: 'ID',
        name: 'Indonesia',
        specs: [
          const PhotoSpec(id: 'visa', name: 'Visa', widthMm: 40, heightMm: 60, note: '4 x 6 cm'),
          _passport35x45(),
        ],
      ),
      PhotoCountry(
        code: 'TH',
        name: 'Thailand',
        specs: [
          _passport35x45(),
          const PhotoSpec(id: 'visa', name: 'Visa', widthMm: 40, heightMm: 60, note: '4 x 6 cm'),
        ],
      ),
      PhotoCountry(
        code: 'VN',
        name: 'Vietnam',
        specs: [const PhotoSpec(id: 'visa', name: 'Visa and ID', widthMm: 40, heightMm: 60, note: '4 x 6 cm')],
      ),
      PhotoCountry(code: 'PH', name: 'Philippines', specs: [_passport35x45()]),
      PhotoCountry(code: 'PK', name: 'Pakistan', specs: [_passport35x45()]),
      PhotoCountry(code: 'BD', name: 'Bangladesh', specs: [_passport35x45()]),
      PhotoCountry(code: 'LK', name: 'Sri Lanka', specs: [_passport35x45()]),
      PhotoCountry(code: 'NP', name: 'Nepal', specs: [_passport35x45()]),
      PhotoCountry(
        code: 'AE',
        name: 'United Arab Emirates',
        specs: [
          const PhotoSpec(id: 'visa', name: 'Visa and Emirates ID', widthMm: 43, heightMm: 55),
          _passport35x45(),
        ],
      ),
      PhotoCountry(
        code: 'SA',
        name: 'Saudi Arabia',
        specs: [
          const PhotoSpec(id: 'visa', name: 'Visa', widthMm: 40, heightMm: 60, note: '4 x 6 cm'),
          _passport35x45(),
        ],
      ),
      PhotoCountry(code: 'QA', name: 'Qatar', specs: [_passport35x45()]),
      PhotoCountry(
        code: 'EG',
        name: 'Egypt',
        specs: [const PhotoSpec(id: 'passport', name: 'Passport', widthMm: 40, heightMm: 60, note: '4 x 6 cm')],
      ),
      PhotoCountry(code: 'ZA', name: 'South Africa', specs: [_passport35x45()]),
      PhotoCountry(code: 'NG', name: 'Nigeria', specs: [_passport35x45()]),
      PhotoCountry(code: 'KE', name: 'Kenya', specs: [_passport35x45()]),
      PhotoCountry(
        code: 'BR',
        name: 'Brazil',
        specs: [const PhotoSpec(id: 'passport', name: 'Passport', widthMm: 50, heightMm: 70, note: '5 x 7 cm')],
      ),
      PhotoCountry(code: 'MX', name: 'Mexico', specs: [_passport35x45()]),
    ]..sort((a, b) => a.name.compareTo(b.name)),
  );

  static PhotoCountry? byCode(String code) {
    for (final c in countries) {
      if (c.code == code) return c;
    }
    return null;
  }

  static List<PhotoCountry> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return countries;
    return [
      for (final c in countries)
        if (c.name.toLowerCase().contains(q) || c.code.toLowerCase() == q) c,
    ];
  }

  static const defaultCountryCode = 'IN';

  /// The standard 35 x 45 mm passport size, used when nothing else is known.
  static PhotoSpec get fallback => _icao;
}

/// Background colours that photo rules usually ask for.
enum PhotoBackground {
  white('White', 0xFFFFFFFF),
  offWhite('Off-white', 0xFFF2F2F2),
  lightGrey('Light grey', 0xFFD9D9D9),
  lightBlue('Light blue', 0xFFB9D9EB),
  blue('Blue', 0xFF2F6FB5),
  red('Red', 0xFFC8102E);

  const PhotoBackground(this.label, this.argb);
  final String label;
  final int argb;
}

/// Paper for the printable sheet of repeated photos.
enum SheetPaper {
  photo4x6('4 x 6 in photo paper', 101.6, 152.4),
  photo5x7('5 x 7 in photo paper', 127, 177.8),
  a4('A4', 210, 297),
  letter('Letter', 215.9, 279.4);

  const SheetPaper(this.label, this.widthMm, this.heightMm);
  final String label;
  final double widthMm;
  final double heightMm;
}

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/cv.dart';

/// The colours of one area of the page: the main column, or a coloured side column.
class _Tone {
  const _Tone({
    required this.text,
    required this.muted,
    required this.head,
    required this.rule,
    required this.chipBg,
    required this.chipFg,
    required this.track,
    required this.fill,
  });
  final PdfColor text;
  final PdfColor muted;
  final PdfColor head;
  final PdfColor rule;
  final PdfColor chipBg;
  final PdfColor chipFg;
  final PdfColor track;
  final PdfColor fill;
}

/// Makes a CV as a PDF in one of the designs of [cvDesigns]. The designs differ in layout, header, headings, entries, skills,
/// photo and colour; the words and the content are the same in all. It is not the official Europass document and carries no Europass logo.
Future<Uint8List> buildCvPdf(
  CvData d, {
  required Future<Uint8List> Function(String asset) loadAsset,
  Uint8List? photo,
  PdfPageFormat format = PdfPageFormat.a4,
}) async {
  final regular = pw.Font.ttf((await loadAsset('assets/fonts/Roboto-Regular.ttf')).buffer.asByteData());
  final bold = pw.Font.ttf((await loadAsset('assets/fonts/Roboto-Bold.ttf')).buffer.asByteData());
  final l = CvLabels.of(d.language);
  final design = cvDesignOf(d.template);
  final accentInt = effectiveAccent(design, d.accent);
  final accent = PdfColor.fromInt(accentInt);
  final soft = PdfColor.fromInt(tintOf(accentInt, 0.88));
  final line = PdfColor.fromInt(tintOf(accentInt, 0.6));
  final deep = PdfColor.fromInt(shadeOf(accentInt, 0.35));
  const ink = PdfColor.fromInt(0xFF0F172A);
  const grey = PdfColor.fromInt(0xFF64748B);
  const white = PdfColors.white;
  final base = design.baseSize;

  final main = _Tone(text: ink, muted: grey, head: accent, rule: accent, chipBg: soft, chipFg: deep, track: const PdfColor.fromInt(0xFFE2E8F0), fill: accent);
  final side = switch (design.sidebar) {
    CvSidebar.accent => _Tone(
      text: white,
      muted: PdfColor.fromInt(tintOf(accentInt, 0.8)),
      head: white,
      rule: PdfColor.fromInt(tintOf(accentInt, 0.5)),
      chipBg: PdfColor.fromInt(shadeOf(accentInt, 0.2)),
      chipFg: white,
      track: PdfColor.fromInt(shadeOf(accentInt, 0.25)),
      fill: white,
    ),
    CvSidebar.dark => _Tone(
      text: white,
      muted: const PdfColor.fromInt(0xFFCBD5E1),
      head: PdfColor.fromInt(tintOf(accentInt, 0.4)),
      rule: const PdfColor.fromInt(0xFF475569),
      chipBg: const PdfColor.fromInt(0xFF374151),
      chipFg: white,
      track: const PdfColor.fromInt(0xFF4B5563),
      fill: PdfColor.fromInt(tintOf(accentInt, 0.3)),
    ),
    CvSidebar.tint => _Tone(text: ink, muted: grey, head: accent, rule: line, chipBg: white, chipFg: deep, track: white, fill: accent),
  };
  final sideBg = switch (design.sidebar) {
    CvSidebar.accent => accent,
    CvSidebar.dark => const PdfColor.fromInt(0xFF1F2937),
    CvSidebar.tint => PdfColor.fromInt(tintOf(accentInt, 0.9)),
  };

  pw.TextStyle ts(double size, PdfColor color, {bool strong = false, double? spacing, double? lineSpacing}) =>
      pw.TextStyle(font: strong ? bold : regular, fontSize: size, color: color, letterSpacing: spacing, lineSpacing: lineSpacing);

  pw.Widget heading(String text, _Tone t, {bool onSide = false}) {
    final style = onSide && design.heading != CvHeading.bar ? CvHeading.underline : design.heading;
    switch (style) {
      case CvHeading.underline:
        return pw.Container(
          margin: const pw.EdgeInsets.only(top: 14, bottom: 6),
          padding: const pw.EdgeInsets.only(bottom: 3),
          decoration: pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: t.rule, width: 1)),
          ),
          child: pw.Text(text.toUpperCase(), style: ts(base, t.head, strong: true, spacing: 0.6)),
        );
      case CvHeading.caps:
        return pw.Container(
          margin: const pw.EdgeInsets.only(top: 14, bottom: 5),
          padding: const pw.EdgeInsets.only(bottom: 2),
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: PdfColor.fromInt(0xFFCBD5E1), width: 0.6)),
          ),
          child: pw.Text(text.toUpperCase(), style: ts(base, t.text, strong: true, spacing: 1.2)),
        );
      case CvHeading.bar:
        return pw.Padding(
          padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
          child: pw.Row(
            children: [
              pw.Container(width: 3, height: base + 4, color: onSide ? t.head : accent),
              pw.SizedBox(width: 6),
              pw.Expanded(child: pw.Text(text.toUpperCase(), style: ts(base + 1, t.head, strong: true, spacing: 0.6))),
            ],
          ),
        );
      case CvHeading.pill:
        return pw.Padding(
          padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
          child: pw.Align(
            alignment: pw.Alignment.centerLeft,
            child: pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: pw.BoxDecoration(color: accent, borderRadius: pw.BorderRadius.circular(9)),
              child: pw.Text(text.toUpperCase(), style: ts(base - 0.5, white, strong: true, spacing: 0.6)),
            ),
          ),
        );
      case CvHeading.boxed:
        return pw.Container(
          width: double.infinity,
          margin: const pw.EdgeInsets.only(top: 12, bottom: 6),
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          color: soft,
          child: pw.Text(text.toUpperCase(), style: ts(base, accent, strong: true, spacing: 0.6)),
        );
      case CvHeading.plain:
        return pw.Container(
          margin: const pw.EdgeInsets.only(top: 14, bottom: 5),
          padding: const pw.EdgeInsets.only(bottom: 2),
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: PdfColor.fromInt(0xFFCBD5E1), width: 0.6)),
          ),
          child: pw.Text(text, style: ts(base + 1.5, t.text, strong: true)),
        );
    }
  }

  pw.Widget fact(String label, String value, _Tone t) => value.trim().isEmpty
      ? pw.SizedBox()
      : pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 4),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (label.isNotEmpty) pw.Text(label, style: ts(base - 2, t.muted)),
              pw.Text(value, style: ts(base, t.text)),
            ],
          ),
        );

  String dateRange(CvEntry e) =>
      [e.from.trim(), if (e.to.trim().isNotEmpty) e.to.trim() else if (e.from.trim().isNotEmpty) l['present']].where((s) => s.isNotEmpty).join(' \u2013 ');

  String whoOf(CvEntry e) => [e.organisation.trim(), e.place.trim()].where((s) => s.isNotEmpty).join(', ');

  pw.Widget entry(CvEntry e, {double dateWidth = 62}) {
    final dates = dateRange(e), who = whoOf(e);
    pw.Widget body() => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (design.entries == CvEntries.inline)
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: pw.Text(e.title.trim(), style: ts(base + 1, ink, strong: true))),
              if (dates.isNotEmpty)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(left: 8),
                  child: pw.Text(dates, style: ts(base - 1, grey)),
                ),
            ],
          )
        else ...[
          if (design.entries == CvEntries.timeline && dates.isNotEmpty) pw.Text(dates, style: ts(base - 1, accent, strong: true)),
          if (e.title.trim().isNotEmpty) pw.Text(e.title.trim(), style: ts(base + 1, ink, strong: true)),
        ],
        if (who.isNotEmpty) pw.Text(who, style: ts(base, grey)),
        if (e.description.trim().isNotEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 2),
            child: pw.Text(e.description.trim(), style: ts(base, ink, lineSpacing: 1.5)),
          ),
      ],
    );
    switch (design.entries) {
      case CvEntries.dateLeft:
        return pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 9),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(
                width: dateWidth,
                child: pw.Text(dates, style: ts(base - 1, grey)),
              ),
              pw.Expanded(child: body()),
            ],
          ),
        );
      case CvEntries.inline:
        return pw.Padding(padding: const pw.EdgeInsets.only(bottom: 8), child: body());
      case CvEntries.timeline:
        return pw.Padding(
          padding: const pw.EdgeInsets.only(left: 4),
          child: pw.Container(
            decoration: pw.BoxDecoration(
              border: pw.Border(left: pw.BorderSide(color: line, width: 1.2)),
            ),
            padding: const pw.EdgeInsets.only(left: 12, bottom: 9),
            child: pw.Stack(
              overflow: pw.Overflow.visible,
              children: [
                body(),
                pw.Positioned(
                  left: -15.5,
                  top: 2,
                  child: pw.Container(
                    width: 7,
                    height: 7,
                    decoration: pw.BoxDecoration(color: accent, shape: pw.BoxShape.circle),
                  ),
                ),
              ],
            ),
          ),
        );
    }
  }

  final spoken = d.languages.where((x) => x.name.trim().isNotEmpty).toList();
  String levelText(CvLanguage x) => x.level == 'Native' ? l['native'] : x.level;

  pw.Widget languageRow(CvLanguage x, _Tone t, {double? width}) {
    final inner = design.levelBars
        ? pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(child: pw.Text(x.name.trim(), style: ts(base, t.text))),
                  pw.Text(levelText(x), style: ts(base - 0.5, t.muted)),
                ],
              ),
              pw.SizedBox(height: 2),
              pw.Row(
                children: [
                  pw.Expanded(
                    flex: (levelFraction(x.level) * 100).round(),
                    child: pw.Container(height: 3.5, color: t.fill),
                  ),
                  if (levelFraction(x.level) < 1)
                    pw.Expanded(
                      flex: 100 - (levelFraction(x.level) * 100).round(),
                      child: pw.Container(height: 3.5, color: t.track),
                    ),
                ],
              ),
            ],
          )
        : pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Expanded(child: pw.Text(x.name.trim(), style: ts(base, t.text))),
              pw.Text(levelText(x), style: ts(base - 0.5, t.head == white ? white : accent, strong: true)),
            ],
          );
    final padded = pw.Padding(padding: const pw.EdgeInsets.only(bottom: 5), child: inner);
    return width == null ? padded : pw.SizedBox(width: width, child: padded);
  }

  pw.Widget skillChips(_Tone t) => pw.Wrap(
    spacing: 4,
    runSpacing: 4,
    children: [
      for (final s in d.skills)
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
          decoration: pw.BoxDecoration(color: t.chipBg, borderRadius: pw.BorderRadius.circular(8)),
          child: pw.Text(s, style: ts(base - 1, t.chipFg)),
        ),
    ],
  );

  pw.Widget skillBody(_Tone t, {CvSkills? style}) {
    switch (style ?? design.skills) {
      case CvSkills.chips:
        return skillChips(t);
      case CvSkills.inline:
        return pw.Text(d.skills.join(',  '), style: ts(base, t.text, lineSpacing: 1.5));
      case CvSkills.bullets:
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            for (final s in d.skills)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 2),
                child: pw.Text('\u2022 $s', style: ts(base, t.text)),
              ),
          ],
        );
    }
  }

  final contact = [d.email.trim(), d.phone.trim(), d.address.trim(), d.website.trim()].where((s) => s.isNotEmpty).toList();
  final personal = [
    if (design.personal && d.birthDate.trim().isNotEmpty) '${l['born']}: ${d.birthDate.trim()}',
    if (design.personal && d.nationality.trim().isNotEmpty) '${l['nationality']}: ${d.nationality.trim()}',
  ];
  final headline = d.headline.trim();
  final name = d.name.trim();

  pw.Widget? photoWidget({double size = 96}) {
    if (photo == null || !design.hasPhoto) return null;
    final image = pw.SizedBox(
      width: size,
      height: design.photo == CvPhoto.rounded ? size * 1.12 : size,
      child: pw.Image(pw.MemoryImage(photo), fit: pw.BoxFit.cover),
    );
    return design.photo == CvPhoto.circle ? pw.ClipOval(child: image) : pw.ClipRRect(horizontalRadius: 8, verticalRadius: 8, child: image);
  }

  final photoInColumn = design.layout == CvLayout.twoColumn && design.header == CvHeader.plain;

  pw.Widget withPhoto(pw.Widget text, {double size = 96, pw.Widget Function(pw.Widget)? frame}) {
    final p = photoInColumn ? null : photoWidget(size: size);
    if (p == null) return text;
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Expanded(child: text),
        pw.Padding(padding: const pw.EdgeInsets.only(left: 12), child: frame == null ? p : frame(p)),
      ],
    );
  }

  pw.Widget header() {
    switch (design.header) {
      case CvHeader.plain:
        return withPhoto(
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(name, style: ts(design.baseSize < 9 ? 21 : 24, ink, strong: true)),
              if (headline.isNotEmpty) pw.Text(headline, style: ts(12, accent)),
              pw.SizedBox(height: 6),
              if (design.layout != CvLayout.table && contact.isNotEmpty) pw.Text(contact.join('   \u00B7   '), style: ts(base, grey)),
              if (design.layout == CvLayout.single && personal.isNotEmpty) pw.Text(personal.join('   \u00B7   '), style: ts(base, grey)),
            ],
          ),
        );
      case CvHeader.centered:
        final p = photoInColumn ? null : photoWidget(size: 72);
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            if (p != null) pw.Padding(padding: const pw.EdgeInsets.only(bottom: 8), child: p),
            pw.Text(name, style: ts(24, ink, strong: true), textAlign: pw.TextAlign.center),
            if (headline.isNotEmpty) pw.Text(headline, style: ts(12, accent), textAlign: pw.TextAlign.center),
            pw.SizedBox(height: 6),
            if (contact.isNotEmpty) pw.Text(contact.join('   \u00B7   '), style: ts(base, grey), textAlign: pw.TextAlign.center),
            if (design.layout == CvLayout.single && personal.isNotEmpty)
              pw.Text(personal.join('   \u00B7   '), style: ts(base, grey), textAlign: pw.TextAlign.center),
            pw.Container(margin: const pw.EdgeInsets.only(top: 8), height: 1, color: accent),
          ],
        );
      case CvHeader.band:
        return pw.Container(
          color: accent,
          padding: const pw.EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: withPhoto(
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(name, style: ts(24, white, strong: true)),
                if (headline.isNotEmpty) pw.Text(headline, style: ts(12, white)),
                if (contact.isNotEmpty)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 6),
                    child: pw.Text(contact.join('   \u00B7   '), style: ts(9, white)),
                  ),
                if (design.layout == CvLayout.single && personal.isNotEmpty) pw.Text(personal.join('   \u00B7   '), style: ts(9, white)),
              ],
            ),
          ),
        );
      case CvHeader.banner:
        return pw.Column(
          children: [
            pw.Container(
              color: accent,
              padding: const pw.EdgeInsets.fromLTRB(20, 22, 20, 22),
              child: withPhoto(
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(name, style: ts(28, white, strong: true)),
                    if (headline.isNotEmpty) pw.Text(headline, style: ts(13, PdfColor.fromInt(tintOf(accentInt, 0.8)))),
                    pw.SizedBox(height: 8),
                    if (contact.isNotEmpty) pw.Text(contact.join('   \u00B7   '), style: ts(9, white)),
                    if (design.layout == CvLayout.single && personal.isNotEmpty) pw.Text(personal.join('   \u00B7   '), style: ts(9, white)),
                  ],
                ),
                size: 88,
                frame: (p) => pw.Container(
                  padding: const pw.EdgeInsets.all(2.5),
                  decoration: pw.BoxDecoration(color: white, borderRadius: pw.BorderRadius.circular(10)),
                  child: p,
                ),
              ),
            ),
            pw.Container(height: 5, color: deep),
          ],
        );
      case CvHeader.twoTone:
        return pw.Column(
          children: [
            pw.Container(
              color: accent,
              padding: const pw.EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: withPhoto(
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(name, style: ts(24, white, strong: true)),
                    if (headline.isNotEmpty) pw.Text(headline, style: ts(12, PdfColor.fromInt(tintOf(accentInt, 0.8)))),
                  ],
                ),
                size: 72,
              ),
            ),
            if (contact.isNotEmpty)
              pw.Container(
                width: double.infinity,
                color: deep,
                padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: pw.Text(contact.join('   \u00B7   '), style: ts(9, white)),
              ),
          ],
        );
      case CvHeader.bigName:
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            withPhoto(
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(name, style: ts(34, accent, strong: true)),
                  if (headline.isNotEmpty) pw.Text(headline, style: ts(13, ink, spacing: 0.4)),
                ],
              ),
              size: 80,
            ),
            pw.Container(margin: const pw.EdgeInsets.only(top: 8, bottom: 6), height: 5, color: accent),
            if (contact.isNotEmpty) pw.Text(contact.join('   \u00B7   '), style: ts(base, grey)),
            if (design.layout == CvLayout.single && personal.isNotEmpty) pw.Text(personal.join('   \u00B7   '), style: ts(base, grey)),
          ],
        );
    }
  }

  List<pw.Widget> profile() => [
    if (d.summary.trim().isNotEmpty) ...[heading(l['profile'], main), pw.Text(d.summary.trim(), style: ts(base, ink, lineSpacing: 1.5))],
  ];

  List<pw.Widget> sectionOf(String title, List<CvEntry> list, {double dateWidth = 62}) {
    final used = list.where((e) => !e.isEmpty).toList();
    return used.isEmpty ? [] : [heading(title, main), for (final e in used) entry(e, dateWidth: dateWidth)];
  }

  List<pw.Widget> work({double dateWidth = 62}) => sectionOf(l['work'], d.work, dateWidth: dateWidth);
  List<pw.Widget> education({double dateWidth = 62}) => sectionOf(l['education'], d.education, dateWidth: dateWidth);

  List<pw.Widget> skillsSection(_Tone t, {bool onSide = false, CvSkills? style}) =>
      d.skills.isEmpty ? [] : [heading(l['skills'], t, onSide: onSide), skillBody(t, style: style)];

  List<pw.Widget> languagesSection(_Tone t, {bool onSide = false}) {
    if (spoken.isEmpty) return [];
    return [
      heading(l['languages'], t, onSide: onSide),
      if (design.levelBars && !onSide && design.layout == CvLayout.single)
        pw.Wrap(spacing: 16, children: [for (final x in spoken) languageRow(x, t, width: 160)])
      else if (design.levelBars || onSide || design.layout == CvLayout.twoColumn)
        for (final x in spoken) languageRow(x, t)
      else
        pw.Text(spoken.map((x) => '${x.name.trim()} (${levelText(x)})').join(',  '), style: ts(base, t.text, lineSpacing: 1.5)),
    ];
  }

  List<pw.Widget> facts(_Tone t, {bool onSide = false}) => [
    heading(l['personal'], t, onSide: onSide),
    fact('Email', d.email, t),
    fact('Tel.', d.phone, t),
    fact('', d.address, t),
    fact('Web', d.website, t),
    if (design.personal) ...[fact(l['born'], d.birthDate, t), fact(l['nationality'], d.nationality, t)],
  ];

  final doc = pw.Document(
    theme: pw.ThemeData.withFont(base: regular, bold: bold),
    title: '${l['cv']} ${d.name}',
    author: d.name,
    creator: 'Doculoom',
  );

  pw.Widget pageBackground(double sideWidth) => pw.FullPage(
    ignoreMargins: true,
    child: pw.Stack(
      fit: pw.StackFit.expand,
      children: [
        if (design.pageTint) pw.Positioned.fill(child: pw.Container(color: PdfColor.fromInt(tintOf(accentInt, 0.94)))),
        if (design.isSidebar)
          pw.Positioned(
            left: design.layout == CvLayout.sidebarLeft ? 0 : null,
            right: design.layout == CvLayout.sidebarRight ? 0 : null,
            top: 0,
            bottom: 0,
            child: pw.Container(width: sideWidth, color: sideBg),
          ),
      ],
    ),
  );

  late final List<pw.Widget> body;
  var horizontal = design.margin;
  var sideWidth = 0.0;

  switch (design.layout) {
    case CvLayout.single:
      body = [header(), pw.SizedBox(height: 4), ...profile(), ...work(), ...education(), ...skillsSection(main), ...languagesSection(main)];
    case CvLayout.table:
      const w = 92.0;
      body = [
        header(),
        if (contact.isNotEmpty || personal.isNotEmpty) ...[
          heading(l['personal'], main),
          for (final (label, value) in [
            ('Email', d.email),
            ('Tel.', d.phone),
            (l['born'], design.personal ? d.birthDate : ''),
            (l['nationality'], design.personal ? d.nationality : ''),
            ('', d.address),
            ('Web', d.website),
          ])
            if (value.trim().isNotEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 3),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.SizedBox(
                      width: w,
                      child: pw.Text(label, style: ts(base - 1, grey)),
                    ),
                    pw.Expanded(child: pw.Text(value.trim(), style: ts(base, ink))),
                  ],
                ),
              ),
        ],
        ...profile(),
        ...work(dateWidth: w),
        ...education(dateWidth: w),
        if (spoken.isNotEmpty) ...[
          heading(l['languages'], main),
          for (final x in spoken)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 3),
              child: pw.Row(
                children: [
                  pw.SizedBox(
                    width: w,
                    child: pw.Text(x.name.trim(), style: ts(base - 1, grey)),
                  ),
                  pw.Expanded(child: pw.Text(levelText(x), style: ts(base, ink))),
                ],
              ),
            ),
        ],
        if (d.skills.isNotEmpty) ...[heading(l['skills'], main), skillBody(main)],
      ];
    case CvLayout.twoColumn:
      final p = photoInColumn ? photoWidget() : null;
      final left = <pw.Widget>[
        if (p != null) pw.Padding(padding: const pw.EdgeInsets.only(bottom: 10), child: p),
        ...facts(main),
        ...languagesSection(main),
        ...skillsSection(main),
      ];
      final right = [...profile(), ...work(), ...education()];
      final leftWidth = design.baseSize < 9 ? 132.0 : 150.0;
      body = [
        header(),
        pw.SizedBox(height: 6),
        pw.Partitions(
          children: [
            pw.Partition(
              width: leftWidth,
              child: pw.Padding(
                padding: const pw.EdgeInsets.only(right: 16),
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: left),
              ),
            ),
            pw.Partition(
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: right),
            ),
          ],
        ),
      ];
    case CvLayout.sidebarLeft || CvLayout.sidebarRight:
      horizontal = 0;
      sideWidth = 176;
      final p = photoWidget(size: 96);
      final sideColumn = <pw.Widget>[
        if (p != null)
          pw.Align(
            alignment: pw.Alignment.center,
            child: pw.Padding(padding: const pw.EdgeInsets.only(bottom: 6), child: p),
          ),
        ...facts(side, onSide: true),
        ...languagesSection(side, onSide: true),
        ...skillsSection(side, onSide: true, style: design.skills == CvSkills.chips ? CvSkills.chips : CvSkills.bullets),
      ];
      final mainColumn = <pw.Widget>[
        pw.Text(name, style: ts(26, ink, strong: true)),
        if (headline.isNotEmpty) pw.Text(headline, style: ts(12.5, accent)),
        pw.SizedBox(height: 4),
        ...profile(),
        ...work(),
        ...education(),
      ];
      final left = design.layout == CvLayout.sidebarLeft;
      final sidePart = pw.Partition(
        width: sideWidth,
        child: pw.Padding(
          padding: pw.EdgeInsets.fromLTRB(left ? 18 : 16, 0, left ? 14 : 18, 0),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: sideColumn),
        ),
      );
      final mainPart = pw.Partition(
        child: pw.Padding(
          padding: pw.EdgeInsets.fromLTRB(left ? 24 : 34, 0, left ? 34 : 24, 0),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: mainColumn),
        ),
      );
      body = [
        pw.Partitions(children: left ? [sidePart, mainPart] : [mainPart, sidePart]),
      ];
  }

  doc.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: format,
        margin: pw.EdgeInsets.fromLTRB(horizontal, 34, horizontal, 34),
        buildBackground: design.isSidebar || design.pageTint ? (c) => pageBackground(sideWidth) : null,
      ),
      build: (c) => body,
    ),
  );
  return doc.save();
}

/// A ready-made stamp: words in a frame, in one colour. `{date}` in the text is replaced by today's date when it is placed.
class Stamp {
  const Stamp(this.text, this.color);
  final String text;

  /// ARGB.
  final int color;

  bool get hasDate => text.contains('{date}');

  /// The words as they go on the page.
  String resolve(String date) => text.replaceAll('{date}', date);

  Map<String, Object?> toJson() => {'text': text, 'color': color};

  static Stamp? fromJson(Object? o) {
    if (o is! Map) return null;
    final text = o['text'];
    final color = o['color'];
    if (text is! String || text.trim().isEmpty || color is! int) return null;
    return Stamp(text, color);
  }

  @override
  bool operator ==(Object other) => other is Stamp && other.text == text && other.color == color;

  @override
  int get hashCode => Object.hash(text, color);

  /// The font size of the stamp as a share of the page width, so the longest line takes about half of the page.
  double fontSize(String resolved) {
    var longest = 1;
    for (final line in resolved.split('\n')) {
      if (line.trim().length > longest) longest = line.trim().length;
    }
    return (0.55 / (longest * 0.62 + 1.2)).clamp(0.03, 0.09);
  }
}

const stampRed = 0xFFD32F2F;
const stampBlue = 0xFF1565C0;
const stampGreen = 0xFF2E7D32;
const stampBlack = 0xFF212121;

/// The colours offered for a stamp of your own.
const stampColors = [stampRed, stampBlue, stampGreen, stampBlack];

/// How many stamps of your own are kept.
const maxCustomStamps = 20;
const maxStampLines = 3;
const maxStampLineLength = 24;

/// A group of ready-made stamps. [region] is the tool region it belongs to (`india`, `usa`, `europe`, `gulf`), empty for everyone.
class StampGroup {
  const StampGroup(this.title, this.stamps, {this.region = ''});
  final String title;
  final List<Stamp> stamps;
  final String region;
}

const stampLibrary = <StampGroup>[
  StampGroup('Everyday', [
    Stamp('PAID', stampGreen),
    Stamp('PAID\n{date}', stampGreen),
    Stamp('RECEIVED\n{date}', stampBlue),
    Stamp('APPROVED', stampGreen),
    Stamp('APPROVED\n{date}', stampGreen),
    Stamp('REJECTED', stampRed),
    Stamp('COMPLETED', stampGreen),
    Stamp('CHECKED', stampBlue),
    Stamp('SIGNED\n{date}', stampBlue),
    Stamp('DRAFT', stampRed),
    Stamp('CONFIDENTIAL', stampRed),
    Stamp('URGENT', stampRed),
    Stamp('COPY', stampBlue),
    Stamp('ORIGINAL', stampGreen),
    Stamp('VOID', stampRed),
  ]),
  StampGroup('For India', [
    Stamp('SELF ATTESTED', stampBlue),
    Stamp('SELF ATTESTED\n{date}', stampBlue),
    Stamp('TRUE COPY', stampBlue),
    Stamp('VERIFIED WITH\nORIGINAL', stampGreen),
    Stamp('FOR KYC\nPURPOSE ONLY', stampRed),
    Stamp('NOT VALID FOR\nANY OTHER PURPOSE', stampRed),
  ], region: 'india'),
  StampGroup('For the United States', [
    Stamp('FOR DEPOSIT ONLY', stampBlue),
    Stamp('COPY - NOT\nAN ORIGINAL', stampRed),
    Stamp('FILED\n{date}', stampBlue),
    Stamp('NO CHARGE', stampGreen),
  ], region: 'usa'),
  StampGroup('For Europe', [
    Stamp('COPY - FOR\nAPPLICATION ONLY', stampRed),
    Stamp('PAID IN FULL\n{date}', stampGreen),
    Stamp('RECEIVED\n{date}', stampBlue),
  ], region: 'europe'),
  StampGroup('For the Gulf', [
    Stamp('COPY - FOR\nVISA PURPOSE ONLY', stampRed),
    Stamp('COPY - FOR\nBANK USE ONLY', stampRed),
    Stamp('PAID\n{date}', stampGreen),
  ], region: 'gulf'),
  StampGroup('In other languages', [
    Stamp('\u092D\u0941\u0917\u0924\u093E\u0928 \u0939\u094B \u0917\u092F\u093E', stampGreen),
    Stamp('\u0645\u062F\u0641\u0648\u0639', stampGreen),
    Stamp('BEZAHLT', stampGreen),
    Stamp('PAY\u00C9', stampGreen),
    Stamp('PAGADO', stampGreen),
    Stamp('PAGATO', stampGreen),
    Stamp('PAGO', stampGreen),
    Stamp('BETAALD', stampGreen),
    Stamp('ZAP\u0141ACONO', stampGreen),
    Stamp('\u00D6DEND\u0130', stampGreen),
    Stamp('\u041E\u041F\u041B\u0410\u0427\u0415\u041D\u041E', stampGreen),
    Stamp('\u092A\u094D\u0930\u093E\u092A\u094D\u0924', stampBlue),
    Stamp('\u062A\u0645 \u0627\u0644\u0627\u0633\u062A\u0644\u0627\u0645', stampBlue),
    Stamp('ERHALTEN', stampBlue),
    Stamp('RE\u00C7U', stampBlue),
    Stamp('RECIBIDO', stampBlue),
    Stamp('RICEVUTO', stampBlue),
    Stamp('RECEBIDO', stampBlue),
    Stamp('ONTVANGEN', stampBlue),
    Stamp('OTRZYMANO', stampBlue),
    Stamp('ALINDI', stampBlue),
    Stamp('\u041F\u041E\u041B\u0423\u0427\u0415\u041D\u041E', stampBlue),
    Stamp('GENEHMIGT', stampGreen),
    Stamp('APPROUV\u00C9', stampGreen),
    Stamp('APROBADO', stampGreen),
    Stamp('APPROVATO', stampGreen),
    Stamp('APROVADO', stampGreen),
    Stamp('GOEDGEKEURD', stampGreen),
    Stamp('ZATWIERDZONO', stampGreen),
    Stamp('ONAYLANDI', stampGreen),
    Stamp('\u041E\u0414\u041E\u0411\u0420\u0415\u041D\u041E', stampGreen),
    Stamp('KOPIE', stampBlue),
    Stamp('COPIE', stampBlue),
    Stamp('COPIA', stampBlue),
    Stamp('C\u00D3PIA', stampBlue),
    Stamp('KOPIA', stampBlue),
    Stamp('KOPYA', stampBlue),
    Stamp('\u041A\u041E\u041F\u0418\u042F', stampBlue),
    Stamp('\u0646\u0633\u062E\u0629', stampBlue),
    Stamp('\u092A\u094D\u0930\u0924\u093F\u0932\u093F\u092A\u093F', stampBlue),
  ]),
];

/// The groups in the order to show: everyday stamps first, then the group of [region], then the rest.
List<StampGroup> orderedStampGroups(String region) {
  final first = stampLibrary.where((g) => g.region.isEmpty && g.title == 'Everyday');
  final mine = stampLibrary.where((g) => g.region.isNotEmpty && g.region == region);
  final rest = stampLibrary.where((g) => !first.contains(g) && !mine.contains(g));
  return [...first, ...mine, ...rest];
}

/// What is wrong with the words of a stamp of your own, or null when it is fine.
String? stampProblem(String text, {bool withDate = false}) {
  final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  if (lines.isEmpty) return 'Type the words for the stamp.';
  if (lines.length > maxStampLines) return 'A stamp has up to 3 lines.';
  if (withDate && lines.length == maxStampLines) return 'With the date, a stamp has up to 2 lines of words.';
  if (lines.any((l) => l.length > maxStampLineLength)) return 'Each line of a stamp has up to 24 characters.';
  return null;
}

/// The words tidied for a stamp: blank lines dropped, capitals, and the date line added when asked.
String stampText(String text, {bool withDate = false}) {
  final lines = text.split('\n').map((l) => l.trim().toUpperCase()).where((l) => l.isNotEmpty).toList();
  if (withDate && lines.length < maxStampLines) lines.add('{date}');
  return lines.join('\n');
}

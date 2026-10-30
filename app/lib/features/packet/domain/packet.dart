import '../../../core/i18n/tr.dart';

/// How large the packet file may be. Many portals refuse a file above a few megabytes.
enum PacketLimit {
  none(null, 'No limit'),
  mb1(1024 * 1024, '1 MB'),
  mb2(2 * 1024 * 1024, '2 MB'),
  mb5(5 * 1024 * 1024, '5 MB'),
  mb10(10 * 1024 * 1024, '10 MB');

  const PacketLimit(this.bytes, this.label);
  final int? bytes;
  final String label;
}

const maxPacketDocuments = 30;
const maxPacketPages = 300;
const maxPacketTitle = 60;
const maxPacketName = 60;
const maxPacketPurpose = 120;

class PacketSettings {
  const PacketSettings({this.title = '', this.name = '', this.purpose = '', this.cover = true, this.numbers = true, this.limit = PacketLimit.none});
  final String title;

  /// Whose packet it is, shown on the cover.
  final String name;

  /// What it is for, for example a visa or a loan, shown on the cover.
  final String purpose;
  final bool cover;

  /// Page numbers at the foot of every page.
  final bool numbers;
  final PacketLimit limit;

  PacketSettings copyWith({String? title, String? name, String? purpose, bool? cover, bool? numbers, PacketLimit? limit}) => PacketSettings(
    title: title ?? this.title,
    name: name ?? this.name,
    purpose: purpose ?? this.purpose,
    cover: cover ?? this.cover,
    numbers: numbers ?? this.numbers,
    limit: limit ?? this.limit,
  );
}

/// A document in the packet.
class PacketEntry {
  const PacketEntry({required this.docId, required this.title, required this.pageCount});
  final String docId;
  final String title;
  final int pageCount;
}

class PacketProblem {
  const PacketProblem(this.template, [this.values = const {}]);
  final String template;
  final Map<String, Object> values;

  String get text => trf(template, values);
}

PacketProblem? titleIssue(String title) {
  final t = title.trim();
  if (t.isEmpty) return const PacketProblem('Enter a title for the packet.');
  if (t.length > maxPacketTitle) return const PacketProblem('The title is too long (60 characters at most).');
  return null;
}

PacketProblem? nameIssue(String name) => name.trim().length > maxPacketName ? const PacketProblem('The name is too long (60 characters at most).') : null;

PacketProblem? purposeIssue(String purpose) =>
    purpose.trim().length > maxPacketPurpose ? const PacketProblem('The purpose is too long (120 characters at most).') : null;

int totalPages(List<PacketEntry> entries) => entries.fold(0, (s, e) => s + e.pageCount);

/// What stops the packet from being made, or null when it can be made.
PacketProblem? packetProblem(PacketSettings settings, List<PacketEntry> entries) {
  final t = titleIssue(settings.title) ?? nameIssue(settings.name) ?? purposeIssue(settings.purpose);
  if (t != null) return t;
  if (entries.isEmpty) return const PacketProblem('Add at least one document.');
  if (entries.length > maxPacketDocuments) return const PacketProblem('A packet has up to 30 documents.');
  if (totalPages(entries) > maxPacketPages) return const PacketProblem('A packet has up to 300 pages. Remove a document or two.');
  return null;
}

/// One line of the contents: the document and the pages it takes in the packet.
class ContentsLine {
  const ContentsLine(this.title, this.from, this.to);
  final String title;
  final int from;
  final int to;

  String get pages => from == to ? '$from' : '$from\u2013$to';
}

/// The contents of the packet. Page 1 is the cover when there is one.
List<ContentsLine> contentsLines(List<PacketEntry> entries, {required bool cover}) {
  var next = cover ? 2 : 1;
  final lines = <ContentsLine>[];
  for (final e in entries) {
    if (e.pageCount < 1) continue;
    lines.add(ContentsLine(e.title, next, next + e.pageCount - 1));
    next += e.pageCount;
  }
  return lines;
}

/// How many pages the finished file has.
int packetPageCount(List<PacketEntry> entries, {required bool cover}) => totalPages(entries) + (cover ? 1 : 0);

/// A file name that is safe on every phone: letters, digits and underscores, ending in the day.
String packetFileName(String title, DateTime now) {
  final cleaned = title.trim().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '_').replaceAll(RegExp(r'^_+|_+$'), '');
  final base = cleaned.isEmpty ? 'Packet' : (cleaned.length > 40 ? cleaned.substring(0, 40) : cleaned);
  final d = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  return '${base}_$d.pdf';
}

/// A step down in picture quality: the longest side in pixels (null keeps the stored picture as it is) and the JPEG quality.
class QualityStep {
  const QualityStep(this.maxSide, this.jpegQuality);
  final int? maxSide;
  final int jpegQuality;
}

/// From the best picture to the smallest that is still readable; the packet uses the first that fits the limit.
const qualitySteps = [
  QualityStep(null, 0),
  QualityStep(2400, 85),
  QualityStep(1800, 78),
  QualityStep(1500, 70),
  QualityStep(1200, 62),
  QualityStep(1000, 52),
  QualityStep(800, 45),
];

/// What the maker says about the size of the file it made.
String sizeLabel(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  final mb = bytes / (1024 * 1024);
  return '${mb.toStringAsFixed(mb < 10 ? 2 : 1)} MB';
}

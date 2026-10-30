import '../i18n/tr.dart';
import 'region.dart';

String _two(int n) => n.toString().padLeft(2, '0');

/// Chinese and Japanese write the year first with the characters for year, month and day.
String formatDate(DateTime d) =>
    (Strings.code == 'zh' || Strings.code == 'ja') && Region.dateStyle != DateStyle.yearFirst ? '${d.year}年${d.month}月${d.day}日' : _formatDate(d);

String _formatDate(DateTime d) => switch (Region.dateStyle) {
  DateStyle.monthFirst => '${monthName(d.month)} ${d.day}, ${d.year}',
  DateStyle.yearFirst => '${d.year}-${_two(d.month)}-${_two(d.day)}',
  _ => '${d.day} ${monthName(d.month)} ${d.year}',
};

String formatDateTime(DateTime d) => '${formatDate(d)}, ${_two(d.hour)}:${_two(d.minute)}';

String defaultScanTitle(DateTime d) => 'Scan ${d.year}-${_two(d.month)}-${_two(d.day)} ${_two(d.hour)}.${_two(d.minute)}';

/// Polish and Russian have a different word for 2 to 4 than for 5 and more.
bool _few(int n) => n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 12 || n % 100 > 14);

String pagesLabel(int n) {
  final word = switch (Strings.code) {
    'ru' => n % 10 == 1 && n % 100 != 11 ? 'страница' : (_few(n) ? 'страницы' : 'страниц'),
    'pl' => n == 1 ? 'strona' : (_few(n) ? 'strony' : 'stron'),
    _ => tr(n == 1 ? 'page' : 'pages'),
  };
  return '$n $word';
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} kB';
  final mb = kb / 1024;
  return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
}

/// "Jan 2026" for "2026-01"; the text itself when it is not a month.
String monthYearLabel(String key) {
  final parts = key.split('-');
  final month = parts.length == 2 ? int.tryParse(parts[1]) : null;
  if (month == null || month < 1 || month > 12) return key;
  if (Strings.code == 'zh' || Strings.code == 'ja') return '${parts[0]}年$month月';
  return '${monthName(month)} ${parts[0]}';
}

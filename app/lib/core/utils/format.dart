const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _two(int n) => n.toString().padLeft(2, '0');

String formatDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

String formatDateTime(DateTime d) => '${formatDate(d)}, ${_two(d.hour)}:${_two(d.minute)}';

String defaultScanTitle(DateTime d) => 'Scan ${d.year}-${_two(d.month)}-${_two(d.day)} ${_two(d.hour)}.${_two(d.minute)}';

String pagesLabel(int n) => n == 1 ? '1 page' : '$n pages';

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} kB';
  final mb = kb / 1024;
  return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
}

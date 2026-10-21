const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _two(int n) => n.toString().padLeft(2, '0');

String formatDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

String formatDateTime(DateTime d) => '${formatDate(d)}, ${_two(d.hour)}:${_two(d.minute)}';

String defaultScanTitle(DateTime d) => 'Scan ${d.year}-${_two(d.month)}-${_two(d.day)} ${_two(d.hour)}.${_two(d.minute)}';

String pagesLabel(int n) => n == 1 ? '1 page' : '$n pages';

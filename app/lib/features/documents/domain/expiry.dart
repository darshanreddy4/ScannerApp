import '../../../core/utils/format.dart';
import 'entities/scanned_document.dart';

/// Documents that end within this many days are shown as "soon".
const expirySoonDays = 60;

enum ExpiryState { expired, soon, later }

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Whole calendar days from [now] to [expires]; negative once it has passed.
int daysUntil(DateTime expires, DateTime now) =>
    DateTime.utc(expires.year, expires.month, expires.day).difference(DateTime.utc(now.year, now.month, now.day)).inDays;

ExpiryState expiryState(DateTime expires, DateTime now) {
  final days = daysUntil(expires, now);
  if (days < 0) return ExpiryState.expired;
  return days <= expirySoonDays ? ExpiryState.soon : ExpiryState.later;
}

String expiryLabel(DateTime expires, DateTime now) {
  final days = daysUntil(expires, now);
  if (days < -1) return 'Expired ${-days} days ago';
  if (days == -1) return 'Expired yesterday';
  if (days == 0) return 'Expires today';
  if (days == 1) return 'Expires tomorrow';
  if (days <= 90) return 'Expires in $days days';
  return 'Expires ${formatDate(_day(expires))}';
}

/// The documents that are over or about to end, soonest first.
List<ScannedDocument> expiringDocuments(Iterable<ScannedDocument> documents, DateTime now) {
  final list = [
    for (final d in documents)
      if (d.expiresAt != null && expiryState(d.expiresAt!, now) != ExpiryState.later) d,
  ]..sort((a, b) => a.expiresAt!.compareTo(b.expiresAt!));
  return list;
}

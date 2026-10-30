import 'package:flutter/material.dart' hide Text;

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../domain/entities/scanned_document.dart';
import '../../domain/expiry.dart';
import '../../../../core/widgets/text.dart';

const expiredColor = Color(0xFFC62828);
const soonColor = Color(0xFFB26A00);

Color expiryColor(ExpiryState s) => switch (s) {
  ExpiryState.expired => expiredColor,
  ExpiryState.soon => soonColor,
  ExpiryState.later => AppColors.inkMuted,
};

/// A small label with when a document ends, coloured by how close that is.
class ExpiryChip extends StatelessWidget {
  const ExpiryChip({super.key, required this.expires, DateTime? now}) : _now = now;
  final DateTime expires;
  final DateTime? _now;

  @override
  Widget build(BuildContext context) {
    final now = _now ?? DateTime.now();
    final color = expiryColor(expiryState(expires, now));
    return Container(
      key: const ValueKey('expiry-chip'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(AppIcons.timer, size: 12, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              expiryLabel(expires, now),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// On the Documents screen: documents that have ended or end soon, so a passport or policy is not forgotten.
class ExpiringBanner extends StatelessWidget {
  const ExpiringBanner({super.key, required this.documents, required this.onOpen, DateTime? now}) : _now = now;
  final List<ScannedDocument> documents;
  final void Function(ScannedDocument) onOpen;
  final DateTime? _now;

  @override
  Widget build(BuildContext context) {
    final now = _now ?? DateTime.now();
    final list = expiringDocuments(documents, now);
    if (list.isEmpty) return const SizedBox.shrink();
    final worst = expiryState(list.first.expiresAt!, now);
    final color = expiryColor(worst);
    final shown = list.take(3).toList();
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
      child: Container(
        key: const ValueKey('expiring-banner'),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md, 10, AppSpacing.md, 2),
              child: Row(
                children: [
                  Icon(AppIcons.timer, size: 16, color: color),
                  const SizedBox(width: 6),
                  Text(
                    worst == ExpiryState.expired ? 'Needs attention' : 'Ending soon',
                    style: TextStyle(fontWeight: FontWeight.w700, color: color),
                  ),
                ],
              ),
            ),
            for (final d in shown)
              InkWell(
                key: ValueKey('expiring-${d.id}'),
                onTap: () => onOpen(d),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          d.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        expiryLabel(d.expiresAt!, now),
                        style: TextStyle(fontSize: 12, color: expiryColor(expiryState(d.expiresAt!, now)), fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            if (list.length > shown.length)
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md, 0, AppSpacing.md, 2),
                child: Text('and ${list.length - shown.length} more', style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

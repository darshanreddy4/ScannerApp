import 'package:flutter/material.dart' hide Text;

import '../../../app/di.dart';
import '../../../core/widgets/text.dart';
import '../../monetization/domain/repositories/monetization_contracts.dart';

/// Explains that videos cannot play because ads are off by the person's own privacy choice, and offers the consent screen.
/// Returns true when the person went to the consent screen, so the caller may offer the video again.
Future<bool> showConsentNeeded(BuildContext context) async {
  final open = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Ad consent needed'),
      content: const Text(
        'Videos are paid for by ads, and ads are turned off by your privacy choice. Change your choice to earn coins from videos, or use the coins you already have.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(key: const ValueKey('consent-open'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Ad choices')),
      ],
    ),
  );
  if (open != true) return false;
  await sl<AdService>().showPrivacyOptions();
  return true;
}

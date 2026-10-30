import 'package:flutter/material.dart' hide Text;
import 'package:url_launcher/url_launcher.dart';

import '../../../app/app_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/text.dart';

/// In-app terms. Have a lawyer review them for your country and business before publishing.
class TermsPage extends StatelessWidget {
  const TermsPage({super.key});

  static const _sections = <(String, String)>[
    ('1. Agreement', 'By installing or using Doculoom you agree to these terms and to the Privacy Policy. If you do not agree, please do not use the app.'),
    (
      '2. What the app does',
      'Doculoom lets you scan, import, edit, organise, print, share and lock documents on your phone. Everything is processed and stored on your device.',
    ),
    (
      '3. Your content',
      'You own your documents. You are responsible for what you scan, store and share, and you promise to have the right to do so. '
          'Do not use the app to copy or distribute material you are not allowed to copy, to break the law, or to infringe the rights of others.',
    ),
    (
      '4. Your device and your data',
      'Your documents are kept only on your phone. If you uninstall the app, clear its data, use "Delete all my data", or lose or reset your phone, '
          'they are gone and we cannot recover them. Keep your own backups of anything important. '
          'Locking relies on your phone\'s screen lock, so keep that secure.',
    ),
    (
      '5. Ads',
      'The free app shows ads provided by Google AdMob. Ads are shown by a third party; we do not control their content. '
          'Please do not click ads in order to inflate our earnings.',
    ),
    (
      '6. Licence',
      'We give you a personal, non-exclusive, non-transferable licence to use the app on your own devices. '
          'You may not copy, modify, reverse engineer or resell the app, except where the law allows it. The app and its design remain our property. '
          'Open-source components are used under their own licences (see Settings > About > Open-source licences).',
    ),
    (
      '7. Printing and sharing',
      'Printing and sharing use your phone\'s system screens and third-party apps or printers. We are not responsible for what those services do with a file you send them, '
          'or for printer settings, paper or ink.',
    ),
    (
      '8. Sharing over the internet',
      'The optional "Anywhere" QR sharing uploads an encrypted copy of one file to our sharing service so someone on another network can download it. Files are limited in size and are deleted when the link expires (at most 7 days) or when you stop sharing. '
          'Anyone who has the full link can download the file, so you are responsible for who you give it to. Do not use the service to share illegal or harmful material or material you have no right to share; we may remove files or block abuse. '
          'The service is provided without any promise that it will always be available, and a file may be unavailable before it expires.',
    ),
    (
      '9. Coins and rewarded videos',
      'Free users can watch a short video to earn coins and spend them on features such as editing saved pages or sharing with a QR code. Coins are a convenience, not money: they have no cash value, cannot be sold, transferred or refunded, '
          'and are stored only on your phone, so they are lost if you uninstall the app or clear its data. A video must be watched to the end to earn coins, and there is a daily limit. '
          'Do not use tricks, automation or modified apps to get coins. We may change prices, rewards and limits, and we may reset coins that were obtained unfairly.',
    ),
    (
      '10. No warranty',
      'The app is provided "as is" and "as available". Scans, text layout, colours, imports of PDF and Word files, and print results may differ from the original. '
          'Check important documents (contracts, IDs, legal or financial papers) before relying on a copy.',
    ),
    (
      '11. Limit of liability',
      'To the fullest extent the law allows, we are not liable for lost data, lost profit, or indirect or consequential damage arising from use of the app. '
          'Nothing in these terms limits liability that cannot be limited by law, including your rights as a consumer.',
    ),
    (
      '12. Changes and ending',
      'We may update the app and these terms. If a change matters, we will tell you in the app. Continuing to use the app after a change means you accept it. '
          'You can stop using the app at any time by uninstalling it. We may stop offering it at any time.',
    ),
    ('13. Contact', 'Questions about these terms: use Settings > About > Help and support.'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Terms and conditions')),
      body: ListView(
        padding: contentPadding(context),
        children: [
          for (final (title, body) in _sections) ...[
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(body, style: const TextStyle(color: AppColors.inkMuted, height: 1.4)),
            const SizedBox(height: AppSpacing.md),
          ],
          if (AppConfig.supportEmail.isNotEmpty) SelectableText(AppConfig.supportEmail, style: const TextStyle(color: AppColors.primary)),
          if (AppConfig.termsUrl.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: OutlinedButton.icon(
                onPressed: () => launchUrl(Uri.parse(AppConfig.termsUrl), mode: LaunchMode.externalApplication),
                icon: const Icon(AppIcons.link, size: 18),
                label: const Text('Open online version'),
              ),
            ),
        ],
      ),
    );
  }
}

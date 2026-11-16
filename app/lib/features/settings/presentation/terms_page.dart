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
      'Doculoom lets you scan, import, edit, organise, print, share and lock documents on your phone, and gives you tools to translate text, make invoices, CVs, application packets and safe ID copies, keep loyalty cards and checklists, and convert Hijri dates. '
          'Your documents and what you make with the tools are processed and stored on your device. The exceptions are ads and the optional internet sharing, which are described in the Privacy Policy.',
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
      'The free app shows ads provided by Google AdMob, including rewarded videos that you choose to watch. Ads are shown by a third party; we do not control their content. '
          'Please do not click ads in order to inflate our earnings. Ads are turned off while a pass is active.',
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
      '9. Coins, passes and rewarded videos',
      'Free users can watch a short video to earn coins, receive a small number of free coins each day, and spend them on tools. By watching enough videos you can also earn a pass, which opens every tool and turns ads off for a set time. '
          'Coins and passes are a convenience, not money: they have no cash value, cannot be sold, transferred or refunded, and a pass ends when its time runs out. '
          'They are stored only on your phone, so they are lost if you uninstall the app or clear its storage; "Delete all my data" does not remove them. A video must be watched to the end to count, and there is a daily limit. '
          'Videos need an internet connection and your consent to ads where the law requires it. '
          'Do not use tricks, automation or modified apps to get coins or passes. We may change prices, rewards, pass lengths and limits, and we may reset coins or passes that were obtained unfairly.',
    ),
    (
      '10. Invoices, tax and calendar tools',
      'The GST, Saudi VAT, US invoice and receipt tools work out amounts from the rates and details you enter and make a PDF on your phone. They are a convenience, not tax, legal or accounting advice. '
          'Rates change and differ by place, so you are responsible for the rates, numbers and amounts on every invoice and for following the tax rules that apply to you. '
          'These tools do not connect to any tax authority or government portal and do not register, report or file anything for you. An invoice made here is not an e-invoice with an IRN, and the Saudi invoice covers only the first phase of e-invoicing and is not an approved ZATCA system. '
          'Hijri dates follow the Umm al-Qura calendar. Where the new moon is sighted a month can start a day or two later, so check the date before you rely on it for prayer, fasting, Eid or any legal purpose.',
    ),
    (
      '11. IDs, cards and signatures',
      'Only copy, cover or share an ID, card or other document that you are entitled to copy and share, and only for a lawful purpose. Do not use the app to forge, alter or misuse a document or to pretend to be someone else. '
          'A safe ID copy hides only what you or the app cover: look at the copy yourself before you hand it over, because we cannot promise that everything sensitive is covered. '
          'A picture of a signature is not a certified digital signature and may not be accepted for some legal documents. '
          'Loyalty card barcodes may not scan at every till, and a card note is not protected, so do not write a PIN or password in it.',
    ),
    (
      '12. Reminders, text reading and translation',
      'Reminders depend on the phone\'s own alarm and battery settings. Some phones stop apps in the background, so a reminder can be late or missing; check the battery steps under "Reminders not arriving?" in the app, and do not rely on a reminder alone for a deadline that matters. '
          'Text reading (OCR) and translation are done by machine and can contain mistakes. Check the result, and have important text translated or checked by a qualified person. '
          'Some translations of the app itself may also contain mistakes.',
    ),
    (
      '13. No warranty',
      'The app is provided "as is" and "as available". Scans, text layout, colours, imports of PDF and Word files, and print results may differ from the original. '
          'Check important documents (contracts, IDs, legal or financial papers) before relying on a copy.',
    ),
    (
      '14. Limit of liability',
      'To the fullest extent the law allows, we are not liable for lost data, lost profit, a missed reminder, a wrong tax amount, or indirect or consequential damage arising from use of the app. '
          'Nothing in these terms limits liability that cannot be limited by law, including your rights as a consumer.',
    ),
    (
      '15. Governing law',
      'These terms are governed by the laws of India, and the courts in Karnataka, India, can settle disputes about them, but this does not take away any right you have under the mandatory consumer laws of the place where you live.',
    ),
    (
      '16. Changes and ending',
      'We may update the app and these terms. If a change matters, we will tell you in the app. Continuing to use the app after a change means you accept it. '
          'You can stop using the app at any time by uninstalling it. We may stop offering it at any time.',
    ),
    (
      '17. Contact',
      'Doculoom is published by darshandmg (Darshan M G), Ranibennur, Karnataka, India. Questions about these terms: use Settings > About > Help and support, or write to the email address below.',
    ),
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

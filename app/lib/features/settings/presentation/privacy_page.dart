import 'package:flutter/material.dart' hide Text;
import 'package:url_launcher/url_launcher.dart';

import '../../../app/app_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/text.dart';

/// Plain-language privacy policy shown inside the app. Keep it in step with the Play Console
/// Data safety form and the public policy page (see README).
class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  static const _sections = <(String, String)>[
    (
      'Your documents stay on your phone',
      'Scans, imported files, page images and anything you create are stored only in this app\'s private storage on your device. '
          'There is no account or sign-in, and we cannot see your documents. The one exception is the optional "Anywhere" QR sharing described below.',
    ),
    (
      'What the app can access',
      'Camera: only while the scanner is open, to photograph documents.\n'
          'Files and photos you pick: only the files you choose to import. The app does not browse your storage.\n'
          'Photo gallery: only when you tap "Save images to gallery", and only to add the images you chose.\n'
          'Screen lock or biometrics: only to confirm it is you when you lock or open a locked document. The app never sees your fingerprint or PIN; Android does the check.',
    ),
    (
      'Reading text from documents',
      '"Extract text (OCR)" reads the words in your pages on the phone, using Google ML Kit models that are bundled with the app. The pages are not uploaded and the feature works offline. '
          'The recognised text is saved in the app\'s private storage next to the document, is searched when you use the library search, and is deleted with the document or from the text screen.',
    ),
    (
      'Photo tools',
      'Passport and ID photos, photo compression and watermarks are all made on your phone; the photos are not uploaded. '
          'If you save business details for watermarks, the name, second line and logo are kept only in the app\'s private storage and are removed with "Delete all my data" or when you uninstall the app.',
    ),
    (
      'PDF, ID card and signature tools',
      'Locking and unlocking PDFs (the password you type is used only to encrypt or decrypt the file on the phone and is never stored), compressing, splitting and numbering PDFs, copying both sides of an ID card onto one page, removing hidden data from photos and signing documents all happen on your phone; nothing is uploaded. '
          'Editing the text of Word and PDF files also happens on the phone; the files are not uploaded and the edited copy is a temporary file that you choose to share or save. '
          'Backups are made and opened on the phone only. A backup file is encrypted with the password you choose before it is saved, and it leaves the phone only if you share it or save it somewhere yourself. '
          'The same is true of the spreadsheet and presentation tools: Excel, CSV and PowerPoint files are opened, edited and converted on the phone only. '
          'Signatures you save are kept only in the app\'s private storage and are removed with "Delete all my data", when you delete them on the Signature screen, or when you uninstall the app. '
          'The files these tools create are temporary copies that you choose to share or save. A picture of a signature is not a certified digital signature.',
    ),
    (
      'QR and barcode scanner',
      'The camera or a picture you choose is read on the phone with Google ML Kit models bundled with the app; nothing is uploaded. '
          'Scanned codes are kept in a history in the app\'s private storage only, and you can switch that off or clear it on the Scan history screen. '
          'Opening a link, calling, writing an email, adding a contact or joining a Wi-Fi network hands the details to the phone\'s own apps or system screen, which asks you to confirm. '
          'Joining a Wi-Fi network adds only the network you confirm; the app does not read your saved networks or passwords.',
    ),
    (
      'Payments, invoices, CV, VAT receipts and certificates',
      'The payment QR, e-invoice viewer, invoice maker, CV maker and PDF certificate tools work entirely on the phone and upload nothing. The Doculoom app does not make payments or contact your bank. '
          'The details you save for the invoice maker (your business details and IBAN), the CV maker and the VAT refund receipts (with the pictures of receipts) are kept only in the app\'s private storage and are removed with "Delete all my data" or when you uninstall the app. '
          'The certificate file (.p12 or .pfx) you choose for signing and its password are used in memory while you sign and are never saved or sent anywhere. The PDFs these tools create are temporary copies that you choose to share or save.',
    ),
    (
      'Reminders and quick access',
      'Document-expiry reminders are stored only on the phone and shown as notifications; the app asks for notification permission and restores the reminders after the phone restarts. '
          'Home-screen shortcuts, the widget and quick-settings tiles only open Doculoom; they collect and show no data.',
    ),
    (
      'Sharing and printing',
      'Nothing leaves your phone unless you share it. Sharing and printing use the standard Android share and print screens, so you choose where a file goes. '
          '"Share with QR code > Same Wi-Fi" starts a small web server on your current Wi-Fi. Anyone on the same network who scans the code can download that one file until it expires or you stop sharing; nothing is uploaded. While a share is running, Doculoom shows a notification and keeps the link working if you minimise or close the app; tap Stop sharing there or in the app to end it. A copy of the file is kept in the app\'s private storage only for that time.\n'
          '"Share with QR code > Anywhere" lets someone on any network or mobile data download the file. The file is encrypted on your phone first, then stored on our sharing service until the link expires (5 minutes by default, at most 7 days) or you tap Stop sharing, and then deleted. '
          'The decryption key is only inside the link or QR code, never sent to us, so we cannot read the file. Like any web service it may briefly record technical data such as the IP address and time of an upload or download. Anyone who has the full link can open the file until it expires, so share it only with people you trust.\n'
          'You can add a password to either mode. The password stays on your phone and is never sent to us. For internet sharing the encryption key is made from the password, so the link contains no key; over Wi-Fi the password is checked by your phone.',
    ),
    (
      'Advertising',
      'The free version shows ads served by Google AdMob, including optional rewarded videos that you choose to watch to earn coins. The coin balance is stored only on your phone. AdMob may collect your device\'s advertising ID, IP address and ad interaction data to show and measure ads. '
          'Where the law requires it (for example in the EEA and UK) the app asks for your consent first, and you can change your choice under Settings > Privacy > Ad privacy choices. '
          'Your documents are never shared with advertisers. Google\'s policy: policies.google.com/privacy.',
    ),
    (
      'Data we collect',
      'The app itself collects no personal data, has no analytics and no tracking. Data leaves the device only in these cases: what the Google ad SDK collects as described above; '
          'limited technical diagnostics that Google ML Kit may send to Google (device model, OS version, app version, a per-installation identifier, performance and error codes, never the content of your documents); '
          'language models that Google\'s library downloads the first time you use translation or a new text script; '
          'and, only if you choose "Share with QR code > Anywhere", the encrypted copy of that one file described above.',
    ),
    (
      'Deleting your data',
      'Delete a document from its menu at any time. To remove everything at once use Settings > Privacy > Delete all my data. '
          'Uninstalling the app also removes all of its stored files.',
    ),
    ('Children', 'Doculoom is a general-audience app and is not directed to children under 13 (or under 16 where a higher age applies).'),
  ];

  Future<void> _openOnline(BuildContext context) async {
    final ok = await launchUrl(Uri.parse(AppConfig.privacyPolicyUrl), mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No app found to open the link'), persist: false));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy policy')),
      body: ListView(
        padding: contentPadding(context),
        children: [
          const Text('Doculoom respects your privacy', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: AppSpacing.md),
          for (final (title, body) in _sections) ...[
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(body, style: const TextStyle(color: AppColors.inkMuted, height: 1.4)),
            const SizedBox(height: AppSpacing.md),
          ],
          if (AppConfig.supportEmail.isNotEmpty) ...[
            const Text('Contact', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            SelectableText(AppConfig.supportEmail, style: const TextStyle(color: AppColors.primary)),
            const SizedBox(height: AppSpacing.md),
          ],
          if (AppConfig.privacyPolicyUrl.isNotEmpty)
            OutlinedButton.icon(onPressed: () => _openOnline(context), icon: const Icon(AppIcons.link, size: 18), label: const Text('Open online version')),
        ],
      ),
    );
  }
}

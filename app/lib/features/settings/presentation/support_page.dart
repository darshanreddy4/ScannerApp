import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/app_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/responsive.dart';

class SupportPage extends StatelessWidget {
  const SupportPage({super.key});

  static const _faq = <(String, String)>[
    (
      'How do I scan a document?',
      'Tap the camera button on the Documents tab. Hold the phone over the page; it captures when the outline is steady. Adjust the corners, pick a filter, then save.',
    ),
    (
      'The camera does not open',
      'ScanVault needs camera access to scan. The first time, tap Allow in the question your phone shows. If you chose Don\'t allow, the scanner shows Allow camera: tap it to be asked again, or Open Settings, then Permissions > Camera > Allow, and come back to the app. The camera opens by itself once access is on. Without access you can still add pictures with Gallery or import a PDF.',
    ),
    (
      'Where are my documents stored?',
      'Only on this phone, inside the app. Nothing is uploaded. Share or save a copy (Files, Drive, gallery) if you want one elsewhere, because uninstalling the app removes them.',
    ),
    (
      'How do I print to an office or Xerox machine?',
      'Open a document, tap Print, choose copies, pages, colour or black and white, and paper size, then tap Print. Pick the printer on the Android print screen. The printer needs to be on the same Wi-Fi or have a print service installed (Mopria, or the maker\'s print plugin).',
    ),
    (
      'How do I lock a document or folder?',
      'Open the three-dot menu on the item and choose Lock. You need a screen lock (PIN, pattern, password or fingerprint) set on your phone. If you forget that, use your phone\'s own recovery; we cannot unlock it for you.',
    ),
    (
      'How do I find my favourites?',
      'On the Documents tab choose the Favourites chip. It lists favourite folders and documents. Items in locked folders are not shown there.',
    ),
    (
      'How do I send a file to someone who is not on my Wi-Fi?',
      'Open the document menu and choose Share with QR code, then pick Anywhere. The file is encrypted on your phone and uploaded; the other person scans the code or opens the link on any network. It is deleted when the time runs out or you tap Stop sharing. Files up to 25 MB can be shared this way.',
    ),
    (
      'Can I protect a QR share with a password?',
      'Yes. On the QR screen tap Protect with a password. Whoever scans the code must type it before they can download. Over Wi-Fi the link locks after 5 wrong tries; over the internet the file is encrypted with the password, so use 8 or more characters and send the password in a separate message. If you forget it, stop sharing and start a new share.',
    ),
    (
      'How do I copy the text from a scan?',
      'Open the document menu and choose Extract text (OCR). Pick the language of the text, then tap Extract text. It runs on the phone and works offline. You can copy it, correct it, or share it as a Markdown file. Printed text works best; handwriting, Arabic and complex formulas are not read reliably yet.',
    ),
    (
      'Does a shared link keep working if I leave the app?',
      'Yes. A share runs until its timer ends or you tap Stop sharing, even if you go back, minimise the app or close it. On Wi-Fi a notification shows while it runs, and the Documents tab lists active shares. Keep the phone on the same Wi-Fi and turned on. The person opening the link sees a page with a Download button and a progress message, and the share counts a download only when the whole file arrived.',
    ),
    (
      'How do I make a passport or ID photo?',
      'Open Tools > Passport and ID photos, choose your country and the photo type, then take or pick a photo. Drag and zoom so the head fits the oval, optionally replace the background, and tap Create photo. You can save it, share it, make it smaller for an upload, or create a print sheet with several copies. Always check the size and background your office asks for.',
    ),
    (
      'How do I make a photo smaller than 50 kB?',
      'Open Tools > Compress photos, add your photos, choose the size limit (20 kB, 50 kB, 100 kB and more, or your own) and tap Compress. The result keeps the picture as sharp as the limit allows. For passport photos that must keep exact pixels, use Under 50 kB on the finished photo in the passport tool.',
    ),
    (
      'How do I add a watermark?',
      'Open Tools > Add watermark, add photos or PDFs, type your words or choose a preset, and see the preview. Choose one mark or a repeated pattern, size, strength and angle. Save your business name, GST or phone number and logo once and add them in one tap.',
    ),
    (
      'How do I make a PDF smaller for an email or upload?',
      'Open Tools > Compress PDF, choose the PDF and a size limit (200 kB, 1 MB, 5 MB or your own), and tap Compress PDF. The app lowers the quality of the pages step by step until the file fits. Text stays readable but can no longer be selected. If the limit is too small to reach, you are told and given the smallest result.',
    ),
    (
      'How do I draw on, highlight or mark up a PDF or Word file?',
      'Open Tools > Edit a PDF or Edit a Word file (or open a saved document and tap Edit), choose the page and tap Markup. Pick a pen, pencil or highlighter, draw with your finger, and change the colour, opacity and thickness. Add a square, circle, arrow or line by dragging, tap Emoji to place a sticker, or tap Text, tap the page and type your words (choose the colour, size and Bold), then drag it, pinch to resize and turn it. The eraser removes a mark you touch, and Undo and Redo step through your changes. Tap Done to add the marks to the page. Marks become part of the page picture, so text under them can no longer be selected. Before you save, Remove markup on the page puts it back as it was.',
    ),
    (
      'How do I search for a word inside a PDF or Word file?',
      'Open the file from Tools > Read PDF or Word and tap the magnifier at the top. Type a word or phrase: every match is highlighted and the bar shows how many there are. Use the up and down arrows (or the search key on your keyboard) to jump to the next or previous match. It ignores capital letters. PDFs must contain real text; scanned PDFs are pictures, so save them to your library and use Extract text (OCR) first. Password-protected PDFs cannot be searched.',
    ),
    (
      'How do I change the words in a Word file?',
      'Open Tools > Edit text in a Word file and choose a .docx file (or open it in the reader and tap the menu > Edit text). Tap a paragraph, change the words and tap Done. Select words and use Bold, Italic, Underline, size and colour, or change the alignment. Add or delete paragraphs, use the magnifier to find and replace, and Undo and Redo step through your changes. Tap Save to share the copy or save it to Files; your original is not changed. Pictures, tables and the page layout stay as they are. Text in headers, footers and text boxes cannot be changed here, and table rows cannot be added or removed.',
    ),
    (
      'How do I change the text in a PDF?',
      'Open Tools > Edit text in a PDF and choose the PDF (or open it in the reader and tap the menu > Edit text). Tap a marked line to retype or remove it. Choose Add text, tap the page and type to write something new; pick its size, colour, Bold, Italic and font. Undo and Redo step through your changes, and Save shares the copy or saves it to Files; your original is not changed. A retyped line is written in a standard font (Sans, Serif or Mono) with the size and colour of the line it replaces, so it can look slightly different, and a longer line is not wrapped, so check the page after you edit. Only Western letters, numbers and common symbols can be typed. Scanned pages have no text to change (use Add text on them), password-protected PDFs must be unlocked first, and the saved copy is not password protected.',
    ),
    (
      'How do I open or edit an Excel or PowerPoint file?',
      'Open Tools > Spreadsheets or Presentations and choose a file (.xlsx, .csv or .pptx), or tap a file in another app and choose ScanVault. Tap a cell or an item to change it, then use Save or share to send it as Excel, CSV, PDF or PowerPoint. Older .xls and .ppt files are not supported; save them as .xlsx or .pptx first. Formulas the app does not know keep their last stored result, and Excel recalculates them when you open the file there.',
    ),
    (
      'How do I put a password on a PDF, or remove one?',
      'Open Tools > Lock or unlock PDF and choose the PDF. If it has no password, type a password twice and tap Lock PDF; the copy is encrypted with AES 256-bit and needs the password to open. If it is protected, type its password and tap Unlock PDF to get a copy without a password. Text, images and links stay as they are. Forgotten passwords cannot be recovered. If another tool says a PDF is password protected, unlock it here first.',
    ),
    (
      'How do I split a PDF or add page numbers?',
      'Open Tools > Split and number PDF and choose the PDF. Tap pages to select them, or type ranges such as 1-3, 5. Then keep the selected pages, remove them, or split into one file per page, every N pages or by ranges. You can also turn pages and add page numbers, a header and a footer. The new PDFs are made from page pictures.',
    ),
    (
      'How do I copy both sides of an ID card on one page?',
      'Open Tools > ID card copy, add a photo of the front and the back, and drag and zoom so the card fills the frame. Choose the paper, real size or larger, and optionally black and white. Create the page, then print it or share the PDF. At real size the copy matches the card, so measure it if an office asks. Keep the copy safe and share it only with whoever needs it.',
    ),
    (
      'How do I remove my location from a photo?',
      'Open Tools > Remove photo data, add JPG or PNG photos and see what each one carries: location, phone model, date and editing program. Tap Remove hidden data to get clean copies that look exactly the same, then share those. Chat apps often remove the location when a photo is sent as a picture, but email, cloud links and "send as file" usually keep it.',
    ),
    (
      'How do I sign a PDF?',
      'Open Tools > Signature, draw your signature with a finger or photograph one written on white paper, and it is saved on your phone. Then tap Sign a PDF or photo, choose the file, drag the signature into place, resize it, pick which pages get it and add the signature. This puts a picture of your signature on the page. It is not a certified digital signature, so it does not prove who signed.',
    ),
    (
      'What are coins?',
      'Free users can watch a short video in Settings to earn 10 coins, as many times as you like. Coins pay for Premium features: editing saved pages costs 5 coins and each new QR share costs 2 coins (opening a file that is already being shared just shows the running share, which is free; stop it first to change its time or password). If the share cannot start, the coins are given back. Watch the video to the end to get the coins. Coins stay on this phone and are lost if you uninstall the app.',
    ),
    ('The scan looks dark or blurry', 'Use good light, hold still, and try the Document or Magic Color filter. Camera quality can be raised in Settings.'),
    (
      'I deleted something by mistake',
      'Deleted documents cannot be restored, because nothing is kept in the cloud. Delete confirmations are there to help avoid this.',
    ),
    ('How do I remove ads?', 'Ad-free purchases are not available yet.'),
  ];

  Future<void> _email(BuildContext context, {required String subject}) async {
    final info = await PackageInfo.fromPlatform();
    final body = 'Please describe the problem:\n\n\n---\nApp version: ${info.version} (${info.buildNumber})';
    final uri = Uri(scheme: 'mailto', path: AppConfig.supportEmail, query: _query({'subject': subject, 'body': body}));
    final ok = await launchUrl(uri);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No email app found. Write to ${AppConfig.supportEmail}'), persist: false));
    }
  }

  String _query(Map<String, String> params) => params.entries.map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}').join('&');

  @override
  Widget build(BuildContext context) {
    final hasEmail = AppConfig.supportEmail.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Help and support')),
      body: ListView(
        padding: contentPadding(context),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Contact us', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(hasEmail ? AppConfig.supportEmail : 'Support email is not set for this build.', style: const TextStyle(color: AppColors.inkMuted)),
                  const SizedBox(height: AppSpacing.sm),
                  const Text(
                    'Tell us what happened and what phone and Android version you have. We read every message and reply as soon as we can.',
                    style: TextStyle(color: AppColors.inkMuted, fontSize: 13),
                  ),
                  if (hasEmail) ...[
                    const SizedBox(height: AppSpacing.md),
                    Wrap(
                      spacing: AppSpacing.sm,
                      children: [
                        FilledButton.icon(
                          onPressed: () => _email(context, subject: 'ScanVault support'),
                          icon: const Icon(AppIcons.send, size: 18),
                          label: const Text('Email support'),
                        ),
                        OutlinedButton(
                          onPressed: () => _email(context, subject: 'ScanVault problem report'),
                          child: const Text('Report a problem'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 4),
            child: Text(
              'Frequently asked questions',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.inkMuted),
            ),
          ),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final (q, a) in _faq)
                  ExpansionTile(
                    title: Text(q, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                    childrenPadding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    shape: const Border(),
                    children: [Text(a, style: const TextStyle(color: AppColors.inkMuted, height: 1.4))],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

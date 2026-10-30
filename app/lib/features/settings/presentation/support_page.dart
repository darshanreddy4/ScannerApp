import 'package:flutter/material.dart' hide Text;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/app_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/text.dart';

class SupportPage extends StatelessWidget {
  const SupportPage({super.key});

  static const _faq = <(String, String)>[
    (
      'How do I scan a document?',
      'Tap the camera button on the Documents tab. Hold the phone over the page; it captures when the outline is steady. Adjust the corners, pick a filter, then save.',
    ),
    (
      'The camera does not open',
      'Doculoom needs camera access to scan. The first time, tap Allow in the question your phone shows. If you chose Don\'t allow, the scanner shows Allow camera: tap it to be asked again, or Open Settings, then Permissions > Camera > Allow, and come back to the app. The camera opens by itself once access is on. Without access you can still add pictures with Gallery or import a PDF.',
    ),
    (
      'What do the filters do, and why is one slow?',
      'Original is the photo as it was taken. Auto balances light and colour and is a good start for most photos and papers. Clean evens out the lighting and whitens the paper for printed pages while keeping colour. B&W makes black text on white paper with smooth edges and keeps pencil and stamps; Sharp B&W is pure black and white with the smallest files. Grey is a neutral grey. Whiteboard turns the board white with dark ink and vivid markers. Vivid, Warm, Cool and Noir are looks for photos. Brightness and contrast are applied before the filter. Trying filters is quick because a small copy of the page is used for the preview; the full-size picture is rendered once when you save, which takes a few seconds per page for the filters that work on the whole page, and two pages are rendered at a time.',
    ),
    (
      'How do I get the best photo quality?',
      'Photos are saved exactly as the camera takes them: no filter, no compression change and no cropping unless you move the corners on the crop screen. The in-app camera takes wide 4K photos so the preview and the photo show the same view; Full sensor is available in Settings but may frame differently. Use the zoom buttons for the ultra-wide or telephoto lens when your phone has them. Settings > Camera quality chooses the in-app camera, and Default filter chooses a look for new scans (Original keeps the photo as it is).',
    ),
    (
      'What are the scan modes under the camera?',
      'The mode decides what happens after the photo; it never changes how the picture looks. Document is the plain scan with the page editor. Receipt reads the photo on the device, names the scan from its shop, total and date, for example Receipt - Fresh Mart - 4.94 - 2026-01-31, and offers Share PDF; check the name, it is a best guess and works best with printed receipts in Latin script. Card and ID show a frame to fit the card in and ask for the back after the front. A card is then read and opens a new contact; an ID asks for the expiry date for a reminder and offers one page with both sides at the size of the real card. Book cuts an open spread into a left and a right page. Whiteboard is the plain scan. Every mode except Document also tags the scan with its name, and the tags appear as filters on the Documents screen. Text is read on the device and nothing is uploaded.',
    ),
    (
      'How do I turn a business card into a contact?',
      'Scan the card, open the document, tap More > Extract text (OCR) and wait for the text. Then tap the three dots at the top > Create a contact (business card). The name, job title, company, phone numbers, emails, website and address that were found are filled in; correct anything that is wrong and tap Save to phone contacts: your Contacts app opens with the details filled in and you confirm the save there. Share contact file sends it as a .vcf file instead. The same screen is available again at any time from the saved card: open its menu and choose Contact from card. A fully printed card in good light reads best. Nothing is uploaded.',
    ),
    (
      'How do I get a reminder before a passport or policy expires?',
      'Open the document\'s menu (the three dots) > More > Set expiry date and pick the day. Documents that have ended, or end within 60 days, appear in a box at the top of the Documents screen and carry a label in the list. On Android you also get a notification 30 days before, 7 days before and on the day, at 9:00, even when the app is closed; if that time has already passed when you set the date (for example a date of today), you get the notification right away; allow notifications when asked, and turn this off or let names show under Settings > Reminders. Without notifications the box still shows when you open Doculoom. Dates are included in backups.',
    ),
    (
      'How do I back up my documents or move them to a new phone?',
      'Open Settings > Backup and restore > Create backup, choose a password of at least 8 characters and save the file to Drive, Files or send it to yourself. On the new phone install Doculoom, open Backup and restore > Restore from a backup, pick the file and type the password. Documents, pages, folders, tags, favourites and locks come back; documents already on the phone are not duplicated, and restoring twice is safe. The file is encrypted on your phone and the password cannot be recovered, so keep it safe. Coins and settings are not included.',
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
      'How do I hide private details such as an ID number?',
      'Open the page in the editor, tap Markup and choose Hide. Drag a box over what must not be seen; it is covered in solid black that cannot be made see-through. Tap Done to burn it into the page. Saved, shared, printed and exported copies (PDF, Word, images, QR share) contain only the covered page. The app keeps your original photo inside the app so you can crop again, and cropping again removes the black boxes; delete the document to remove the original. Imported PDFs are turned into page pictures first, so the hidden text is gone from the copies you share.',
    ),
    (
      'How do I hide text in a PDF so it cannot be copied out?',
      'Open Tools > Hide text in a PDF and choose the PDF. Switch to Hide, then drag over names, numbers or anything private on any page; tap a black box to remove it. Tap Hide and save. The areas are painted black before the new file is made, and every page becomes a picture, so the covered text is not in the file at all and cannot be selected, copied or searched. Share the new copy, not the original: your original file is not changed. Text on the other pages can no longer be selected either.',
    ),
    (
      'How do I fill in a PDF form?',
      'Open Tools > Fill a PDF form and choose the PDF. Boxes of a real form are outlined: tap one to type, tick, or pick from a list. For any PDF, even a scan with no boxes, choose Text, Date, Tick or Cross and tap the page where it should go; tap a mark to remove it and use the undo button for the last one. Save PDF makes a new file and leaves the original as it is. Turn on Make it permanent (flatten) to make everything part of the page so it cannot be changed later. Only Western letters, numbers and common symbols can be typed. To sign the result use Tools > Signature.',
    ),
    (
      'How do I crop PDF pages, turn pages into pictures or flatten a PDF?',
      'Tools > Crop PDF pages: choose the PDF, move the sliders to cut the margins (one page at a time or the same cut on every page) and tap Crop PDF. The cut part is hidden, not erased, and text stays selectable; to remove something for good use Hide text in a PDF. Tools > PDF to pictures: Pages makes a JPEG or PNG of the pages you choose, and Pictures inside saves the photos and graphics placed in the PDF exactly as stored (a few kinds cannot be saved and are counted). Tools > Flatten PDF makes comments, stamps, drawings and form boxes part of the pages so they cannot be changed or removed. All of it happens on your phone.',
    ),
    (
      'How are my scans named and filed?',
      'A new scan that still has the app\'s own name (for example Scan 2026-10-25 14.07) is named from the biggest heading near the top of its first page, or from a date on it when there is no heading; a card takes the name of the person. A name you chose, or the name of an imported file, is never changed. Receipts, IDs, business cards, books and whiteboards are also filed into folders called Receipts, IDs, Business cards, Books and Whiteboards, made the first time they are needed; if you already have a folder with that name it is used, and a scan started inside a folder stays there. IDs are never read for a name. Both are on in Settings > Scanning: Name scans from their text and File scans into folders. Reading the heading happens on the phone and takes about a second.',
    ),
    (
      'How do I turn a photo of a table into an Excel sheet?',
      'Open Tools > Table to Excel and scan the table with the camera, or choose a photo; or pick the Table mode under the camera. Fit only the table in the frame, hold the phone straight above it with good light, and keep the page flat. The text is read on the phone and the cells are rebuilt: tap a cell to correct it, press and hold to delete a row or a column, and use Columns apart (Tight, Normal, Loose) if words were joined or split in the wrong place. Share Excel or CSV, open the sheet to keep editing, or save it to Files. Numbers become real numbers; codes with leading zeros stay text. For a table over several pages choose Table to spreadsheet in the menu of a saved scan: the pages follow one another. Printed tables read best; handwriting and tables with merged cells may need corrections.',
    ),
    (
      'How do I have a document read aloud?',
      'Open the document menu and choose Read aloud, or use the menu of the text screen or of a PDF or Word file in the reader. Tap Read, Pause or Resume, move between pieces with the arrows, or tap a piece to start from there. Choose the speed and the language of the voice. It uses the voice built into your phone, so nothing is sent anywhere. If the phone has no voice for a language, open its voice settings to install one.',
    ),
    (
      'How do I read the text in a picture or PDF, translate it and listen to it?',
      'Open Tools > OCR and translate (the first card). Add pictures or choose files, including PDFs, which are read page by page. Set the script of the text (Latin or Devanagari), then correct the text by hand if needed. Pick From (or leave Detect automatically) and To, then tap Translate; the swap button turns the languages round. Listen reads the text or the translation aloud with the voice built into your phone, in the right language. Copy, Share, or Use as text to translate the result again. Reading and listening happen on the phone. Translation also runs on the phone, but each language needs a one-time download of about 30 MB (and English as a go-between for two other languages), which needs the internet; after that it works offline. Remove languages you no longer need from the menu at the top. Translations can be imperfect, especially for long or informal text.',
    ),
    (
      'How do I turn many bills into an Excel sheet with the totals?',
      'Open Tools > Receipts to Excel. Add photos of bills (Pictures or Take a photo), PDFs (each page of a PDF is one bill) or saved scans (My scans; the ones in your Receipts folder are ticked for you). Each bill is read on the phone and becomes a row with the shop, the date, the subtotal, the tax, any tip or service charge, and the total. The parts are checked against each other: when a total or tax was not printed it is worked out and the bill says so, and when the parts do not add up the bill shows a note. The kind of spending (groceries, fuel, food and so on) is guessed from the shop and can be changed. Tap a bill to correct it. Above the bills you see the total spent, the spending by month and by kind, and amounts in different currencies are never added together. A second photo of the same bill is flagged. Share Excel (sheets for the bills, the months, the kinds of spending and the lines, with real formulas), share a CSV, save it to Files or open it to edit. Printed bills read best; a crumpled or faint bill may need a correction, and bills printed in a script other than Latin (such as Hindi) are not read.',
    ),
    (
      'How do I see what changed between two versions of a PDF?',
      'Open Tools > Compare two PDFs, choose the original (older) file and the revised (newer) file, and tap Compare. The words that were taken out are shown in red and the words put in are shown in green, with the words around them. Under Pages you see each page that differs, with boxes where the words changed and where the page looks different (a new picture, a moved line). A page that was added or removed in the middle does not shift the pages after it. Pages that are scans have no text, so with Read pages that are pictures turned on they are read on the phone first; this takes longer and a mistake of the text reader can show as a change. Share the list of changes or a PDF of the marked pages. Up to 60 pages of each file are compared, and a file with a password must be unlocked first.',
    ),
    (
      'How do I change the language, the paper size or the way dates are written?',
      'Open Settings > Region and language. Choose the language of the app (English, Hindi, Spanish, French, German, Portuguese, Arabic, Urdu, Chinese, Japanese, Kannada, Marathi, Italian, Dutch, Polish, Turkish or Russian, or the language of the phone), the paper size (A4 or US Letter, or automatic by the region of the phone) and the date format (day first, month first or year first). Paper size is used for printing, for ID card copies, and for the pages of PDF and Word files the app makes. Pages you scan keep the shape of the photo. Menus and messages are translated; some long explanations and rarely used screens are still in English, and the text of the Europe tools is translated into the European languages only.',
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
      'Open Tools > Spreadsheets or Presentations and choose a file (.xlsx, .csv or .pptx), or tap a file in another app and choose Doculoom. Tap a cell or an item to change it, then use Save or share to send it as Excel, CSV, PDF or PowerPoint. Older .xls and .ppt files are not supported; save them as .xlsx or .pptx first. Formulas the app does not know keep their last stored result, and Excel recalculates them when you open the file there.',
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
      'How do I keep several signatures or initials?',
      'Open Tools > Signature. You can keep up to 20 pictures: tap Initials above the list to make short initials for the pages of a long contract, or tap All to see everything. Open the menu of any picture to rename it, make it the one that is picked first, change its ink colour, make a copy, share it as a picture or move it up or down.',
    ),
    (
      'How do I read a QR code or barcode?',
      'Open Tools > Scan QR or barcode and point the camera at the code, or tap the picture button to read one from a screenshot or photo. Links can be opened, contacts added to your phone, Wi-Fi networks joined, and any code copied or shared. Everything is read on the phone and nothing is uploaded. Scans are kept in the history on this phone only; you can switch that off or clear it there.',
    ),
    (
      'Why are some tools in a folded list on the Tools page?',
      'Tools made for one country (for example the SEPA payment QR, e-invoice viewer, invoice maker, CV maker, VAT refund receipts and PDF certificate signing for Europe) come first for your country. The tools of other countries wait in the folded list "Tools for other countries". Nothing is removed: turn on Settings > Region and language > Show tools for all countries to list them all, or choose the country yourself under Tools for.',
    ),
    (
      'How do I make or read a payment QR (SEPA, Swiss QR-bill)?',
      'Open Tools > Payment QR (SEPA), type who is paid, the IBAN, and optionally the amount and a reference, and Doculoom makes a Girocode that European banking apps read. The scanner also reads Girocodes and Swiss QR-bills and shows the details to copy; Doculoom does not make payments, so check the details in your banking app. Making a Swiss QR-bill is not supported.',
    ),
    (
      'Which e-invoices can I open?',
      'Open Tools > E-invoice viewer and choose a PDF with invoice data inside (Factur-X, ZUGFeRD) or an XML file (XRechnung, Peppol UBL, FatturaPA). You see the seller, buyer, lines, totals and payment details, and can copy the IBAN or make a payment QR. Doculoom only shows what the file says; it does not check that the invoice is correct or legally valid, and an ordinary PDF invoice has no data to show.',
    ),
    (
      'Is the invoice maker a legal e-invoice?',
      'No. The invoice maker lays out a PDF with VAT, IBAN and a payment QR code to the German DIN 5008 layout. It is not an XML e-invoice for systems that require one, and it does not give tax advice: check the VAT rates and wording with your tax adviser. Your details are kept on this phone for the next invoice.',
    ),
    (
      'How do I sign a PDF with my own certificate?',
      'Open Tools > Sign with certificate, choose the PDF, then your certificate file (.p12 or .pfx), type its password and tap Unlock. Pick the page and where the signature box goes, and tap Sign the PDF. The new file is a standard PDF signature (PAdES) and keeps the original content. The certificate file and its password are not stored. Whether others accept the signature depends on the certificate: a self-made certificate is not trusted by others, one from a trust service can give a qualified or advanced signature. Signing does not add a trusted timestamp, and ID cards and smart cards are not supported, only certificate files.',
    ),
    (
      'What does the signature check tell me?',
      'The same page shows the signatures already in a PDF. It checks that the signature belongs to the file and whether the file changed after signing. It does not check whether the signer or the certificate authority is trusted, or whether the certificate was revoked, so it is not a full legal validation.',
    ),
    (
      'How do the VAT refund receipts work?',
      'Open Tools > VAT refund receipts and add each tax-free receipt with a picture, the country, the total and the VAT on the form. Doculoom shows the usual deadline (the end of the third month after the month of purchase) and how many days are left; follow the date on your tax-free form. Mark the receipt as stamped, sent for refund and refunded as it moves on, and share the list as a spreadsheet. Doculoom does not claim refunds for you and does not send reminders for the deadlines.',
    ),
    (
      'Is the CV maker the official Europass?',
      'No. The CV maker writes a clear European-style CV as a PDF in your language. It is not the official Europass document. What you type is kept on this phone.',
    ),
    (
      'How do I get to Scan, ID photo and Read PDF faster?',
      'Press and hold the Doculoom icon on the home screen to see shortcuts. You can also add the Doculoom widget from your home screen widgets, and add the Scan, ID photo and Read PDF tiles to the quick settings panel by pulling it down and tapping the pencil.',
    ),
    (
      'Which filter is best for handwriting?',
      'Handwriting gives a clean white page with darker ink and keeps the colour of the pen. Pencil makes faint graphite darker and clearer in grey. Notebook takes the ruled lines of a notebook page away and keeps the writing; it works best with a straight, even photo.',
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
                          onPressed: () => _email(context, subject: 'Doculoom support'),
                          icon: const Icon(AppIcons.send, size: 18),
                          label: const Text('Email support'),
                        ),
                        OutlinedButton(
                          onPressed: () => _email(context, subject: 'Doculoom problem report'),
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
            padding: EdgeInsetsDirectional.only(start: 4, bottom: 4),
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
                    childrenPadding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
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

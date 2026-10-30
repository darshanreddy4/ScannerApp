import 'package:flutter/material.dart' hide Text;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/di.dart';
import '../../documents/domain/entities/scanned_document.dart';
import '../../documents/domain/usecases/document_usecases.dart';
import '../../documents/presentation/widgets/document_actions.dart';
import '../../ocr/presentation/read_document_text.dart';
import '../../contacts/domain/contact_parser.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../domain/auto_title.dart';
import '../domain/entities/scan_mode.dart';
import '../domain/receipt_parser.dart';
import 'organize_scan.dart';
import '../../../core/widgets/text.dart';

/// Where to go after the follow-up: a contact filled in from a card, the one-page ID copy, or the spreadsheet of a table.
class ModeNext {
  const ModeNext({this.contactText, this.idPhotos, this.tablePages});
  final String? contactText;
  final List<String>? idPhotos;

  /// The page pictures of a table scan, to be read into a spreadsheet.
  final List<String>? tablePages;
}

/// What a saved scan needs next, depending on what it is: tags, a name from its text, a folder of its kind, and the steps of its mode.
Future<ModeNext?> runModeFollowUp(BuildContext context, ScanMode mode, ScannedDocument doc) async {
  var current = doc;
  // Tags make scans of one kind easy to find later.
  if (mode != ScanMode.document && !doc.tags.contains(mode.label)) {
    final tagged = await sl<UpdateDocumentMeta>()(doc.id, tags: [...doc.tags, mode.label]);
    current = tagged.valueOrNull ?? doc;
  }
  if (!context.mounted) return null;
  final settings = context.read<SettingsCubit>().state;

  ModeNext? next;
  switch (mode) {
    case ScanMode.receipt:
      final text = await readDocumentText(context, current);
      if (text == null || !context.mounted) return null;
      final title = parseReceipt(text).title;
      if (title != null) {
        final renamed = await sl<RenameDocument>()(current.id, title);
        current = renamed.valueOrNull ?? current;
      }
      if (settings.smartFolders) await fileIntoSmartFolder(current, mode);
      if (context.mounted) await _receiptSaved(context, current, named: title != null);
      return null;
    case ScanMode.card:
      final text = await readDocumentText(context, current);
      if (text != null) {
        next = ModeNext(contactText: text);
        // The person on the card is the best name for the scan.
        final name = parseContactText(text).name.trim();
        if (settings.autoName && name.isNotEmpty && isDefaultScanTitle(current.title)) {
          current = (await sl<RenameDocument>()(current.id, name)).valueOrNull ?? current;
        }
      }
    case ScanMode.id:
      await _askExpiry(context, current);
      if (!context.mounted) return null;
      if (doc.pages.length == 2 && await _askCombine(context)) next = ModeNext(idPhotos: [for (final p in doc.pages) p.imagePath]);
    case ScanMode.document || ScanMode.whiteboard:
      current = await autoNameScan(context, current);
    case ScanMode.table:
      next = ModeNext(tablePages: [for (final p in doc.pages) p.imagePath]);
    case ScanMode.book:
      break;
  }
  if (settings.smartFolders) await fileIntoSmartFolder(current, mode);
  return next;
}

Future<void> _receiptSaved(BuildContext context, ScannedDocument doc, {required bool named}) async {
  final share = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Receipt saved'),
      content: Text(named ? doc.title : 'No shop, total or date could be read, so the name was left as it is. You can rename it later.'),
      actions: [
        TextButton(key: const ValueKey('receipt-done'), onPressed: () => Navigator.pop(ctx, false), child: const Text('Done')),
        FilledButton(key: const ValueKey('receipt-share'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Share PDF')),
      ],
    ),
  );
  if (share == true && context.mounted) await shareDocumentPdf(context, doc);
}

Future<bool> _askCombine(BuildContext context) async {
  final yes = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Put front and back on one page?'),
      content: const Text('Both sides are printed at the size of the real card on one sheet, ready to print or send.'),
      actions: [
        TextButton(key: const ValueKey('id-combine-skip'), onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')),
        FilledButton(key: const ValueKey('id-combine-yes'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Make the page')),
      ],
    ),
  );
  return yes == true;
}

Future<void> _askExpiry(BuildContext context, ScannedDocument doc) async {
  final wants = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('When does this ID expire?'),
      content: const Text('Add the date and Doculoom can remind you before it runs out.'),
      actions: [
        TextButton(key: const ValueKey('id-expiry-skip'), onPressed: () => Navigator.pop(ctx, false), child: const Text('Skip')),
        FilledButton(key: const ValueKey('id-expiry-pick'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Pick the date')),
      ],
    ),
  );
  if (wants != true || !context.mounted) return;
  final now = DateTime.now();
  final picked = await showDatePicker(
    context: context,
    initialDate: DateTime(now.year + 1, now.month, now.day),
    firstDate: DateTime(2000),
    lastDate: DateTime(now.year + 40),
    helpText: 'When does it expire?',
  );
  if (picked == null || !context.mounted) return;
  final saved = await sl<UpdateDocumentMeta>()(doc.id, expires: DateTime(picked.year, picked.month, picked.day, 12));
  if (!saved.isOk || !context.mounted) return;
  await replanReminders(context);
  if (context.mounted) await offerExpiryReminders(context);
}

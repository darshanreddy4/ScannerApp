import 'dart:io';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../../app/app_config.dart';
import '../../../../app/di.dart';
import '../../../../core/error/result.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/widgets/dialogs.dart';
import '../../../../core/widgets/feedback.dart';
import '../../../export/domain/entities/export_options.dart';
import '../../../export/data/share_packager.dart';
import '../../../export/domain/repositories/export_repository.dart';
import '../../../export/domain/usecases/export_usecases.dart';
import '../../../monetization/domain/repositories/monetization_contracts.dart';
import '../../../ocr/domain/text_repository.dart';
import '../../../ocr/presentation/read_document_text.dart';
import '../../../tables/presentation/table_page.dart';
import '../../../speech/presentation/read_aloud_page.dart';
import '../../../monetization/presentation/plan_cubit.dart';
import '../../../qr/presentation/qr_share_page.dart';
import '../../../scanner/presentation/bloc/scan_session_cubit.dart';
import '../../../rewards/domain/coin_rules.dart';
import '../../../rewards/presentation/unlock.dart';
import '../../../security/domain/auth_service.dart';
import '../../../settings/domain/feature_access.dart';
import '../../../settings/presentation/settings_cubit.dart';
import '../../domain/entities/compress_level.dart';
import '../bloc/documents_cubit.dart';
import '../../../reminders/domain/reminder_service.dart';
import '../../domain/entities/scanned_document.dart';
import '../../domain/usecases/document_usecases.dart';
import 'document_widgets.dart' show confirmDestructive, pickFolder, DocThumb;
import 'share_options_sheet.dart';
import '../../../../core/widgets/text.dart';

enum DocAction {
  sharePdf,
  shareImages,
  shareDocx,
  shareQr,
  extractText,
  readAloud,
  tableToSheet,
  contact,
  saveFiles,
  saveGallery,
  print,
  compress,
  lock,
  delete,
  editPages,
  split,
  duplicate,
  move,
  rename,
  favorite,
  pin,
  tags,
  date,
  expiry,
}

/// Asks the phone owner to confirm with fingerprint, face, PIN, pattern or password.
/// When the phone has no screen lock, [allowIfUnavailable] decides whether the action may go ahead.
Future<bool> confirmOwner(BuildContext context, String reason, {bool allowIfUnavailable = false}) async {
  final result = await sl<AuthService>().authenticate(reason);
  if (!context.mounted) return false;
  return result.when(
    ok: (outcome) {
      if (outcome == AuthOutcome.unavailable) {
        if (allowIfUnavailable) return true;
        showMessage(context, 'Set up a screen lock (PIN, pattern, password or fingerprint) in your phone settings first.');
      }
      return outcome == AuthOutcome.success;
    },
    err: (f) {
      showFailure(context, f);
      return false;
    },
  );
}

/// Opens the per-document actions sheet. [refresh] reloads whatever screen shows the document;
/// [onDeleted] is called after the document is deleted (a detail page uses it to close itself).
Future<void> showDocumentActions(BuildContext context, ScannedDocument doc, {required Future<void> Function() refresh, VoidCallback? onDeleted}) async {
  if (doc.locked && !await confirmOwner(context, 'Unlock "${doc.title}"', allowIfUnavailable: true)) return;
  if (!context.mounted) return;
  final access = FeatureAccess.editSavedDocuments(
    billingEnabled: AppConfig.billingEnabled,
    coinsEnabled: AppConfig.rewardsEnabled,
    plan: context.read<PlanCubit>().state,
    enabled: context.read<SettingsCubit>().state.editSavedDocuments,
  );
  final action = await showModalBottomSheet<DocAction>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _ActionsSheet(document: doc, editAccess: access),
  );
  if (action == null || !context.mounted) return;
  await _run(context, doc, action, access, refresh, onDeleted);
}

// Running an action

String _safeName(String title) {
  final cleaned = title.replaceAll(RegExp(r'[^\w\- ]+'), '').trim().replaceAll(RegExp(r'\s+'), '_');
  return cleaned.isEmpty ? 'document' : cleaned;
}

/// Awaits [future]; a failure is shown to the user. Callers check `isOk` or `valueOrNull`.
Future<Result<T>> _do<T>(BuildContext context, Future<Result<T>> future) async {
  final result = await future;
  final failure = result.failureOrNull;
  if (failure != null && context.mounted) showFailure(context, failure);
  return result;
}

/// Asks how the PDF should be sent (size, password, ZIP), then builds that one copy and opens the share sheet.
/// The saved document is never changed: every step works on a temporary copy.
Future<void> shareDocumentPdf(BuildContext context, ScannedDocument doc) async {
  final options = await showShareOptions(context, title: doc.title);
  if (options == null || !context.mounted) return;
  final plan = context.read<PlanCubit>().state;
  final quality = options.size.effective(context.read<SettingsCubit>().state.exportQuality);
  final packed = await _do(
    context,
    runBusy(context, 'Preparing file', () async {
      final built = await sl<ExportDocument>()(document: doc, format: ExportFormat.pdf, quality: quality);
      final path = built.valueOrNull;
      if (path == null) return Err<PackedShare>(built.failureOrNull!);
      return sl<SharePackager>().pack(pdfPath: path, password: options.password, zip: options.zip);
    }),
  );
  final file = packed.valueOrNull;
  if (file == null || !context.mounted) return;
  await _do(context, sl<ShareService>().shareFile(path: file.path, mimeType: file.mimeType, subject: doc.title));
  await sl<AdService>().showInterstitialIfEligible(plan);
}

Future<void> _shareAs(BuildContext context, ScannedDocument doc, ExportFormat format) async {
  final plan = context.read<PlanCubit>().state;
  final path = await _build(context, doc, format);
  if (path == null || !context.mounted) return;
  await _do(context, sl<ShareFile>()(path: path, format: format, subject: doc.title));
  await sl<AdService>().showInterstitialIfEligible(plan);
}

Future<String?> _build(BuildContext context, ScannedDocument doc, ExportFormat format) async {
  final quality = context.read<SettingsCubit>().state.exportQuality;
  final result = await _do(context, runBusy(context, 'Preparing file', () => sl<ExportDocument>()(document: doc, format: format, quality: quality)));
  return result.valueOrNull;
}

/// Copies the page images to the cache folder under friendly names so other apps can read them.
Future<List<String>> _stageImages(ScannedDocument doc) async {
  final tmp = await getTemporaryDirectory();
  final dir = Directory(p.join(tmp.path, 'share_images', doc.id));
  if (await dir.exists()) await dir.delete(recursive: true);
  await dir.create(recursive: true);
  final base = _safeName(doc.title);
  final out = <String>[];
  for (var i = 0; i < doc.pages.length; i++) {
    final target = p.join(dir.path, '$base-${i + 1}.jpg');
    await File(doc.pages[i].imagePath).copy(target);
    out.add(target);
  }
  return out;
}

Future<void> _run(
  BuildContext context,
  ScannedDocument doc,
  DocAction action,
  FeatureState editAccess,
  Future<void> Function() refresh,
  VoidCallback? onDeleted,
) async {
  switch (action) {
    case DocAction.sharePdf:
      await shareDocumentPdf(context, doc);

    case DocAction.shareDocx:
      await _shareAs(context, doc, ExportFormat.docx);

    case DocAction.shareImages:
      await _do(
        context,
        runBusy(context, 'Preparing images', () async {
          final paths = await _stageImages(doc);
          return sl<ShareService>().shareFiles(paths: paths, mimeType: 'image/jpeg', subject: doc.title);
        }),
      );

    case DocAction.shareQr:
      final path = await _build(context, doc, ExportFormat.pdf);
      if (path == null || !context.mounted) return;
      await context.push(
        '/qr-share',
        extra: QrShareArgs(filePath: path, fileName: p.basename(path), mimeType: ExportFormat.pdf.mimeType),
      );

    case DocAction.extractText:
      await context.push('/ocr', extra: doc);

    case DocAction.tableToSheet:
      await context.push(
        '/table',
        extra: TableArgs(title: doc.title, imagePaths: [for (final pg in doc.pages) pg.imagePath]),
      );

    case DocAction.readAloud:
      // Text that was read before is used as it is; otherwise the pages are read now.
      final saved = (await sl<TextRepository>().loadText(doc.id)).valueOrNull;
      var text = saved == null ? '' : saved.map((p) => p.plain).where((t) => t.trim().isNotEmpty).join('\n\n');
      if (text.isEmpty && context.mounted) {
        final read = await readDocumentText(context, doc);
        if (read == null) return;
        text = read;
      }
      if (!context.mounted) return;
      await context.push(
        '/read-aloud',
        extra: ReadAloudArgs(title: doc.title, text: text),
      );

    case DocAction.contact:
      final text = await readDocumentText(context, doc);
      if (text != null && context.mounted) await context.push('/contact', extra: text);

    case DocAction.saveFiles:
      final path = await _build(context, doc, ExportFormat.pdf);
      if (path == null || !context.mounted) return;
      final saved = await _do(
        context,
        sl<SaveService>().saveToFiles(sourcePath: path, fileName: '${_safeName(doc.title)}.pdf', mimeType: ExportFormat.pdf.mimeType),
      );
      if (saved.valueOrNull == true && context.mounted) showMessage(context, 'Saved as PDF');

    case DocAction.saveGallery:
      final saved = await _do(
        context,
        runBusy(context, 'Saving images', () => sl<SaveService>().saveImagesToGallery([for (final pg in doc.pages) pg.imagePath])),
      );
      final count = saved.valueOrNull;
      if (count != null && context.mounted) showMessage(context, count == 1 ? 'Saved 1 image to your gallery' : 'Saved $count images to your gallery');

    case DocAction.print:
      await context.push('/print', extra: doc);

    case DocAction.compress:
      final level = await showDialog<CompressLevel>(context: context, builder: (_) => const _CompressDialog());
      if (level == null || !context.mounted) return;
      final before = (await sl<GetDocumentSize>()(doc.id)).valueOrNull;
      if (!context.mounted) return;
      if (!(await _do(context, runBusy(context, 'Compressing', () => sl<CompressDocument>()(id: doc.id, level: level)))).isOk) return;
      final after = (await sl<GetDocumentSize>()(doc.id)).valueOrNull;
      await refresh();
      if (context.mounted && before != null && after != null) showMessage(context, 'Compressed from ${formatBytes(before)} to ${formatBytes(after)}');

    case DocAction.lock:
      if (!doc.locked && !await confirmOwner(context, 'Lock "${doc.title}"')) return;
      if (!context.mounted) return;
      if (!(await _do(context, sl<UpdateDocumentMeta>()(doc.id, locked: !doc.locked))).isOk) return;
      await refresh();
      if (context.mounted) showMessage(context, doc.locked ? 'Document unlocked' : 'Document locked. Opening it now needs your phone lock.');

    case DocAction.delete:
      final ok = await confirmDestructive(context, title: 'Delete document?', message: '"${doc.title}" will be permanently removed from this device.');
      if (!ok || !context.mounted) return;
      if (!(await _do(context, sl<DeleteDocument>()(doc.id))).isOk) return;
      if (onDeleted != null) {
        onDeleted();
      } else {
        await refresh();
      }

    case DocAction.editPages:
      if (editAccess == FeatureState.locked) {
        if (AppConfig.rewardsEnabled) {
          if (!await requestUnlock(context, CoinFeature.editSavedDocument)) return;
        } else {
          showMessage(context, 'Editing saved documents is a Premium feature');
          return;
        }
        if (!context.mounted) return;
      }
      context.read<ScanSessionCubit>().loadDocument(doc, defaultFilter: context.read<SettingsCubit>().state.defaultFilter);
      await context.push('/scan/edit');
      await refresh();

    case DocAction.split:
      if (doc.pageCount < 2) {
        showMessage(context, 'A document needs at least 2 pages to be split');
        return;
      }
      final start = await showDialog<int>(
        context: context,
        builder: (_) => _SplitDialog(pageCount: doc.pageCount),
      );
      if (start == null || !context.mounted) return;
      if (!(await _do(context, runBusy(context, 'Splitting', () => sl<SplitDocument>()(id: doc.id, startPage: start)))).isOk) return;
      await refresh();
      if (context.mounted) showMessage(context, 'Pages $start-${doc.pageCount} moved to a new document');

    case DocAction.duplicate:
      if (!(await _do(context, runBusy(context, 'Copying', () => sl<DuplicateDocument>()(doc.id)))).isOk) return;
      await refresh();
      if (context.mounted) showMessage(context, 'Copy created');

    case DocAction.move:
      final folders = (await _do(context, sl<ListFolders>()())).valueOrNull;
      if (folders == null || !context.mounted) return;
      final target = await pickFolder(context, folders, doc.folderId);
      if (target == null || !context.mounted) return;
      if (!(await _do(context, sl<MoveDocument>()(doc.id, target.folderId))).isOk) return;
      await refresh();

    case DocAction.rename:
      final title = await promptText(context, title: 'Rename document', initial: doc.title);
      if (title == null || !context.mounted) return;
      if (!(await _do(context, sl<RenameDocument>()(doc.id, title))).isOk) return;
      await refresh();

    case DocAction.favorite:
      if (!(await _do(context, sl<UpdateDocumentMeta>()(doc.id, favorite: !doc.favorite))).isOk) return;
      await refresh();

    case DocAction.pin:
      if (!(await _do(context, sl<UpdateDocumentMeta>()(doc.id, pinned: !doc.pinned))).isOk) return;
      await refresh();

    case DocAction.tags:
      final text = await promptText(context, title: 'Tags', initial: doc.tags.join(', '), hint: 'work, invoice, 2025', allowEmpty: true);
      if (text == null || !context.mounted) return;
      final tags = {
        for (final t in text.split(','))
          if (t.trim().isNotEmpty) t.trim(),
      }.toList();
      if (!(await _do(context, sl<UpdateDocumentMeta>()(doc.id, tags: tags))).isOk) return;
      await refresh();

    case DocAction.expiry:
      var change = true;
      if (doc.expiresAt != null) {
        final choice = await showDialog<String>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: Text('Expiry: ${formatDate(doc.expiresAt!)}'),
            children: [
              SimpleDialogOption(key: const ValueKey('expiry-change'), onPressed: () => Navigator.pop(ctx, 'change'), child: const Text('Change the date')),
              SimpleDialogOption(key: const ValueKey('expiry-remove'), onPressed: () => Navigator.pop(ctx, 'remove'), child: const Text('Remove the date')),
            ],
          ),
        );
        if (choice == null || !context.mounted) return;
        change = choice == 'change';
        if (!change) {
          if (!(await _do(context, sl<UpdateDocumentMeta>()(doc.id, clearExpiry: true))).isOk) return;
          if (context.mounted) await replanReminders(context);
          await refresh();
          return;
        }
      }
      final now = DateTime.now();
      final picked = await showDatePicker(
        context: context,
        initialDate: doc.expiresAt ?? DateTime(now.year + 1, now.month, now.day),
        firstDate: DateTime(2000),
        lastDate: DateTime(now.year + 40),
        helpText: 'When does it expire?',
      );
      if (picked == null || !context.mounted) return;
      if (!(await _do(context, sl<UpdateDocumentMeta>()(doc.id, expires: DateTime(picked.year, picked.month, picked.day, 12)))).isOk) return;
      if (context.mounted) await replanReminders(context);
      if (context.mounted) await offerExpiryReminders(context);
      await refresh();

    case DocAction.date:
      final day = await showDatePicker(
        context: context,
        initialDate: doc.createdAt,
        firstDate: DateTime(2000),
        lastDate: DateTime.now().add(const Duration(days: 366)),
      );
      if (day == null || !context.mounted) return;
      final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(doc.createdAt));
      if (time == null || !context.mounted) return;
      final when = DateTime(day.year, day.month, day.day, time.hour, time.minute);
      if (!(await _do(context, sl<UpdateDocumentMeta>()(doc.id, date: when))).isOk) return;
      await refresh();
  }
}

/// Reloads the library, which plans the reminders again from the new or removed date.
Future<void> replanReminders(BuildContext context) async {
  DocumentsCubit cubit;
  try {
    cubit = context.read<DocumentsCubit>();
  } catch (_) {
    return;
  }
  await cubit.load();
}

/// The first time a date is set, explains the reminders and shows the system question for notifications.
Future<void> offerExpiryReminders(BuildContext context) async {
  if (!sl.isRegistered<ReminderService>() || !context.read<SettingsCubit>().state.expiryReminders) return;
  final service = sl<ReminderService>();
  if (!await service.shouldExplain() || !context.mounted) return;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Get a reminder?'),
      content: const Text(
        'Doculoom can send a notification 30 days before, 7 days before and on the day this document expires. Document names stay out of the notification unless you turn that on in Settings.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')),
        FilledButton(
          key: const ValueKey('reminder-allow'),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Allow notifications'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  await service.askOnce();
  // The reminders were planned while notifications were still off.
  if (context.mounted) await replanReminders(context);
}

// Sheet

class _ActionsSheet extends StatefulWidget {
  const _ActionsSheet({required this.document, required this.editAccess});
  final ScannedDocument document;
  final FeatureState editAccess;

  @override
  State<_ActionsSheet> createState() => _ActionsSheetState();
}

class _ActionsSheetState extends State<_ActionsSheet> {
  bool _editOpen = false;
  bool _moreOpen = false;
  late final Future<Result<int>> _size = sl<GetDocumentSize>()(widget.document.id);

  void _pick(DocAction a) => Navigator.pop(context, a);

  @override
  Widget build(BuildContext context) {
    final doc = widget.document;
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(document: doc, size: _size, onRename: () => _pick(DocAction.rename)),
          const Divider(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: AppSpacing.sm,
              crossAxisSpacing: AppSpacing.sm,
              childAspectRatio: 1.35,
              children: [
                _QuickTile(icon: AppIcons.pdf, label: 'Share PDF', onTap: () => _pick(DocAction.sharePdf)),
                _QuickTile(icon: AppIcons.gallery, label: 'Share images', onTap: () => _pick(DocAction.shareImages)),
                _QuickTile(icon: AppIcons.print, label: 'Print', onTap: () => _pick(DocAction.print)),
                _QuickTile(icon: AppIcons.quality, label: 'Compress', onTap: () => _pick(DocAction.compress)),
                _QuickTile(icon: doc.locked ? AppIcons.unlock : AppIcons.lock, label: doc.locked ? 'Unlock' : 'Lock', onTap: () => _pick(DocAction.lock)),
                _QuickTile(icon: AppIcons.delete, label: 'Delete', danger: true, onTap: () => _pick(DocAction.delete)),
              ],
            ),
          ),
          const Divider(height: 24),
          _Row(icon: AppIcons.storage, label: 'Save to Files or Drive (PDF)', onTap: () => _pick(DocAction.saveFiles)),
          _Row(icon: AppIcons.download, label: 'Save images to gallery', onTap: () => _pick(DocAction.saveGallery)),
          _Row(icon: AppIcons.docx, label: 'Share as Word (DOCX)', onTap: () => _pick(DocAction.shareDocx)),
          _Row(icon: AppIcons.qr, label: 'Share with QR code', onTap: () => _pick(DocAction.shareQr)),
          _Row(icon: AppIcons.ocr, label: 'Extract text (OCR)', onTap: () => _pick(DocAction.extractText)),
          _Row(icon: AppIcons.speak, label: 'Read aloud', onTap: () => _pick(DocAction.readAloud)),
          _Row(icon: AppIcons.sheet, label: 'Table to spreadsheet', onTap: () => _pick(DocAction.tableToSheet)),
          _Row(icon: AppIcons.person, label: 'Contact from card', onTap: () => _pick(DocAction.contact)),
          _Row(icon: AppIcons.emptyDocs, label: 'Move to folder', onTap: () => _pick(DocAction.move)),
          _Expander(
            icon: AppIcons.editDocument,
            label: 'Edit',
            open: _editOpen,
            onToggle: () => setState(() => _editOpen = !_editOpen),
            children: [
              if (widget.editAccess != FeatureState.hidden)
                _Row(
                  icon: AppIcons.editDocument,
                  label: 'Edit pages',
                  indent: true,
                  trailing: widget.editAccess == FeatureState.locked ? const _PremiumChip() : null,
                  onTap: () => _pick(DocAction.editPages),
                ),
              _Row(
                icon: AppIcons.split,
                label: 'Split document',
                subtitle: doc.pageCount < 2 ? 'Needs at least 2 pages' : null,
                indent: true,
                onTap: doc.pageCount < 2 ? null : () => _pick(DocAction.split),
              ),
              _Row(icon: AppIcons.edit, label: 'Rename', indent: true, onTap: () => _pick(DocAction.rename)),
            ],
          ),
          _Expander(
            icon: AppIcons.more,
            label: 'More',
            open: _moreOpen,
            onToggle: () => setState(() => _moreOpen = !_moreOpen),
            children: [
              _Row(
                icon: doc.favorite ? AppIcons.starFilled : AppIcons.star,
                label: doc.favorite ? 'Remove from favourites' : 'Add to favourites',
                indent: true,
                onTap: () => _pick(DocAction.favorite),
              ),
              _Row(icon: AppIcons.pin, label: doc.pinned ? 'Unpin from top' : 'Pin to top', indent: true, onTap: () => _pick(DocAction.pin)),
              _Row(icon: AppIcons.tag, label: 'Tags', indent: true, onTap: () => _pick(DocAction.tags)),
              _Row(icon: AppIcons.copy, label: 'Duplicate', indent: true, onTap: () => _pick(DocAction.duplicate)),
              _Row(icon: AppIcons.timer, label: 'Date and time', indent: true, onTap: () => _pick(DocAction.date)),
              _Row(
                icon: AppIcons.timer,
                label: doc.expiresAt == null ? 'Set expiry date' : 'Expiry: ${formatDate(doc.expiresAt!)}',
                indent: true,
                onTap: () => _pick(DocAction.expiry),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.document, required this.size, required this.onRename});
  final ScannedDocument document;
  final Future<Result<int>> size;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
    child: Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 52,
            height: 64,
            child: ColoredBox(
              color: AppColors.background,
              child: DocThumb(document: document, cacheWidth: 160),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: onRename,
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        document.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(AppIcons.edit, size: 15, color: AppColors.inkMuted),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              FutureBuilder<Result<int>>(
                future: size,
                builder: (_, snap) {
                  final bytes = snap.data?.valueOrNull;
                  final parts = [pagesLabel(document.pageCount), if (bytes != null) formatBytes(bytes), formatDate(document.updatedAt)];
                  return Text(parts.join('  |  '), style: const TextStyle(color: AppColors.inkMuted, fontSize: 13));
                },
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({required this.icon, required this.label, required this.onTap, this.danger = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.danger : AppColors.ink;
    return Material(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22, color: danger ? AppColors.danger : AppColors.primary),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: color, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, required this.onTap, this.indent = false, this.trailing, this.subtitle});
  final IconData icon;
  final String label;
  final String? subtitle;

  /// Null greys the row out and ignores taps.
  final VoidCallback? onTap;
  final bool indent;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    contentPadding: EdgeInsetsDirectional.only(start: indent ? AppSpacing.xl : AppSpacing.md, end: AppSpacing.md),
    enabled: onTap != null,
    leading: Icon(icon, size: 20, color: onTap == null ? AppColors.inkMuted : AppColors.ink),
    title: Text(label),
    subtitle: subtitle == null ? null : Text(subtitle!),
    trailing: trailing,
    onTap: onTap,
  );
}

class _Expander extends StatelessWidget {
  const _Expander({required this.icon, required this.label, required this.open, required this.onToggle, required this.children});
  final IconData icon;
  final String label;
  final bool open;
  final VoidCallback onToggle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        leading: Icon(icon, size: 20, color: AppColors.ink),
        title: Text(label),
        trailing: Icon(open ? AppIcons.expandLess : AppIcons.expandMore, size: 20, color: AppColors.inkMuted),
        onTap: onToggle,
      ),
      if (open) ...children,
    ],
  );
}

class _PremiumChip extends StatelessWidget {
  const _PremiumChip();

  @override
  Widget build(BuildContext context) => AppConfig.rewardsEnabled
      ? Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(AppIcons.coins, size: 16, color: AppColors.warning),
            const SizedBox(width: 4),
            Text(
              '${CoinFeature.editSavedDocument.cost}',
              style: const TextStyle(color: AppColors.warning, fontWeight: FontWeight.w700),
            ),
          ],
        )
      : const Icon(AppIcons.premium, size: 18, color: AppColors.warning);
}

class _CompressDialog extends StatelessWidget {
  const _CompressDialog();

  @override
  Widget build(BuildContext context) => SimpleDialog(
    title: const Text('Compress document'),
    children: [
      const Padding(
        padding: EdgeInsetsDirectional.fromSTEB(24, 0, 24, 8),
        child: Text('The original photos are replaced by the smaller version. This cannot be undone.', style: TextStyle(color: AppColors.inkMuted)),
      ),
      for (final level in CompressLevel.values)
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, level),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(level.label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              Text(level.description, style: const TextStyle(color: AppColors.inkMuted, fontSize: 13)),
            ],
          ),
        ),
    ],
  );
}

class _SplitDialog extends StatelessWidget {
  const _SplitDialog({required this.pageCount});
  final int pageCount;

  // A scrolling list cannot sit inside SimpleDialog (it measures its children, which a list cannot answer), so this is an AlertDialog.
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Split document'),
    contentPadding: const EdgeInsetsDirectional.fromSTEB(0, 12, 0, 0),
    content: SizedBox(
      width: double.maxFinite,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsetsDirectional.fromSTEB(24, 0, 24, 8),
            child: Text('Choose where the new document starts. Earlier pages stay here.', style: TextStyle(color: AppColors.inkMuted)),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (var start = 2; start <= pageCount; start++)
                  ListTile(title: Text(start == pageCount ? 'Page $start only' : 'Pages $start to $pageCount'), onTap: () => Navigator.pop(context, start)),
              ],
            ),
          ),
        ],
      ),
    ),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
  );
}

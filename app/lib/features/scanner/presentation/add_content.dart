import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/error/failures.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/feedback.dart';
import '../../importer/domain/importer.dart';
import '../../settings/presentation/settings_cubit.dart';
import 'bloc/scan_session_cubit.dart';

// Entry points for adding pages from the library or from inside the editor.
// With `append: true` the pages join the scan session that is already open (they merge into one
// document); otherwise a fresh session is started.

/// Opens the camera for a new scan, optionally filing the result into [folderId].
void startScan(BuildContext context, {String? folderId}) {
  context.read<ScanSessionCubit>().start(defaultFilter: context.read<SettingsCubit>().state.defaultFilter, folderId: folderId);
  context.push('/scan');
}

/// Imports one or more gallery images.
Future<void> startImport(BuildContext context, {String? folderId, bool append = false}) async {
  final session = context.read<ScanSessionCubit>();
  final settings = context.read<SettingsCubit>().state;
  if (!append) session.start(defaultFilter: settings.defaultFilter, folderId: folderId);

  try {
    final files = await ImagePicker().pickMultiImage();
    if (files.isEmpty || !context.mounted) return;
    await importImagePaths(context, [for (final f in files) f.path], append: append);
  } catch (_) {
    if (context.mounted) showFailure(context, const PermissionFailure('Photo library access is unavailable.'));
  }
}

/// Queues images that are already on the device (picked, or received from another app) into the open session.
Future<void> importImagePaths(BuildContext context, List<String> paths, {bool append = false}) async {
  final session = context.read<ScanSessionCubit>();
  final settings = context.read<SettingsCubit>().state;
  final ok = await session.importMany(paths);
  if (!context.mounted) return;
  if (!ok) {
    if (session.state.error != null) showFailure(context, session.state.error!);
    return;
  }
  if (settings.showCropAfterCapture) {
    context.push('/scan/crop');
    return;
  }
  final done = await session.commitAll();
  if (!context.mounted) return;
  if (!done) {
    if (session.state.error != null) showFailure(context, session.state.error!);
  } else if (!append && session.state.pages.isNotEmpty) {
    context.push('/scan/edit');
  }
}

/// Picks a PDF/Word file and converts it to pages.
Future<void> startImportFile(BuildContext context, ImportKind kind, {String? folderId, bool append = false}) async {
  final session = context.read<ScanSessionCubit>();
  final settings = context.read<SettingsCubit>().state;
  if (!append) session.start(defaultFilter: settings.defaultFilter, folderId: folderId);

  final String? path;
  try {
    final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: kind.extensions);
    path = picked.isEmpty ? null : picked.first.path;
  } catch (_) {
    if (context.mounted) showFailure(context, const PermissionFailure('The file picker is unavailable.'));
    return;
  }
  if (path == null || !context.mounted) return;

  final ok = append ? await session.importDocumentFile(kind, path) : await runWithProgress(context, session, () => session.importDocumentFile(kind, path!));
  // The pages are rendered, so the picker's private copy of the file is no longer needed.
  unawaited(_dropPickedCopies());
  if (!context.mounted) return;
  if (!ok) {
    if (session.state.error != null) showFailure(context, session.state.error!);
  } else if (!append) {
    context.push('/scan/edit');
  }
}

Future<void> _dropPickedCopies() async {
  try {
    await FilePicker.clearTemporaryFiles();
  } catch (_) {
    // Cleared at the next launch instead.
  }
}

/// Runs [task] behind a modal progress dialog that follows the session's progress label.
Future<T> runWithProgress<T>(BuildContext context, ScanSessionCubit session, Future<T> Function() task) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => BlocProvider.value(value: session, child: const _ProgressDialog()),
  );
  try {
    return await task();
  } finally {
    navigator.pop();
  }
}

/// Picks several PDF/Word files and merges them, in the order chosen, into one document in the editor.
Future<void> startCombineFiles(BuildContext context, {String? folderId}) async {
  final session = context.read<ScanSessionCubit>();
  final settings = context.read<SettingsCubit>().state;
  session.start(defaultFilter: settings.defaultFilter, folderId: folderId);

  final List<PlatformFile> picked;
  try {
    picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['pdf', 'docx']);
  } catch (_) {
    if (context.mounted) showFailure(context, const PermissionFailure('The file picker is unavailable.'));
    return;
  }
  if (picked.length < 2 || !context.mounted) {
    if (picked.length == 1 && context.mounted) {
      showFailure(context, const ImportFailure('Pick at least two files to combine.'));
    }
    return;
  }

  final ok = await runWithProgress(context, session, () async {
    for (final f in picked) {
      final path = f.path;
      if (path == null) continue;
      final kind = path.toLowerCase().endsWith('.pdf') ? ImportKind.pdf : ImportKind.docx;
      if (!await session.importDocumentFile(kind, path)) return false;
    }
    return true;
  });
  unawaited(_dropPickedCopies());
  if (!context.mounted) return;
  if (ok && session.state.pages.isNotEmpty) {
    session.setTitle('Combined ${formatDate(DateTime.now())}');
    context.push('/scan/edit');
  } else if (session.state.error != null) {
    showFailure(context, session.state.error!);
  }
}

/// Bottom sheet offering every way to add pages: camera, gallery, PDF, Word.
Future<void> showAddSheet(BuildContext context, {String? folderId, bool append = false}) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (_) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(append ? 'Add to this document' : 'Add new document', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            ),
          ),
          const _SheetTile(icon: AppIcons.gallery, title: 'Import from gallery', subtitle: 'Select one or many JPEG or PNG images', value: 'import'),
          _SheetTile(
            icon: AppIcons.camera,
            title: 'Scan from camera',
            subtitle: append ? 'Capture more pages' : 'Capture several pages in a row',
            value: 'camera',
          ),
          const _SheetTile(icon: AppIcons.pdf, title: 'Import PDF', subtitle: 'Convert every page into an editable scan', value: 'pdf'),
          const _SheetTile(icon: AppIcons.docx, title: 'Import Word document', subtitle: 'DOCX with images or text', value: 'docx'),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    ),
  );
  if (!context.mounted || choice == null) return;
  switch (choice) {
    case 'camera':
      if (append) {
        context.go('/scan'); // the session lives in the cubit, so leaving the editor loses nothing
      } else {
        startScan(context, folderId: folderId);
      }
    case 'pdf':
      await startImportFile(context, ImportKind.pdf, folderId: folderId, append: append);
    case 'docx':
      await startImportFile(context, ImportKind.docx, folderId: folderId, append: append);
    default:
      await startImport(context, folderId: folderId, append: append);
  }
}

class _SheetTile extends StatelessWidget {
  const _SheetTile({required this.icon, required this.title, required this.subtitle, required this.value});
  final IconData icon;
  final String title;
  final String subtitle;
  final String value;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(10)),
      child: Icon(icon, color: AppColors.primary),
    ),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
    subtitle: Text(subtitle),
    trailing: const Icon(AppIcons.next, size: 18, color: AppColors.inkMuted),
    onTap: () => Navigator.of(context).pop(value),
  );
}

class _ProgressDialog extends StatelessWidget {
  const _ProgressDialog();

  @override
  Widget build(BuildContext context) {
    final label = context.select((ScanSessionCubit c) => c.state.busyLabel);
    return PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text(label ?? 'Working')),
          ],
        ),
      ),
    );
  }
}

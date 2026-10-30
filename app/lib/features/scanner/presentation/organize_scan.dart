import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/di.dart';
import '../../documents/domain/entities/scanned_document.dart';
import '../../documents/domain/usecases/document_usecases.dart';
import '../../ocr/domain/ocr_engine.dart';
import '../../ocr/presentation/read_document_text.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../domain/auto_title.dart';
import '../domain/entities/scan_mode.dart';
import '../domain/smart_folders.dart';

/// Names a new scan from the heading, or else the date, on its first page. A name the person chose, or one that came from a file, is kept.
/// Returns the document with its new name, or the same one when nothing better was found.
Future<ScannedDocument> autoNameScan(BuildContext context, ScannedDocument doc) async {
  final settings = context.read<SettingsCubit>().state;
  if (!settings.autoName || !isDefaultScanTitle(doc.title) || doc.pages.isEmpty) return doc;
  final title = await withReadingDialog<String?>(context, 'Naming the scan', () async {
    try {
      final read = await sl<OcrEngine>().recognize(doc.pages.first.imagePath, settings.ocrScript).timeout(const Duration(seconds: 8));
      final page = read.valueOrNull;
      if (page == null) return null;
      return suggestTitle(page) ?? suggestTitleFromDate(page.plainText);
    } catch (_) {
      // Naming is a nicety: a slow or failed read leaves the default name.
      return null;
    }
  });
  if (title == null || title == doc.title) return doc;
  final renamed = await sl<RenameDocument>()(doc.id, title);
  return renamed.valueOrNull ?? doc;
}

/// Puts a scan into the folder of its kind (Receipts, IDs and so on), made when it does not exist yet. A scan started inside a folder stays there.
/// This is best effort: when it fails the scan simply stays where it was saved.
Future<void> fileIntoSmartFolder(ScannedDocument doc, ScanMode mode) async {
  final target = smartFolderFor(mode);
  if (target == null || doc.folderId != null) return;
  final folders = (await sl<ListFolders>()()).valueOrNull;
  if (folders == null) return;
  Folder? folder;
  for (final f in folders) {
    if (f.name.trim().toLowerCase() == target.name.toLowerCase()) {
      folder = f;
      break;
    }
  }
  folder ??= (await sl<CreateFolder>()(
    target.name,
    style: FolderStyle(icon: target.icon, color: target.color),
  )).valueOrNull;
  if (folder == null) return;
  await sl<MoveDocument>()(doc.id, folder.id);
}

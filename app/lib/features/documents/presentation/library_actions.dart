import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/di.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/feedback.dart';
import '../../export/domain/repositories/export_repository.dart';
import '../../importer/domain/importer.dart';
import '../../office/sheets/presentation/sheet_page.dart';
import '../../reader/presentation/reader_page.dart';
import '../data/library_files.dart';
import '../domain/entities/scanned_document.dart';
import '../domain/library_target.dart';

IconData libraryKindIcon(LibraryFileKind kind) => switch (kind) {
  LibraryFileKind.pdf => AppIcons.pdf,
  LibraryFileKind.word => AppIcons.editDocument,
  LibraryFileKind.excel => AppIcons.sheet,
  LibraryFileKind.powerpoint => AppIcons.slides,
  LibraryFileKind.text => AppIcons.text,
  LibraryFileKind.image => AppIcons.gallery,
  LibraryFileKind.other => AppIcons.document,
};

Color libraryKindColor(LibraryFileKind kind) => switch (kind) {
  LibraryFileKind.pdf => const Color(0xFFDC2626),
  LibraryFileKind.word => const Color(0xFF2563EB),
  LibraryFileKind.excel => const Color(0xFF16A34A),
  LibraryFileKind.powerpoint => const Color(0xFFEA580C),
  LibraryFileKind.text => AppColors.inkMuted,
  LibraryFileKind.image => AppColors.primary,
  LibraryFileKind.other => AppColors.inkMuted,
};

/// Keeps what an editor made in the library: a new file, or a new version of [existingId]. Returns the library id, or null when it failed.
Future<String?> saveToLibrary(BuildContext context, {required String path, required String title, String? existingId, bool announce = true}) async {
  final library = sl<LibraryFiles>();
  // The copy being saved must not be kept a second time when it is shared next.
  library.dontKeep(path);
  final result = await library.store(path: path, title: existingId == null ? title : null, existingId: existingId);
  if (!context.mounted) return result.valueOrNull?.id;
  final failure = result.failureOrNull;
  if (failure != null) {
    showFailure(context, failure);
    return null;
  }
  if (announce) showMessage(context, 'Saved in Doculoom');
  return result.valueOrNull?.id;
}

/// Opens a file from the library in the tool made for it.
Future<void> openLibraryFile(BuildContext context, ScannedDocument doc) async {
  final path = doc.filePath;
  if (path == null) return;
  final target = LibraryTarget(path: path, id: doc.id);
  switch (doc.fileKind) {
    case LibraryFileKind.word:
      await context.push('/docx-edit', extra: target);
    case LibraryFileKind.excel:
      await context.push('/sheet', extra: SheetArgs(path: path, libraryId: doc.id));
    case LibraryFileKind.powerpoint:
      await context.push('/slides', extra: target);
    case LibraryFileKind.pdf:
      await context.push('/reader', extra: ReaderArgs(path: path, kind: ImportKind.pdf, libraryId: doc.id));
    case LibraryFileKind.text:
      await context.push('/text-file', extra: target);
    case LibraryFileKind.image:
    case LibraryFileKind.other:
      await shareLibraryFile(context, doc);
  }
}

/// Hands a library file to another app under its own name.
Future<void> shareLibraryFile(BuildContext context, ScannedDocument doc) async {
  final library = sl<LibraryFiles>();
  final staged = await library.stage(doc);
  final failure = (await sl<ShareService>().shareFile(path: staged, mimeType: libraryMimeType(doc.fileExtension), subject: doc.title)).failureOrNull;
  if (failure != null && context.mounted) showFailure(context, failure);
}

String libraryMimeType(String extension) => switch (extension.toLowerCase()) {
  'pdf' => 'application/pdf',
  'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'pptx' => 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'csv' => 'text/csv',
  'tsv' => 'text/tab-separated-values',
  'txt' => 'text/plain',
  'md' => 'text/markdown',
  'jpg' || 'jpeg' => 'image/jpeg',
  'png' => 'image/png',
  _ => 'application/octet-stream',
};

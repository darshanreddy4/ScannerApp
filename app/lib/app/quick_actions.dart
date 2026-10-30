import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../core/error/failures.dart';
import '../core/widgets/feedback.dart';
import '../features/importer/domain/importer.dart';
import '../features/reader/presentation/reader_page.dart';
import '../features/scanner/presentation/add_content.dart';
import '../features/scanner/presentation/bloc/scan_session_cubit.dart';
import 'router.dart';

/// The one-tap entries from the home screen: app-icon shortcuts, the widget and the quick-settings tiles.
enum QuickAction {
  scan('scan'),
  idPhoto('id_photo'),
  readPdf('read_pdf'),
  qrScan('qr_scan');

  const QuickAction(this.id);

  /// The id the Android side sends.
  final String id;

  /// The screen this action opens.
  String get route => switch (this) {
    scan => '/scan',
    idPhoto => '/passport-photo',
    readPdf => '/reader',
    qrScan => '/qr-scan',
  };
}

QuickAction? quickActionFrom(String? id) => QuickAction.values.where((a) => a.id == id).firstOrNull;

Future<String?> _pickPdfOrWord() async {
  final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['pdf', 'docx']);
  return picked.isEmpty ? null : picked.first.path;
}

void _openScan(BuildContext context) {
  final open = context.read<ScanSessionCubit>().state.pages.isNotEmpty;
  // Unsaved pages are kept: the camera adds to them instead of starting over.
  if (open) {
    context.push('/scan');
  } else {
    startScan(context);
  }
}

/// Opens the screen for [action]. Nothing happens when that screen is already on top, so a second tap does not stack copies.
Future<void> runQuickAction(
  BuildContext context,
  QuickAction action, {
  GoRouter? router,
  void Function(BuildContext context) openScan = _openScan,
  Future<String?> Function() pickPdf = _pickPdfOrWord,
}) async {
  final r = router ?? appRouter;
  final here = r.routerDelegate.currentConfiguration.last.matchedLocation;
  if (action != QuickAction.readPdf && (here == action.route || here.startsWith('${action.route}/'))) return;
  switch (action) {
    case QuickAction.scan:
      openScan(context);
    case QuickAction.idPhoto:
    case QuickAction.qrScan:
      unawaited(r.push(action.route));
    case QuickAction.readPdf:
      try {
        final path = await pickPdf();
        if (path == null) return;
        await r.push(
          action.route,
          extra: ReaderArgs(path: path, kind: path.toLowerCase().endsWith('.pdf') ? ImportKind.pdf : ImportKind.docx),
        );
      } catch (_) {
        if (context.mounted) showFailure(context, const PermissionFailure('The file picker is unavailable.'));
      }
  }
}

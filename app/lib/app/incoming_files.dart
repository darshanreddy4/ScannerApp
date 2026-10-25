import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

import '../core/theme/app_colors.dart';
import '../features/importer/domain/importer.dart';
import '../features/office/sheets/presentation/sheet_page.dart';
import '../features/reader/presentation/reader_page.dart';
import '../features/scanner/presentation/add_content.dart';
import '../features/scanner/presentation/bloc/scan_session_cubit.dart';
import '../features/settings/presentation/settings_cubit.dart';
import 'router.dart';

enum IncomingKind { pdf, docx, xlsx, csv, pptx, image, unsupported }

IncomingKind classifyIncoming(String path, String mime) {
  final ext = p.extension(path).toLowerCase();
  if (ext == '.pdf' || mime == 'application/pdf') return IncomingKind.pdf;
  if (ext == '.docx' || mime == 'application/vnd.openxmlformats-officedocument.wordprocessingml.document') return IncomingKind.docx;
  if (ext == '.xlsx' || mime == 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet') return IncomingKind.xlsx;
  if (ext == '.csv' || mime == 'text/csv' || mime == 'text/comma-separated-values') return IncomingKind.csv;
  if (ext == '.pptx' || mime == 'application/vnd.openxmlformats-officedocument.presentationml.presentation') return IncomingKind.pptx;
  if (const ['.jpg', '.jpeg', '.png'].contains(ext) || mime == 'image/jpeg' || mime == 'image/png') return IncomingKind.image;
  return IncomingKind.unsupported;
}

/// Opens files other apps send here ("Open with" and "Share to ScanVault").
class IncomingFiles {
  static const _channel = MethodChannel('scanvault/incoming');
  static bool _started = false;

  /// Call once the first frame is up so the router can take a push.
  static Future<void> start() async {
    if (_started) return;
    _started = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'incoming') await _handle(call.arguments);
    });
    try {
      await _handle(await _channel.invokeMethod<List<Object?>>('takePending'));
    } on MissingPluginException {
      // Not running on Android (tests, desktop).
    }
  }

  static Future<void> _handle(Object? raw) async {
    final context = appRouter.routerDelegate.navigatorKey.currentContext;
    if (raw is! List || raw.isEmpty || context == null) return;
    final items = [for (final e in raw) Map<String, String>.from(e as Map)];

    if (items.any((i) => i.containsKey('error')) && items.every((i) => i.containsKey('error'))) {
      _say(context, 'This file could not be opened.');
      return;
    }

    final files = [
      for (final i in items)
        if (i['path'] != null) (path: i['path']!, kind: classifyIncoming(i['path']!, i['mime'] ?? '')),
    ];
    final images = [
      for (final f in files)
        if (f.kind == IncomingKind.image) f.path,
    ];
    final doc = files.where((f) => f.kind == IncomingKind.pdf || f.kind == IncomingKind.docx).firstOrNull;

    final office = files.where((f) => f.kind == IncomingKind.xlsx || f.kind == IncomingKind.csv || f.kind == IncomingKind.pptx).firstOrNull;

    if (office != null) {
      if (office.kind == IncomingKind.pptx) {
        await appRouter.push('/slides', extra: office.path);
      } else {
        await appRouter.push('/sheet', extra: SheetArgs(path: office.path));
      }
    } else if (doc != null) {
      await appRouter.push(
        '/reader',
        extra: ReaderArgs(path: doc.path, kind: doc.kind == IncomingKind.pdf ? ImportKind.pdf : ImportKind.docx),
      );
    } else if (images.isNotEmpty) {
      final session = context.read<ScanSessionCubit>();
      // Unsaved work in the editor is kept: the new images join it instead of replacing it.
      final hasSession = session.state.pages.isNotEmpty;
      if (!hasSession) session.start(defaultFilter: context.read<SettingsCubit>().state.defaultFilter);
      await importImagePaths(context, images, append: hasSession);
    } else {
      _say(context, 'ScanVault opens PDF, Word, Excel, CSV, PowerPoint, JPG and PNG files.');
    }
  }

  static void _say(BuildContext context, String message) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(backgroundColor: AppColors.ink, content: Text(message), persist: false));
  }
}

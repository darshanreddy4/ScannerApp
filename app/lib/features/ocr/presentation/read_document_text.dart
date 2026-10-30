import 'package:flutter/material.dart' hide Text;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/di.dart';
import '../../../core/widgets/feedback.dart';
import '../../documents/domain/entities/scanned_document.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../domain/recognize_document_text.dart';
import '../../../core/widgets/text.dart';

/// Shows a small blocking "working" box while [work] runs.
Future<T> withReadingDialog<T>(BuildContext context, String label, Future<T> Function() work) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Row(mainAxisSize: MainAxisSize.min, children: [const CircularProgressIndicator(), const SizedBox(width: 16), Text(label)]),
          ),
        ),
      ),
    ),
  );
  try {
    return await work();
  } finally {
    navigator.pop();
  }
}

/// Reads the text of every page on the device, and keeps it so the scan can be found by its words.
Future<String?> readDocumentText(BuildContext context, ScannedDocument doc) async {
  final script = context.read<SettingsCubit>().state.ocrScript;
  final result = await withReadingDialog(context, 'Reading text', () => sl<RecognizeDocumentText>()(document: doc, script: script));
  final pages = result.valueOrNull;
  if (pages == null) {
    if (context.mounted) showFailure(context, result.failureOrNull!);
    return null;
  }
  return pages.map((p) => p.plain).join('\n');
}

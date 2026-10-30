import 'dart:async';
import 'package:flutter/material.dart';

import 'app/app.dart';
import 'core/i18n/app_language.dart';
import 'core/i18n/tr.dart';
import 'app/di.dart';
import 'app/incoming_files.dart';
import 'features/qr/domain/share_sessions.dart';
import 'core/storage/temp_files.dart';
import 'features/documents/data/datasources/document_local_data_source.dart';
import 'features/monetization/domain/repositories/monetization_contracts.dart';

Future<void> main() async {
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      debugPrint('Unhandled Flutter error: ${details.exceptionAsString()}');
    };

    // Until the settings are read, text follows the language of the phone.
    Strings.use(AppLanguage.system);
    configureDependencies();
    // Shares keep running outside the app; show the ones that are still active.
    unawaited(sl<ShareSessions>().restore());
    await _cleanStorage();
    unawaited(sl<AdService>().initialize());

    WidgetsBinding.instance.addObserver(_CacheTrimmer());
    runApp(const DoculoomApp());
    WidgetsBinding.instance.addPostFrameCallback((_) => IncomingFiles.start());
  }, (error, stack) => debugPrint('Uncaught error: $error\n$stack'));
}

/// The cache and any half-written page folders are rebuilt on demand, so they are cleared at launch.
Future<void> _cleanStorage() async {
  try {
    await sl<TempFiles>().clearAtStartup();
    await sl<DocumentLocalDataSource>().removeOrphanFiles();
  } catch (e) {
    debugPrint('Storage cleanup skipped: $e');
  }
}

/// Trims shared and exported copies when the app goes to the background.
class _CacheTrimmer with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) sl<TempFiles>().pruneStale().ignore();
  }
}

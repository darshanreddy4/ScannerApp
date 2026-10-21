import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app/app.dart';
import 'app/di.dart';
import 'features/monetization/domain/repositories/monetization_contracts.dart';

Future<void> main() async {
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      debugPrint('Unhandled Flutter error: ${details.exceptionAsString()}');
    };

    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    configureDependencies();
    await _clearStaleWorkFiles();
    unawaited(sl<AdService>().initialize());

    runApp(const ScanVaultApp());
  }, (error, stack) => debugPrint('Uncaught error: $error\n$stack'));
}

/// Temporary scan/export files from earlier sessions are never needed again.
Future<void> _clearStaleWorkFiles() async {
  try {
    final tmp = (await getTemporaryDirectory()).path;
    for (final name in const ['scan_work', 'exports']) {
      final dir = Directory(p.join(tmp, name));
      if (await dir.exists()) await dir.delete(recursive: true);
    }
  } catch (e) {
    debugPrint('Temp cleanup skipped: $e');
  }
}

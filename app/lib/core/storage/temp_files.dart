import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Keeps the app's cache folder small. Everything in it can be rebuilt; documents live elsewhere.
class TempFiles {
  TempFiles({Future<Directory> Function()? tempDir}) : _tempDir = tempDir ?? getTemporaryDirectory;

  final Future<Directory> Function() _tempDir;

  static const scanWorkDir = 'scan_work';

  /// Files received from other apps ("Open with"). They stay a day so a reopened screen still finds them.
  static const incomingDir = 'incoming';
  static const _incomingKeep = Duration(days: 1);
  static const _exportKeep = Duration(minutes: 30);

  // Ad and web caches belong to Google's SDKs.
  static bool _foreign(String name) => name.startsWith('WebView') || name.startsWith('org.chromium');

  /// Nothing in the cache is needed after a restart, except freshly received files.
  Future<void> clearAtStartup() async {
    final tmp = await _tempDir();
    if (!await tmp.exists()) return;
    await for (final e in tmp.list()) {
      final name = p.basename(e.path);
      if (_foreign(name)) continue;
      if (name == incomingDir) {
        await _deleteOlderThan(Directory(e.path), DateTime.now().subtract(_incomingKeep));
      } else {
        await _delete(e);
      }
    }
  }

  /// Removes scan working copies that existed at [cutoff] or earlier. Files a new session creates later are kept.
  Future<void> clearScanWork(DateTime cutoff) async {
    final dir = Directory(p.join((await _tempDir()).path, scanWorkDir));
    if (await dir.exists()) await _deleteOlderThan(dir, cutoff, includeEqual: true);
  }

  /// Drops shared and exported copies that other apps have long finished reading.
  Future<void> pruneStale() async {
    final tmp = await _tempDir();
    if (!await tmp.exists()) return;
    final now = DateTime.now();
    await for (final e in tmp.list()) {
      final name = p.basename(e.path);
      if (_foreign(name) || name == scanWorkDir) continue;
      if (name == incomingDir) {
        await _deleteOlderThan(Directory(e.path), now.subtract(_incomingKeep));
      } else if (e is Directory && (name == 'exports' || name == 'share_images')) {
        await _deleteOlderThan(e, now.subtract(_exportKeep));
      } else if (e is File) {
        final modified = (await e.stat()).modified;
        if (modified.isBefore(now.subtract(_exportKeep))) await _delete(e);
      }
    }
  }

  Future<void> _deleteOlderThan(Directory dir, DateTime cutoff, {bool includeEqual = false}) async {
    if (!await dir.exists()) return;
    await for (final e in dir.list()) {
      final modified = (await e.stat()).modified;
      if (modified.isBefore(cutoff) || (includeEqual && modified == cutoff)) await _delete(e);
    }
  }

  Future<void> _delete(FileSystemEntity e) async {
    try {
      await e.delete(recursive: true);
    } on FileSystemException {
      // Another task may be using it; it is removed on a later pass.
    }
  }
}

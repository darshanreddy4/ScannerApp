import '../../../core/error/result.dart';

/// A running local file share. The file is served only on the local network, never uploaded.
abstract interface class ShareHandle {
  String get url;
  DateTime get expiresAt;

  /// Emits the number of completed downloads each time one finishes.
  Stream<int> get downloads;

  /// Emits once when the share ends (stopped by the user or expired).
  Future<void> get done;

  Future<void> stop();
}

abstract interface class LocalShareServer {
  Future<Result<ShareHandle>> start({
    required String filePath,
    required String fileName,
    required String mimeType,
    Duration ttl = const Duration(minutes: 5),

    /// When set, whoever opens the link must type it before the file is released.
    String? password,
  });
}

/// A running share found again after the app was closed and reopened.
class RestoredShare {
  const RestoredShare({required this.handle, required this.fileName, required this.isProtected});
  final ShareHandle handle;
  final String fileName;
  final bool isProtected;
}

/// A local share server whose shares keep running outside the app screen and can be found again.
abstract interface class RestorableShares {
  Future<List<RestoredShare>> restore();
}

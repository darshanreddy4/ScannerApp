import '../../../core/error/result.dart';
import 'local_share.dart';

/// How the file reaches the other person.
enum ShareMode {
  /// Straight from this phone, only for people on the same Wi-Fi or hotspot. Nothing is uploaded.
  wifi,

  /// Encrypted on this phone, stored on the relay until the link expires, downloadable from any network.
  internet,
}

/// How long a share stays available. Free accounts get [min5]; the rest is Premium.
enum ShareDuration {
  min5(Duration(minutes: 5), '5 min'),
  min15(Duration(minutes: 15), '15 min'),
  min30(Duration(minutes: 30), '30 min'),
  hour1(Duration(hours: 1), '1 hour'),
  hour6(Duration(hours: 6), '6 hours'),
  day1(Duration(days: 1), '1 day'),
  day7(Duration(days: 7), '7 days');

  const ShareDuration(this.value, this.label);
  final Duration value;
  final String label;

  /// A share served from the phone only lives while the phone is on the network, so long times make no sense there.
  bool allowedIn(ShareMode mode) => mode == ShareMode.internet || value <= const Duration(hours: 1);
}

/// Uploads an end-to-end encrypted copy to the relay and returns a link that carries the key.
abstract interface class RemoteShareService {
  /// False when this build has no relay address, so the option is hidden.
  bool get isConfigured;

  /// Largest file the relay accepts.
  int get maxBytes;

  Future<Result<ShareHandle>> start({
    required String filePath,
    required String fileName,
    required String mimeType,
    required Duration ttl,

    /// When set, the file is encrypted with a key made from this password and the link carries no key.
    String? password,
  });
}

/// Rules for the optional share password.
abstract final class SharePassword {
  static const maxLength = 64;

  /// Over the internet the password is the only secret protecting the file, so it must be longer.
  static int minLength(ShareMode mode) => mode == ShareMode.internet ? 8 : 4;

  /// Null when [password] is acceptable, otherwise a message for the person.
  static String? problem(String password, ShareMode mode) {
    final min = minLength(mode);
    if (password.length < min) {
      return mode == ShareMode.internet ? 'Use at least $min characters for internet sharing.' : 'Use at least $min characters.';
    }
    if (password.length > maxLength) return 'Use at most $maxLength characters.';
    return null;
  }
}

/// Brings back an internet share saved by [PersistentShareHandle.toJson].
abstract interface class RemoteShareRestorer {
  ShareHandle? restore(Map<String, Object?> json);
}

/// A share that can be saved, so "Stop sharing" still works after the app was closed.
abstract interface class PersistentShareHandle implements ShareHandle {
  Map<String, Object?> toJson();
}

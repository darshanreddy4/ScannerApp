import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/error/result.dart';
import 'local_share.dart';
import 'share_options.dart';

/// One file that is being shared right now.
class ActiveShare {
  ActiveShare({
    required this.id,
    required this.fileName,
    required this.mimeType,
    required this.mode,
    required this.handle,
    required this.isProtected,
    required this.ttl,
    this.filePath = '',
  });

  final String id;
  final String fileName;
  final String mimeType;
  final ShareMode mode;
  final ShareHandle handle;
  final bool isProtected;
  final Duration ttl;

  /// The file being shared; empty for shares found again after the app was closed.
  final String filePath;
  int downloads = 0;
  bool ended = false;

  String get url => handle.url;
  DateTime get expiresAt => handle.expiresAt;
  bool get expired => ended || !expiresAt.isAfter(DateTime.now());
  Duration get left => expiresAt.difference(DateTime.now());
}

/// Remembers internet shares so "Stop sharing" still reaches the relay after the app was closed.
abstract interface class ShareStore {
  Future<List<Map<String, Object?>>> load();
  Future<void> save(List<Map<String, Object?>> shares);
}

/// Every active share. Shares belong here, not to a screen: leaving the screen does not end a share, only its
/// timer or an explicit stop does.
class ShareSessions {
  ShareSessions({required this.local, required this.remote, ShareStore? store}) : _store = store;

  final LocalShareServer local;
  final RemoteShareService remote;
  final ShareStore? _store;

  /// The shares in start order; a new list is published on every change.
  final ValueNotifier<List<ActiveShare>> shares = ValueNotifier(const []);

  final _subscriptions = <String, StreamSubscription<int>>{};
  int _counter = 0;

  ActiveShare? byId(String id) {
    for (final s in shares.value) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// The newest running share of this file, so opening the same file again shows it instead of starting another.
  ActiveShare? activeFor(String filePath) {
    if (filePath.isEmpty) return null;
    for (final s in shares.value.reversed) {
      if (s.filePath == filePath && !s.expired) return s;
    }
    return null;
  }

  Future<Result<ActiveShare>> start({
    required ShareMode mode,
    required String filePath,
    required String fileName,
    required String mimeType,
    required Duration ttl,
    String? password,
  }) async {
    final result = mode == ShareMode.wifi
        ? await local.start(filePath: filePath, fileName: fileName, mimeType: mimeType, ttl: ttl, password: password)
        : await remote.start(filePath: filePath, fileName: fileName, mimeType: mimeType, ttl: ttl, password: password);
    final handle = result.valueOrNull;
    if (handle == null) return Err(result.failureOrNull!);
    final share = ActiveShare(
      id: _newId(),
      fileName: fileName,
      mimeType: mimeType,
      mode: mode,
      handle: handle,
      isProtected: password != null,
      ttl: ttl,
      filePath: filePath,
    );
    _add(share);
    return Ok(share);
  }

  /// Finds shares that survived the app being closed: the ones running in the phone's service and the saved internet ones.
  Future<void> restore() async {
    final server = local;
    if (server is RestorableShares) {
      for (final found in await (server as RestorableShares).restore()) {
        if (shares.value.any((s) => s.url == found.handle.url)) continue;
        _add(
          ActiveShare(
            id: _newId(),
            fileName: found.fileName,
            mimeType: '',
            mode: ShareMode.wifi,
            handle: found.handle,
            isProtected: found.isProtected,
            ttl: Duration.zero,
          ),
        );
      }
    }
    final restorer = remote;
    final store = _store;
    if (store != null && restorer is RemoteShareRestorer) {
      for (final json in await store.load()) {
        final handle = (restorer as RemoteShareRestorer).restore(json);
        if (handle == null || shares.value.any((s) => s.url == handle.url)) continue;
        _add(
          ActiveShare(
            id: _newId(),
            fileName: json['fileName'] as String? ?? 'File',
            mimeType: json['mimeType'] as String? ?? '',
            mode: ShareMode.internet,
            handle: handle,
            isProtected: json['protected'] == true,
            ttl: Duration.zero,
          ),
        );
      }
      await _persist();
    }
  }

  Future<void> stop(String id) async {
    final share = byId(id);
    if (share == null) return;
    await share.handle.stop();
    _remove(share);
  }

  Future<void> stopAll() async {
    for (final share in List.of(shares.value)) {
      await stop(share.id);
    }
  }

  String _newId() => 'share-${++_counter}-${DateTime.now().microsecondsSinceEpoch}';

  void _add(ActiveShare share) {
    shares.value = [...shares.value, share];
    _subscriptions[share.id] = share.handle.downloads.listen((n) {
      share.downloads = n;
      shares.value = List.of(shares.value);
    });
    share.downloads = 0;
    unawaited(share.handle.done.then((_) => _remove(share)));
    // The expiry timer of the handle may already have fired.
    if (share.expired) _remove(share);
    unawaited(_persist());
  }

  void _remove(ActiveShare share) {
    share.ended = true;
    unawaited(_subscriptions.remove(share.id)?.cancel());
    if (shares.value.contains(share))
      shares.value = [
        for (final s in shares.value)
          if (s != share) s,
      ];
    unawaited(_persist());
  }

  Future<void> _persist() async {
    final store = _store;
    if (store == null) return;
    final saved = <Map<String, Object?>>[
      for (final s in shares.value)
        if (s.handle is PersistentShareHandle && !s.expired)
          {...(s.handle as PersistentShareHandle).toJson(), 'fileName': s.fileName, 'mimeType': s.mimeType, 'protected': s.isProtected},
    ];
    await store.save(saved);
  }
}

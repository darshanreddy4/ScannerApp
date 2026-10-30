import 'dart:async';

import 'package:flutter/services.dart';

import '../../../core/error/failures.dart';
import '../../../core/error/result.dart';
import '../domain/local_share.dart';

/// Android: the file is served by a foreground service, so the link keeps working while the app is minimised or
/// closed. This class only starts and stops shares and reads their state.
class NativeLocalShareServer implements LocalShareServer, RestorableShares {
  NativeLocalShareServer({MethodChannel? channel}) : _channel = channel ?? const MethodChannel('doculoom/share');

  final MethodChannel _channel;

  @override
  Future<Result<ShareHandle>> start({
    required String filePath,
    required String fileName,
    required String mimeType,
    Duration ttl = const Duration(minutes: 5),
    String? password,
  }) => guard(() async {
    final info = await _channel.invokeMapMethod<String, Object?>('start', {
      'filePath': filePath,
      'fileName': fileName,
      'mimeType': mimeType,
      'ttlMs': ttl.inMilliseconds,
      'password': password,
    });
    return _handle(info!);
  }, onError: (e) => ExportFailure(e is PlatformException && e.message != null ? e.message! : 'Sharing could not be started on this network.', cause: e));

  @override
  Future<List<RestoredShare>> restore() async {
    try {
      final list = await _channel.invokeListMethod<Map<Object?, Object?>>('list') ?? const [];
      return [
        for (final raw in list)
          RestoredShare(handle: _handle(raw.cast<String, Object?>()), fileName: raw['fileName']! as String, isProtected: raw['protected'] == true),
      ];
    } on PlatformException {
      return const [];
    }
  }

  ShareHandle _handle(Map<String, Object?> info) => _NativeHandle(
    channel: _channel,
    id: info['id']! as String,
    url: info['url']! as String,
    expiresAt: DateTime.fromMillisecondsSinceEpoch((info['expiresAt']! as num).toInt()),
    initialDownloads: (info['downloads'] as num?)?.toInt() ?? 0,
  );
}

class _NativeHandle implements ShareHandle {
  _NativeHandle({required MethodChannel channel, required this.id, required this.url, required this.expiresAt, int initialDownloads = 0})
    : _channel = channel,
      _count = initialDownloads {
    _poll = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  final MethodChannel _channel;
  final String id;
  @override
  final String url;
  @override
  final DateTime expiresAt;

  final _downloads = StreamController<int>.broadcast();
  final _done = Completer<void>();
  late final Timer _poll;
  int _count;
  bool _stopped = false;

  @override
  Stream<int> get downloads => _downloads.stream;

  @override
  Future<void> get done => _done.future;

  Future<void> _refresh() async {
    if (_stopped) return;
    try {
      final info = await _channel.invokeMapMethod<String, Object?>('info', {'id': id});
      final live = info?['live'] == true;
      final count = (info?['downloads'] as num?)?.toInt() ?? _count;
      if (count != _count && !_downloads.isClosed) {
        _count = count;
        _downloads.add(count);
      }
      if (!live) _finish();
    } on PlatformException {
      // The service answers again on the next tick.
    } on MissingPluginException {
      _finish();
    }
    if (DateTime.now().isAfter(expiresAt)) _finish();
  }

  void _finish() {
    if (_stopped) return;
    _stopped = true;
    _poll.cancel();
    unawaited(_downloads.close());
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Future<void> stop() async {
    if (_stopped) return;
    try {
      await _channel.invokeMethod<void>('stop', {'id': id});
    } on PlatformException {
      // Already gone.
    }
    _finish();
  }
}

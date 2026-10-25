import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scanvault/core/error/failures.dart';
import 'package:scanvault/core/error/result.dart';
import 'package:scanvault/features/qr/data/native_share_server.dart';
import 'package:scanvault/features/qr/data/relay_share_service.dart';
import 'package:scanvault/features/qr/domain/local_share.dart';
import 'package:scanvault/features/qr/domain/share_options.dart';
import 'package:scanvault/features/qr/domain/share_sessions.dart';

class _Store implements ShareStore {
  List<Map<String, Object?>> saved = [];
  @override
  Future<List<Map<String, Object?>>> load() async => saved;
  @override
  Future<void> save(List<Map<String, Object?>> shares) async => saved = shares;
}

class _Handle implements PersistentShareHandle {
  _Handle(this.url, this.expiresAt);
  @override
  final String url;
  @override
  final DateTime expiresAt;
  bool stopped = false;
  final _done = Completer<void>();
  final controller = StreamController<int>.broadcast();

  @override
  Stream<int> get downloads => controller.stream;
  @override
  Future<void> get done => _done.future;
  @override
  Future<void> stop() async {
    stopped = true;
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Map<String, Object?> toJson() => {'id': url, 'deleteToken': 't', 'url': url, 'expiresAt': expiresAt.millisecondsSinceEpoch};
}

class _WifiHandle implements ShareHandle {
  _WifiHandle(this.url, this.expiresAt);
  @override
  final String url;
  @override
  final DateTime expiresAt;
  final _done = Completer<void>();
  final controller = StreamController<int>.broadcast();
  @override
  Stream<int> get downloads => controller.stream;
  @override
  Future<void> get done => _done.future;
  @override
  Future<void> stop() async {
    if (!_done.isCompleted) _done.complete();
  }
}

class _Local implements LocalShareServer {
  @override
  Future<Result<ShareHandle>> start({
    required String filePath,
    required String fileName,
    required String mimeType,
    Duration ttl = const Duration(minutes: 5),
    String? password,
  }) async => Ok(_WifiHandle('http://192.168.1.2:1/a/$fileName', DateTime.now().add(ttl)));
}

class _Remote implements RemoteShareService, RemoteShareRestorer {
  final handles = <_Handle>[];
  @override
  bool get isConfigured => true;
  @override
  int get maxBytes => 1000;
  @override
  Future<Result<ShareHandle>> start({
    required String filePath,
    required String fileName,
    required String mimeType,
    required Duration ttl,
    String? password,
  }) async {
    final h = _Handle('https://relay/d/x#$fileName', DateTime.now().add(ttl));
    handles.add(h);
    return Ok(h);
  }

  @override
  ShareHandle? restore(Map<String, Object?> json) {
    final h = _Handle(json['url']! as String, DateTime.fromMillisecondsSinceEpoch(json['expiresAt']! as int));
    handles.add(h);
    return h;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ShareSessions', () {
    test('a share stays active until it is stopped, whatever screen started it', () async {
      final remote = _Remote();
      final sessions = ShareSessions(local: _Local(), remote: remote, store: _Store());
      final result = await sessions.start(
        mode: ShareMode.internet,
        filePath: '/x',
        fileName: 'a.pdf',
        mimeType: 'application/pdf',
        ttl: const Duration(hours: 1),
        password: 'longpassword',
      );

      final share = result.valueOrNull!;
      expect(sessions.shares.value, [share]);
      expect(share.isProtected, isTrue);
      expect(remote.handles.single.stopped, isFalse);

      await sessions.stop(share.id);
      expect(remote.handles.single.stopped, isTrue);
      expect(sessions.shares.value, isEmpty);
    });

    test('download counts reach the list', () async {
      final sessions = ShareSessions(local: _Local(), remote: _Remote());
      final share = (await sessions.start(
        mode: ShareMode.wifi,
        filePath: '/x',
        fileName: 'a.pdf',
        mimeType: 'application/pdf',
        ttl: const Duration(minutes: 5),
      )).valueOrNull!;
      var notified = 0;
      sessions.shares.addListener(() => notified++);
      (share.handle as _WifiHandle).controller.add(2);
      await Future<void>.delayed(Duration.zero);
      expect(share.downloads, 2);
      expect(notified, greaterThan(0));
    });

    test('a share that ends by itself disappears', () async {
      final sessions = ShareSessions(local: _Local(), remote: _Remote());
      final share = (await sessions.start(
        mode: ShareMode.wifi,
        filePath: '/x',
        fileName: 'a.pdf',
        mimeType: 'application/pdf',
        ttl: const Duration(minutes: 5),
      )).valueOrNull!;
      await share.handle.stop();
      await Future<void>.delayed(Duration.zero);
      expect(sessions.shares.value, isEmpty);
    });

    test('internet shares are saved and brought back after the app restarts, and can still be stopped', () async {
      final store = _Store();
      final first = ShareSessions(local: _Local(), remote: _Remote(), store: store);
      await first.start(mode: ShareMode.internet, filePath: '/x', fileName: 'a.pdf', mimeType: 'application/pdf', ttl: const Duration(hours: 1));
      await Future<void>.delayed(Duration.zero);
      expect(store.saved, hasLength(1));
      expect(store.saved.single['fileName'], 'a.pdf');

      // New process: nothing in memory, only the saved list.
      final remote = _Remote();
      final second = ShareSessions(local: _Local(), remote: remote, store: store);
      await second.restore();
      expect(second.shares.value, hasLength(1));
      expect(second.shares.value.single.fileName, 'a.pdf');
      expect(second.shares.value.single.mode, ShareMode.internet);

      await second.stop(second.shares.value.single.id);
      expect(remote.handles.single.stopped, isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(store.saved, isEmpty);
    });

    test('wi-fi shares are not saved, they are found again from the service', () async {
      final store = _Store();
      final sessions = ShareSessions(local: _Local(), remote: _Remote(), store: store);
      await sessions.start(mode: ShareMode.wifi, filePath: '/x', fileName: 'a.pdf', mimeType: 'application/pdf', ttl: const Duration(minutes: 5));
      await Future<void>.delayed(Duration.zero);
      expect(store.saved, isEmpty);
    });
  });

  group('RelayShareService.restore', () {
    test('brings back a saved share, and ignores bad or finished ones', () {
      final relay = RelayShareService(baseUrl: 'https://relay.example');
      final soon = DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch;
      final handle = relay.restore({'id': 'abc', 'deleteToken': 'tok', 'url': 'https://relay.example/d/abc#k=1', 'expiresAt': soon});
      expect(handle, isNotNull);
      expect(handle!.url, 'https://relay.example/d/abc#k=1');
      expect((handle as PersistentShareHandle).toJson()['deleteToken'], 'tok');

      expect(relay.restore({'id': 'abc'}), isNull);
      expect(
        relay.restore({'id': 'abc', 'deleteToken': 'tok', 'url': 'u', 'expiresAt': DateTime.now().subtract(const Duration(minutes: 1)).millisecondsSinceEpoch}),
        isNull,
      );
    });
  });

  group('NativeLocalShareServer', () {
    const channel = MethodChannel('scanvault/share');
    late List<MethodCall> calls;
    late bool live;
    late int downloads;

    setUp(() {
      calls = [];
      live = true;
      downloads = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        switch (call.method) {
          case 'start':
            return {
              'id': 's1',
              'url': 'http://192.168.1.5:4000/tok/a.pdf',
              'fileName': 'a.pdf',
              'expiresAt': DateTime.now().add(const Duration(minutes: 5)).millisecondsSinceEpoch,
              'downloads': 0,
              'protected': false,
            };
          case 'info':
            return {'live': live, 'downloads': downloads};
          case 'list':
            return [
              {
                'id': 's9',
                'url': 'http://192.168.1.5:4000/t/b.pdf',
                'fileName': 'b.pdf',
                'expiresAt': DateTime.now().add(const Duration(minutes: 9)).millisecondsSinceEpoch,
                'downloads': 3,
                'protected': true,
              },
            ];
        }
        return null;
      });
    });

    tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

    test('starts a share in the service and sends the options along', () async {
      final result = await NativeLocalShareServer().start(
        filePath: '/f.pdf',
        fileName: 'a.pdf',
        mimeType: 'application/pdf',
        ttl: const Duration(minutes: 15),
        password: 'secret',
      );
      final handle = result.valueOrNull!;
      expect(handle.url, 'http://192.168.1.5:4000/tok/a.pdf');
      final args = calls.single.arguments as Map;
      expect(args['ttlMs'], 15 * 60 * 1000);
      expect(args['password'], 'secret');
      expect(args['filePath'], '/f.pdf');
      await handle.stop();
    });

    test('the handle reports downloads and ends when the service says it ended', () async {
      final handle = (await NativeLocalShareServer().start(filePath: '/f', fileName: 'a.pdf', mimeType: 'x')).valueOrNull!;
      final seen = <int>[];
      handle.downloads.listen(seen.add);
      downloads = 1;
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(seen, [1]);

      live = false;
      await handle.done.timeout(const Duration(seconds: 3));
    });

    test('stop tells the service', () async {
      final handle = (await NativeLocalShareServer().start(filePath: '/f', fileName: 'a.pdf', mimeType: 'x')).valueOrNull!;
      await handle.stop();
      expect(calls.last.method, 'stop');
      expect((calls.last.arguments as Map)['id'], 's1');
      await handle.done;
    });

    test('a missing Wi-Fi connection becomes a readable failure', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'no_network', message: 'Connect to Wi-Fi first.'),
      );
      final result = await NativeLocalShareServer().start(filePath: '/f', fileName: 'a.pdf', mimeType: 'x');
      expect(result.failureOrNull, isA<ExportFailure>());
      expect(result.failureOrNull!.message, 'Connect to Wi-Fi first.');
    });

    test('shares still running after a restart are found again', () async {
      final found = await NativeLocalShareServer().restore();
      expect(found, hasLength(1));
      expect(found.single.fileName, 'b.pdf');
      expect(found.single.isProtected, isTrue);

      final sessions = ShareSessions(local: NativeLocalShareServer(), remote: _Remote());
      await sessions.restore();
      expect(sessions.shares.value.single.fileName, 'b.pdf');
      await sessions.shares.value.single.handle.stop();
    });
  });
}

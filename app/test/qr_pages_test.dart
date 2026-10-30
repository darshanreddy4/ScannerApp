import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:doculoom/app/di.dart';
import 'package:doculoom/core/theme/app_icons.dart';
import 'support/coins_fakes.dart';
import 'package:doculoom/features/rewards/domain/coin_rules.dart';
import 'package:doculoom/features/monetization/domain/repositories/monetization_contracts.dart' show RewardResult;
import 'package:doculoom/features/rewards/presentation/coins_cubit.dart';
import 'package:doculoom/core/error/failures.dart';
import 'package:doculoom/core/error/result.dart';
import 'package:doculoom/features/monetization/domain/entities/plan_status.dart';
import 'package:doculoom/features/monetization/domain/repositories/monetization_contracts.dart';
import 'package:doculoom/features/monetization/presentation/plan_cubit.dart';
import 'package:doculoom/features/qr/domain/local_share.dart';
import 'package:doculoom/features/qr/domain/share_options.dart';
import 'package:doculoom/features/qr/domain/share_sessions.dart';
import 'package:doculoom/features/qr/presentation/qr_share_page.dart';
import 'package:doculoom/features/tools/presentation/tools_view.dart';

class _Handle implements ShareHandle {
  _Handle(this.url, {Duration ttl = const Duration(minutes: 5)}) : expiresAt = DateTime.now().add(ttl);
  bool stopped = false;
  final _done = Completer<void>();

  @override
  final String url;
  @override
  final DateTime expiresAt;
  @override
  Stream<int> get downloads => const Stream.empty();
  @override
  Future<void> get done => _done.future;
  @override
  Future<void> stop() async {
    stopped = true;
    if (!_done.isCompleted) _done.complete();
  }
}

class _Server implements LocalShareServer {
  _Server({this.failure});
  final Failure? failure;
  final handles = <_Handle>[];
  final ttls = <Duration>[];
  final passwords = <String?>[];

  @override
  Future<Result<ShareHandle>> start({
    required String filePath,
    required String fileName,
    required String mimeType,
    Duration ttl = const Duration(minutes: 5),
    String? password,
  }) async {
    if (failure != null) return Err(failure!);
    ttls.add(ttl);
    passwords.add(password);
    final h = _Handle('http://192.168.1.20:5050/abc123/contract.pdf', ttl: ttl);
    handles.add(h);
    return Ok(h);
  }
}

class _Remote implements RemoteShareService {
  _Remote({this.configured = true});
  final bool configured;
  final handles = <_Handle>[];
  final ttls = <Duration>[];
  final passwords = <String?>[];

  @override
  bool get isConfigured => configured;
  @override
  int get maxBytes => 25 * 1024 * 1024;

  @override
  Future<Result<ShareHandle>> start({
    required String filePath,
    required String fileName,
    required String mimeType,
    required Duration ttl,
    String? password,
  }) async {
    ttls.add(ttl);
    passwords.add(password);
    final h = _Handle('https://relay.example/d/id123#k=key&n=contract.pdf', ttl: ttl);
    handles.add(h);
    return Ok(h);
  }
}

class _Plans implements PlanRepository {
  _Plans(this.plan);
  final PlanStatus plan;
  @override
  Future<PlanStatus> current() async => plan;
  @override
  Future<void> setPlan(PlanStatus plan) async {}
}

void main() {
  const args = QrShareArgs(filePath: '/tmp/contract.pdf', fileName: 'contract.pdf', mimeType: 'application/pdf');

  setUp(() async => sl.reset());

  Future<void> open(
    WidgetTester tester, {
    PlanStatus plan = PlanStatus.free,
    bool billing = false,
    bool rewards = false,
    CoinsCubit? coins,
    Size size = const Size(400, 1000),
  }) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    if (!sl.isRegistered<ShareSessions>()) sl.registerSingleton(ShareSessions(local: sl(), remote: sl()));
    final cubit = PlanCubit(_Plans(plan));
    await tester.runAsync(cubit.load);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: TextButton(onPressed: () => context.push('/share'), child: const Text('OPEN')),
          ),
          routes: [
            GoRoute(
              path: 'share',
              builder: (_, _) => QrSharePage(args: args, billingEnabled: billing, rewardsEnabled: rewards),
            ),
            GoRoute(
              path: 'paywall',
              builder: (_, _) => const Scaffold(body: Text('PAYWALL')),
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: cubit),
          BlocProvider.value(value: coins ?? coinsCubit()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows a QR code for the link and Stop sharing switches the server off', (tester) async {
    final server = _Server();
    sl
      ..registerSingleton<LocalShareServer>(server)
      ..registerSingleton<RemoteShareService>(_Remote());
    await open(tester);

    expect(find.byType(QrImageView), findsOneWidget);
    await tester.scrollUntilVisible(find.byType(SelectableText), 100);
    expect(find.byWidgetPredicate((w) => w is SelectableText && w.data == server.handles.single.url), findsOneWidget);
    expect(find.textContaining('Expires in'), findsOneWidget);
    expect(server.handles.single.stopped, isFalse);

    await tester.tap(find.text('Stop sharing'));
    await tester.pumpAndSettle();

    expect(server.handles.single.stopped, isTrue);
    expect(find.byType(QrImageView), findsNothing);
    expect(sl<ShareSessions>().shares.value, isEmpty);
  });

  testWidgets('leaving the screen keeps the share running until it is stopped', (tester) async {
    final server = _Server();
    sl
      ..registerSingleton<LocalShareServer>(server)
      ..registerSingleton<RemoteShareService>(_Remote());
    await open(tester);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.byType(QrImageView), findsNothing);
    expect(server.handles.single.stopped, isFalse, reason: 'going back must not switch the link off');
    final share = sl<ShareSessions>().shares.value.single;
    expect(share.url, server.handles.single.url);

    // Opening it again shows the same link without starting a second server.
    await tester.pumpWidget(const SizedBox());
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => QrSharePage(args: QrShareArgs.resume(share.id)),
        ),
      ],
    );
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider(create: (_) => PlanCubit(_Plans(PlanStatus.free))),
          BlocProvider.value(value: coinsCubit()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsOneWidget);
    expect(server.handles.length, 1);
    expect(find.text('Same Wi-Fi'), findsNothing, reason: 'the options of a running share are fixed');

    await tester.tap(find.text('Stop sharing'));
    await tester.pumpAndSettle();
    expect(server.handles.single.stopped, isTrue);
  });

  testWidgets('an expired share is removed from the active list', (tester) async {
    final server = _Server();
    sl
      ..registerSingleton<LocalShareServer>(server)
      ..registerSingleton<RemoteShareService>(_Remote());
    await open(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(sl<ShareSessions>().shares.value, hasLength(1));

    await server.handles.single.stop();
    await tester.pumpAndSettle();
    expect(sl<ShareSessions>().shares.value, isEmpty);
  });

  testWidgets('explains how to fix a missing Wi-Fi connection', (tester) async {
    sl
      ..registerSingleton<LocalShareServer>(_Server(failure: const ExportFailure('Connect to Wi-Fi (or turn on a hotspot) to share with a QR code.')))
      ..registerSingleton<RemoteShareService>(_Remote());
    await open(tester);

    expect(find.textContaining('Connect to Wi-Fi'), findsOneWidget);
    expect(find.byType(QrImageView), findsNothing);
  });

  testWidgets('Anywhere stops the Wi-Fi share and starts an internet share', (tester) async {
    final server = _Server();
    final remote = _Remote();
    sl
      ..registerSingleton<LocalShareServer>(server)
      ..registerSingleton<RemoteShareService>(remote);
    await open(tester);

    await tester.tap(find.text('Anywhere'));
    await tester.pumpAndSettle();

    expect(server.handles.single.stopped, isTrue);
    expect(remote.handles.length, 1);
    expect(find.textContaining('any network or mobile data'), findsOneWidget);
    expect(find.textContaining('downloads'), findsNothing);

    await tester.tap(find.text('Stop sharing'));
    await tester.pumpAndSettle();
    expect(remote.handles.single.stopped, isTrue);
  });

  testWidgets('Anywhere is unavailable when no relay is configured', (tester) async {
    final server = _Server();
    sl
      ..registerSingleton<LocalShareServer>(server)
      ..registerSingleton<RemoteShareService>(_Remote(configured: false));
    await open(tester);

    expect(find.textContaining('not set up in this version'), findsOneWidget);
    await tester.tap(find.text('Anywhere'));
    await tester.pumpAndSettle();
    expect(server.handles.length, 1, reason: 'tapping a disabled option must not restart the share');
  });

  testWidgets('Free users keep 5 minutes and are sent to Upgrade when purchases exist', (tester) async {
    final server = _Server();
    sl
      ..registerSingleton<LocalShareServer>(server)
      ..registerSingleton<RemoteShareService>(_Remote());
    await open(tester, billing: true);

    await tester.tap(find.text('1 hour'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Premium feature'), findsOneWidget);
    expect(server.handles.length, 1);
    expect(server.ttls.single, const Duration(minutes: 5));

    await tester.tap(find.text('Upgrade'));
    await tester.pumpAndSettle();
    expect(find.text('PAYWALL'), findsOneWidget);
  });

  testWidgets('Premium users choose how long the share lasts', (tester) async {
    final server = _Server();
    final remote = _Remote();
    sl
      ..registerSingleton<LocalShareServer>(server)
      ..registerSingleton<RemoteShareService>(remote);
    await open(tester, plan: PlanStatus.premium, billing: true);

    await tester.tap(find.text('30 min'));
    await tester.pumpAndSettle();
    expect(server.ttls.last, const Duration(minutes: 30));
    expect(server.handles.first.stopped, isTrue);

    await tester.tap(find.text('Anywhere'));
    await tester.pumpAndSettle();
    expect(find.text('7 days'), findsOneWidget);
    await tester.tap(find.text('7 days'));
    await tester.pumpAndSettle();
    expect(remote.ttls.last, const Duration(days: 7));
    expect(find.textContaining('Expires in 6d'), findsOneWidget);
  });

  group('coins', () {
    Future<_Server> setUp(
      WidgetTester tester, {
      int coins = 0,
      List<RewardResult> videos = const [],
      PlanStatus plan = PlanStatus.free,
      MemoryWallet? wallet,
      int? dailyAdCap,
      Failure? serverFailure,
      bool freeUsed = true,
    }) async {
      final server = _Server(failure: serverFailure);
      sl
        ..registerSingleton<LocalShareServer>(server)
        ..registerSingleton<RemoteShareService>(_Remote());
      final w = wallet ?? MemoryWallet(balance: coins);
      if (freeUsed) w.freeUsed.add(CoinFeature.qrShare.id);
      final cubit = coinsCubit(wallet: w, ads: ScriptedAds(videos), dailyAdCap: dailyAdCap);
      await tester.runAsync(cubit.load);
      await open(tester, plan: plan, billing: true, rewards: true, coins: cubit);
      return server;
    }

    testWidgets('a Free user without coins is offered a video, and walking away starts no share', (tester) async {
      final server = await setUp(tester);
      expect(find.text('Not enough coins'), findsOneWidget);
      expect(find.textContaining('costs 1 coin and you have 0'), findsOneWidget);
      expect(find.text('Watch video (+10)'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(server.ttls, isEmpty, reason: 'nothing was shared');
      expect(find.text('OPEN'), findsOneWidget, reason: 'back on the screen before');
    });

    testWidgets('every new share costs 1 coin, and its time can then be changed at no extra cost', (tester) async {
      final wallet = MemoryWallet(balance: 5);
      final server = await setUp(tester, wallet: wallet);
      expect(find.text('Use 1 coin?'), findsOneWidget);
      await tester.tap(find.text('Use 1 coin'));
      await tester.pumpAndSettle();

      expect(server.ttls, [const Duration(minutes: 5)]);
      expect(wallet.balance, 4);
      expect(find.byIcon(AppIcons.lock), findsNothing, reason: 'the time chips are no longer locked');

      await tester.tap(find.text('1 hour'));
      await tester.pumpAndSettle();
      expect(find.text('Use 1 coin?'), findsNothing);
      expect(server.ttls.last, const Duration(hours: 1));
      expect(wallet.balance, 4);
    });

    testWidgets('declining to spend the coins starts no share and keeps the coins', (tester) async {
      final wallet = MemoryWallet(balance: 5);
      final server = await setUp(tester, wallet: wallet);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(server.ttls, isEmpty);
      expect(wallet.balance, 5);
      expect(find.text('OPEN'), findsOneWidget);
    });

    testWidgets('watching a video to the end pays 10 coins and continues to the purchase', (tester) async {
      final wallet = MemoryWallet();
      final server = await setUp(tester, videos: [RewardResult.earned], wallet: wallet);
      await tester.tap(find.text('Watch video (+10)'));
      await tester.pumpAndSettle();

      expect(find.text('Use 1 coin?'), findsOneWidget, reason: 'now affordable, so it asks to spend');
      await tester.tap(find.text('Use 1 coin'));
      await tester.pumpAndSettle();
      expect(wallet.balance, 9);
      expect(wallet.adsToday, 1);
      expect(server.ttls, [const Duration(minutes: 5)]);
    });

    testWidgets('a video closed early pays nothing and starts no share', (tester) async {
      final wallet = MemoryWallet();
      final server = await setUp(tester, videos: [RewardResult.dismissed], wallet: wallet);
      await tester.tap(find.text('Watch video (+10)'));
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();

      expect(wallet.balance, 0);
      expect(server.ttls, isEmpty);
      expect(find.text('OPEN'), findsOneWidget);
    });

    testWidgets('Premium users share without coins', (tester) async {
      final wallet = MemoryWallet();
      final server = await setUp(tester, plan: PlanStatus.premium, wallet: wallet);
      expect(find.textContaining('coins'), findsNothing);
      expect(server.ttls, [const Duration(minutes: 5)]);
      await tester.tap(find.text('1 hour'));
      await tester.pumpAndSettle();
      expect(server.ttls.last, const Duration(hours: 1));
      expect(wallet.balance, 0);
    });

    testWidgets('coins are given back when the share could not start', (tester) async {
      final wallet = MemoryWallet(balance: 5);
      final server = await setUp(tester, wallet: wallet, serverFailure: const ExportFailure('Connect to Wi-Fi first.'));
      await tester.tap(find.text('Use 1 coin'));
      await tester.pumpAndSettle();
      expect(server.ttls, isEmpty);
      expect(wallet.balance, 5, reason: 'nothing was shared, so nothing was paid');
    });

    testWidgets('opening a file that is already being shared shows the same share and costs nothing', (tester) async {
      final wallet = MemoryWallet(balance: 5);
      final server = await setUp(tester, wallet: wallet);
      await tester.tap(find.text('Use 1 coin'));
      await tester.pumpAndSettle();
      expect(wallet.balance, 4);
      expect(server.handles.length, 1);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(server.handles.single.stopped, isFalse, reason: 'leaving the screen keeps sharing');

      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('OPEN'));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('already-sharing')), findsOneWidget);
        expect(find.text('Use 1 coin?'), findsNothing);
        expect(find.byType(QrImageView), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
      expect(server.handles.length, 1, reason: 'no second share was started');
      expect(sl<ShareSessions>().shares.value.length, 1);
      expect(wallet.balance, 4);
    });

    testWidgets('after Stop sharing, sharing the file again is a new share that is paid for again', (tester) async {
      final wallet = MemoryWallet(balance: 5);
      final server = await setUp(tester, wallet: wallet);
      await tester.tap(find.text('Use 1 coin'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stop sharing'));
      await tester.pumpAndSettle();
      expect(sl<ShareSessions>().shares.value, isEmpty);

      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();
      expect(find.text('Use 1 coin?'), findsOneWidget);
      await tester.tap(find.text('Use 1 coin'));
      await tester.pumpAndSettle();
      expect(server.handles.length, 2);
      expect(wallet.balance, 3);
    });

    testWidgets('with no daily limit the video is offered however many were watched', (tester) async {
      await setUp(tester, wallet: MemoryWallet(adsToday: 500));
      expect(find.textContaining('Watch video'), findsOneWidget);
      expect(find.textContaining('used today'), findsNothing);
    });

    testWidgets('after a configured daily limit there is no video offer', (tester) async {
      final server = await setUp(tester, wallet: MemoryWallet(adsToday: 10), dailyAdCap: 10);
      expect(find.text('Not enough coins'), findsOneWidget);
      expect(find.textContaining('used today'), findsOneWidget);
      expect(find.textContaining('Watch video'), findsNothing);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(server.ttls, isEmpty);
    });
  });

  testWidgets('without coins in play, opening the same file twice shows the running share and starts no second one', (tester) async {
    final server = _Server();
    sl
      ..registerSingleton<LocalShareServer>(server)
      ..registerSingleton<RemoteShareService>(_Remote());
    await open(tester);
    expect(server.handles.length, 1);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();
    expect(server.handles.length, 1);
    expect(find.byKey(const ValueKey('already-sharing')), findsOneWidget);
    expect(find.text('Stop sharing'), findsOneWidget);
  });

  group('password', () {
    Future<void> setPassword(WidgetTester tester, String text) async {
      await tester.tap(find.text('Protect with a password'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), text);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
    }

    testWidgets('setting a password restarts the share with it, and Remove takes it off', (tester) async {
      final server = _Server();
      sl
        ..registerSingleton<LocalShareServer>(server)
        ..registerSingleton<RemoteShareService>(_Remote());
      await open(tester);
      expect(server.passwords, [null]);

      await setPassword(tester, 'open sesame');
      expect(server.passwords, [null, 'open sesame']);
      expect(server.handles.first.stopped, isTrue, reason: 'the old unprotected link is switched off');
      expect(find.text('Password protected'), findsOneWidget);
      expect(find.textContaining('must type the password'), findsOneWidget);

      await tester.tap(find.text('Password protected'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(server.passwords.last, isNull);
      expect(find.text('Protect with a password'), findsOneWidget);
    });

    testWidgets('a password that is too short is refused with a reason', (tester) async {
      final server = _Server();
      sl
        ..registerSingleton<LocalShareServer>(server)
        ..registerSingleton<RemoteShareService>(_Remote());
      await open(tester);

      await setPassword(tester, 'abc');
      expect(find.text('Use at least 4 characters.'), findsOneWidget);
      expect(server.passwords, [null], reason: 'nothing restarted');

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Protect with a password'), findsOneWidget);
    });

    testWidgets('internet sharing needs 8 characters and a short Wi-Fi password is dropped when switching', (tester) async {
      final server = _Server();
      final remote = _Remote();
      sl
        ..registerSingleton<LocalShareServer>(server)
        ..registerSingleton<RemoteShareService>(remote);
      await open(tester);

      await setPassword(tester, 'abcd');
      expect(server.passwords.last, 'abcd');

      await tester.tap(find.text('Anywhere'));
      await tester.pumpAndSettle();
      expect(remote.passwords, [null], reason: 'a 4-character password is not accepted online');
      expect(find.textContaining('Password removed'), findsOneWidget);
      expect(find.text('Protect with a password'), findsOneWidget);

      await setPassword(tester, 'longer password');
      expect(remote.passwords.last, 'longer password');
      expect(find.textContaining('contains no key'), findsOneWidget);
    });

    testWidgets('a long enough password survives switching modes', (tester) async {
      final server = _Server();
      final remote = _Remote();
      sl
        ..registerSingleton<LocalShareServer>(server)
        ..registerSingleton<RemoteShareService>(remote);
      await open(tester);

      await setPassword(tester, 'long enough pass');
      await tester.tap(find.text('Anywhere'));
      await tester.pumpAndSettle();
      expect(remote.passwords, ['long enough pass']);
    });
  });

  testWidgets('long durations are not offered for Wi-Fi sharing', (tester) async {
    sl
      ..registerSingleton<LocalShareServer>(_Server())
      ..registerSingleton<RemoteShareService>(_Remote());
    await open(tester, plan: PlanStatus.premium, billing: true);

    expect(find.text('1 hour'), findsOneWidget);
    expect(find.text('6 hours'), findsNothing);
    expect(find.text('7 days'), findsNothing);
  });

  for (final size in const [Size(1280, 800), Size(800, 1280)]) {
    testWidgets('the share screen stays a readable column on a ${size.width.toInt()}x${size.height.toInt()} tablet', (tester) async {
      sl
        ..registerSingleton<LocalShareServer>(_Server())
        ..registerSingleton<RemoteShareService>(_Remote());
      await open(tester, size: size);

      final qr = tester.getRect(find.byType(QrImageView));
      expect(qr.width, lessThanOrEqualTo(260));
      expect(qr.center.dx, closeTo(size.width / 2, 2), reason: 'centred');
      expect(find.text('Same Wi-Fi'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('tools hub lists the file and photo tools', (tester) async {
    tester.view.physicalSize = const Size(400 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ToolsView())));
    for (final title in [
      'Read PDF or Word',
      'Edit a PDF',
      'Edit text in a PDF',
      'Edit a Word file',
      'Edit text in a Word file',
      'Combine files',
      'Compress PDF',
      'Lock or unlock PDF',
      'Split and number PDF',
      'Signature',
      'Fill a PDF form',
      'Hide text in a PDF',
      'Crop PDF pages',
      'PDF to pictures',
      'Flatten PDF',
      'Spreadsheets (Excel and CSV)',
      'Table to Excel',
      'Presentations (PowerPoint)',
      'Passport and ID photos',
      'ID card copy',
      'Compress photos',
      'Add watermark',
      'Remove photo data',
      'QR code generator',
    ]) {
      await tester.scrollUntilVisible(find.text(title), 200);
      expect(find.text(title), findsOneWidget, reason: title);
    }
  });

  testWidgets('Table to Excel asks whether to scan or choose a photo, and closing the question does nothing', (tester) async {
    tester.view.physicalSize = const Size(400 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ToolsView())));
    await tester.scrollUntilVisible(find.text('Table to Excel'), 200);
    await tester.tap(find.text('Table to Excel'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('table-camera')), findsOneWidget);
    expect(find.byKey(const ValueKey('table-gallery')), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('table-camera')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

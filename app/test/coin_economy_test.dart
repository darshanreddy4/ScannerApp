import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:doculoom/app/di.dart';
import 'package:doculoom/features/documents/data/datasources/document_local_data_source.dart';
import 'package:doculoom/features/documents/data/repositories/document_repository_impl.dart';
import 'package:doculoom/features/documents/domain/entities/scanned_document.dart';
import 'package:doculoom/features/documents/domain/usecases/document_usecases.dart';
import 'package:doculoom/features/documents/presentation/bloc/documents_cubit.dart';
import 'package:doculoom/features/documents/presentation/pages/home_page.dart';
import 'package:doculoom/features/documents/presentation/widgets/document_widgets.dart';
import 'package:doculoom/features/monetization/domain/ad_pass.dart';
import 'package:doculoom/features/monetization/domain/entities/plan_status.dart';
import 'package:doculoom/features/monetization/domain/repositories/monetization_contracts.dart';
import 'package:doculoom/features/monetization/presentation/inline_ad.dart';
import 'package:doculoom/features/monetization/presentation/plan_cubit.dart';
import 'package:doculoom/features/rewards/data/coin_wallet_impl.dart';
import 'package:doculoom/features/rewards/domain/coin_rules.dart';
import 'package:doculoom/features/rewards/presentation/coins_cubit.dart';
import 'package:doculoom/features/rewards/presentation/passes_sheet.dart';
import 'package:doculoom/features/rewards/presentation/unlock.dart';
import 'package:doculoom/features/settings/data/settings_repository.dart';
import 'package:doculoom/features/settings/domain/app_settings.dart';
import 'package:doculoom/features/settings/presentation/settings_cubit.dart';
import 'package:doculoom/features/tools/presentation/tools_view.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/coins_fakes.dart';

class _Plans implements PlanRepository {
  _Plans([this.plan = PlanStatus.free]);
  final PlanStatus plan;
  @override
  Future<PlanStatus> current() async => plan;
  @override
  Future<void> setPlan(PlanStatus plan) async {}
}

class _Prefs implements SettingsRepository {
  @override
  Future<AppSettings> load() async => const AppSettings();
  @override
  Future<void> save(AppSettings settings) async {}
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  tearDown(() {
    AdPass.until.value = null;
    AdPass.now = DateTime.now;
  });

  group('the price list', () {
    test('free, light and heavy cost 0, 1 and 5 coins', () {
      expect(CoinTier.values.map((t) => t.cost), [0, 1, 5]);
      expect(CoinFeature.tool('Compress PDF', CoinTier.heavy).cost, 5);
      expect(CoinFeature.specialFilters.cost, 1);
      expect(CoinFeature.editSavedDocument.cost, 5);
    });

    test('only a light tool has a free use each day', () {
      expect(CoinFeature.readText.hasFreeDailyUse, isTrue);
      expect(CoinFeature.editSavedDocument.hasFreeDailyUse, isFalse);
    });

    test('the passes ask for 5, 12, 20 and 23 videos for 30 minutes, 2, 6 and 24 hours', () {
      expect(passTiers.map((t) => (t.minutes, t.videos)), [(30, 5), (120, 12), (360, 20), (1440, 23)]);
      expect(passTiers.map((t) => t.label), ['30 minutes', '2 hours', '6 hours', '24 hours']);
    });

    test('a person gets 3 free coins a day and 10 for a video', () {
      expect((CoinRules.dailyCoins, CoinRules.rewardPerAd), (3, 10));
    });

    test('the filters that come with every scan are free', () {
      expect(freeFilterNames, {'original', 'auto', 'magicColor', 'documentBw', 'grayscale'});
    });
  });

  group('the wallet', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('the daily coins are given once a day', () async {
      var now = DateTime(2026, 10, 29, 9);
      final w = CoinWalletImpl(clock: () => now);
      expect(await w.claimDaily(3), 3);
      expect(await w.claimDaily(3), 0);
      expect((await w.read()).balance, 3);
      now = DateTime(2026, 10, 30, 0, 1);
      expect(await w.claimDaily(3), 3);
      expect((await w.read()).balance, 6, reason: 'unused coins are kept');
    });

    test('a pass starts with its last video and counts them on the way', () async {
      final now = DateTime(2026, 10, 29, 9);
      final w = CoinWalletImpl(clock: () => now);
      for (var i = 1; i <= 4; i++) {
        final s = await w.countPassVideo(minutes: 30, needed: 5, length: const Duration(minutes: 30));
        expect((s.passProgress, s.passUntil), (i, null));
      }
      final s = await w.countPassVideo(minutes: 30, needed: 5, length: const Duration(minutes: 30));
      expect(s.passUntil, now.add(const Duration(minutes: 30)));
      expect(s.passProgress, 0);
    });

    test('a second pass adds its time to the one that is running', () async {
      final now = DateTime(2026, 10, 29, 9);
      final w = CoinWalletImpl(clock: () => now);
      await w.countPassVideo(minutes: 30, needed: 1, length: const Duration(minutes: 30));
      final s = await w.countPassVideo(minutes: 120, needed: 1, length: const Duration(hours: 2));
      expect(s.passUntil, now.add(const Duration(minutes: 150)));
    });

    test('choosing another pass starts the count again, and a new day does too', () async {
      var now = DateTime(2026, 10, 29, 9);
      final w = CoinWalletImpl(clock: () => now);
      await w.countPassVideo(minutes: 30, needed: 5, length: const Duration(minutes: 30));
      await w.countPassVideo(minutes: 30, needed: 5, length: const Duration(minutes: 30));
      final other = await w.countPassVideo(minutes: 120, needed: 12, length: const Duration(hours: 2));
      expect((other.passMinutes, other.passProgress), (120, 1));
      now = DateTime(2026, 10, 30, 9);
      expect((await w.read()).passProgress, 0);
    });

    test('a pass that has ended is gone', () async {
      var now = DateTime(2026, 10, 29, 9);
      final w = CoinWalletImpl(clock: () => now);
      await w.countPassVideo(minutes: 30, needed: 1, length: const Duration(minutes: 30));
      expect((await w.read()).passUntil, isNotNull);
      now = DateTime(2026, 10, 29, 9, 31);
      expect((await w.read()).passUntil, isNull);
    });

    test('each tool has one free use a day', () async {
      var now = DateTime(2026, 10, 29, 9);
      final w = CoinWalletImpl(clock: () => now);
      expect(await w.useFreeDaily('a'), isTrue);
      expect(await w.useFreeDaily('a'), isFalse);
      expect(await w.useFreeDaily('b'), isTrue);
      now = DateTime(2026, 10, 30, 9);
      expect(await w.useFreeDaily('a'), isTrue);
    });
  });

  group('opening a tool without coins', () {
    final heavy = CoinFeature.tool('Compress PDF', CoinTier.heavy);
    final light = CoinFeature.tool('Signature', CoinTier.light);

    test('a heavy tool is not covered, and stays open for ten minutes once paid for', () async {
      var now = DateTime(2026, 10, 29, 9);
      final c = coinsCubit(clock: () => now);
      expect(await c.coverWithoutCoins(heavy), UnlockCover.none);
      c.markPaid(heavy);
      expect(await c.coverWithoutCoins(heavy), UnlockCover.grace);
      expect(await c.coverWithoutCoins(CoinFeature.tool('Flatten PDF', CoinTier.heavy)), UnlockCover.none);
      now = now.add(const Duration(minutes: 11));
      expect(await c.coverWithoutCoins(heavy), UnlockCover.none);
    });

    test('a light tool is free once a day, then stays open ten minutes, then costs a coin', () async {
      var now = DateTime(2026, 10, 29, 9);
      final c = coinsCubit(clock: () => now);
      expect(await c.coverWithoutCoins(light), UnlockCover.freeDaily);
      expect(await c.coverWithoutCoins(light), UnlockCover.grace);
      now = now.add(const Duration(minutes: 11));
      expect(await c.coverWithoutCoins(light), UnlockCover.none);
    });

    test('a cost that is per action does not stay open', () async {
      final c = coinsCubit();
      c.markPaid(CoinFeature.qrShare);
      expect(await c.coverWithoutCoins(CoinFeature.qrShare), UnlockCover.freeDaily, reason: 'only its free use of the day');
      expect(await c.coverWithoutCoins(CoinFeature.qrShare), UnlockCover.none);
    });

    test('a running pass opens everything, and the ad code sees it', () async {
      final now = DateTime(2026, 10, 29, 9);
      AdPass.now = () => now;
      final c = coinsCubit(wallet: MemoryWallet()..now = () => now, ads: ScriptedAds([for (var i = 0; i < 5; i++) RewardResult.earned]), clock: () => now);
      for (var i = 0; i < 5; i++) {
        expect(await c.watchForPass(passTiers.first), RewardResult.earned);
      }
      expect(c.passActive, isTrue);
      expect(AdPass.active, isTrue);
      expect(await c.coverWithoutCoins(heavy), UnlockCover.pass);
      expect(c.state.balance, 0, reason: 'a video for a pass pays no coins');
    });

    test('a video closed early does not count toward a pass', () async {
      final wallet = MemoryWallet();
      final c = coinsCubit(wallet: wallet, ads: ScriptedAds([RewardResult.dismissed, RewardResult.earned]));
      await c.watchForPass(passTiers.first);
      expect(wallet.passProgress, 0);
      await c.watchForPass(passTiers.first);
      expect(wallet.passProgress, 1);
      expect(c.state.progressFor(passTiers.first), 1);
      expect(c.state.progressFor(passTiers[1]), 0);
    });

    test('a video refused for lack of consent earns nothing and opens nothing', () async {
      final c = coinsCubit(ads: ScriptedAds([RewardResult.consentNeeded]));
      expect(await c.watchAd(), RewardResult.consentNeeded);
      expect(c.state.balance, 0);
    });

    test('videos that fail to load never open a tool: coins are the only way in', () async {
      final c = coinsCubit(ads: ScriptedAds());
      for (var i = 0; i < 4; i++) {
        expect(await c.watchAd(), RewardResult.unavailable);
        expect(await c.coverWithoutCoins(heavy), UnlockCover.none);
      }
      expect(c.state.balance, 0);
    });

    test('the daily coins are added to the balance', () async {
      final c = coinsCubit(wallet: MemoryWallet(dailyClaim: 3));
      expect(await c.claimDaily(), 3);
      expect(c.state.balance, 3);
      expect(await c.claimDaily(), 0);
    });
  });

  group('when interstitials may show', () {
    const policy = AdPolicy();
    final now = DateTime(2026, 10, 29, 9);

    bool shows({bool foreground = true, bool adFree = false}) =>
        policy.shouldShowInterstitial(plan: PlanStatus.free, lastShownAt: null, now: now, actionsSinceLastAd: 2, foreground: foreground, adFree: adFree);

    test('only when the app is on screen', () {
      expect(shows(), isTrue);
      expect(shows(foreground: false), isFalse);
    });

    test('never during a pass, and never for Premium', () {
      expect(shows(adFree: true), isFalse);
      expect(policy.shouldShowInterstitial(plan: PlanStatus.premium, lastShownAt: null, now: now, actionsSinceLastAd: 5), isFalse);
    });

    test('at most one in two actions, and not right after another', () {
      expect(policy.shouldShowInterstitial(plan: PlanStatus.free, lastShownAt: null, now: now, actionsSinceLastAd: 1), isFalse);
      expect(
        policy.shouldShowInterstitial(plan: PlanStatus.free, lastShownAt: now.subtract(const Duration(minutes: 1)), now: now, actionsSinceLastAd: 2),
        isFalse,
      );
    });
  });

  group('asking to open a tool', () {
    Future<List<bool>> run(WidgetTester tester, CoinsCubit coins, CoinFeature feature, {int times = 1}) async {
      final results = <bool>[];
      await tester.pumpWidget(
        BlocProvider.value(
          value: coins,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(onPressed: () async => results.add(await requestUnlock(context, feature)), child: const Text('go')),
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < times; i++) {
        await tester.tap(find.text('go'));
        await tester.pumpAndSettle();
      }
      return results;
    }

    final heavy = CoinFeature.tool('Compress PDF', CoinTier.heavy);
    final light = CoinFeature.tool('Signature', CoinTier.light);

    testWidgets('a heavy tool asks for 5 coins, takes them, and is then open again for ten minutes', (tester) async {
      final wallet = MemoryWallet(balance: 12);
      final coins = coinsCubit(wallet: wallet);
      final results = await run(tester, coins, heavy);
      expect(find.text('Use 5 coins?'), findsOneWidget);
      await tester.tap(find.text('Use 5 coins'));
      await tester.pumpAndSettle();
      expect(results, [true]);
      expect(wallet.balance, 7);

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text('Use 5 coins?'), findsNothing);
      expect(results, [true, true]);
      expect(wallet.balance, 7, reason: 'the same tool again within ten minutes is free');
    });

    testWidgets('the first use of a light tool each day is free and says so; the next costs 1 coin', (tester) async {
      final wallet = MemoryWallet(balance: 3);
      final coins = coinsCubit(wallet: wallet);
      final results = await run(tester, coins, light);
      expect(results, [true]);
      expect(find.text('This is your free use of it for today'), findsOneWidget);
      expect(wallet.balance, 3);

      final other = CoinFeature.tool('Signature', CoinTier.light);
      wallet.freeUsed.add(other.id);
      final again = coinsCubit(wallet: wallet);
      await run(tester, again, other);
      expect(find.text('Use 1 coin?'), findsOneWidget);
    });

    testWidgets('with too few coins the choices are cancel, passes and a video', (tester) async {
      final coins = coinsCubit(wallet: MemoryWallet(balance: 2));
      final results = await run(tester, coins, heavy);
      expect(find.text('Not enough coins'), findsOneWidget);
      expect(find.textContaining('costs 5 coins and you have 2'), findsOneWidget);
      expect(find.byKey(const ValueKey('unlock-passes')), findsOneWidget);
      expect(find.text('Watch video (+10)'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(results, [false]);
    });

    testWidgets('a video that is watched adds 10 coins and leads to the question', (tester) async {
      final wallet = MemoryWallet(balance: 0);
      final coins = coinsCubit(wallet: wallet, ads: ScriptedAds([RewardResult.earned, RewardResult.earned]));
      final results = await run(tester, coins, heavy);
      await tester.tap(find.text('Watch video (+10)'));
      await tester.pumpAndSettle();
      expect(find.text('Use 5 coins?'), findsOneWidget);
      await tester.tap(find.text('Use 5 coins'));
      await tester.pumpAndSettle();
      expect(results, [true]);
      expect(wallet.balance, 5);
    });

    testWidgets('when no video loads nothing opens, however often it is tried, and the message says to go online', (tester) async {
      final wallet = MemoryWallet();
      final coins = coinsCubit(wallet: wallet, ads: ScriptedAds());
      final results = await run(tester, coins, heavy);
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('Watch video (+10)'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Turn on mobile data or Wi-Fi'), findsOneWidget);
        await tester.pumpAndSettle(const Duration(seconds: 5));
        await tester.tap(find.text('go'));
        await tester.pumpAndSettle();
      }
      expect(results, [false, false, false]);
      expect(wallet.balance, 0);
    });

    testWidgets('when ads are off by the privacy choice the message is about consent, not the connection, and offers the consent screen', (tester) async {
      await sl.reset();
      final ads = ScriptedAds([RewardResult.consentNeeded, RewardResult.consentNeeded]);
      sl.registerSingleton<AdService>(ads);
      final coins = coinsCubit(ads: ads);
      final results = await run(tester, coins, heavy);
      await tester.tap(find.text('Watch video (+10)'));
      await tester.pumpAndSettle();
      expect(find.text('Ad consent needed'), findsOneWidget);
      expect(find.textContaining('Turn on mobile data'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('consent-open')));
      await tester.pumpAndSettle();
      expect(ads.privacyOpened, 1);
      expect(find.text('Watch video (+10)'), findsOneWidget, reason: 'after the consent screen the video can be offered again');

      await tester.tap(find.text('Watch video (+10)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(ads.privacyOpened, 1, reason: 'Cancel does not open it');
      expect(results, [false]);
      await sl.reset();
    });

    testWidgets('coins earned online are spent with no connection at all', (tester) async {
      final wallet = MemoryWallet(balance: 5);
      final coins = coinsCubit(wallet: wallet, ads: ScriptedAds());
      final results = await run(tester, coins, heavy);
      await tester.tap(find.text('Use 5 coins'));
      await tester.pumpAndSettle();
      expect(results, [true]);
      expect(wallet.balance, 0);
    });

    testWidgets('a pass opens the tool, and the passes sheet shows exactly what each one asks for', (tester) async {
      final wallet = MemoryWallet();
      final coins = coinsCubit(wallet: wallet, ads: ScriptedAds([for (var i = 0; i < 5; i++) RewardResult.earned]));
      final results = await run(tester, coins, heavy);
      await tester.tap(find.byKey(const ValueKey('unlock-passes')));
      await tester.pumpAndSettle();
      for (final pass in passTiers) {
        expect(find.textContaining('Watch ${pass.videos} videos to unlock all tools and remove ads for ${pass.label}.'), findsOneWidget);
        expect(find.text('0 of ${pass.videos} watched today'), findsOneWidget);
      }
      for (var i = 1; i <= 5; i++) {
        await tester.tap(find.byKey(const ValueKey('pass-watch-30')));
        await tester.pumpAndSettle(const Duration(seconds: 5));
      }
      expect(find.byKey(const ValueKey('pass-running')), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(results, [true], reason: 'the tool opens once the pass has started');
    });

    testWidgets('the passes sheet counts each video and refuses none that were closed early', (tester) async {
      final coins = coinsCubit(ads: ScriptedAds([RewardResult.earned, RewardResult.dismissed, RewardResult.earned]));
      await tester.pumpWidget(
        BlocProvider.value(
          value: coins,
          child: const MaterialApp(home: Scaffold(body: PassesSheet())),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('pass-watch-120')));
      await tester.pumpAndSettle(const Duration(seconds: 5));
      expect(find.text('1 of 12 watched today'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pass-watch-120')));
      await tester.pumpAndSettle(const Duration(seconds: 5));
      expect(find.text('1 of 12 watched today'), findsOneWidget, reason: 'a video closed early does not count');
      await tester.tap(find.byKey(const ValueKey('pass-watch-120')));
      await tester.pumpAndSettle(const Duration(seconds: 5));
      expect(find.text('2 of 12 watched today'), findsOneWidget);
    });
  });

  group('the tools screen', () {
    Future<GoRouter> open(WidgetTester tester, {required MemoryWallet wallet, ScriptedAds? ads, PlanStatus plan = PlanStatus.free}) async {
      tester.view.physicalSize = const Size(400 * 3, 3000 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: ToolsView()),
          ),
          GoRoute(
            path: '/compress-pdf',
            builder: (_, _) => const Scaffold(body: Text('compress opened')),
          ),
          GoRoute(
            path: '/signature',
            builder: (_, _) => const Scaffold(body: Text('signature opened')),
          ),
          GoRoute(
            path: '/qr',
            builder: (_, _) => const Scaffold(body: Text('qr opened')),
          ),
        ],
      );
      final plans = PlanCubit(_Plans(plan));
      await tester.runAsync(plans.load);
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider.value(value: plans),
            BlocProvider(
              create: (_) => coinsCubit(wallet: wallet, ads: ads),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      return router;
    }

    Future<void> tapTool(WidgetTester tester, String title) async {
      final tile = find.text(title).first;
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      await tester.tap(tile);
      await tester.pumpAndSettle();
    }

    testWidgets('a heavy tool asks for coins, and cancelling opens nothing', (tester) async {
      await open(tester, wallet: MemoryWallet(balance: 1));
      await tapTool(tester, 'Compress PDF');
      expect(find.text('Not enough coins'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('compress opened'), findsNothing);
    });

    testWidgets('a heavy tool opens after paying 5 coins', (tester) async {
      final wallet = MemoryWallet(balance: 6);
      await open(tester, wallet: wallet);
      await tapTool(tester, 'Compress PDF');
      await tester.tap(find.text('Use 5 coins'));
      await tester.pumpAndSettle();
      expect(find.text('compress opened'), findsOneWidget);
      expect(wallet.balance, 1);
    });

    testWidgets('a light tool opens free the first time and shows why', (tester) async {
      final wallet = MemoryWallet(balance: 0);
      await open(tester, wallet: wallet);
      await tapTool(tester, 'Signature');
      expect(find.text('signature opened'), findsOneWidget);
      expect(wallet.balance, 0);
      expect(wallet.freeUsed, contains('tool:Signature'));
    });

    testWidgets('one ad slot sits between the tool groups', (tester) async {
      await open(tester, wallet: MemoryWallet());
      expect(find.byType(InlineAd, skipOffstage: false), findsOneWidget);
    });

    testWidgets('Premium opens every tool at once', (tester) async {
      final wallet = MemoryWallet(balance: 0);
      await open(tester, wallet: wallet, plan: PlanStatus.premium);
      await tapTool(tester, 'Compress PDF');
      expect(find.text('compress opened'), findsOneWidget);
      expect(find.text('Not enough coins'), findsNothing);
    });

    testWidgets('a running pass opens every tool without coins', (tester) async {
      final wallet = MemoryWallet(balance: 0, passUntil: DateTime.now().add(const Duration(hours: 1)));
      await open(tester, wallet: wallet);
      await tester.runAsync(() async {});
      await tapTool(tester, 'Compress PDF');
      expect(find.text('compress opened'), findsOneWidget);
    });
  });

  group('the banner in the document list', () {
    late Directory root;
    late Directory work;
    late DocumentRepositoryImpl repo;

    setUp(() async {
      await sl.reset();
      root = Directory.systemTemp.createTempSync('sv_ban_root');
      work = Directory.systemTemp.createTempSync('sv_ban_work');
      repo = DocumentRepositoryImpl(DocumentLocalDataSource(rootDir: root));
    });

    tearDown(() {
      root.deleteSync(recursive: true);
      work.deleteSync(recursive: true);
    });

    Future<void> doc(String title) async {
      final f = File(p.join(work.path, '$title.jpg'))..writeAsStringSync(title);
      await repo.saveDocument(
        title: title,
        pages: [NewPage(imagePath: f.path, rawPath: f.path, width: 10, height: 10)],
      );
    }

    DocumentsCubit cubit() => DocumentsCubit(
      listDocuments: ListDocuments(repo),
      listFolders: ListFolders(repo),
      deleteDocument: DeleteDocument(repo),
      renameDocument: RenameDocument(repo),
      moveDocument: MoveDocument(repo),
      mergeDocuments: MergeDocuments(repo),
      createFolder: CreateFolder(repo),
      renameFolder: RenameFolder(repo),
      updateFolderMeta: UpdateFolderMeta(repo),
      deleteFolder: DeleteFolder(repo),
    );

    Future<void> show(WidgetTester tester, int count) async {
      tester.view.physicalSize = const Size(390 * 3, 1600 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.runAsync(() async {
        for (var i = 1; i <= count; i++) {
          await doc('Doc $i');
        }
      });
      sl.registerSingleton<AdService>(ScriptedAds());
      final docs = cubit();
      await tester.runAsync(docs.load);
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider(create: (_) => PlanCubit(_Plans())),
            BlocProvider(create: (_) => SettingsCubit(_Prefs())),
            BlocProvider.value(value: docs),
            BlocProvider(create: (_) => coinsCubit()),
          ],
          child: const MaterialApp(home: HomePage()),
        ),
      );
      await tester.pumpAndSettle();
    }

    double top(WidgetTester tester, Finder f) => tester.getTopLeft(f).dy;

    // With no ad loaded the slot is empty, so it is outside what the tree reports as visible.
    Finder slot(WidgetTester tester) => find.byType(InlineAd, skipOffstage: false);

    testWidgets('no ad slot with no documents or one, which have nothing to sit between', (tester) async {
      await show(tester, 1);
      expect(slot(tester), findsNothing);
    });

    // The empty slot takes no space, so its place is read from the sliver order, not from pixels.
    int before(WidgetTester tester) {
      final group = tester.widget<SliverMainAxisGroup>(find.byType(SliverMainAxisGroup));
      expect(group.children[1], isA<SliverToBoxAdapter>());
      expect(find.descendant(of: find.byWidget(group.children[1], skipOffstage: false), matching: slot(tester), skipOffstage: false), findsOneWidget);
      final cards = find.byWidgetPredicate((w) => w is DocumentGridCard || w is DocumentListTile, description: 'document card');
      return find.descendant(of: find.byWidget(group.children[0], skipOffstage: false), matching: cards, skipOffstage: false).evaluate().length;
    }

    testWidgets('with two documents the ad slot sits between them', (tester) async {
      await show(tester, 2);
      expect(slot(tester), findsOneWidget);
      expect(before(tester), inInclusiveRange(1, 2));
    });

    testWidgets('with more documents there is one ad slot, after the first one to three', (tester) async {
      await show(tester, 5);
      expect(slot(tester), findsOneWidget);
      expect(before(tester), inInclusiveRange(1, 3));
    });

    testWidgets('nothing is fixed above the navigation bar', (tester) async {
      await show(tester, 3);
      final bar = find.byType(NavigationBar);
      expect(bar, findsOneWidget);
      expect(find.ancestor(of: bar, matching: slot(tester)), findsNothing);
      final column = find.ancestor(of: bar, matching: find.byType(Column)).first;
      expect(find.descendant(of: column, matching: slot(tester)), findsNothing);
    });
  });
}

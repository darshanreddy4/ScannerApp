import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:scanvault/app/app_config.dart';
import 'package:scanvault/app/di.dart';
import 'package:scanvault/core/error/failures.dart';
import 'package:scanvault/core/error/result.dart';
import 'package:scanvault/features/export/domain/repositories/export_repository.dart';
import 'package:scanvault/features/monetization/domain/entities/plan_status.dart';
import 'package:scanvault/features/monetization/domain/repositories/monetization_contracts.dart';
import 'package:scanvault/features/monetization/presentation/plan_cubit.dart';
import 'package:scanvault/features/settings/data/settings_repository.dart';
import 'package:scanvault/features/settings/domain/app_settings.dart';
import 'package:scanvault/features/settings/presentation/app_links.dart';
import 'package:scanvault/features/settings/presentation/settings_cubit.dart';
import 'package:scanvault/features/settings/presentation/settings_view.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'support/coins_fakes.dart';

class _Plans implements PlanRepository {
  @override
  Future<PlanStatus> current() async => PlanStatus.free;
  @override
  Future<void> setPlan(PlanStatus plan) async {}
}

class _Prefs implements SettingsRepository {
  @override
  Future<AppSettings> load() async => const AppSettings();
  @override
  Future<void> save(AppSettings settings) async {}
}

class _Share implements ShareService {
  String? text;
  String? subject;
  Failure? failure;

  @override
  Future<Result<void>> shareText({required String text, String? subject}) async {
    this.text = text;
    this.subject = subject;
    return failure != null ? Err(failure!) : const Ok(null);
  }

  @override
  Future<Result<void>> shareFile({required String path, required String mimeType, String? subject}) async => const Ok(null);
  @override
  Future<Result<void>> shareFiles({required List<String> paths, required String mimeType, String? subject}) async => const Ok(null);
}

class _Launcher extends UrlLauncherPlatform with MockPlatformInterfaceMixin {
  final opened = <String>[];
  final unavailable = <String>{};

  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    opened.add(url);
    return !unavailable.any(url.startsWith);
  }
}

void main() {
  late _Share share;
  late _Launcher launcher;

  setUp(() async {
    share = _Share();
    launcher = _Launcher();
    UrlLauncherPlatform.instance = launcher;
    await sl.reset();
    sl
      ..registerSingleton<ShareService>(share)
      ..registerSingleton<AdService>(ScriptedAds());
  });

  Future<void> openSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider(create: (_) => PlanCubit(_Plans())),
          BlocProvider(create: (_) => SettingsCubit(_Prefs())),
          BlocProvider(create: (_) => coinsCubit()),
        ],
        child: const MaterialApp(home: Scaffold(body: SettingsView())),
      ),
    );
  }

  Future<void> reveal(WidgetTester tester, Finder f) async {
    await tester.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(f);
    await tester.pump();
  }

  test('the link points to the Google Play page of this app', () {
    expect(AppConfig.androidPackage, 'com.scanvault.scanvault');
    expect(AppConfig.appStoreUrl, 'https://play.google.com/store/apps/details?id=com.scanvault.scanvault');
    expect(shareMessage(), contains(AppConfig.appStoreUrl));
    expect(shareMessage(), contains('ScanVault'));
  });

  testWidgets('Settings has Share the app and Rate us', (tester) async {
    await openSettings(tester);
    await reveal(tester, find.byKey(const ValueKey('share-app')));
    expect(find.text('Share the app'), findsOneWidget);
    await reveal(tester, find.byKey(const ValueKey('rate-app')));
    expect(find.text('Rate us'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Share the app opens the share sheet with the message and link', (tester) async {
    await openSettings(tester);
    await reveal(tester, find.byKey(const ValueKey('share-app')));
    await tester.tap(find.byKey(const ValueKey('share-app')));
    await tester.pump();
    expect(share.text, shareMessage());
    expect(share.subject, 'ScanVault');
  });

  testWidgets('a share sheet that cannot open is reported', (tester) async {
    share.failure = const ExportFailure('The share sheet could not be opened.');
    await openSettings(tester);
    await reveal(tester, find.byKey(const ValueKey('share-app')));
    await tester.tap(find.byKey(const ValueKey('share-app')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('The share sheet could not be opened.'), findsOneWidget);
  });

  testWidgets('Rate us opens the Play Store app first', (tester) async {
    await openSettings(tester);
    await reveal(tester, find.byKey(const ValueKey('rate-app')));
    await tester.tap(find.byKey(const ValueKey('rate-app')));
    await tester.pump();
    expect(launcher.opened, ['market://details?id=com.scanvault.scanvault']);
  });

  testWidgets('without the Play Store app, Rate us opens the web page', (tester) async {
    launcher.unavailable.add('market://');
    await openSettings(tester);
    await reveal(tester, find.byKey(const ValueKey('rate-app')));
    await tester.tap(find.byKey(const ValueKey('rate-app')));
    await tester.pump();
    expect(launcher.opened, ['market://details?id=com.scanvault.scanvault', AppConfig.appStoreUrl]);
  });

  testWidgets('if nothing can open, the person is told where to rate', (tester) async {
    launcher.unavailable.addAll(['market://', 'https://']);
    await openSettings(tester);
    await reveal(tester, find.byKey(const ValueKey('rate-app')));
    await tester.tap(find.byKey(const ValueKey('rate-app')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Search for ScanVault'), findsOneWidget);
  });
}

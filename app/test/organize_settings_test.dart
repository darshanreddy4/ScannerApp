import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:doculoom/app/di.dart';
import 'package:doculoom/core/theme/app_theme.dart';
import 'package:doculoom/features/monetization/domain/entities/plan_status.dart';
import 'package:doculoom/features/monetization/domain/repositories/monetization_contracts.dart';
import 'package:doculoom/features/monetization/presentation/plan_cubit.dart';
import 'package:doculoom/features/reminders/domain/reminder_service.dart';
import 'package:doculoom/features/settings/data/settings_repository.dart';
import 'package:doculoom/features/settings/domain/app_settings.dart';
import 'package:doculoom/features/settings/presentation/settings_cubit.dart';
import 'package:doculoom/features/settings/presentation/settings_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/coins_fakes.dart';
import 'support/reminder_fakes.dart';

class _Plans implements PlanRepository {
  @override
  Future<PlanStatus> current() async => PlanStatus.free;
  @override
  Future<void> setPlan(PlanStatus plan) async {}
}

class _NoAds implements AdService {
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> privacyOptionsRequired() async => false;
  @override
  Future<void> showPrivacyOptions() async {}
  @override
  Future<RewardResult> showRewarded() async => RewardResult.unavailable;
  @override
  Future<void> showInterstitialIfEligible(PlanStatus plan) async {}
}

class _Prefs implements SettingsRepository {
  _Prefs(this.initial);
  final AppSettings initial;
  AppSettings? saved;
  @override
  Future<AppSettings> load() async => initial;
  @override
  Future<void> save(AppSettings settings) async => saved = settings;
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await sl.reset();
    sl
      ..registerSingleton<AdService>(_NoAds())
      ..registerSingleton(ReminderService(FakeReminderPlatform()));
  });

  test('naming and filing are on for everyone until they are turned off', () {
    const s = AppSettings();
    expect(s.autoName, isTrue);
    expect(s.smartFolders, isTrue);
    expect(s.copyWith(autoName: false).autoName, isFalse);
    expect(s.copyWith(autoName: false).smartFolders, isTrue);
    expect(s.copyWith(smartFolders: false), isNot(s));
  });

  test('both choices are kept between visits, and an install from before has them on', () async {
    final repo = SettingsRepositoryImpl();
    expect((await repo.load()).autoName, isTrue);
    await repo.save((await repo.load()).copyWith(autoName: false, smartFolders: false));
    final again = await repo.load();
    expect(again.autoName, isFalse);
    expect(again.smartFolders, isFalse);
    await repo.save(again.copyWith(smartFolders: true));
    final third = await repo.load();
    expect(third.autoName, isFalse, reason: 'one choice does not change the other');
    expect(third.smartFolders, isTrue);
  });

  testWidgets('the switches are shown, reflect the settings and are saved when changed', (tester) async {
    tester.view.physicalSize = const Size(400 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final prefs = _Prefs(const AppSettings());
    final cubit = SettingsCubit(prefs);
    await tester.runAsync(cubit.load);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider(create: (_) => PlanCubit(_Plans())),
          BlocProvider.value(value: cubit),
          BlocProvider(create: (_) => coinsCubit()),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: SettingsView()),
        ),
      ),
    );
    await tester.pump();
    await tester.scrollUntilVisible(find.byKey(const ValueKey('setting-auto-name')), 200, scrollable: find.byType(Scrollable).first);
    expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('setting-auto-name'))).value, isTrue);
    expect(find.textContaining('A name you chose is never changed'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('setting-auto-name')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('setting-auto-name')));
    await tester.pump();
    expect(cubit.state.autoName, isFalse);
    expect(prefs.saved!.autoName, isFalse);
    expect(prefs.saved!.smartFolders, isTrue);

    await tester.scrollUntilVisible(find.byKey(const ValueKey('setting-smart-folders')), 200, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.byKey(const ValueKey('setting-smart-folders')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('setting-smart-folders')));
    await tester.pump();
    expect(cubit.state.smartFolders, isFalse);
    expect(prefs.saved!.autoName, isFalse);
    expect(tester.takeException(), isNull);
  });
}

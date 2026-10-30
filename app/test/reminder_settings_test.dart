import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:doculoom/app/di.dart';
import 'package:doculoom/core/theme/app_theme.dart';
import 'package:doculoom/features/monetization/domain/entities/plan_status.dart';
import 'package:doculoom/features/monetization/domain/repositories/monetization_contracts.dart';
import 'package:doculoom/features/monetization/presentation/plan_cubit.dart';
import 'package:doculoom/features/reminders/data/reminder_platform.dart';
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
  _Prefs([this.initial = const AppSettings()]);
  final AppSettings initial;
  AppSettings? saved;
  @override
  Future<AppSettings> load() async => initial;
  @override
  Future<void> save(AppSettings settings) async => saved = settings;
}

void main() {
  late FakeReminderPlatform platform;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await sl.reset();
    sl.registerSingleton<AdService>(_NoAds());
  });

  Future<_Prefs> open(
    WidgetTester tester, {
    ReminderAccess access = ReminderAccess.granted,
    ReminderAccess? afterAsk,
    AppSettings settings = const AppSettings(),
    bool register = true,
  }) async {
    platform = FakeReminderPlatform(access: access, afterAsk: afterAsk);
    if (register) sl.registerSingleton(ReminderService(platform));
    tester.view.physicalSize = const Size(400 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final prefs = _Prefs(settings);
    final settingsCubit = SettingsCubit(prefs);
    await tester.runAsync(settingsCubit.load);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider(create: (_) => PlanCubit(_Plans())),
          BlocProvider.value(value: settingsCubit),
          BlocProvider(create: (_) => coinsCubit()),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: SettingsView()),
        ),
      ),
    );
    await tester.pump();
    await tester.scrollUntilVisible(find.byKey(const ValueKey('reminders-switch'), skipOffstage: false), 200, scrollable: find.byType(Scrollable).first);
    await tester.pump();
    return prefs;
  }

  String subtitle(WidgetTester tester) => tester.widget<Text>(find.byKey(const ValueKey('reminders-subtitle'))).data!;
  bool on(WidgetTester tester, String key) => tester.widget<SwitchListTile>(find.byKey(ValueKey(key))).value;

  testWidgets('with permission the reminders say when they come', (tester) async {
    await open(tester);
    expect(on(tester, 'reminders-switch'), isTrue);
    expect(subtitle(tester), contains('30 days before, 7 days before and on the day'));
    expect(find.byKey(const ValueKey('reminders-open-settings')), findsNothing);
  });

  testWidgets('names are off by default', (tester) async {
    await open(tester);
    expect(on(tester, 'reminders-names'), isFalse);
  });

  testWidgets('when notifications are blocked the screen says so and offers the phone settings', (tester) async {
    await open(tester, access: ReminderAccess.blocked);
    expect(subtitle(tester), contains('turned off for Doculoom'));
    await tester.ensureVisible(find.byKey(const ValueKey('reminders-open-settings')));
    await tester.tap(find.byKey(const ValueKey('reminders-open-settings')));
    await tester.pump();
    expect(platform.settingsOpened, 1);
  });

  testWidgets('when notifications are not allowed yet it says when it will ask', (tester) async {
    await open(tester, access: ReminderAccess.denied);
    expect(subtitle(tester), contains('asked to allow notifications'));
  });

  testWidgets('where the phone cannot do reminders the switch is off and unusable, with an honest note', (tester) async {
    await open(tester, access: ReminderAccess.unsupported);
    expect(on(tester, 'reminders-switch'), isFalse);
    expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('reminders-switch'))).onChanged, isNull);
    expect(subtitle(tester), contains('Not available on this phone'));
  });

  testWidgets('without the service registered (other platforms) the screen still works', (tester) async {
    await open(tester, register: false);
    expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('reminders-switch'))).onChanged, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('turning reminders off is saved, switches the names option off for use, and the explanation goes', (tester) async {
    final prefs = await open(tester);
    await tester.tap(find.byKey(const ValueKey('reminders-switch')));
    await tester.pump();
    await tester.pump();
    expect(prefs.saved!.expiryReminders, isFalse);
    expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('reminders-names'))).onChanged, isNull, reason: 'nothing to show names in');
    expect(subtitle(tester), startsWith('Off.'));
  });

  testWidgets('turning reminders on asks for permission once when the phone can still ask', (tester) async {
    final prefs = await open(tester, access: ReminderAccess.denied, afterAsk: ReminderAccess.granted, settings: const AppSettings(expiryReminders: false));
    await tester.tap(find.byKey(const ValueKey('reminders-switch')));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(prefs.saved!.expiryReminders, isTrue);
    expect(platform.requests, 1);
    expect(subtitle(tester), contains('30 days before'));

    await tester.tap(find.byKey(const ValueKey('reminders-switch')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('reminders-switch')));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    expect(platform.requests, 1, reason: 'the question is not shown again and again');
  });

  testWidgets('the names option can be turned on', (tester) async {
    final prefs = await open(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('reminders-names')));
    await tester.tap(find.byKey(const ValueKey('reminders-names')));
    await tester.pump();
    expect(prefs.saved!.reminderShowNames, isTrue);
  });
}

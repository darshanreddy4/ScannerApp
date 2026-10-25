import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scanvault/app/di.dart';
import 'support/coins_fakes.dart';
import 'package:scanvault/features/monetization/domain/entities/plan_status.dart';
import 'package:scanvault/features/monetization/domain/repositories/monetization_contracts.dart';
import 'package:scanvault/features/monetization/presentation/plan_cubit.dart';
import 'package:scanvault/features/settings/data/settings_repository.dart';
import 'package:scanvault/features/settings/domain/app_settings.dart';
import 'package:scanvault/features/settings/presentation/settings_cubit.dart';
import 'package:scanvault/features/settings/presentation/settings_view.dart';

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
  @override
  Future<AppSettings> load() async => const AppSettings();
  @override
  Future<void> save(AppSettings settings) async {}
}

void main() {
  setUpAll(() {
    if (!sl.isRegistered<AdService>()) sl.registerSingleton<AdService>(_NoAds());
  });

  testWidgets('settings labels keep readable widths on a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
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

    for (final label in ['Camera quality', 'Default filter', 'Export quality']) {
      final finder = find.text(label, skipOffstage: false);
      await tester.scrollUntilVisible(finder, 200, scrollable: find.byType(Scrollable).first);
      final width = tester.getSize(finder).width;
      expect(width, greaterThan(90), reason: '"$label" must not be squeezed into a narrow column');
    }
    expect(tester.takeException(), isNull);
  });
}

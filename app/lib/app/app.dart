import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/theme/app_theme.dart';
import '../core/widgets/responsive.dart';
import '../features/documents/presentation/bloc/documents_cubit.dart';
import '../features/monetization/presentation/plan_cubit.dart';
import '../features/rewards/presentation/coins_cubit.dart';
import '../features/scanner/presentation/bloc/scan_session_cubit.dart';
import '../features/settings/domain/app_settings.dart';
import '../features/settings/presentation/settings_cubit.dart';
import 'di.dart';
import 'router.dart';

class ScanVaultApp extends StatelessWidget {
  const ScanVaultApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => sl<PlanCubit>()..load()),
        BlocProvider(create: (_) => sl<SettingsCubit>()..load()),
        BlocProvider(create: (_) => sl<CoinsCubit>()..load()),
        BlocProvider(create: (_) => sl<DocumentsCubit>()..load()),
        BlocProvider(create: (_) => sl<ScanSessionCubit>()),
      ],
      child: MaterialApp.router(
        title: 'ScanVault',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        routerConfig: appRouter,
        // Very large system fonts would break dense screens, so text is capped at 130%.
        builder: (context, child) {
          final size = context.select((SettingsCubit c) => c.state.interfaceSize);
          final system = MediaQuery.textScalerOf(context).scale(1).clamp(0.9, 1.3);
          final theme = Theme.of(context);
          final iconSize = 24 * size.scale;
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(system * size.scale)),
            child: size == InterfaceSize.medium
                ? OrientationPolicy(child: child ?? const SizedBox.shrink())
                : Theme(
                    data: theme.copyWith(
                      iconTheme: theme.iconTheme.copyWith(size: iconSize),
                      iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(iconSize: iconSize)),
                    ),
                    child: OrientationPolicy(child: child ?? const SizedBox.shrink()),
                  ),
          );
        },
      ),
    );
  }
}

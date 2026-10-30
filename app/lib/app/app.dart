import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/i18n/app_language.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/responsive.dart';
import '../features/documents/presentation/bloc/documents_cubit.dart';
import '../features/monetization/presentation/plan_cubit.dart';
import '../features/reminders/domain/reminder_service.dart';
import '../features/rewards/presentation/coins_cubit.dart';
import '../features/scanner/presentation/bloc/scan_session_cubit.dart';
import '../features/settings/domain/app_settings.dart';
import '../features/settings/presentation/settings_cubit.dart';
import 'di.dart';
import 'router.dart';

class DoculoomApp extends StatelessWidget {
  const DoculoomApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => sl<PlanCubit>()..load()),
        BlocProvider(create: (_) => sl<SettingsCubit>()..load()),
        BlocProvider(create: (_) => sl<CoinsCubit>()..claimDaily()),
        BlocProvider(create: (_) => sl<DocumentsCubit>()..load()),
        BlocProvider(create: (_) => sl<ScanSessionCubit>()),
      ],
      child: MultiBlocListener(
        listeners: [
          BlocListener<DocumentsCubit, DocumentsState>(
            listenWhen: (a, b) => b.status == LoadStatus.ready && (a.status != b.status || !identical(a.documents, b.documents)),
            listener: (context, _) => _syncReminders(context),
          ),
          BlocListener<SettingsCubit, AppSettings>(
            listenWhen: (a, b) => a.expiryReminders != b.expiryReminders || a.reminderShowNames != b.reminderShowNames,
            listener: (context, _) => _syncReminders(context),
          ),
          // Dates, page counts and other text made in code are written when a screen is built, so every screen is built again.
          BlocListener<SettingsCubit, AppSettings>(
            listenWhen: (a, b) => a.language != b.language || a.dateStyle != b.dateStyle || a.paper != b.paper,
            listener: _buildAllAgain,
          ),
        ],
        child: BlocSelector<SettingsCubit, AppSettings, AppLanguage>(
          selector: (s) => s.language,
          builder: (context, language) => MaterialApp.router(
            title: 'Doculoom',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            locale: language.locale,
            supportedLocales: [for (final c in AppLanguage.supportedCodes) Locale(c)],
            localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
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
        ),
      ),
    );
  }

  /// Marks every widget as needing to be built again, keeping all screens and their state.
  void _buildAllAgain(BuildContext context, AppSettings _) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      void visit(Element e) {
        e.markNeedsBuild();
        e.visitChildren(visit);
      }

      (context as Element).visitChildren(visit);
    });
  }

  /// Keeps the phone's scheduled expiry reminders in step with the documents and the settings.
  void _syncReminders(BuildContext context) {
    if (!sl.isRegistered<ReminderService>()) return;
    final settings = context.read<SettingsCubit>().state;
    sl<ReminderService>().sync(context.read<DocumentsCubit>().state.documents, enabled: settings.expiryReminders, showNames: settings.reminderShowNames);
  }
}

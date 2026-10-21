import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/theme/app_theme.dart';
import '../features/documents/presentation/bloc/documents_cubit.dart';
import '../features/monetization/presentation/plan_cubit.dart';
import '../features/scanner/presentation/bloc/scan_session_cubit.dart';
import 'di.dart';
import 'router.dart';

class ScanVaultApp extends StatelessWidget {
  const ScanVaultApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => sl<PlanCubit>()..load()),
        BlocProvider(create: (_) => sl<DocumentsCubit>()..load()),
        BlocProvider(create: (_) => sl<ScanSessionCubit>()),
      ],
      child: MaterialApp.router(
        title: 'ScanVault',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        routerConfig: appRouter,
      ),
    );
  }
}

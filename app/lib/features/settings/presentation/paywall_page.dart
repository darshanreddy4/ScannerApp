import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/responsive.dart';
import '../../monetization/domain/entities/plan_status.dart';
import '../../monetization/presentation/plan_cubit.dart';
import '../../../core/widgets/text.dart';

/// Placeholder paywall. Replace the button handler with an `in_app_purchase`
/// purchase + receipt validation before shipping; the rest of the app only reads [PlanCubit].
class PaywallPage extends StatelessWidget {
  const PaywallPage({super.key});

  static const _benefits = ['Remove all ads', 'Unlimited exports', 'Priority access to new features'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(AppIcons.close), onPressed: () => context.pop()),
      ),
      body: SafeArea(
        child: ContentWidth(
          maxWidth: 520,
          child: CustomScrollView(
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Icon(AppIcons.premium, size: 44, color: AppColors.primary),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      const Text('Upgrade to Premium', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
                      const SizedBox(height: AppSpacing.lg),
                      for (final b in _benefits)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm + 4),
                          child: Row(
                            children: [
                              const Icon(AppIcons.check, size: 18, color: AppColors.success),
                              const SizedBox(width: AppSpacing.sm + 4),
                              Expanded(child: Text(b, style: const TextStyle(fontSize: 16))),
                            ],
                          ),
                        ),
                      const Spacer(),
                      const SizedBox(height: AppSpacing.lg),
                      // Unlocking without a purchase is allowed in debug builds only.
                      FilledButton(
                        onPressed: kDebugMode
                            ? () async {
                                await context.read<PlanCubit>().setPlan(PlanStatus.premium);
                                if (context.mounted) context.pop();
                              }
                            : null,
                        child: Text(kDebugMode ? 'Continue (debug unlock)' : 'Purchases not configured', textAlign: TextAlign.center),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

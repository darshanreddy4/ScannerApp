import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../monetization/domain/entities/plan_status.dart';
import '../../monetization/presentation/plan_cubit.dart';

class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final plan = context.watch<PlanCubit>().state;
    final premium = plan == PlanStatus.premium;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Card(
          child: ListTile(
            leading: _IconBadge(icon: AppIcons.premium, color: premium ? AppColors.success : AppColors.primary),
            title: Text(premium ? 'Premium plan' : 'Free plan', style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(premium ? 'Ads are turned off' : 'Supported by ads. Upgrade to remove them.'),
            trailing: premium ? null : const Icon(AppIcons.next),
            onTap: premium ? null : () => context.push('/paywall'),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const Card(
          child: Column(
            children: [
              ListTile(
                leading: _IconBadge(icon: AppIcons.shield),
                title: Text('Private by design', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('Documents, images and extracted text never leave this device.'),
              ),
              Divider(),
              ListTile(
                leading: _IconBadge(icon: AppIcons.lock),
                title: Text('Stored in app-private storage'),
                subtitle: Text('Files are saved in the app sandbox and removed when you delete a document.'),
              ),
            ],
          ),
        ),
        if (premium && kDebugMode) ...[
          const SizedBox(height: AppSpacing.md),
          OutlinedButton(
            onPressed: () => context.read<PlanCubit>().setPlan(PlanStatus.free),
            child: const Text('Switch back to Free (debug)'),
          ),
        ],
      ],
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon, this.color = AppColors.primary});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: color),
      );
}

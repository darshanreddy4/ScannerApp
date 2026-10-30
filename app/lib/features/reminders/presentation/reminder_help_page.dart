import 'package:flutter/material.dart' hide Text;

import '../../../app/di.dart';
import '../../../core/i18n/tr.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/text.dart';
import '../data/reminder_platform.dart';
import '../domain/reminder_help.dart';
import '../domain/reminder_service.dart';

/// Helps when a phone does not show reminders: a test notification to try with the app closed, and the settings that decide whether
/// the phone lets the app wake up for an alarm.
class ReminderHelpPage extends StatefulWidget {
  const ReminderHelpPage({super.key, this.service});
  final ReminderService? service;

  @override
  State<ReminderHelpPage> createState() => _ReminderHelpPageState();
}

class _ReminderHelpPageState extends State<ReminderHelpPage> {
  late final ReminderService _service = widget.service ?? sl<ReminderService>();
  late Future<(ReminderAccess, ReminderHelp)> _info = _load();

  Future<(ReminderAccess, ReminderHelp)> _load() async => (await _service.status(), reminderHelpFor(await _service.maker()));

  Future<void> _test() async {
    final ok = await _service.scheduleTest();
    if (!mounted) return;
    showMessage(context, ok ? 'Test set. Close Doculoom now and wait 2 minutes.' : 'Reminders are not available on this phone.');
  }

  Widget _step(
    int n,
    String title,
    String text, {
    required String button,
    required Key buttonKey,
    required Future<void> Function() onTap,
    bool filled = false,
  }) => Card(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(trf('Step {n}: {title}', {'n': n, 'title': tr(title)}), style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(text, style: const TextStyle(fontSize: 13, color: AppColors.inkMuted, height: 1.4)),
          const SizedBox(height: AppSpacing.sm),
          filled
              ? FilledButton(
                  key: buttonKey,
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: onTap,
                  child: Text(button),
                )
              : OutlinedButton(
                  key: buttonKey,
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: onTap,
                  child: Text(button),
                ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Reminders not arriving?')),
    body: FutureBuilder<(ReminderAccess, ReminderHelp)>(
      future: _info,
      builder: (context, snap) {
        final data = snap.data;
        if (data == null) return const Center(child: CircularProgressIndicator());
        final (access, help) = data;
        return ListView(
          padding: contentPadding(context).copyWith(bottom: AppSpacing.xl),
          children: [
            const Text(
              'Reminders are set in the phone\'s own alarm system, so they arrive when Doculoom is closed, and they are set again after a restart. Some phones save battery by stopping apps in the background, and then a reminder can be late or missing. These steps fix that.',
              style: TextStyle(fontSize: 13, color: AppColors.inkMuted, height: 1.4),
            ),
            const SizedBox(height: AppSpacing.md),
            if (access == ReminderAccess.unsupported)
              const Text(
                'Reminders are not available on this phone.',
                key: ValueKey('help-unsupported'),
                style: TextStyle(color: AppColors.danger),
              )
            else ...[
              if (access != ReminderAccess.granted)
                _step(
                  1,
                  'Allow notifications',
                  'Notifications are off for Doculoom, so nothing can be shown.',
                  button: 'Open phone settings',
                  buttonKey: const ValueKey('help-notifications'),
                  onTap: () async {
                    await _service.openSettings();
                  },
                  filled: true,
                ),
              _step(
                access == ReminderAccess.granted ? 1 : 2,
                'Battery',
                'Open the battery settings, pick Doculoom, and choose Unrestricted or Do not optimise.',
                button: 'Battery settings',
                buttonKey: const ValueKey('help-battery'),
                onTap: () async {
                  await _service.openBatterySettings();
                },
              ),
              if (help.hasMakerScreen)
                _step(
                  access == ReminderAccess.granted ? 2 : 3,
                  trf('{maker} settings', {'maker': help.maker}),
                  help.hint,
                  button: 'Open background settings',
                  buttonKey: const ValueKey('help-maker'),
                  onTap: () async {
                    await _service.openAutostartSettings();
                  },
                )
              else
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Text(
                    help.hint,
                    key: const ValueKey('help-generic'),
                    style: const TextStyle(fontSize: 13, color: AppColors.inkMuted),
                  ),
                ),
              _step(
                access == ReminderAccess.granted ? (help.hasMakerScreen ? 3 : 2) : (help.hasMakerScreen ? 4 : 3),
                'Test',
                'Send a test notification, close Doculoom, and wait 2 minutes. If it arrives, your reminders will too.',
                button: 'Send a test in 2 minutes',
                buttonKey: const ValueKey('help-test'),
                onTap: _test,
                filled: true,
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'Do not use Force stop on Doculoom: Android removes its alarms until you open it again. Swiping it away from recent apps is fine on most phones.',
                style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted, height: 1.4),
              ),
            ],
          ],
        );
      },
    ),
  );
}

import 'package:flutter/material.dart' hide Text;

import '../error/failures.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import 'text.dart';

void showFailure(BuildContext context, Failure failure) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: AppColors.ink,
        content: Row(
          children: [
            const Icon(AppIcons.warning, color: Colors.white, size: 20),
            const SizedBox(width: AppSpacing.sm + 4),
            Expanded(child: Text(failure.message)),
          ],
        ),
      ),
    );
}

/// Dims the screen and shows a progress card while a long operation runs.
class BusyOverlay extends StatelessWidget {
  const BusyOverlay({super.key, required this.visible, this.label});

  final bool visible;
  final String? label;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return Positioned.fill(
      child: AbsorbPointer(
        child: ColoredBox(
          color: Colors.black45,
          child: Center(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
                    if (label != null) ...[const SizedBox(width: AppSpacing.md), Text(label!)],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Short confirmation message.
void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), persist: false));
}

/// Runs [task] behind a blocking progress dialog.
Future<T> runBusy<T>(BuildContext context, String label, Future<T> Function() task) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => PopScope(
      canPop: false,
      child: Dialog(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
              const SizedBox(width: AppSpacing.md),
              Flexible(child: Text(label)),
            ],
          ),
        ),
      ),
    ),
  );
  try {
    return await task();
  } finally {
    if (navigator.mounted) navigator.pop();
  }
}

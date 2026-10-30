import 'dart:async';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/di.dart';
import '../../../core/widgets/feedback.dart';
import '../../monetization/domain/repositories/monetization_contracts.dart';
import '../../monetization/presentation/plan_cubit.dart';
import '../domain/entities/scan_mode.dart';
import 'bloc/scan_session_cubit.dart';
import '../../tables/presentation/table_page.dart';
import 'mode_followup.dart';
import '../../../core/widgets/text.dart';

/// Called after a page was added. Receipt, card and ID scans do not go through the page editor: a card or ID asks for its back side,
/// then the scan is saved, read and opened. Returns true when it has taken the person to the result (or is still working on it).
Future<bool> continueModeScan(BuildContext context) async {
  final session = context.read<ScanSessionCubit>();
  final mode = session.state.mode;
  final pages = session.state.pages.length;
  if (!mode.finishesItself || pages == 0 || session.state.editingDocumentId != null) return false;
  if (mode.twoSided && pages == 1) {
    final back = await _askBack(context, mode);
    if (back || !context.mounted) return false;
  }
  await saveScanAndFollow(context);
  return true;
}

/// Saves the open scan and continues with what its mode needs: reading a receipt, a contact from a card, the date of an ID.
Future<void> saveScanAndFollow(BuildContext context) async {
  final session = context.read<ScanSessionCubit>();
  final plan = context.read<PlanCubit>().state;
  final mode = session.state.mode;
  final doc = await session.save();
  if (!context.mounted) return;
  if (doc == null) {
    if (session.state.error != null) showFailure(context, session.state.error!);
    return;
  }
  final next = await runModeFollowUp(context, mode, doc);
  if (!context.mounted) return;
  context.go('/document/${doc.id}');
  final contactText = next?.contactText;
  final idPhotos = next?.idPhotos;
  if (contactText != null) context.push('/contact', extra: contactText);
  if (idPhotos != null) context.push('/id-card', extra: idPhotos);
  final tablePages = next?.tablePages;
  if (tablePages != null)
    context.push(
      '/table',
      extra: TableArgs(title: doc.title, imagePaths: tablePages),
    );
  // The ad waits for the result to be on screen, and is skipped if the person is already typing or has left the app.
  unawaited(sl<AdService>().showInterstitialIfEligible(plan));
}

Future<bool> _askBack(BuildContext context, ScanMode mode) async {
  final noun = mode.noun.toLowerCase();
  final scan = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Front scanned'),
      content: Text('Scan the back of the $noun too?'),
      actions: [
        TextButton(key: const ValueKey('back-skip'), onPressed: () => Navigator.pop(ctx, false), child: const Text('Only the front')),
        FilledButton(key: const ValueKey('back-scan'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Scan the back')),
      ],
    ),
  );
  return scan ?? true;
}

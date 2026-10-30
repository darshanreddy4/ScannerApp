import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/app_config.dart';
import '../../../app/di.dart';
import '../../../core/widgets/feedback.dart';
import '../../export/domain/repositories/export_repository.dart';

/// The message sent when someone shares the app.
String shareMessage() =>
    'I use Doculoom to scan, sign and manage documents on my phone. It works offline and keeps everything private on the phone. Get it here: ${AppConfig.appStoreUrl}';

/// Opens the share sheet so the person can send a link to the app.
Future<void> shareApp(BuildContext context) async {
  final result = await sl<ShareService>().shareText(text: shareMessage(), subject: 'Doculoom');
  final failure = result.failureOrNull;
  if (failure != null && context.mounted) showFailure(context, failure);
}

/// Opens the app's page in Google Play so the person can rate it, or the web page when Play is not installed.
Future<void> rateApp(BuildContext context) async {
  final opened = await _open(Uri.parse('market://details?id=${AppConfig.androidPackage}')) || await _open(Uri.parse(AppConfig.appStoreUrl));
  if (!opened && context.mounted) showMessage(context, 'Could not open Google Play. Search for Doculoom there to rate it.');
}

Future<bool> _open(Uri uri) async {
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

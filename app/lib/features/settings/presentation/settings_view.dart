import '../../cards/data/card_store.dart';
import '../../checklists/data/checklist_store.dart';
import '../../hijri/domain/hijri.dart';
import '../../taxinvoice/data/tax_profile_store.dart';
import '../../markup/data/stamp_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:package_info_plus/package_info_plus.dart';

import '../../../app/app_config.dart';
import '../../../app/di.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/feedback.dart';
import '../../documents/domain/usecases/document_usecases.dart';
import '../../documents/presentation/bloc/documents_cubit.dart';
import '../../documents/presentation/widgets/document_widgets.dart' show confirmDestructive;
import '../../monetization/domain/repositories/monetization_contracts.dart';
import '../../rewards/presentation/coins_card.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/responsive.dart';
import '../../export/domain/entities/export_options.dart';
import '../../ocr/domain/ocr_models.dart';
import '../../monetization/domain/entities/plan_status.dart';
import '../../monetization/presentation/plan_cubit.dart';
import '../../scanner/domain/entities/filter_settings.dart';
import '../../scanner/presentation/widgets/filter_labels.dart';
import '../../photo_tools/domain/watermark.dart';
import '../../photo_tools/domain/watermark_service.dart';
import '../../signature/domain/signature.dart' show SignatureStore;
import '../../cv/data/cv_store.dart';
import '../../invoice/data/invoice_profile_store.dart';
import '../../qr/domain/scan_services.dart' show ScanHistory;
import '../../vat_refund/data/vat_refund_store.dart';
import 'package:path_provider/path_provider.dart';
import '../../reminders/data/reminder_platform.dart';
import '../../reminders/domain/reminder_service.dart';
import '../../../core/i18n/app_language.dart';
import '../../../core/i18n/tr.dart';
import '../../../core/utils/region.dart';
import '../domain/app_settings.dart';
import 'app_links.dart';
import 'settings_cubit.dart';
import '../../../core/widgets/text.dart';

class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final plan = context.watch<PlanCubit>().state;
    final premium = plan == PlanStatus.premium;
    final settings = context.watch<SettingsCubit>().state;
    final cubit = context.read<SettingsCubit>();

    return ListView(
      padding: contentPadding(context),
      children: [
        if (AppConfig.rewardsEnabled && !premium) ...[const CoinsCard(), const SizedBox(height: AppSpacing.md)],
        if (AppConfig.billingEnabled || kDebugMode) ...[
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
        ],
        const _SectionLabel('Scanning'),
        Card(
          child: Column(
            children: [
              _SelectTile<InterfaceSize>(
                icon: AppIcons.fontSize,
                title: 'Text and icon size',
                subtitle: 'Make buttons, icons and text smaller or larger',
                value: settings.interfaceSize,
                options: InterfaceSize.values,
                labelOf: (s) => s.label,
                onChanged: (s) => cubit.update((c) => c.copyWith(interfaceSize: s)),
              ),
              const Divider(),
              SwitchListTile(
                secondary: const _IconBadge(icon: AppIcons.crop),
                title: const Text('Show crop screen after capture'),
                subtitle: const Text('Turn off to add pages instantly while scanning'),
                value: settings.showCropAfterCapture,
                onChanged: (v) => cubit.update((s) => s.copyWith(showCropAfterCapture: v)),
              ),
              const Divider(),
              SwitchListTile(
                secondary: const _IconBadge(icon: AppIcons.autoCapture),
                title: const Text('Auto-capture'),
                subtitle: const Text('Capture when the document is detected and steady'),
                value: settings.autoCapture,
                onChanged: (v) => cubit.update((s) => s.copyWith(autoCapture: v)),
              ),
              const Divider(),
              _SelectTile<CameraQuality>(
                icon: AppIcons.camera,
                title: 'Camera quality',
                subtitle: 'Applies the next time the camera opens',
                value: settings.cameraQuality,
                options: CameraQuality.values,
                labelOf: (q) => q.label,
                onChanged: (q) => cubit.update((s) => s.copyWith(cameraQuality: q)),
              ),
              const Divider(),
              _SelectTile<ScanFilter>(
                icon: AppIcons.filterMagic,
                title: 'Default filter',
                value: settings.defaultFilter,
                options: filterOrder,
                labelOf: (f) => f.label,
                onChanged: (f) => cubit.update((s) => s.copyWith(defaultFilter: f)),
              ),
              const Divider(),
              _SelectTile<OcrScript>(
                icon: AppIcons.ocr,
                title: 'Text recognition language',
                subtitle: 'Used when extracting text from pages',
                value: settings.ocrScript,
                options: OcrScript.values,
                labelOf: (s) => s.label,
                onChanged: (s) => cubit.update((c) => c.copyWith(ocrScript: s)),
              ),
              const Divider(),
              SwitchListTile(
                key: const ValueKey('setting-auto-name'),
                secondary: const _IconBadge(icon: AppIcons.edit),
                title: const Text('Name scans from their text'),
                subtitle: const Text('Uses the heading or the date on the first page. A name you chose is never changed.'),
                value: settings.autoName,
                onChanged: (v) => cubit.update((s) => s.copyWith(autoName: v)),
              ),
              const Divider(),
              SwitchListTile(
                key: const ValueKey('setting-smart-folders'),
                secondary: const _IconBadge(icon: AppIcons.emptyDocs),
                title: const Text('File scans into folders'),
                subtitle: const Text('Receipts, IDs, cards, books and whiteboards go into their own folder.'),
                value: settings.smartFolders,
                onChanged: (v) => cubit.update((s) => s.copyWith(smartFolders: v)),
              ),
              const Divider(),
              _SelectTile<ExportQuality>(
                icon: AppIcons.quality,
                title: 'Export quality',
                value: settings.exportQuality,
                options: ExportQuality.values,
                labelOf: (q) => q.label,
                onChanged: (q) => cubit.update((s) => s.copyWith(exportQuality: q)),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (kDebugMode) ...[
          const _SectionLabel('Feature controls (owner)'),
          Card(
            child: SwitchListTile(
              secondary: const _IconBadge(icon: AppIcons.edit),
              title: const Text('Edit saved documents'),
              subtitle: Text(
                settings.editSavedDocuments
                    ? 'On: Premium users can edit saved documents. Free users see a lock.'
                    : 'Off: the Edit button is hidden for everyone.',
              ),
              value: settings.editSavedDocuments,
              onChanged: (v) => cubit.update((s) => s.copyWith(editSavedDocuments: v)),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        const _SectionLabel('Region and language'),
        Card(
          child: Column(
            children: [
              _SelectTile<AppLanguage>(
                key: const ValueKey('setting-language'),
                icon: AppIcons.language,
                title: 'Language of the app',
                subtitle: 'Menus and messages. Text that is not translated yet stays in English.',
                value: settings.language,
                options: AppLanguage.values,
                labelOf: (l) => l == AppLanguage.system ? tr('System language') : l.label,
                onChanged: (l) => cubit.update((c) => c.copyWith(language: l)),
              ),
              const Divider(),
              _SelectTile<PaperChoice>(
                key: const ValueKey('setting-paper'),
                icon: AppIcons.pdf,
                title: 'Paper size',
                subtitle: 'For printing and for pages the app makes itself',
                value: settings.paper,
                options: PaperChoice.values,
                labelOf: (p) => tr(p.label),
                onChanged: (p) => cubit.update((c) => c.copyWith(paper: p)),
              ),
              const Divider(),
              _SelectTile<DateStyle>(
                key: const ValueKey('setting-date-style'),
                icon: AppIcons.calendar,
                title: 'Date format',
                subtitle: 'How dates are written',
                value: settings.dateStyle,
                options: DateStyle.values,
                labelOf: (d) => tr(d.label),
                onChanged: (d) => cubit.update((c) => c.copyWith(dateStyle: d)),
              ),
              const Divider(),
              _SelectTile<ToolRegion>(
                key: const ValueKey('setting-tool-region'),
                icon: AppIcons.tools,
                title: 'Tools for',
                subtitle: 'Tools made for one country come first on the Tools page',
                value: settings.toolRegion,
                options: ToolRegion.values,
                labelOf: (r) => tr(r.label),
                onChanged: (r) => cubit.update((c) => c.copyWith(toolRegion: r)),
              ),
              const Divider(),
              SwitchListTile(
                key: const ValueKey('setting-show-all-tools'),
                secondary: const _IconBadge(icon: AppIcons.tools),
                title: const Text('Show tools for all countries'),
                subtitle: const Text('Off: other countries\' tools wait in a folded list. Nothing is removed.'),
                value: settings.showAllTools,
                onChanged: (v) => cubit.update((c) => c.copyWith(showAllTools: v)),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const _SectionLabel('Reminders'),
        const _ReminderSettings(),
        const SizedBox(height: AppSpacing.md),
        const _SectionLabel('Privacy'),
        Card(
          child: Column(
            children: [
              const ListTile(
                leading: _IconBadge(icon: AppIcons.shield),
                title: Text('Private by design', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('Documents, images and extracted text never leave this device.'),
              ),
              const Divider(),
              const ListTile(
                leading: _IconBadge(icon: AppIcons.lock),
                title: Text('Stored in app-private storage'),
                subtitle: Text('Files are saved in the app sandbox and removed when you delete a document.'),
              ),
              const Divider(),
              ListTile(
                leading: const _IconBadge(icon: AppIcons.info),
                title: const Text('Privacy policy'),
                trailing: const Icon(AppIcons.next),
                onTap: () => context.push('/privacy'),
              ),
              FutureBuilder<bool>(
                future: sl<AdService>().privacyOptionsRequired(),
                builder: (_, snap) => snap.data == true
                    ? Column(
                        children: [
                          const Divider(),
                          ListTile(
                            leading: const _IconBadge(icon: AppIcons.shield),
                            title: const Text('Ad privacy choices'),
                            trailing: const Icon(AppIcons.next),
                            onTap: () => sl<AdService>().showPrivacyOptions(),
                          ),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
              const Divider(),
              ListTile(
                key: const ValueKey('backup-tile'),
                leading: const _IconBadge(icon: AppIcons.backup),
                title: const Text('Backup and restore'),
                subtitle: const Text('Keep an encrypted copy of your documents'),
                trailing: const Icon(AppIcons.next),
                onTap: () => context.push('/backup'),
              ),
              const Divider(),
              ListTile(
                leading: const _IconBadge(icon: AppIcons.delete, color: AppColors.danger),
                title: const Text('Delete all my data', style: TextStyle(color: AppColors.danger)),
                subtitle: const Text('Removes every document and folder from this phone'),
                onTap: () => _deleteAll(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const _SectionLabel('Spread the word'),
        Card(
          child: Column(
            children: [
              ListTile(
                key: const ValueKey('share-app'),
                leading: const _IconBadge(icon: AppIcons.share),
                title: const Text('Share the app'),
                subtitle: const Text('Send a link to friends and family'),
                trailing: const Icon(AppIcons.next),
                onTap: () => shareApp(context),
              ),
              const Divider(),
              ListTile(
                key: const ValueKey('rate-app'),
                leading: const _IconBadge(icon: AppIcons.star, color: AppColors.warning),
                title: const Text('Rate us'),
                subtitle: const Text('Tell others what you think on Google Play'),
                trailing: const Icon(AppIcons.next),
                onTap: () => rateApp(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const _SectionLabel('About'),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const _IconBadge(icon: AppIcons.chat),
                title: const Text('Help and support'),
                trailing: const Icon(AppIcons.next),
                onTap: () => context.push('/support'),
              ),
              const Divider(),
              ListTile(
                leading: const _IconBadge(icon: AppIcons.docx),
                title: const Text('Terms and conditions'),
                trailing: const Icon(AppIcons.next),
                onTap: () => context.push('/terms'),
              ),
              const Divider(),
              ListTile(
                leading: const _IconBadge(icon: AppIcons.info),
                title: const Text('Open-source licences'),
                trailing: const Icon(AppIcons.next),
                onTap: () => showLicensePage(context: context, applicationName: 'Doculoom'),
              ),
              const Divider(),
              const _VersionTile(),
            ],
          ),
        ),
        if (premium && kDebugMode) ...[
          const SizedBox(height: AppSpacing.md),
          OutlinedButton(onPressed: () => context.read<PlanCubit>().setPlan(PlanStatus.free), child: const Text('Switch back to Free (debug)')),
        ],
      ],
    );
  }
}

Future<void> _deleteAll(BuildContext context) async {
  final docs = context.read<DocumentsCubit>();
  final ok = await confirmDestructive(
    context,
    title: 'Delete all data?',
    message: 'Every document, page and folder will be permanently removed from this phone. This cannot be undone.',
    action: 'Delete everything',
  );
  if (!ok || !context.mounted) return;
  final result = await runBusy(context, 'Deleting', () => sl<DeleteAllData>()());
  if (!context.mounted) return;
  final failure = result.failureOrNull;
  if (failure != null) {
    showFailure(context, failure);
  } else {
    // Saved business details and the logo are personal data too.
    if (sl.isRegistered<BusinessProfileStore>()) {
      try {
        await sl<BusinessProfileStore>().save(const BusinessProfile());
      } catch (_) {
        // The documents are gone; the small profile can be removed from the watermark screen.
      }
    }
    // Saved signatures are personal data too.
    if (sl.isRegistered<SignatureStore>()) {
      try {
        await sl<SignatureStore>().deleteAll();
      } catch (_) {
        // They can still be deleted one by one from the signature screen.
      }
    }
    // Scan history, saved invoice and CV details and tax-free receipts are personal data too.
    for (final clear in <Future<void> Function()>[
      () => sl<ScanHistory>().clear(),
      () => const InvoiceProfileStore().clear(),
      () => CvStore(appDir: getApplicationDocumentsDirectory).clear(),
      () => VatRefundStore().clear(),
      () => const StampStore().clear(),
      () => const CardStore().clear(),
      () => const ChecklistStore().clear(),
      () => const TaxProfileStore(gstProfileKey).clear(),
      () => const TaxProfileStore(usInvoiceProfileKey).clear(),
      () => const TaxProfileStore(zatcaProfileKey).clear(),
      () => const HijriReminderStore().clear(),
    ]) {
      try {
        await clear();
      } catch (_) {
        // Each one can still be cleared on its own screen.
      }
    }
    await docs.load();
    // Notifications already scheduled for the dates that were just deleted are cancelled.
    if (sl.isRegistered<ReminderService>()) {
      try {
        await sl<ReminderService>().refresh();
      } catch (_) {
        // They stop at the next start of the app.
      }
    }
    if (context.mounted) showMessage(context, 'All data deleted');
  }
}

class _VersionTile extends StatelessWidget {
  const _VersionTile();

  @override
  Widget build(BuildContext context) => FutureBuilder<PackageInfo>(
    future: PackageInfo.fromPlatform(),
    builder: (_, snap) => ListTile(
      leading: const _IconBadge(icon: AppIcons.scan),
      title: const Text('Doculoom'),
      subtitle: Text(snap.hasData ? 'Version ${snap.data!.version} (${snap.data!.buildNumber})' : ''),
    ),
  );
}

class _SelectTile<T> extends StatelessWidget {
  const _SelectTile({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.options,
    required this.labelOf,
    required this.onChanged,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final T value;
  final List<T> options;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md, AppSpacing.sm + 4, AppSpacing.md, AppSpacing.sm + 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _IconBadge(icon: icon),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 16)),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(subtitle!, style: const TextStyle(fontSize: 13, color: AppColors.inkMuted)),
                ),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<T>(
                initialValue: value,
                isExpanded: true,
                isDense: true,
                decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                onChanged: (v) {
                  if (v != null) onChanged(v);
                },
                items: [
                  for (final o in options)
                    DropdownMenuItem<T>(
                      value: o,
                      child: Text(labelOf(o), overflow: TextOverflow.ellipsis),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Switches for the document-expiry notifications, with what the phone currently allows.
class _ReminderSettings extends StatefulWidget {
  const _ReminderSettings();

  @override
  State<_ReminderSettings> createState() => _ReminderSettingsState();
}

class _ReminderSettingsState extends State<_ReminderSettings> {
  Future<ReminderAccess> _access = _status();

  static Future<ReminderAccess> _status() => sl.isRegistered<ReminderService>() ? sl<ReminderService>().status() : Future.value(ReminderAccess.unsupported);

  Future<void> _toggle(bool on) async {
    final cubit = context.read<SettingsCubit>();
    await cubit.update((s) => s.copyWith(expiryReminders: on));
    if (on && sl.isRegistered<ReminderService>() && await sl<ReminderService>().shouldExplain()) await sl<ReminderService>().askOnce();
    if (mounted) {
      setState(() {
        _access = _status();
      });
    }
  }

  String _subtitle(ReminderAccess a, bool on) {
    if (a == ReminderAccess.unsupported) return 'Not available on this phone. Documents that are ending are still listed on the Documents screen.';
    if (!on) return 'Off. Documents that are ending are still listed on the Documents screen.';
    return switch (a) {
      ReminderAccess.blocked => 'Notifications are turned off for Doculoom in the phone settings.',
      ReminderAccess.denied => 'You will be asked to allow notifications when you set the first expiry date.',
      _ => 'A notification 30 days before, 7 days before and on the day, at 9:00.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsCubit>().state;
    final cubit = context.read<SettingsCubit>();
    return Card(
      child: FutureBuilder<ReminderAccess>(
        future: _access,
        builder: (context, snap) {
          final access = snap.data ?? ReminderAccess.unsupported;
          return Column(
            children: [
              SwitchListTile(
                key: const ValueKey('reminders-switch'),
                secondary: const _IconBadge(icon: AppIcons.timer),
                title: const Text('Expiry reminders'),
                subtitle: Text(_subtitle(access, settings.expiryReminders), key: const ValueKey('reminders-subtitle')),
                value: settings.expiryReminders && access != ReminderAccess.unsupported,
                onChanged: access == ReminderAccess.unsupported ? null : _toggle,
              ),
              if (settings.expiryReminders && access == ReminderAccess.blocked)
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(end: AppSpacing.md, bottom: AppSpacing.sm),
                    child: TextButton(
                      key: const ValueKey('reminders-open-settings'),
                      onPressed: () async {
                        await sl<ReminderService>().openSettings();
                      },
                      child: const Text('Open phone settings'),
                    ),
                  ),
                ),
              const Divider(),
              SwitchListTile(
                key: const ValueKey('reminders-names'),
                secondary: const _IconBadge(icon: AppIcons.eye),
                title: const Text('Show document names'),
                subtitle: const Text('Off keeps names off the lock screen. The reminder only says that a document expires.'),
                value: settings.reminderShowNames,
                onChanged: settings.expiryReminders ? (v) => cubit.update((s) => s.copyWith(reminderShowNames: v)) : null,
              ),
              if (access != ReminderAccess.unsupported)
                ListTile(
                  key: const ValueKey('reminders-help'),
                  leading: const _IconBadge(icon: AppIcons.info),
                  title: const Text('Reminders not arriving?'),
                  subtitle: const Text('Test them and check the phone\'s battery settings'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/reminder-help'),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(start: 4, bottom: AppSpacing.sm),
    child: Text(
      text,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.inkMuted, letterSpacing: 0.3),
    ),
  );
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

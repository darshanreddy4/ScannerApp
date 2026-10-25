import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../app/di.dart';
import '../../../core/error/failures.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/responsive.dart';
import '../../export/domain/repositories/export_repository.dart';
import '../domain/pdf_protector.dart';
import 'pdf_password_cubit.dart';

/// Puts a password on a PDF, or takes the password off a PDF you can open.
class PdfPasswordPage extends StatelessWidget {
  const PdfPasswordPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => PdfPasswordCubit(protector: sl<PdfProtector>(), outputDir: getTemporaryDirectory),
    child: const _PasswordView(),
  );
}

class _PasswordView extends StatefulWidget {
  const _PasswordView();

  @override
  State<_PasswordView> createState() => _PasswordViewState();
}

class _PasswordViewState extends State<_PasswordView> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _show = false;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _pick(BuildContext context) async {
    try {
      final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['pdf']);
      final path = picked.isEmpty ? null : picked.first.path;
      if (path == null || !context.mounted) return;
      _password.clear();
      _confirm.clear();
      await context.read<PdfPasswordCubit>().pick(path);
    } catch (_) {
      if (context.mounted) showFailure(context, const PermissionFailure('The file picker is unavailable.'));
    }
  }

  Future<void> _share(ProtectedPdf r) async {
    final failure = (await sl<ShareService>().shareFiles(paths: [r.path], mimeType: 'application/pdf')).failureOrNull;
    if (failure != null && mounted) showFailure(context, failure);
  }

  Future<void> _save(ProtectedPdf r) async {
    final result = await sl<SaveService>().saveToFiles(
      sourcePath: r.path,
      fileName: p.basename(r.path).replaceAll(RegExp(r'_\d{10,}(?=\.pdf$)'), ''),
      mimeType: 'application/pdf',
    );
    if (!mounted) return;
    final failure = result.failureOrNull;
    if (failure != null) {
      showFailure(context, failure);
    } else if (result.valueOrNull == true) {
      showMessage(context, 'Saved');
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PdfPasswordCubit, PdfPasswordState>(
      builder: (context, state) {
        final cubit = context.read<PdfPasswordCubit>();
        final working = state.status == PasswordStatus.working;
        final info = state.protection;
        final locking = state.canLock;
        final wrong = state.failure is PasswordFailure && state.status == PasswordStatus.done;
        InputDecoration deco(String label, {String? error}) => InputDecoration(
          labelText: label,
          errorText: error,
          suffixIcon: IconButton(
            tooltip: _show ? 'Hide password' : 'Show password',
            icon: Icon(_show ? AppIcons.eyeOff : AppIcons.eye, size: 20),
            onPressed: () => setState(() => _show = !_show),
          ),
        );
        return Scaffold(
          appBar: AppBar(
            title: const Text('Lock or unlock PDF'),
            actions: [if (state.path != null && !state.busy) TextButton(onPressed: cubit.clear, child: const Text('Clear'))],
          ),
          body: SafeArea(
            child: Stack(
              children: [
                ListView(
                  padding: contentPadding(context, base: AppSpacing.md, maxWidth: 640),
                  children: [
                    if (state.path == null)
                      FilledButton.icon(
                        onPressed: state.busy ? null : () => _pick(context),
                        icon: const Icon(AppIcons.importFile, size: 18),
                        label: const Text('Choose a PDF'),
                      )
                    else
                      Card(
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          leading: Icon(info == null ? AppIcons.pdf : (info.encrypted ? AppIcons.lock : AppIcons.unlock), color: AppColors.primary),
                          title: Text(state.name!, maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            info == null
                                ? 'Checking...'
                                : '${formatBytes(info.bytes)} · ${info.encrypted ? (info.needsPassword ? 'Protected with a password' : 'Has restrictions, no password to open') : 'No password'}',
                          ),
                          trailing: state.busy ? null : TextButton(onPressed: () => _pick(context), child: const Text('Change')),
                        ),
                      ),
                    if (state.path == null && state.failure != null)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.md),
                        child: Text(state.failure!.message, style: const TextStyle(color: AppColors.danger, height: 1.4)),
                      ),
                    if (info != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      if (locking) ...[
                        const Text('Set a password', style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: AppSpacing.sm),
                        TextField(
                          controller: _password,
                          enabled: !state.busy,
                          obscureText: !_show,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: deco('Password'),
                          onChanged: cubit.setPassword,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        TextField(
                          controller: _confirm,
                          enabled: !state.busy,
                          obscureText: !_show,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: deco(
                            'Repeat the password',
                            error: state.confirm.isNotEmpty && state.confirm != state.password ? 'The two passwords are not the same.' : null,
                          ),
                          onChanged: cubit.setConfirm,
                          onSubmitted: (_) => cubit.run(),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        const Text(
                          'Letters and numbers work in every PDF reader. If you forget the password, nobody can recover the file, not even this app.',
                          style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted, height: 1.4),
                        ),
                      ] else if (info.needsPassword) ...[
                        const Text('Password of this PDF', style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: AppSpacing.sm),
                        TextField(
                          controller: _password,
                          enabled: !state.busy,
                          obscureText: !_show,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: deco('Password', error: wrong ? 'That password is not correct.' : null),
                          onChanged: cubit.setPassword,
                          onSubmitted: (_) => cubit.run(),
                        ),
                      ] else
                        const Text(
                          'This PDF opens without a password but limits things such as printing or copying. Unlocking removes those limits from your copy.',
                          style: TextStyle(height: 1.4),
                        ),
                      const SizedBox(height: AppSpacing.md),
                      FilledButton.icon(
                        onPressed: state.busy ? null : cubit.run,
                        icon: working
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : Icon(locking ? AppIcons.lock : AppIcons.unlock, size: 18),
                        label: Text(working ? 'Working' : (locking ? 'Lock PDF' : (info.needsPassword ? 'Unlock PDF' : 'Remove restrictions'))),
                      ),
                    ],
                    if (state.failure != null && state.path != null && !wrong)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.md),
                        child: Text(state.failure!.message, style: const TextStyle(color: AppColors.danger, height: 1.4)),
                      ),
                    if (state.result != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      _ResultCard(state: state, onShare: () => _share(state.result!), onSave: () => _save(state.result!)),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    const _Note(),
                  ],
                ),
                BusyOverlay(visible: state.status == PasswordStatus.checking, label: 'Checking...'),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.state, required this.onShare, required this.onSave});
  final PdfPasswordState state;
  final VoidCallback onShare;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final r = state.result!;
    return Card(
      margin: EdgeInsets.zero,
      color: AppColors.primarySoft,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(state.lockedNow ? 'Your PDF is locked' : 'Your PDF is unlocked', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: AppSpacing.xs),
            Text(
              state.lockedNow
                  ? 'It needs the password to open (${formatBytes(r.bytes)}). Text, images and links are unchanged. Share this copy, not the original, and keep the password safe.'
                  : 'Anyone can open this copy without a password (${formatBytes(r.bytes)}). Text, images and links are unchanged.',
              style: const TextStyle(fontSize: 12.5, height: 1.4),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: onShare,
                  icon: const Icon(AppIcons.share, size: 18),
                  label: const Text('Share'),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: onSave,
                  icon: const Icon(AppIcons.storage, size: 18),
                  label: const Text('Save to Files'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note();

  @override
  Widget build(BuildContext context) => const Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(AppIcons.shield, size: 20, color: AppColors.success),
          SizedBox(width: AppSpacing.sm + 4),
          Expanded(
            child: Text(
              'Locking uses AES 256-bit encryption and works on your phone; the file and the password never leave it. You need the current password to unlock a protected PDF; this app cannot recover forgotten passwords. Very old PDF readers may not open AES 256 files.',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    ),
  );
}

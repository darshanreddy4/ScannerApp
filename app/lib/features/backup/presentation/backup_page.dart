import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide Text;
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
import '../../documents/presentation/bloc/documents_cubit.dart';
import '../../export/domain/repositories/export_repository.dart';
import '../data/backup_container.dart';
import '../data/backup_service.dart';
import '../../../core/widgets/text.dart';
import '../../../core/i18n/tr.dart';

const _backupMime = 'application/octet-stream';

String backupFileName(DateTime now) => 'Doculoom-backup-${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.dlbackup';

/// Makes an encrypted copy of every document, or adds the documents of such a copy back to this phone.
class BackupPage extends StatefulWidget {
  const BackupPage({super.key, this.service, this.workDir = getTemporaryDirectory, this.pickBackup, this.onRestored});

  final BackupService? service;
  final Future<Directory> Function() workDir;

  /// Chooses the backup file to restore; replaced in tests.
  final Future<String?> Function()? pickBackup;

  /// Called after documents were added; by default the document list is reloaded.
  final VoidCallback? onRestored;

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  String? _busy;

  BackupService get _service => widget.service ?? sl<BackupService>();

  Future<String?> _askPassword({required bool confirm}) => showDialog<String>(
    context: context,
    builder: (_) => _PasswordDialog(confirm: confirm),
  );

  Future<void> _create() async {
    final password = await _askPassword(confirm: true);
    if (password == null || !mounted) return;
    setState(() => _busy = 'Encrypting backup');
    final dir = await Directory(p.join((await widget.workDir()).path, 'exports')).create(recursive: true);
    final out = p.join(dir.path, backupFileName(DateTime.now()));
    final result = await _service.create(password: password, outputPath: out);
    if (!mounted) return;
    setState(() => _busy = null);
    final summary = result.valueOrNull;
    if (summary == null) {
      showFailure(context, result.failureOrNull!);
      return;
    }
    await _offerFile(out, summary);
  }

  Future<void> _offerFile(String path, BackupSummary summary) async {
    final name = p.basename(path);
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                '${summary.documents} document${summary.documents == 1 ? '' : 's'}, ${summary.pages} page${summary.pages == 1 ? '' : 's'}, ${formatBytes(summary.bytes)}. '
                'Keep it somewhere safe, together with the password.',
              ),
            ),
            ListTile(
              key: const ValueKey('backup-share'),
              leading: const Icon(AppIcons.share),
              title: const Text('Share'),
              onTap: () => Navigator.pop(context, 'share'),
            ),
            ListTile(
              key: const ValueKey('backup-save'),
              leading: const Icon(AppIcons.storage),
              title: const Text('Save to Files or Drive'),
              onTap: () => Navigator.pop(context, 'save'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'share') {
      final failure = (await sl<ShareService>().shareFile(path: path, mimeType: _backupMime, subject: name)).failureOrNull;
      if (failure != null && mounted) showFailure(context, failure);
    } else {
      final result = await sl<SaveService>().saveToFiles(sourcePath: path, fileName: name, mimeType: _backupMime);
      if (!mounted) return;
      final failure = result.failureOrNull;
      if (failure != null) {
        showFailure(context, failure);
      } else if (result.valueOrNull == true) {
        showMessage(context, 'Saved');
      }
    }
  }

  Future<String?> _pick() async {
    final custom = widget.pickBackup;
    if (custom != null) return custom();
    try {
      final picked = await FilePicker.pickFiles(type: FileType.any);
      return picked.isEmpty ? null : picked.first.path;
    } catch (_) {
      if (mounted) showFailure(context, const PermissionFailure('The file picker is unavailable.'));
      return null;
    }
  }

  Future<void> _restore() async {
    final path = await _pick();
    if (path == null || !mounted) return;
    if (!await looksLikeBackup(path)) {
      showMessage(context, 'This file is not a Doculoom backup.');
      return;
    }
    if (!mounted) return;
    final password = await _askPassword(confirm: false);
    if (password == null || !mounted) return;
    setState(() => _busy = 'Restoring backup');
    final result = await _service.restore(path: path, password: password);
    if (!mounted) return;
    setState(() => _busy = null);
    final summary = result.valueOrNull;
    if (summary == null) {
      showFailure(context, result.failureOrNull!);
      return;
    }
    (widget.onRestored ?? context.read<DocumentsCubit>().load).call();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore finished'),
        content: Text(
          key: const ValueKey('restore-result'),
          summary.added == 0
              ? 'Nothing new was added. ${summary.alreadyHere == 0 ? 'The backup had no documents.' : 'All ${summary.alreadyHere} documents in it are already on this phone.'}'
              : 'Added ${summary.added} document${summary.added == 1 ? '' : 's'} (${summary.pages} page${summary.pages == 1 ? '' : 's'}).'
                    '${summary.alreadyHere == 0 ? '' : ' ${summary.alreadyHere} ${summary.alreadyHere == 1 ? 'was' : 'were'} already on this phone and left as they are.'}',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup and restore')),
      body: Stack(
        children: [
          ListView(
            padding: contentPadding(context, base: AppSpacing.md, maxWidth: 560),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(AppIcons.backup, color: AppColors.primary),
                          SizedBox(width: 10),
                          Text('Back up', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      const Text(
                        'Save all your documents and folders in one file, protected by a password you choose. Store it in Drive, on a computer or send it to yourself, so a lost or reset phone does not mean lost documents.',
                        style: TextStyle(color: AppColors.inkMuted, height: 1.4),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      FilledButton.icon(
                        key: const ValueKey('backup-create'),
                        onPressed: _busy == null ? _create : null,
                        icon: const Icon(AppIcons.upload, size: 18),
                        label: const Text('Create backup'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(AppIcons.restore, color: AppColors.primary),
                          SizedBox(width: 10),
                          Text('Restore', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      const Text(
                        'Choose a backup file and type its password. The documents in it are added to this phone. Documents you already have are not changed or duplicated.',
                        style: TextStyle(color: AppColors.inkMuted, height: 1.4),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      OutlinedButton.icon(
                        key: const ValueKey('backup-restore'),
                        onPressed: _busy == null ? _restore : null,
                        icon: const Icon(AppIcons.download, size: 18),
                        label: const Text('Restore from a backup'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              const Text(
                'The password cannot be recovered. Without it nobody, including us, can open the backup. Coins and settings are not part of a backup.',
                key: ValueKey('backup-note'),
                style: TextStyle(color: AppColors.inkMuted, fontSize: 12, height: 1.4),
              ),
            ],
          ),
          BusyOverlay(visible: _busy != null, label: _busy),
        ],
      ),
    );
  }
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.confirm});
  final bool confirm;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _password = TextEditingController();
  final _again = TextEditingController();
  var _show = false;

  @override
  void dispose() {
    _password.dispose();
    _again.dispose();
    super.dispose();
  }

  String? get _problem {
    if (_password.text.isEmpty) return null;
    if (widget.confirm && _password.text.length < minBackupPasswordLength) return 'Use at least $minBackupPasswordLength characters';
    if (widget.confirm && _again.text.isNotEmpty && _again.text != _password.text) return 'The passwords do not match';
    return null;
  }

  bool get _ready => _password.text.isNotEmpty && (!widget.confirm || (_password.text.length >= minBackupPasswordLength && _password.text == _again.text));

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.confirm ? 'Choose a password' : 'Backup password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const ValueKey('backup-password'),
            controller: _password,
            autofocus: true,
            obscureText: !_show,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: tr('Password'),
              suffixIcon: IconButton(icon: Icon(_show ? AppIcons.eyeOff : AppIcons.eye), onPressed: () => setState(() => _show = !_show)),
            ),
          ),
          if (widget.confirm) ...[
            const SizedBox(height: AppSpacing.sm),
            TextField(
              key: const ValueKey('backup-password-again'),
              controller: _again,
              obscureText: !_show,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: tr('Type it again'), errorText: _problem),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text('Write it down. It cannot be recovered.', style: TextStyle(fontSize: 12, color: AppColors.inkMuted)),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          key: const ValueKey('backup-password-ok'),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: _ready ? () => Navigator.pop(context, _password.text) : null,
          child: Text(widget.confirm ? 'Continue' : 'Restore'),
        ),
      ],
    );
  }
}

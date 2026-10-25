import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../app/app_config.dart';
import '../../../app/di.dart';
import '../../../core/error/failures.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/responsive.dart';
import '../../monetization/domain/entities/plan_status.dart';
import '../../monetization/presentation/plan_cubit.dart';
import '../../rewards/domain/coin_rules.dart';
import '../../rewards/presentation/coins_cubit.dart';
import '../../rewards/presentation/unlock.dart';
import '../../settings/domain/feature_access.dart';
import '../domain/share_options.dart';
import '../domain/share_sessions.dart';

class QrShareArgs {
  const QrShareArgs({required this.filePath, required this.fileName, required this.mimeType}) : shareId = null;

  /// Opens a share that is already running, for example from the Documents list.
  const QrShareArgs.resume(String this.shareId) : filePath = '', fileName = '', mimeType = '';

  final String filePath;
  final String fileName;
  final String mimeType;
  final String? shareId;
}

/// Shows a QR code for one file: straight from this phone to people on the same Wi-Fi,
/// or through an encrypted internet link that works on any network.
class QrSharePage extends StatefulWidget {
  const QrSharePage({super.key, required this.args, this.billingEnabled = AppConfig.billingEnabled, this.rewardsEnabled = AppConfig.rewardsEnabled});
  final QrShareArgs args;

  /// Whether purchases exist; Premium-only options are locked for Free users only when they do.
  final bool billingEnabled;

  /// Whether Free users can pay for Premium options with coins from rewarded videos.
  final bool rewardsEnabled;

  @override
  State<QrSharePage> createState() => _QrSharePageState();
}

class _QrSharePageState extends State<QrSharePage> {
  ActiveShare? _share;
  Failure? _failure;
  bool _starting = true;
  int _generation = 0;
  ShareMode _mode = ShareMode.wifi;
  ShareDuration _duration = ShareDuration.min5;
  String? _password;

  /// Set once this share was paid for with coins, so its time can be changed on this screen at no extra cost.
  bool _durationPaid = false;

  /// True while the coin question is on screen; nothing is shown behind it.
  bool _paying = false;

  /// Coins were taken for this share and it has not started yet.
  bool _charged = false;
  Duration _left = Duration.zero;
  Timer? _tick;

  /// True when this screen was opened for a share that was started earlier, so its options are fixed.
  bool _resumed = false;

  /// True when the file was already being shared and that share is shown instead of a new one.
  bool _alreadySharing = false;

  final ShareSessions _sessions = sl<ShareSessions>();
  RemoteShareService get _remote => sl<RemoteShareService>();

  @override
  void initState() {
    super.initState();
    _sessions.shares.addListener(_onSharesChanged);
    final id = widget.args.shareId;
    final existing = id != null ? _sessions.byId(id) : _sessions.activeFor(widget.args.filePath);
    if (existing != null) {
      _resumed = true;
      _alreadySharing = id == null;
      _share = existing;
      _mode = existing.mode;
      _starting = false;
      _tick = Timer.periodic(const Duration(seconds: 1), (_) => _update());
      _update();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _begin());
    }
  }

  /// Free users pay coins for a new share before it starts; leaving the question unanswered closes the screen.
  Future<void> _begin() async {
    if (!mounted) return;
    if (widget.rewardsEnabled && context.read<PlanCubit>().state != PlanStatus.premium) {
      setState(() => _paying = true);
      final paid = await requestUnlock(context, CoinFeature.qrShare);
      if (!mounted) return;
      setState(() => _paying = false);
      if (!paid) {
        if (context.canPop()) context.pop();
        return;
      }
      _charged = true;
      _durationPaid = true;
    }
    await _start();
  }

  void _onSharesChanged() {
    if (mounted) setState(() {});
  }

  /// Changing an option replaces this screen's share with a new one; it is not a second share.
  Future<void> _stopCurrent() async {
    _tick?.cancel();
    final old = _share;
    _share = null;
    if (old != null) await _sessions.stop(old.id);
  }

  Future<void> _start() async {
    final generation = ++_generation;
    await _stopCurrent();
    if (!mounted) return;
    setState(() {
      _starting = true;
      _failure = null;
    });

    final result = await _sessions.start(
      mode: _mode,
      filePath: widget.args.filePath,
      fileName: widget.args.fileName,
      mimeType: widget.args.mimeType,
      ttl: _duration.value,
      password: _password,
    );

    final share = result.valueOrNull;
    // An option changed while this was starting, so this share is stale.
    if (!mounted || generation != _generation) {
      if (share != null) await _sessions.stop(share.id);
      return;
    }
    if (share == null) {
      if (_charged) {
        _charged = false;
        await context.read<CoinsCubit>().refund(CoinFeature.qrShare.cost);
      }
      if (!mounted) return;
      setState(() {
        _starting = false;
        _failure = result.failureOrNull;
      });
      return;
    }
    _charged = false;
    _share = share;
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _update());
    setState(() => _starting = false);
    _update();
  }

  void _update() {
    final s = _share;
    if (s == null || !mounted) return;
    setState(() => _left = s.left);
    if (_left <= Duration.zero) _tick?.cancel();
  }

  /// Leaving the screen keeps the share running; it ends with its timer or "Stop sharing".
  @override
  void dispose() {
    _generation++;
    _tick?.cancel();
    _sessions.shares.removeListener(_onSharesChanged);
    super.dispose();
  }

  Future<void> _stopSharing() async {
    final s = _share;
    if (s != null) await _sessions.stop(s.id);
    if (mounted && context.canPop()) context.pop();
  }

  void _setMode(ShareMode mode) {
    if (mode == _mode) return;
    final password = _password;
    final dropPassword = password != null && SharePassword.problem(password, mode) != null;
    setState(() {
      _mode = mode;
      if (!_duration.allowedIn(mode)) _duration = ShareDuration.hour1;
      if (dropPassword) _password = null;
    });
    if (dropPassword) showMessage(context, 'Password removed: internet sharing needs at least ${SharePassword.minLength(mode)} characters. Set a new one.');
    _start();
  }

  Future<void> _askPassword() async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _PasswordDialog(mode: _mode, current: _password),
    );
    if (result == null || !mounted || result == _password) return;
    setState(() => _password = result.isEmpty ? null : result);
    _start();
  }

  Future<void> _setDuration(ShareDuration d, FeatureState access) async {
    if (d != ShareDuration.min5 && access == FeatureState.locked && !_durationPaid) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: const Text('Choosing how long a share lasts is a Premium feature'),
            persist: false,
            action: SnackBarAction(label: 'Upgrade', onPressed: () => context.push('/paywall')),
          ),
        );
      return;
    }
    if (d == _duration) return;
    setState(() => _duration = d);
    _start();
  }

  String get _remaining {
    final s = _left.inSeconds.clamp(0, 7 * 86400);
    if (s >= 86400) return '${s ~/ 86400}d ${(s % 86400) ~/ 3600}h';
    if (s >= 3600) return '${s ~/ 3600}h ${(s % 3600) ~/ 60}m';
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final share = _share;
    final expired = share != null && (share.expired || _left <= Duration.zero);
    final access = FeatureAccess.customShareDuration(
      plan: context.watch<PlanCubit>().state,
      billingEnabled: widget.billingEnabled,
      coinsEnabled: widget.rewardsEnabled,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Share with QR code')),
      body: SafeArea(
        child: ListView(
          padding: contentPadding(context, base: AppSpacing.lg, maxWidth: 560),
          children: [
            Text(
              widget.args.fileName.isEmpty ? (share?.fileName ?? '') : widget.args.fileName,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.md),
            if (_alreadySharing) ...[const _AlreadySharing(), const SizedBox(height: AppSpacing.md)],
            if (!_resumed) ...[
              _Options(
                mode: _mode,
                duration: _duration,
                access: access,
                durationPaid: _durationPaid,
                internetAvailable: _remote.isConfigured,
                onMode: _setMode,
                onDuration: (d) => _setDuration(d, access),
              ),
              const SizedBox(height: AppSpacing.sm),
              _PasswordRow(enabled: _password != null, onTap: _askPassword),
              const SizedBox(height: AppSpacing.md),
            ],
            if (_paying)
              const SizedBox.shrink()
            else if (_starting)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_failure != null)
              _FailureNote(text: _failure!.message)
            else if (share != null) ...[
              Center(
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppSpacing.radius),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Opacity(
                    opacity: expired ? 0.15 : 1,
                    child: QrImageView(data: share.url, size: 240, backgroundColor: Colors.white, errorCorrectionLevel: QrErrorCorrectLevel.M),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.md,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(AppIcons.timer, size: 18, color: AppColors.inkMuted),
                      const SizedBox(width: 6),
                      Text(expired ? 'Link expired' : 'Expires in $_remaining', style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                  if (share.mode == ShareMode.wifi)
                    Text('${share.downloads} download${share.downloads == 1 ? '' : 's'}', style: const TextStyle(color: AppColors.inkMuted)),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              _Note(mode: share.mode, protected: share.isProtected),
              const SizedBox(height: AppSpacing.md),
              SelectableText(
                share.url,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
              ),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                onPressed: expired
                    ? null
                    : () async {
                        await Clipboard.setData(ClipboardData(text: share.url));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context)
                            ..hideCurrentSnackBar()
                            ..showSnackBar(const SnackBar(content: Text('Link copied'), persist: false));
                        }
                      },
                icon: const Icon(AppIcons.copy, size: 18),
                label: const Text('Copy link'),
              ),
              if (!expired) ...[
                const SizedBox(height: AppSpacing.md),
                const Text(
                  'You can leave this screen or the app. Sharing continues until the time is up or you stop it.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: AppColors.inkMuted, height: 1.4),
                ),
              ],
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: share == null || expired ? AppColors.inkMuted : AppColors.danger),
                onPressed: share == null || expired ? () => context.pop() : _stopSharing,
                child: Text(share == null || expired ? 'Close' : 'Stop sharing'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlreadySharing extends StatelessWidget {
  const _AlreadySharing();

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('already-sharing'),
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(color: const Color(0xFFEFF4FF), borderRadius: BorderRadius.circular(AppSpacing.radius)),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(AppIcons.info, size: 18, color: AppColors.primary),
        SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            'This file is already being shared, so this is the same code. To change the time or password, or to share the latest version, stop sharing and start again.',
            style: TextStyle(fontSize: 13, height: 1.4),
          ),
        ),
      ],
    ),
  );
}

class _Options extends StatelessWidget {
  const _Options({
    required this.mode,
    required this.duration,
    required this.access,
    required this.durationPaid,
    required this.internetAvailable,
    required this.onMode,
    required this.onDuration,
  });

  final ShareMode mode;
  final ShareDuration duration;
  final FeatureState access;
  final bool durationPaid;
  final bool internetAvailable;
  final ValueChanged<ShareMode> onMode;
  final ValueChanged<ShareDuration> onDuration;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<ShareMode>(
          showSelectedIcon: false,
          segments: [
            const ButtonSegment(value: ShareMode.wifi, icon: Icon(AppIcons.wifi, size: 18), label: Text('Same Wi-Fi')),
            ButtonSegment(value: ShareMode.internet, icon: const Icon(AppIcons.link, size: 18), label: const Text('Anywhere'), enabled: internetAvailable),
          ],
          selected: {mode},
          onSelectionChanged: (s) => onMode(s.first),
        ),
        if (!internetAvailable)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'Sharing over the internet is not set up in this version.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        const Text(
          'Available for',
          style: TextStyle(fontSize: 13, color: AppColors.inkMuted, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            for (final d in ShareDuration.values)
              if (d.allowedIn(mode))
                ChoiceChip(
                  label: Text(d.label),
                  avatar: d != ShareDuration.min5 && access == FeatureState.locked && !durationPaid ? const Icon(AppIcons.lock, size: 14) : null,
                  selected: d == duration,
                  onSelected: (_) => onDuration(d),
                ),
          ],
        ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.mode, this.protected = false});
  final ShareMode mode;
  final bool protected;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(AppIcons.shield, size: 20, color: AppColors.success),
          const SizedBox(width: AppSpacing.sm + 4),
          Expanded(
            child: Text(
              (mode == ShareMode.wifi
                      ? 'Scan with any phone camera on the same Wi-Fi or hotspot. The file goes straight from this phone and is never uploaded. Keep this phone on the same Wi-Fi while others download. '
                      : 'Works on any network or mobile data. The file is encrypted on this phone before it is uploaded, so the service cannot read it. ') +
                  (protected
                      ? (mode == ShareMode.wifi
                            ? 'Whoever opens the code must type the password; after 5 wrong tries the link locks.'
                            : 'The link contains no key: the file only opens with the password. Share the password separately, not in the same message.')
                      : (mode == ShareMode.wifi
                            ? 'Anyone who can see this code on your network can download it until it expires or you stop sharing.'
                            : 'Anyone with the link or code can download it until it expires or you stop sharing, then it is deleted.')),
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    ),
  );
}

class _PasswordRow extends StatelessWidget {
  const _PasswordRow({required this.enabled, required this.onTap});
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: ListTile(
      dense: true,
      leading: Icon(enabled ? AppIcons.lock : AppIcons.unlock, color: enabled ? AppColors.success : AppColors.inkMuted),
      title: Text(enabled ? 'Password protected' : 'Protect with a password'),
      subtitle: Text(enabled ? 'People must enter it to download' : 'Optional. Ask for a password before the download'),
      trailing: Text(
        enabled ? 'Change' : 'Set',
        style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600),
      ),
      onTap: onTap,
    ),
  );
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.mode, required this.current});
  final ShareMode mode;
  final String? current;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  late final TextEditingController _controller = TextEditingController(text: widget.current ?? '');
  bool _visible = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final problem = SharePassword.problem(_controller.text, widget.mode);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    Navigator.pop(context, _controller.text);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Share password'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          autofocus: true,
          obscureText: !_visible,
          maxLength: SharePassword.maxLength,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            hintText: 'Password',
            errorText: _error,
            counterText: '',
            suffixIcon: IconButton(
              tooltip: _visible ? 'Hide password' : 'Show password',
              icon: Icon(_visible ? AppIcons.eyeOff : AppIcons.eye, size: 20),
              onPressed: () => setState(() => _visible = !_visible),
            ),
          ),
          onChanged: (_) => setState(() => _error = null),
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          widget.mode == ShareMode.internet
              ? 'Use at least ${SharePassword.minLength(widget.mode)} characters. Anyone with the link can try guesses, so a longer password is safer. Tell people the password separately.'
              : 'Use at least ${SharePassword.minLength(widget.mode)} characters. On Wi-Fi the password travels over your local network without encryption. Tell people the password separately.',
          style: const TextStyle(fontSize: 12, color: AppColors.inkMuted, height: 1.4),
        ),
      ],
    ),
    actions: [
      if (widget.current != null) TextButton(onPressed: () => Navigator.pop(context, ''), child: const Text('Remove')),
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      TextButton(onPressed: _save, child: const Text('Save')),
    ],
  );
}

class _FailureNote extends StatelessWidget {
  const _FailureNote({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpacing.lg),
    child: Column(
      children: [
        const Icon(AppIcons.wifi, size: 44, color: AppColors.inkMuted),
        const SizedBox(height: AppSpacing.md),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.inkMuted, height: 1.4),
        ),
      ],
    ),
  );
}

import 'dart:async';

import 'package:flutter/material.dart' hide Text;
import 'package:go_router/go_router.dart';

import '../../../app/di.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../domain/share_options.dart';
import '../domain/share_sessions.dart';
import 'qr_share_page.dart';
import '../../../core/widgets/text.dart';

/// Lists the files that are being shared right now, so a share started earlier can be reopened or stopped.
class ActiveSharesBanner extends StatelessWidget {
  const ActiveSharesBanner({super.key});

  @override
  Widget build(BuildContext context) {
    if (!sl.isRegistered<ShareSessions>()) return const SizedBox.shrink();
    final sessions = sl<ShareSessions>();
    return ValueListenableBuilder<List<ActiveShare>>(
      valueListenable: sessions.shares,
      builder: (context, shares, _) {
        if (shares.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
          child: Column(
            children: [for (final s in shares) _ShareTile(share: s, onStop: () => sessions.stop(s.id))],
          ),
        );
      },
    );
  }
}

class _ShareTile extends StatefulWidget {
  const _ShareTile({required this.share, required this.onStop});
  final ActiveShare share;
  final VoidCallback onStop;

  @override
  State<_ShareTile> createState() => _ShareTileState();
}

class _ShareTileState extends State<_ShareTile> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String get _left {
    final s = widget.share.left.inSeconds.clamp(0, 7 * 86400);
    if (s >= 86400) return '${s ~/ 86400}d ${(s % 86400) ~/ 3600}h';
    if (s >= 3600) return '${s ~/ 3600}h ${(s % 3600) ~/ 60}m';
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final share = widget.share;
    final wifi = share.mode == ShareMode.wifi;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: ListTile(
        dense: true,
        leading: Icon(wifi ? AppIcons.wifi : AppIcons.link, color: AppColors.primary),
        title: Text(
          'Sharing ${share.fileName}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text('$_left left${wifi ? ' · ${share.downloads} download${share.downloads == 1 ? '' : 's'}' : ''}'),
        trailing: TextButton(
          onPressed: widget.onStop,
          child: const Text('Stop', style: TextStyle(color: AppColors.danger)),
        ),
        onTap: () => context.push('/qr-share', extra: QrShareArgs.resume(share.id)),
      ),
    );
  }
}

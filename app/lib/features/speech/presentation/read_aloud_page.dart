import 'package:flutter/material.dart' hide Text;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/di.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/responsive.dart';
import '../domain/speech_chunks.dart';
import '../domain/speech_service.dart';
import 'read_aloud_cubit.dart';
import '../../../core/widgets/text.dart';
import '../../../core/i18n/tr.dart';

/// What the Read aloud screen reads.
class ReadAloudArgs {
  const ReadAloudArgs({required this.title, required this.text, this.language});
  final String title;
  final String text;

  /// The voice language to start with (for example the language a text was translated into); null follows the text.
  final String? language;
}

/// Reads text aloud with the phone's own voice, piece by piece, with pause, skip, speed and language.
class ReadAloudPage extends StatelessWidget {
  const ReadAloudPage({super.key, required this.args, this.service});
  final ReadAloudArgs args;

  /// For tests; the phone's engine is used otherwise.
  final SpeechService? service;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => ReadAloudCubit(service: service ?? sl<SpeechService>(), text: args.text, language: args.language)..start(),
    child: _ReadView(title: args.title),
  );
}

class _ReadView extends StatefulWidget {
  const _ReadView({required this.title});
  final String title;

  @override
  State<_ReadView> createState() => _ReadViewState();
}

class _ReadViewState extends State<_ReadView> {
  final _scroll = ScrollController();
  final _keys = <int, GlobalKey>{};

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _reveal(int index, int count) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _keys[index]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 250), alignment: 0.3);
      } else if (_scroll.hasClients && count > 1) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent * index / (count - 1));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ReadAloudCubit, ReadAloudState>(
      listenWhen: (a, b) => a.index != b.index && b.speaking,
      listener: (context, s) => _reveal(s.index, s.chunks.length),
      builder: (context, state) {
        final cubit = context.read<ReadAloudCubit>();
        final problem = state.status == ReadStatus.unavailable || state.status == ReadStatus.languageMissing || state.status == ReadStatus.failed;
        return Scaffold(
          appBar: AppBar(title: Text(widget.title, overflow: TextOverflow.ellipsis)),
          body: SafeArea(
            child: state.status == ReadStatus.loading
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      Expanded(
                        child: state.hasText
                            ? ListView.builder(
                                key: const ValueKey('read-list'),
                                controller: _scroll,
                                padding: contentPadding(context, base: AppSpacing.md, maxWidth: 720),
                                itemCount: state.chunks.length,
                                itemBuilder: (context, i) {
                                  final on = i == state.index && (state.speaking || state.status == ReadStatus.paused);
                                  return Padding(
                                    key: _keys.putIfAbsent(i, GlobalKey.new),
                                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                                    child: Material(
                                      color: on ? AppColors.primarySoft : Colors.transparent,
                                      borderRadius: BorderRadius.circular(8),
                                      child: InkWell(
                                        key: ValueKey('read-chunk-$i'),
                                        borderRadius: BorderRadius.circular(8),
                                        onTap: () => cubit.seek(i),
                                        child: Padding(
                                          padding: const EdgeInsets.all(AppSpacing.sm),
                                          child: Text(
                                            state.chunks[i],
                                            style: TextStyle(fontSize: 16, height: 1.45, fontWeight: on ? FontWeight.w600 : FontWeight.w400),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              )
                            : const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(AppSpacing.lg),
                                  child: Text(
                                    'There is no text to read.',
                                    key: ValueKey('read-empty'),
                                    style: TextStyle(color: AppColors.inkMuted),
                                  ),
                                ),
                              ),
                      ),
                      Material(
                        elevation: 6,
                        color: Theme.of(context).colorScheme.surface,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.5),
                          child: SingleChildScrollView(
                            padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (state.message != null)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Icon(AppIcons.info, size: 18, color: AppColors.danger),
                                        const SizedBox(width: AppSpacing.sm),
                                        Expanded(
                                          child: Text(state.message!, key: const ValueKey('read-message'), style: const TextStyle(fontSize: 13, height: 1.4)),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (problem)
                                  Align(
                                    alignment: AlignmentDirectional.centerStart,
                                    child: TextButton(
                                      key: const ValueKey('read-open-settings'),
                                      onPressed: cubit.openVoiceSettings,
                                      child: const Text('Open voice settings'),
                                    ),
                                  ),
                                if (state.hasText)
                                  Text(
                                    'Part ${state.index + 1} of ${state.chunks.length}',
                                    key: const ValueKey('read-position'),
                                    style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
                                  ),
                                Wrap(
                                  alignment: WrapAlignment.center,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: AppSpacing.xs,
                                  children: [
                                    IconButton(
                                      key: const ValueKey('read-prev'),
                                      tooltip: tr('Previous part'),
                                      onPressed: state.hasText ? cubit.previous : null,
                                      icon: const Icon(AppIcons.skipPrevious),
                                    ),
                                    FilledButton.icon(
                                      key: const ValueKey('read-play'),
                                      style: FilledButton.styleFrom(minimumSize: const Size(120, 48)),
                                      onPressed: state.hasText && state.status != ReadStatus.unavailable ? cubit.toggle : null,
                                      icon: Icon(state.speaking ? AppIcons.pause : AppIcons.play, size: 20),
                                      label: Text(state.speaking ? 'Pause' : (state.status == ReadStatus.paused ? 'Resume' : 'Read')),
                                    ),
                                    IconButton(
                                      key: const ValueKey('read-next'),
                                      tooltip: tr('Next part'),
                                      onPressed: state.hasText ? cubit.next : null,
                                      icon: const Icon(AppIcons.skipNext),
                                    ),
                                    IconButton(
                                      key: const ValueKey('read-stop'),
                                      tooltip: tr('Stop'),
                                      onPressed: state.hasText ? cubit.stop : null,
                                      icon: const Icon(AppIcons.stopSquare),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                Wrap(
                                  spacing: AppSpacing.sm,
                                  children: [
                                    for (final r in ReadAloudCubit.rates)
                                      ChoiceChip(
                                        key: ValueKey('read-rate-$r'),
                                        label: Text('${r == r.roundToDouble() ? r.toInt() : r}x'),
                                        selected: state.rate == r,
                                        onSelected: (_) => cubit.setRate(r),
                                      ),
                                  ],
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Voice language', style: TextStyle(fontSize: 13)),
                                    DropdownButton<String?>(
                                      key: const ValueKey('read-language'),
                                      isExpanded: true,
                                      value: state.language,
                                      items: [
                                        for (final (code, name) in speechLanguages)
                                          DropdownMenuItem(
                                            value: code,
                                            child: Text(name, overflow: TextOverflow.ellipsis),
                                          ),
                                      ],
                                      onChanged: cubit.setLanguage,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

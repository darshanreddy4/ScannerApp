import 'package:flutter/material.dart' hide Text;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/app_config.dart';
import '../../../../core/i18n/app_language.dart';
import '../../../../core/i18n/tr.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/widgets/style_kit.dart';
import '../../../../core/widgets/text.dart';
import '../../../monetization/domain/entities/plan_status.dart';
import '../../../monetization/presentation/plan_cubit.dart';
import '../../../rewards/presentation/coins_card.dart';
import '../../../rewards/presentation/coins_cubit.dart';
import '../../../settings/domain/app_settings.dart';
import '../../../settings/presentation/settings_cubit.dart';

/// Top bar of the Documents and Settings pages: the app mark and page title on one side, and on the other the
/// language, the look of the text and the coin balance. Each one opens something that already exists in the app.
class HomeTopBar extends StatelessWidget implements PreferredSizeWidget {
  const HomeTopBar({super.key, required this.title});
  final String title;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 1);

  @override
  Widget build(BuildContext context) => AppBar(
    automaticallyImplyLeading: false,
    titleSpacing: AppSpacing.md,
    title: LayoutBuilder(
      builder: (context, box) => Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: Image.asset('assets/images/app_icon.png', width: 36, height: 36, excludeFromSemantics: true),
          ),
          const SizedBox(width: AppSpacing.sm + 2),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: box.maxWidth * 0.68),
            child: const FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerEnd, child: _TopActions()),
          ),
        ],
      ),
    ),
    bottom: const PreferredSize(preferredSize: Size.fromHeight(1), child: Divider()),
  );
}

class _TopActions extends StatelessWidget {
  const _TopActions();

  @override
  Widget build(BuildContext context) {
    final language = context.select((SettingsCubit c) => c.state.language);
    final premium = context.select((PlanCubit c) => c.state) == PlanStatus.premium;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _LanguageChip(code: language.resolved.toUpperCase()),
        const SizedBox(width: AppSpacing.sm),
        const _LookButton(),
        if (AppConfig.rewardsEnabled && !premium) ...[const SizedBox(width: AppSpacing.sm), const _CoinsPill()],
      ],
    );
  }
}

const _barHeight = 34.0;

class _LanguageChip extends StatelessWidget {
  const _LanguageChip({required this.code});
  final String code;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tr('Language of the app'),
    child: Material(
      color: AppColors.surface,
      shape: StadiumBorder(side: BorderSide(color: AppColors.primary.withValues(alpha: 0.45), width: 1.2)),
      child: InkWell(
        key: const ValueKey('top-language'),
        customBorder: const StadiumBorder(),
        onTap: () => showLanguagePicker(context),
        child: SizedBox(
          height: _barHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(AppIcons.globe, size: 16, color: AppColors.primary),
                const SizedBox(width: 5),
                Text(
                  code,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.primary),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _LookButton extends StatelessWidget {
  const _LookButton();

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tr('Text and icon size'),
    child: Material(
      color: AppColors.surface,
      shape: CircleBorder(side: BorderSide(color: AppColors.border.withValues(alpha: 1), width: 1.2)),
      child: InkWell(
        key: const ValueKey('top-look'),
        customBorder: const CircleBorder(),
        onTap: () => showTextSizePicker(context),
        child: const SizedBox(
          width: _barHeight,
          height: _barHeight,
          child: Icon(AppIcons.palette, size: 17, color: AppColors.ink),
        ),
      ),
    ),
  );
}

class _CoinsPill extends StatelessWidget {
  const _CoinsPill();

  @override
  Widget build(BuildContext context) {
    final balance = context.select((CoinsCubit c) => c.state.balance);
    final unclaimed = context.select((CoinsCubit c) => !c.state.dailyClaimed);
    return Badge(
      isLabelVisible: unclaimed,
      smallSize: 10,
      backgroundColor: AppColors.danger,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: ShapeDecoration(
            shape: const StadiumBorder(),
            gradient: const LinearGradient(colors: [Color(0xFFFBBF24), Color(0xFFF97316)]),
          ),
          child: InkWell(
            key: const ValueKey('top-coins'),
            customBorder: const StadiumBorder(),
            onTap: () => _showCoins(context),
            child: SizedBox(
              height: _barHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 11),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(AppIcons.coins, size: 16, color: Colors.white),
                    const SizedBox(width: 5),
                    Text(
                      '$balance',
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showCoins(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const SingleChildScrollView(padding: EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md), child: CoinsCard()),
  );
}

/// A row in a picker: coloured icon tile, title, small line below, and a tick on the chosen one.
class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({super.key, required this.icon, required this.color, required this.title, this.subtitle, required this.selected, required this.onTap});
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm + 2),
    child: Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: selected ? AppColors.primary : AppColors.border, width: selected ? 2 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md - 2),
          child: Row(
            children: [
              GradientIconTile(icon: icon, color: color, size: 42),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                    if (subtitle != null) Text(subtitle!, style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
                  ],
                ),
              ),
              if (selected) const Icon(Icons.check_circle, color: AppColors.primary),
            ],
          ),
        ),
      ),
    ),
  );
}

const _tileColors = [
  Color(0xFF2563EB),
  Color(0xFF7C3AED),
  Color(0xFFDB2777),
  Color(0xFF0D9488),
  Color(0xFFF97316),
  Color(0xFF16A34A),
  Color(0xFF0284C7),
  Color(0xFFD97706),
];

Future<void> _showSheet(
  BuildContext context, {
  required IconData icon,
  required Color color,
  required String title,
  String? subtitle,
  required Widget Function(BuildContext) body,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.86),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm + 4),
              child: Row(
                children: [
                  GradientIconTile(icon: icon, color: color, size: 40),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                        if (subtitle != null) Text(subtitle, style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Flexible(child: body(ctx)),
          ],
        ),
      ),
    ),
  );
}

/// The list of languages the app can be shown in, with a search field. It sets the same language as the Settings page.
Future<void> showLanguagePicker(BuildContext context) {
  final cubit = context.read<SettingsCubit>();
  return _showSheet(
    context,
    icon: AppIcons.language,
    color: AppColors.primary,
    title: 'Language of the app',
    body: (_) => BlocProvider.value(value: cubit, child: const _LanguageList()),
  );
}

class _LanguageList extends StatefulWidget {
  const _LanguageList();

  @override
  State<_LanguageList> createState() => _LanguageListState();
}

class _LanguageListState extends State<_LanguageList> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final current = context.select((SettingsCubit c) => c.state.language);
    final q = _query.trim().toLowerCase();
    final shown = [
      for (final l in AppLanguage.values)
        if (q.isEmpty || l.label.toLowerCase().contains(q) || tr(l.label).toLowerCase().contains(q) || (l.code ?? '').contains(q)) l,
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm + 2),
          child: TextField(
            key: const ValueKey('language-search'),
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: tr('Search language'),
              prefixIcon: const Icon(AppIcons.search, size: 20),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: AppColors.border),
              ),
            ),
          ),
        ),
        Flexible(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.md),
            shrinkWrap: true,
            children: [
              for (final l in shown)
                _ChoiceCard(
                  key: ValueKey('language-${l.name}'),
                  icon: AppIcons.language,
                  color: _tileColors[l.index % _tileColors.length],
                  title: l == AppLanguage.system ? tr('System language') : l.label,
                  subtitle: l.resolved.toUpperCase(),
                  selected: l == current,
                  onTap: () {
                    context.read<SettingsCubit>().update((c) => c.copyWith(language: l));
                    Navigator.pop(context);
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The sizes of text and icons, the same choice the Settings page offers.
Future<void> showTextSizePicker(BuildContext context) {
  final cubit = context.read<SettingsCubit>();
  return _showSheet(
    context,
    icon: AppIcons.palette,
    color: const Color(0xFF7C3AED),
    title: 'Text and icon size',
    subtitle: tr('Make buttons, icons and text smaller or larger'),
    body: (_) => BlocProvider.value(value: cubit, child: const _SizeList()),
  );
}

class _SizeList extends StatelessWidget {
  const _SizeList();

  @override
  Widget build(BuildContext context) {
    final current = context.select((SettingsCubit c) => c.state.interfaceSize);
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.md),
      shrinkWrap: true,
      children: [
        for (final s in InterfaceSize.values)
          _ChoiceCard(
            key: ValueKey('size-${s.name}'),
            icon: AppIcons.fontSize,
            color: _tileColors[(s.index + 1) % _tileColors.length],
            title: tr(s.label),
            selected: s == current,
            onTap: () {
              context.read<SettingsCubit>().update((c) => c.copyWith(interfaceSize: s));
              Navigator.pop(context);
            },
          ),
      ],
    );
  }
}

import 'package:flutter/material.dart' hide Text;

import '../../../app/di.dart';
import '../../../core/i18n/tr.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/text.dart';
import '../../documents/presentation/widgets/document_widgets.dart' show confirmDestructive;
import '../../reminders/domain/reminder_service.dart';
import '../domain/hijri.dart';

const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

String _weekday(DateTime d) => tr(_weekdays[d.weekday - 1]);

String _hijriText(HijriDate h) => '${h.day} ${tr(hijriMonthNames[h.month - 1])} ${h.year}';

/// The Islamic calendar as Saudi Arabia counts it (Umm al-Qura): today's date, a month view, a converter in both directions, and
/// reminders that come back every Hijri year, such as Ramadan and the two Eids.
class HijriPage extends StatefulWidget {
  const HijriPage({super.key, this.now, this.store = const HijriReminderStore()});
  final DateTime? now;
  final HijriReminderStore store;

  @override
  State<HijriPage> createState() => _HijriPageState();
}

class _HijriPageState extends State<HijriPage> {
  late final DateTime _today = DateTime((widget.now ?? DateTime.now()).year, (widget.now ?? DateTime.now()).month, (widget.now ?? DateTime.now()).day);
  late DateTime _selected = _clamp(_today);
  late int _viewYear;
  late int _viewMonth;
  bool _toGregorian = false;
  int _formMonth = 1;
  final _formDay = TextEditingController();
  final _formYear = TextEditingController();
  List<HijriReminder> _reminders = const [];
  bool _loaded = false;

  static DateTime _clamp(DateTime d) => d.isBefore(hijriFirstDay) ? hijriFirstDay : (d.isAfter(hijriLastDay) ? hijriLastDay : d);

  @override
  void initState() {
    super.initState();
    _goTo(_selected);
    _load();
  }

  @override
  void dispose() {
    _formDay.dispose();
    _formYear.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final all = await widget.store.load();
    if (!mounted) return;
    setState(() {
      _reminders = all;
      _loaded = true;
    });
  }

  void _goTo(DateTime d) {
    final h = toHijri(d);
    if (h == null) return;
    _selected = d;
    _viewYear = h.year;
    _viewMonth = h.month;
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(context: context, initialDate: _selected, firstDate: hijriFirstDay, lastDate: hijriLastDay);
    if (d != null && mounted) setState(() => _goTo(DateTime(d.year, d.month, d.day)));
  }

  /// The Gregorian day for the Hijri date typed in, or the reason it is not one.
  ({DateTime? day, String? problem}) _fromForm() {
    final day = int.tryParse(_formDay.text.trim());
    final year = int.tryParse(_formYear.text.trim());
    if (day == null || year == null) return (day: null, problem: null);
    if (year < hijriFirstYear || year > hijriLastYear)
      return (day: null, problem: trf('Years {from} to {to} are supported.', {'from': hijriFirstYear, 'to': hijriLastYear}));
    final length = hijriMonthLength(year, _formMonth)!;
    if (day < 1 || day > length)
      return (day: null, problem: trf('{month} {year} has {n} days.', {'month': tr(hijriMonthNames[_formMonth - 1]), 'year': year, 'n': length}));
    return (day: toGregorian(year, _formMonth, day), problem: null);
  }

  void _formChanged() {
    final r = _fromForm();
    setState(() {
      if (r.day != null) _goTo(r.day!);
    });
  }

  void _shiftMonth(int by) {
    var y = _viewYear, m = _viewMonth + by;
    if (m < 1) {
      m = 12;
      y--;
    } else if (m > 12) {
      m = 1;
      y++;
    }
    if (y < hijriFirstYear || y > hijriLastYear) return;
    setState(() {
      _viewYear = y;
      _viewMonth = m;
    });
  }

  Future<void> _save(List<HijriReminder> all) async {
    await widget.store.save(all);
    if (!mounted) return;
    setState(() => _reminders = all);
    if (!sl.isRegistered<ReminderService>()) return;
    final service = sl<ReminderService>();
    if (await service.shouldExplain() && mounted) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Get a reminder?'),
          content: const Text(
            'Doculoom can send a notification on the day, or a few days before. For dates you made up yourself, the notification does not name the date unless you turn that on in Settings.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')),
            FilledButton(key: const ValueKey('hijri-allow'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Allow notifications')),
          ],
        ),
      );
      if (ok == true) await service.askOnce();
    }
    await service.refresh();
  }

  Future<void> _addOccasions() async {
    final chosen = await showModalBottomSheet<({Set<String> keys, int before})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _OccasionSheet(taken: {for (final r in _reminders) ?r.occasion}),
    );
    if (chosen == null || chosen.keys.isEmpty || !mounted) return;
    final all = [..._reminders];
    for (final k in chosen.keys) {
      final o = hijriOccasionOf(k)!;
      if (all.length >= maxHijriReminders) break;
      all.add(HijriReminder(id: 'occ-$k', title: o.name, month: o.month, day: o.day, daysBefore: chosen.before, occasion: k));
    }
    await _save(all);
  }

  Future<void> _addSelected() async {
    final h = toHijri(_selected);
    if (h == null) return;
    if (_reminders.length >= maxHijriReminders) {
      showMessage(context, 'You can keep up to 40 yearly reminders.');
      return;
    }
    final title = await showDialog<String>(
      context: context,
      builder: (_) => _TitleDialog(initial: trf('{day} {month}', {'day': h.day, 'month': tr(hijriMonthNames[h.month - 1])})),
    );
    if (title == null || title.trim().isEmpty || !mounted) return;
    await _save([..._reminders, HijriReminder(id: 'own-${DateTime.now().microsecondsSinceEpoch}', title: title.trim(), month: h.month, day: h.day)]);
  }

  Future<void> _remove(HijriReminder r) async {
    final ok = await confirmDestructive(context, title: 'Remove this reminder?', message: 'It will no longer come back each year.', action: 'Remove');
    if (!ok || !mounted) return;
    await _save([
      for (final x in _reminders)
        if (x.id != r.id) x,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final todayH = toHijri(_today);
    return Scaffold(
      appBar: AppBar(title: const Text('Hijri calendar')),
      body: ListView(
        padding: contentPadding(context).copyWith(bottom: AppSpacing.xl),
        children: [
          if (todayH != null)
            Container(
              key: const ValueKey('hijri-today'),
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(AppSpacing.radius)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Today', style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
                  Text('${_weekday(_today)}, ${_hijriText(todayH)} AH', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  Text(formatDate(_today), style: const TextStyle(color: AppColors.inkMuted)),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'Dates follow the Umm al-Qura calendar used in Saudi Arabia. Where the new moon is sighted, a month can start a day or two later, so check the date for prayer, fasting and Eid.',
            style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted, height: 1.4),
          ),
          const SizedBox(height: AppSpacing.md),
          _calendar(),
          const SizedBox(height: AppSpacing.md),
          _converter(),
          const SizedBox(height: AppSpacing.md),
          _selectedCard(),
          const SizedBox(height: AppSpacing.md),
          _remindersCard(),
        ],
      ),
    );
  }

  Widget _calendar() {
    final first = hijriMonthStart(_viewYear, _viewMonth);
    final length = hijriMonthLength(_viewYear, _viewMonth) ?? 29;
    final lead = first == null ? 0 : first.weekday % 7;
    final names = MaterialLocalizations.of(context).narrowWeekdays;
    final selectedH = toHijri(_selected);
    final todayH = toHijri(_today);
    bool occasion(int d) => hijriOccasions.any((o) => o.month == _viewMonth && o.day == d);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm + 2),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  key: const ValueKey('hijri-prev'),
                  tooltip: tr('Previous month'),
                  onPressed: _viewYear == hijriFirstYear && _viewMonth == 1 ? null : () => _shiftMonth(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    '${tr(hijriMonthNames[_viewMonth - 1])} $_viewYear',
                    key: const ValueKey('hijri-title'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  key: const ValueKey('hijri-next'),
                  tooltip: tr('Next month'),
                  onPressed: _viewYear == hijriLastYear && _viewMonth == 12 ? null : () => _shiftMonth(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            Row(
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Center(
                      child: Text(names[i], style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            if (first != null)
              for (var row = 0; row < ((lead + length) / 7).ceil(); row++)
                Row(
                  children: [
                    for (var col = 0; col < 7; col++)
                      Expanded(
                        child: () {
                          final d = row * 7 + col - lead + 1;
                          if (d < 1 || d > length) return const SizedBox(height: 46);
                          final g = DateTime(first.year, first.month, first.day + d - 1);
                          final isSelected = selectedH != null && selectedH == HijriDate(_viewYear, _viewMonth, d);
                          final isToday = todayH != null && todayH == HijriDate(_viewYear, _viewMonth, d);
                          return Padding(
                            padding: const EdgeInsets.all(1.5),
                            child: InkWell(
                              key: ValueKey('hijri-day-$d'),
                              borderRadius: BorderRadius.circular(8),
                              onTap: () => setState(() => _selected = g),
                              child: Container(
                                height: 43,
                                decoration: BoxDecoration(
                                  color: isSelected ? AppColors.primary : null,
                                  border: isToday && !isSelected ? Border.all(color: AppColors.primary, width: 1.5) : null,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        '$d',
                                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: isSelected ? Colors.white : AppColors.ink),
                                      ),
                                      Text(
                                        occasion(d) ? '\u2022 ${g.day}' : '${g.day}',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          color: isSelected ? Colors.white70 : (occasion(d) ? AppColors.primary : AppColors.inkMuted),
                                          fontWeight: occasion(d) ? FontWeight.w700 : FontWeight.w400,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }(),
                      ),
                  ],
                ),
            const SizedBox(height: 4),
            const Text(
              'Big numbers are Hijri days. Small numbers are the days of the Gregorian month. A dot marks an occasion.',
              style: TextStyle(fontSize: 11.5, color: AppColors.inkMuted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _converter() {
    final form = _fromForm();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Convert a date', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: AppSpacing.sm),
            SegmentedButton<bool>(
              key: const ValueKey('hijri-mode'),
              segments: const [
                ButtonSegment(value: false, label: Text('To Hijri')),
                ButtonSegment(value: true, label: Text('To Gregorian')),
              ],
              selected: {_toGregorian},
              onSelectionChanged: (s) => setState(() => _toGregorian = s.first),
            ),
            const SizedBox(height: AppSpacing.sm + 4),
            if (!_toGregorian)
              OutlinedButton.icon(
                key: const ValueKey('hijri-pick-date'),
                onPressed: _pickDate,
                icon: const Icon(AppIcons.timer, size: 18),
                label: Text(formatDate(_selected)),
              )
            else ...[
              DropdownButtonFormField<int>(
                key: ValueKey('hijri-month-$_formMonth'),
                isExpanded: true,
                initialValue: _formMonth,
                decoration: InputDecoration(labelText: tr('Hijri month')),
                items: [
                  for (var i = 0; i < 12; i++)
                    DropdownMenuItem(
                      value: i + 1,
                      child: Text.rich(TextSpan(text: tr(hijriMonthNames[i])), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  _formMonth = v;
                  _formChanged();
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('hijri-form-day'),
                      controller: _formDay,
                      keyboardType: TextInputType.number,
                      maxLength: 2,
                      onChanged: (_) => _formChanged(),
                      decoration: InputDecoration(labelText: tr('Day'), counterText: ''),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      key: const ValueKey('hijri-form-year'),
                      controller: _formYear,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      onChanged: (_) => _formChanged(),
                      decoration: InputDecoration(labelText: tr('Hijri year (AH)'), counterText: '', errorText: form.problem, errorMaxLines: 3),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _selectedCard() {
    final h = toHijri(_selected);
    if (h == null) return const SizedBox.shrink();
    final names = [
      for (final o in hijriOccasions)
        if (o.month == h.month && o.day == h.day) o,
    ];
    return Card(
      key: const ValueKey('hijri-selected'),
      color: AppColors.primarySoft,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_weekday(_selected)}, ${_hijriText(h)} AH',
              key: const ValueKey('hijri-result'),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(formatDate(_selected), style: const TextStyle(color: AppColors.inkMuted)),
            for (final o in names)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  tr(o.name),
                  key: ValueKey('hijri-occasion-${o.key}'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              key: const ValueKey('hijri-add-selected'),
              onPressed: _addSelected,
              icon: const Icon(AppIcons.timer, size: 18),
              label: const Text('Remind me every year'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _remindersCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Yearly reminders', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text(
            'A notification each Hijri year, on the day or a few days before. The Gregorian date moves by about 11 days a year.',
            style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted, height: 1.4),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (_loaded && _reminders.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'None yet. Add Ramadan, the Eids or a date of your own.',
                key: ValueKey('hijri-empty'),
                style: TextStyle(color: AppColors.inkMuted),
              ),
            ),
          for (final r in _reminders) _reminderTile(r),
          const SizedBox(height: AppSpacing.sm),
          FilledButton.icon(
            key: const ValueKey('hijri-add-occasion'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: _reminders.length >= maxHijriReminders ? null : _addOccasions,
            icon: const Icon(AppIcons.add, size: 18),
            label: const Text('Add Ramadan, Eid and more'),
          ),
        ],
      ),
    ),
  );

  Widget _reminderTile(HijriReminder r) {
    final next = hijriOccurrences(r.month, r.day, _today, count: 1);
    final name = r.occasion != null ? tr(hijriOccasionOf(r.occasion!)?.name ?? r.title) : r.title;
    final when = r.daysBefore == 0 ? tr('on the day') : (r.daysBefore == 1 ? tr('1 day before') : trf('{n} days before', {'n': r.daysBefore}));
    return ListTile(
      key: ValueKey('hijri-reminder-${r.id}'),
      contentPadding: EdgeInsets.zero,
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        next.isEmpty
            ? '${r.day} ${tr(hijriMonthNames[r.month - 1])} \u00B7 $when'
            : '${r.day} ${tr(hijriMonthNames[r.month - 1])} \u00B7 ${tr('next')} ${formatDate(next.first)} \u00B7 $when',
      ),
      trailing: IconButton(
        key: ValueKey('hijri-delete-${r.id}'),
        tooltip: tr('Remove'),
        icon: const Icon(AppIcons.delete, size: 20, color: AppColors.danger),
        onPressed: () => _remove(r),
      ),
    );
  }
}

class _OccasionSheet extends StatefulWidget {
  const _OccasionSheet({required this.taken});
  final Set<String> taken;

  @override
  State<_OccasionSheet> createState() => _OccasionSheetState();
}

class _OccasionSheetState extends State<_OccasionSheet> {
  final _keys = <String>{};
  int _before = 1;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, MediaQuery.viewInsetsOf(context).bottom + AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Choose the dates', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          for (final o in hijriOccasions)
            CheckboxListTile(
              key: ValueKey('hijri-occ-${o.key}'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              enabled: !widget.taken.contains(o.key),
              value: _keys.contains(o.key) || widget.taken.contains(o.key),
              title: Text(o.name),
              subtitle: Text('${o.day} ${tr(hijriMonthNames[o.month - 1])}'),
              onChanged: (v) => setState(() => v == true ? _keys.add(o.key) : _keys.remove(o.key)),
            ),
          const SizedBox(height: AppSpacing.sm),
          const Text('Remind me'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final n in hijriDaysBefore)
                ChoiceChip(
                  key: ValueKey('hijri-before-$n'),
                  label: Text(n == 0 ? tr('On the day') : (n == 1 ? tr('1 day before') : trf('{n} days before', {'n': n}))),
                  selected: _before == n,
                  onSelected: (_) => setState(() => _before = n),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            key: const ValueKey('hijri-sheet-add'),
            style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 46)),
            onPressed: _keys.isEmpty ? null : () => Navigator.pop(context, (keys: _keys, before: _before)),
            child: const Text('Add'),
          ),
        ],
      ),
    ),
  );
}

class _TitleDialog extends StatefulWidget {
  const _TitleDialog({required this.initial});
  final String initial;

  @override
  State<_TitleDialog> createState() => _TitleDialogState();
}

class _TitleDialogState extends State<_TitleDialog> {
  late final _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Name this date'),
    content: TextField(
      key: const ValueKey('hijri-title-field'),
      controller: _c,
      autofocus: true,
      maxLength: 40,
      decoration: InputDecoration(labelText: tr('For example: Zakat due')),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(key: const ValueKey('hijri-title-save'), onPressed: () => Navigator.pop(context, _c.text), child: const Text('Save')),
    ],
  );
}

import 'package:material_ui/material_ui.dart';

import '../features/calendar/calendar_rules.dart';
import '../features/reminders/reminder_repeat_rules.dart';
import 'form_kit.dart';
import 'package:onespace/l10n/phrases.dart';

/// R66: the one Repeat control (Ahmed: "use the repeat control in the
/// reminders"). Reminders, events and to-do lists all show the same words and
/// chips; each form turns on only what makes sense for it.
class RepeatControl extends StatelessWidget {
  const RepeatControl({
    super.key,
    required this.value,
    required this.start,
    required this.onChanged,
    this.enabled = true,
    this.showTimes = false,
    this.onAddTime,
    this.footnote,
    this.forList = false,
  });

  final ReminderRepeat value;
  /// The first occurrence (its weekday is the default for "Weekly").
  final DateTime start;
  final ValueChanged<ReminderRepeat> onChanged;
  final bool enabled;
  /// Reminders only: extra alert times on the same day.
  final bool showTimes;
  final VoidCallback? onAddTime;
  final String? footnote;
  /// To-do lists: "Weekly" may be any day of the week (the list resets each
  /// week), and Monthly/Yearly have no "every N".
  final bool forList;

  @override
  Widget build(BuildContext context) {
    final repeat = value;
    final interval = repeat.interval;
    final unit = repeat.preset == 'daily' ? 'day' : repeat.preset == 'weekly' ? 'week'
        : repeat.preset == 'monthly' ? 'month' : 'year';
    final showInterval = repeat.repeats && repeat.preset != 'weekdays' &&
        !(forList && (repeat.preset == 'monthly' || repeat.preset == 'yearly'));
    void set(ReminderRepeat r) { if (enabled) onChanged(r); }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ChoiceRow<String>(label: tt('Repeat'),
        options: {for (final p in ReminderRepeat.presets) p: switch (p) {
          'none' => 'Once', 'daily' => 'Daily', 'weekdays' => 'Weekdays',
          'weekly' => 'Weekly', 'monthly' => 'Monthly', _ => 'Yearly'}},
        selected: repeat.preset,
        onSelected: (v) => set(repeat.copyWith(preset: v ?? 'none', interval: 1,
          weekdays: v == 'weekly' ? (forList ? <int>{} : {start.weekday}) : null))),
      if (showInterval) Row(children: [
        Text(tt('Every')),
        IconButton(onPressed: enabled && interval > 1 ? () => set(repeat.copyWith(interval: interval - 1)) : null,
          icon: const Icon(Icons.remove_circle_outline), tooltip: tt('Less often')),
        Text('$interval', style: const TextStyle(fontWeight: FontWeight.bold)),
        IconButton(onPressed: enabled && interval < 99 ? () => set(repeat.copyWith(interval: interval + 1)) : null,
          icon: const Icon(Icons.add_circle_outline), tooltip: tt('More apart')),
        Text(tt(interval == 1 ? unit : '${unit}s')),
      ]),
      if (repeat.preset == 'weekly') Wrap(spacing: 6, runSpacing: 4, children: [
        if (forList) ChoiceChip(label: Text(tt('Any day')), selected: repeat.weekdays.isEmpty,
          onSelected: (_) => set(repeat.copyWith(weekdays: <int>{}))),
        for (var d = 1; d <= 7; d++) FilterChip(
          label: Text(OneSpacePhrases.weekdaysShort[d - 1]),
          selected: repeat.weekdays.contains(d),
          onSelected: (on) {
            final next = {...repeat.weekdays};
            if (on) { next.add(d); } else if (forList || next.length > 1) { next.remove(d); }
            set(repeat.copyWith(weekdays: next));
          }),
      ]),
      if (repeat.repeats) ...[
        if (showTimes) ...[
          const SizedBox(height: 8),
          Text(tt('Times of day')),
          Wrap(spacing: 6, runSpacing: 4, children: [
            Chip(label: Text(tt(ReminderRepeat.clock(ReminderRepeat.hhmm(start.hour, start.minute))))),
            for (final t in repeat.extraTimes) InputChip(
              label: Text(tt(ReminderRepeat.clock(t))),
              onDeleted: () => set(repeat.copyWith(extraTimes: repeat.extraTimes.where((x) => x != t).toList()))),
            ActionChip(avatar: const Icon(Icons.add, size: 18),
              label: Text(tt('Add another time')), onPressed: enabled ? onAddTime : null),
          ]),
        ],
        const SizedBox(height: 6),
        Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
          Text(tt('Ends')),
          ChoiceChip(label: Text(tt('Never')), selected: repeat.until == null,
            onSelected: (_) => set(repeat.copyWith(clearUntil: true))),
          ChoiceChip(
            label: Text(repeat.until == null ? tt('On a date')
              : '${tt('On')} ${MaterialLocalizations.of(context).formatMediumDate(repeat.until!)}'),
            selected: repeat.until != null,
            onSelected: (_) async {
              final picked = await showDatePicker(context: context,
                initialDate: repeat.until ?? start.add(const Duration(days: 30)),
                firstDate: CalendarRules.day(start), lastDate: DateTime(2100));
              if (picked != null) set(repeat.copyWith(until: picked));
            }),
        ]),
        if (footnote != null) Padding(padding: const EdgeInsets.only(top: 4),
          child: Text(footnote!, style: Theme.of(context).textTheme.bodySmall)),
      ],
    ]);
  }
}

/// R66: to-do lists keep their stored format (tasks.recurrence + rule.mode);
/// this maps the shared Repeat control to and from it.
class ListRepeat {
  const ListRepeat._();

  /// The list's (recurrence, rule fields) for a Repeat value.
  static (String, Map<String, dynamic>) toList(ReminderRepeat r) {
    final until = r.until == null ? null : CalendarRules.sqlDate(r.until!);
    Map<String, dynamic> m(String mode, [Map<String, dynamic> extra = const {}]) =>
      {'mode': mode, 'interval': 1, 'weekdays': <int>[], ...extra, 'until': until};
    final days = r.weekdays.toList()..sort();
    switch (r.preset) {
      case 'daily':
        return r.interval <= 1 ? ('daily', m('daily'))
          : ('daily', m('every_n_days', {'interval': r.interval}));
      case 'weekdays':
        return ('daily', m('weekdays'));
      case 'weekly':
        if (days.isEmpty) {
          return r.interval <= 1 ? ('weekly', m('weekly'))
            : ('weekly', m('every_n_weeks', {'interval': r.interval}));
        }
        return r.interval <= 1 ? ('daily', m('selected_weekdays', {'weekdays': days}))
          : ('weekly', m('every_n_weeks', {'interval': r.interval, 'weekdays': days}));
      case 'monthly':
        return ('monthly', m('monthly'));
      case 'yearly':
        return ('yearly', m('yearly'));
      default:
        return ('none', {'mode': 'none', 'until': null});
    }
  }

  /// The Repeat value for a stored list, or null for an older custom schedule
  /// (weekends, working days, days of the month) that the control can't show.
  static ReminderRepeat? fromList(String recurrence, Map<String, dynamic> rule) {
    final mode = (rule['mode'] ?? recurrence).toString();
    final n = ((rule['interval'] as num?)?.toInt() ?? 1).clamp(1, 99);
    final days = {for (final d in (rule['weekdays'] as List? ?? const [])) if (d is num) d.toInt()};
    final until = DateTime.tryParse(rule['until']?.toString() ?? '');
    ReminderRepeat r(String preset, {int interval = 1, Set<int> weekdays = const {}}) =>
      ReminderRepeat(preset: preset, interval: interval, weekdays: weekdays, until: until);
    return switch (mode) {
      'none' => const ReminderRepeat(),
      'daily' => r('daily'),
      'every_n_days' => r('daily', interval: n),
      'weekdays' => r('weekdays'),
      'weekly' => r('weekly'),
      'selected_weekdays' => r('weekly', weekdays: days),
      'every_n_weeks' => r('weekly', interval: n, weekdays: days),
      'monthly' => r('monthly'),
      'yearly' => r('yearly'),
      _ => null,
    };
  }
}

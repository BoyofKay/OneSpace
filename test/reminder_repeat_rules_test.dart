import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/reminders/reminder_repeat_rules.dart';

void main() {
  final start = DateTime(2026, 11, 20, 8, 0);

  test('one-time reminders store no rule', () {
    expect(const ReminderRepeat().toRule(start: start, timeZone: 'Asia/Riyadh'), isNull);
  });

  test('daily with a second time keeps both times sorted', () {
    final rule = const ReminderRepeat(preset: 'daily', extraTimes: ['20:00'])
        .toRule(start: start, timeZone: 'Asia/Riyadh')!;
    expect(rule['freq'], 'daily');
    expect(rule['times'], ['08:00', '20:00']);
    expect(rule['tz'], 'Asia/Riyadh');
    expect(ReminderRepeat.describe(rule), 'Every day at 8:00 AM and 8:00 PM');
  });

  test('weekdays preset is stored as weekly Mon–Fri and read back', () {
    final rule = const ReminderRepeat(preset: 'weekdays')
        .toRule(start: start, timeZone: 'America/New_York')!;
    expect(rule['freq'], 'weekly');
    expect(rule['weekdays'], [1, 2, 3, 4, 5]);
    expect(ReminderRepeat.fromRule(rule, start: start).preset, 'weekdays');
    expect(ReminderRepeat.describe(rule), 'Every weekday at 8:00 AM');
  });

  test('every 2 weeks on chosen days with an end date', () {
    final rule = ReminderRepeat(preset: 'weekly', interval: 2, weekdays: const {7, 3},
        until: DateTime(2027, 1, 31)).toRule(start: start, timeZone: 'UTC')!;
    expect(rule['weekdays'], [3, 7]);
    expect(rule['until'], '2027-01-31');
    expect(ReminderRepeat.describe(rule),
        'Every 2 weeks on Wed, Sun at 8:00 AM · until 2027-01-31');
  });

  test('reading a rule separates the main time from extra times', () {
    final back = ReminderRepeat.fromRule(
        {'freq': 'daily', 'interval': 1, 'times': ['08:00', '14:00', '20:00'], 'tz': 'UTC'},
        start: start);
    expect(back.preset, 'daily');
    expect(back.extraTimes, ['14:00', '20:00']);
  });

  test('system history actions have plain names', () {
    expect(ReminderRepeat.actionLabel('missed'), 'Missed');
    expect(ReminderRepeat.actionLabel('source_closed'), 'Linked item closed');
    expect(ReminderRepeat.actionLabel('deferred'), 'Held until wake-up');
  });
}

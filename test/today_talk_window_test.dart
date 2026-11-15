import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/spaces/today_talk_window.dart';

void main() {
  // Backlog B-12: Ahmed works 9-17 in Riyadh (Sun-Thu), Kandice 8-16 in
  // Pennsylvania (Mon-Fri). Both sleep 23:00-07:00 / 22:00-06:00.
  const ahmed = StatedSchedule(timeZone: 'Asia/Riyadh',
      workStart: 9 * 60, workEnd: 17 * 60, sleepStart: 23 * 60, sleepEnd: 7 * 60,
      workDays: {7, 1, 2, 3, 4});
  const kandice = StatedSchedule(timeZone: 'America/New_York',
      workStart: 8 * 60, workEnd: 16 * 60, sleepStart: 22 * 60, sleepEnd: 6 * 60,
      workDays: {1, 2, 3, 4, 5});

  test('finds the shared free window across time zones', () {
    final now = DateTime.utc(2026, 11, 19, 20); // Thu 23:00 Riyadh, 15:00 NY
    final window = nextTalkWindow(ahmed, kandice, now)!;
    // Friday: Ahmed is off; Kandice is up from 06:00 and works from 08:00 NY.
    expect(window.start, DateTime.utc(2026, 11, 20, 11));
    expect(window.end, DateTime.utc(2026, 11, 20, 13));
    expect(talkWindowLabel(window, now, 'Asia/Riyadh'),
        'Next good time to talk: tomorrow 2:00 PM – 4:00 PM');
  });

  test('days further out are named', () {
    final now = DateTime.utc(2026, 11, 18, 20); // Wed 23:00 Riyadh
    final window = nextTalkWindow(ahmed, kandice, now)!;
    expect(talkWindowLabel(window, now, 'Asia/Riyadh'),
        'Next good time to talk: Fri, Nov 20 2:00 PM – 4:00 PM');
  });

  test('a window that is open now says so', () {
    final now = DateTime.utc(2026, 11, 20, 11, 20);
    final window = nextTalkWindow(ahmed, kandice, now)!;
    expect(window.isNow(now), isTrue);
    expect(talkWindowLabel(window, now, 'Asia/Riyadh'),
        'Good time to talk: now until 4:00 PM');
  });

  test('no schedules, no guess', () {
    const empty = StatedSchedule(timeZone: 'Asia/Riyadh');
    expect(nextTalkWindow(empty, kandice, DateTime.utc(2026, 11, 19)), isNull);
  });

  test('reads database times and weekdays', () {
    final s = StatedSchedule.fromJson({
      'time_zone': 'Asia/Riyadh', 'work_start': '09:00:00', 'work_end': '17:30:00',
      'sleep_start': null, 'work_days': [7, 1, 2, 3, 4, 9],
    });
    expect(s.workStart, 540);
    expect(s.workEnd, 1050);
    expect(s.workDays, {7, 1, 2, 3, 4});
    expect(s.hasSleep, isFalse);
  });
}

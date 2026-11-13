import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/remember/remember_rules.dart';

void main() {
  test('Remember includes annual occasions and skips expired one-time events',
      () {
    final upcoming = RememberRules.upcomingEvents([
      {
        'title': 'Our anniversary',
        'event_date': '2019-11-20',
        'recurrence': 'yearly',
        'kind': 'occasion',
      },
      {
        'title': 'Last week',
        'event_date': '2026-11-01',
        'recurrence': 'none',
      },
      {
        'title': 'Tomorrow',
        'event_date': '2026-11-14',
        'recurrence': 'none',
      },
      {
        'title': 'Beyond the horizon',
        'event_date': '2027-04-01',
        'recurrence': 'none',
      },
    ], DateTime(2026, 11, 13));
    expect(upcoming.map((item) => item.title).toList(), [
      'Tomorrow',
      'Our anniversary',
    ]);
    expect(upcoming.last.date, DateTime(2026, 11, 20));
  });

  test('Due dates include overdue items and sort by due date', () {
    final dues = RememberRules.upcomingDues([
      {'id': 'b', 'title': 'Heater', 'type': 'activity', 'due_on': '2026-11-21'},
      {'id': 'a', 'title': 'Call the office', 'type': 'todo',
       'due_on': '2026-11-10'},
      {'id': 'invalid', 'title': 'No due date', 'due_on': null},
    ]);
    expect(dues.map((item) => item.title).toList(), [
      'Call the office',
      'Heater',
    ]);
    expect(dues.last.id, 'b');
    expect(RememberRules.daysFromToday(dues.first.date, DateTime(2026, 11, 13)), -3);
    expect(RememberRules.daysFromToday(dues.last.date, DateTime(2026, 11, 13)), 8);
  });

  test('reminders retain their parent Activity for direct navigation', () {
    final due=RememberRules.upcomingDues([
      {
        'id':'component-123',
        'activity_id':'activity-456',
        'title':'Email Gym B',
        'type':'reminder',
        'due_on':'2026-11-15',
      },
    ]).single;
    expect(due.kind,'reminder');
    expect(due.id,'component-123');
    expect(due.activityId,'activity-456');
    expect(RememberRules.daysFromToday(
      due.date, DateTime(2026,11,13)),2);
  });

  test('Malformed records do not disrupt Remember', () {
    expect(RememberRules.upcomingEvents([42, null, {}], DateTime(2026, 11, 13)),
        isEmpty);
    expect(RememberRules.upcomingDues([42, null, {}]), isEmpty);
  });
}

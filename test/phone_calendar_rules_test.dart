import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/core/phone_calendar_sync.dart';
import 'package:onespace/features/settings/special_dates.dart';

void main() {
  final today = DateTime(2026, 11, 16);
  test('one-off, yearly and weekly events, trips, occasions and special dates', () {
    final items = PhoneCalendarRules.build(
      events: [
        {'id': 'a', 'title': 'Dinner', 'event_date': '2026-11-20'},
        {'id': 'b', 'title': 'Old', 'event_date': '2025-01-01'},
        {'id': 'c', 'title': 'Walk', 'event_date': '2026-11-16', 'repeat_rule': {'freq': 'weekly'}},
        {'id': 'd', 'title': 'Call', 'starts_at': '2026-11-18T15:00:00Z', 'ends_at': '2026-11-18T16:30:00Z'},
      ],
      trips: [{'id': 't', 'title': 'Cairo', 'start_on': '2026-12-01', 'end_on': '2026-12-05'}],
      occasions: [{'id': 'o', 'title': 'Gift', 'occasion_on': '2026-12-25', 'annual': false}],
      specials: [const SpecialDate(id: 's', kind: 'anniversary', month: 3, day: 2, year: 2020)],
      nameOf: (_) => '',
      today: today);
    expect(items.where((i) => i.title == 'Dinner').length, 1);
    expect(items.where((i) => i.title == 'Old'), isEmpty);
    expect(items.where((i) => i.title == 'Walk').length, greaterThan(50));
    final call = items.firstWhere((i) => i.title == 'Call');
    expect(call.allDay, isFalse);
    expect(call.end!.difference(call.start!).inMinutes, 90);
    final trip = items.firstWhere((i) => i.title.contains('Cairo'));
    expect(trip.days, 5);
    expect(trip.toChannel()['endDate'], '2026-12-06');
    expect(items.where((i) => i.title.contains('Gift')).length, 1);
    expect(items.where((i) => i.title.contains('anniversary')).length, 1);
  });
}

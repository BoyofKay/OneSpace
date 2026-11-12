import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/calendar/calendar_rules.dart';

void main() {
  test('An annual birthday recurs on the same calendar day', () {
    final birthday = DateTime(1990, 12, 14);
    final next = CalendarRules.nextOccurrence(
      original: birthday, recurrence: 'yearly', today: DateTime(2026, 12, 15),
    );
    expect(next, DateTime(2027, 12, 14));
    expect(CalendarRules.occursOn(
      original: birthday, recurrence: 'yearly', selected: DateTime(2027, 12, 14),
    ), isTrue);
  });
  test('Leap-day occasions skip non-leap years', () {
    final leap = DateTime(2024, 2, 29);
    expect(CalendarRules.nextOccurrence(
      original: leap, recurrence: 'yearly', today: DateTime(2026, 11, 12),
    ), DateTime(2028, 2, 29));
    expect(CalendarRules.occursOn(
      original: leap, recurrence: 'yearly', selected: DateTime(2027, 2, 28),
    ), isFalse);
  });
  test('Past nonrecurring events are not upcoming', () {
    expect(CalendarRules.nextOccurrence(
      original: DateTime(2020, 1, 1),
      recurrence: 'none', today: DateTime(2026, 11, 12),
    ), isNull);
  });
  test('Countdown uses calendar days without DST hour shifts', () {
    expect(CalendarRules.calendarDaysUntil(
      DateTime(2026, 11, 12, 23), DateTime(2026, 11, 13, 1),
    ), 1);
  });
  test('Month and leap-day validity is strict', () {
    expect(CalendarRules.isValid(2026, 2, 29), isFalse);
    expect(CalendarRules.isValid(2028, 2, 29), isTrue);
    expect(CalendarRules.sqlDate(DateTime(2026, 1, 3)), '2026-01-03');
  });
}

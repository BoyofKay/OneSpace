import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/calendar/event_time_rules.dart';

void main() {
  test('end follows start by one hour, capped at 23:59', () {
    expect(EventTimeRules.endFor(const TimeOfDay(hour: 9, minute: 30)), const TimeOfDay(hour: 10, minute: 30));
    expect(EventTimeRules.endFor(const TimeOfDay(hour: 23, minute: 15)), const TimeOfDay(hour: 23, minute: 59));
  });
  test('end must be strictly after start', () {
    const s = TimeOfDay(hour: 9, minute: 0);
    expect(EventTimeRules.validEnd(s, const TimeOfDay(hour: 9, minute: 0)), isFalse);
    expect(EventTimeRules.validEnd(s, const TimeOfDay(hour: 8, minute: 59)), isFalse);
    expect(EventTimeRules.validEnd(s, const TimeOfDay(hour: 9, minute: 1)), isTrue);
    expect(EventTimeRules.validStart(const TimeOfDay(hour: 23, minute: 59)), isFalse);
  });
}

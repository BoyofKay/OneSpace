import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/plans/task_date_rules.dart';

void main() {
  final now = DateTime(2026, 11, 12, 23, 50);
  test('A task may be dated today or in the future', () {
    expect(TaskDateRules.isAllowed(DateTime(2026, 11, 12), now), isTrue);
    expect(TaskDateRules.isAllowed(DateTime(2026, 11, 13), now), isTrue);
    expect(TaskDateRules.isAllowed(null, now), isTrue);
  });
  test('Yesterday is rejected regardless of current clock time', () {
    expect(TaskDateRules.isAllowed(DateTime(2026, 11, 11, 23, 59), now),
        isFalse);
    expect(TaskDateRules.initialForPicker(DateTime(2026, 11, 11), now),
        DateTime(2026, 11, 12));
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/counters/smart_duration.dart';

void main() {
  final today = DateTime(2026, 11, 16);
  String label(DateTime d) => SmartSpan.between(today, d).label;

  test('picks the units that matter', () {
    expect(label(today), 'Today');
    expect(label(DateTime(2026, 11, 17)), 'Tomorrow');
    expect(label(DateTime(2026, 11, 15)), 'Yesterday');
    expect(label(DateTime(2026, 11, 26)), '10 days');
    expect(label(DateTime(2026, 12, 9)), '3 weeks 2 days');
    expect(label(DateTime(2027, 3, 20)), '4 months 4 days');
    expect(label(DateTime(2024, 8, 16)), '2 years 3 months');
    expect(label(DateTime(2023, 11, 10)), '3 years 6 days');
    expect(label(DateTime(2025, 11, 16)), '1 year');
  });

  test('direction and totals', () {
    final s = SmartSpan.between(today, DateTime(2020, 3, 2));
    expect(s.future, isFalse);
    expect(s.years, 6);
    expect(s.months, 8);
    expect(s.days, 14);
    expect(s.totalDays, 2450);
    expect(s.sentence, '6 years 8 months ago');
    expect(SmartSpan.between(today, DateTime(2026, 12, 9)).sentence, 'in 3 weeks 2 days');
  });

  test('month ends', () {
    final s = SmartSpan.between(DateTime(2026, 3, 1), DateTime(2026, 1, 31));
    expect((s.months, s.days), (1, 1));
  });

  test('Arabic units', () {
    expect(SmartUnits.format(1, 'year', arabic: true), 'سنة');
    expect(SmartUnits.format(2, 'month', arabic: true), 'شهران');
    expect(SmartUnits.format(5, 'day', arabic: true), '5 أيام');
    expect(SmartUnits.format(15, 'day', arabic: true), '15 يومًا');
    expect(SmartUnits.format(1000, 'day'), '1,000 days');
  });

  test('next milestone', () {
    final m = CounterMilestone.next(DateTime(2024, 2, 21), today)!;
    expect(m.label, '1,000 days');
    expect(m.on, DateTime(2026, 11, 17));
    expect(m.inDays, 1);
    final y = CounterMilestone.next(DateTime(2020, 11, 20), today)!;
    expect(y.label, '6 years');
    expect(y.inDays, 4);
    expect(CounterMilestone.next(DateTime(2027, 1, 1), today), isNull);
    expect(CounterMilestone.nextYearly(DateTime(2020, 2, 29), today), DateTime(2027, 2, 28));
  });
}

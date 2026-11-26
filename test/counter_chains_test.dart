import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/counters/counter_chains.dart';
import 'package:onespace/features/counters/counter_timelines.dart';

void main() {
  test('Today shows only between the first and the last point', () {
    expect(CounterChains.showToday([DateTime(2018, 3, 1), DateTime(2030, 1, 1)], DateTime(2026, 11, 26)), isTrue);
    expect(CounterChains.showToday([DateTime(2018), DateTime(2020)], DateTime(2026, 11, 26)), isFalse);
    expect(CounterChains.showToday([DateTime(2027), DateTime(2030)], DateTime(2026, 11, 26)), isFalse);
    expect(CounterChains.showToday([DateTime(2026, 11, 26), DateTime(2030)], DateTime(2026, 11, 26)), isFalse);
  });

  test('Named timelines: a counter fits only a timeline of its own kind (D100)', () {
    final shared = NamedTimeline.fromRow({'id': 't1', 'title': 'Our story', 'space_id': 's1',
      'counter_timeline_members': [{'counter_id': 'a'}, {'counter_id': 'b'}]});
    final mine = NamedTimeline.fromRow({'id': 't2', 'title': 'Travels', 'private_space_id': 'u1'});
    expect(shared.counterIds, ['a', 'b']);
    expect(shared.shared, isTrue);
    expect(shared.fits({'space_id': 's1'}), isTrue);
    expect(shared.fits({'private_space_id': 'u1'}), isFalse);
    expect(mine.fits({'private_space_id': 'u1'}), isTrue);
  });

  test('Timeline names are required and short', () {
    expect(NamedTimeline.validateTitle('  '), isNotNull);
    expect(NamedTimeline.validateTitle('Our story'), isNull);
    expect(NamedTimeline.validateTitle('x' * 81), isNotNull);
  });
}

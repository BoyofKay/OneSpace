import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/counters/counter_chains.dart';

void main() {
  final a = CounterLink(id: 'a', date: DateTime(2018, 3, 1));
  final b = CounterLink(id: 'b', date: DateTime(2019, 6, 1), linkedTo: 'a');
  final c = CounterLink(id: 'c', date: DateTime(2020, 9, 1), linkedTo: 'b');
  final d = CounterLink(id: 'd', date: DateTime(2022, 1, 1));
  final all = [c, a, d, b];

  List<CounterLink> apply(List<CounterLink> list, Map<String, String?> changes) => [
        for (final x in list)
          changes.containsKey(x.id) ? CounterLink(id: x.id, date: x.date, linkedTo: changes[x.id]) : x,
      ];

  test('More than two counters join one timeline, oldest first', () {
    expect(CounterChains.group('c', all).map((x) => x.id), ['a', 'b', 'c']);
    expect(CounterChains.group('d', all).map((x) => x.id), ['d']);
  });

  test('Connecting keeps every existing link and joins the timelines', () {
    final changes = CounterChains.connect('d', 'c', all);
    final after = apply(all, changes);
    expect(CounterChains.group('a', after).map((x) => x.id), ['a', 'b', 'c', 'd']);
    expect(CounterChains.connect('a', 'c', all), isEmpty, reason: 'already on the same timeline');
  });

  test('Removing a middle counter keeps the others connected', () {
    final after = apply(all, CounterChains.remove('b', all));
    expect(CounterChains.group('b', after).map((x) => x.id), ['b']);
    expect(CounterChains.group('a', after).map((x) => x.id), ['a', 'c']);
  });

  test('Removing the first counter keeps the others connected', () {
    final after = apply(all, CounterChains.remove('a', all));
    expect(CounterChains.group('a', after).map((x) => x.id), ['a']);
    expect(CounterChains.group('c', after).map((x) => x.id), ['b', 'c']);
  });

  test('Today shows only between the first and the last point', () {
    final dates = [DateTime(2018, 3, 1), DateTime(2030, 1, 1)];
    expect(CounterChains.showToday(dates, DateTime(2026, 11, 26)), isTrue);
    expect(CounterChains.showToday([DateTime(2018), DateTime(2020)], DateTime(2026, 11, 26)), isFalse);
    expect(CounterChains.showToday([DateTime(2027), DateTime(2030)], DateTime(2026, 11, 26)), isFalse);
    expect(CounterChains.showToday([DateTime(2026, 11, 26), DateTime(2030)], DateTime(2026, 11, 26)), isFalse);
  });
}

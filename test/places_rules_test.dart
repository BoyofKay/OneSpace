import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/places/places_screen.dart';
import 'package:onespace/features/counters/counters_screen.dart';

void main() {
  test('trip from bucket-list places', () {
    final one = PlaceRules.tripPrefill([{'name': 'Eiffel Tower', 'city': 'Paris', 'country': 'France'},
      {'name': 'Louvre', 'city': 'Paris', 'country': 'France'}]);
    expect(one['title'], 'Trip to Paris');
    expect(one['notes'], contains('• Louvre — Paris, France'));
    final many = PlaceRules.tripPrefill([{'name': 'Santorini'}, {'name': 'Rome', 'city': 'Rome'}, {'name': 'Petra'}]);
    expect(many['title'], 'Trip to Santorini & Rome +1');
  });

  test('counters: coming up first (soonest), then looking back (latest)', () {
    final today = DateTime(2026, 11, 16);
    final list = CountersRules.sortForList([
      CounterPoint(id: 'a', title: 'First date', date: DateTime(2020, 3, 2)),
      CounterPoint(id: 'b', title: 'Wedding day', date: DateTime(2021, 5, 1), yearly: true),
      CounterPoint(id: 'c', title: 'Trip', date: DateTime(2026, 12, 20)),
      CounterPoint(id: 'd', title: 'Moved in', date: DateTime(2023, 1, 9)),
    ], today);
    expect(list.map((p) => p.id), ['c', 'b', 'd', 'a']);
    expect(list[1].target(today), DateTime(2027, 5, 1));
  });
}

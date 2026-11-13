import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/world/trip_rules.dart';

void main(){
 test('Travel countdown respects calendar dates, not instants',(){
  expect(TripRules.daysUntil(DateTime(2026,12,14),DateTime(2026,12,13,23,59)),1);
  expect(TripRules.countdownLabel(DateTime(2026,12,14),DateTime(2026,12,14)), 'Departure is today');
  expect(TripRules.countdownLabel(DateTime(2026,12,14),DateTime(2026,12,15)), 'Departure was yesterday');
 });
 test('Trip budgets do not add mixed currencies together',(){
  final items=<Map<String,dynamic>>[
   {'currency':'USD','estimated_cost':100,'archived_at':null},
   {'currency':'SAR','estimated_cost':'50.5','archived_at':null},
   {'currency':'USD','estimated_cost':25.25,'archived_at':null},
  ];
  final sums=TripRules.sumByCurrency(items);
  expect(sums['USD'],125.25);
  expect(sums['SAR'],50.5);
  expect(TripRules.formatTotals(sums),'SAR 50.50 · USD 125.25');
 });
 test('Archived or malformed amounts are excluded',(){
  final items=<Map<String,dynamic>>[
   {'currency':'USD','estimated_cost':300,'archived_at':'2026-11-13'},
   {'currency':'USD','estimated_cost':'not a number','archived_at':null},
   {'currency':'USD','estimated_cost':-10,'archived_at':null},
   {'currency':'USD','estimated_cost':null,'archived_at':null},
  ];
  expect(TripRules.sumByCurrency(items),isEmpty);
 });
}

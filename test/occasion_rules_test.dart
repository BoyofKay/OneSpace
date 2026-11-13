import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/occasions/occasion_rules.dart';
void main(){
 test('Annual occasion rolls to next calendar year',(){
  final next=OccasionRules.nextDate(
   original:DateTime(2020,12,25),annual:true,today:DateTime(2026,12,26));
  expect(next,DateTime(2027,12,25));
 });
 test('Leap-day occasion stays annual and uses last valid February date',(){
  final next=OccasionRules.nextDate(
   original:DateTime(2024,2,29),annual:true,today:DateTime(2026,1,1));
  expect(next,DateTime(2026,2,28));
 });
 test('One-off occasion cannot be presented as upcoming after the date',(){
  expect(OccasionRules.nextDate(original:DateTime(2026,10,1),
    annual:false,today:DateTime(2026,11,13)),isNull);
 });
 test('Preparation lead time spans previous month or year',(){
  expect(OccasionRules.prepStart(DateTime(2027,1,2),40),DateTime(2026,11,23));
 });
 test('Estimated cost respects currency and archived steps',(){
  final out=OccasionRules.estimatedByCurrency([
   {'currency':'USD','estimated_cost':45,'archived_at':null},
   {'currency':'SAR','estimated_cost':250,'archived_at':null},
   {'currency':'USD','estimated_cost':35,'archived_at':null},
   {'currency':'USD','estimated_cost':1000,'archived_at':'2026-01-01'},
  ]);
  expect(out['USD'],80);
  expect(out['SAR'],250);
 });
}

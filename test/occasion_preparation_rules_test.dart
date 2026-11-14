import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/occasions/occasion_preparation_rules.dart';

void main(){
 test('four phases use occasion lead days and a single next annual occurrence',(){
  final steps=OccasionPreparationRules.steps(
   plan:{'title':'Birthday','occasion_on':'2026-12-25','annual':true,
    'prep_lead_days':30,'saving_lead_days':60},
   today:DateTime(2026,11,14));
  expect(steps.map((x)=>x.phase),['save','research','order','prepare']);
  expect(steps[0].dateLabel,'2026-10-26');
  expect(steps[1].dateLabel,'2026-11-25');
  expect(steps[2].dateLabel,'2026-12-11');
  expect(steps[3].dateLabel,'2026-12-22');
  expect(steps.every((x)=>x.occasionDate==DateTime(2026,12,25)),true);
 });
 test('annual and leap day rollover remain consistent',(){
  final steps=OccasionPreparationRules.steps(
   plan:{'title':'Special','occasion_on':'2024-02-29','annual':true,
    'prep_lead_days':0,'saving_lead_days':0},
   today:DateTime(2027,1,4));
  expect(steps.first.occasionDate,DateTime(2027,2,28));
  expect(steps.first.dateLabel,'2027-02-28');
 });
 test('single completed one-off date creates no future suggestions',(){
  expect(OccasionPreparationRules.steps(
   plan:{'title':'Past','occasion_on':'2025-01-01','annual':false},
   today:DateTime(2026,11,14)),isEmpty);
 });
 test('past suggestions move to future 9 AM without backdating',(){
  final now=DateTime(2026,11,14,11);
  expect(OccasionPreparationRules.nextFutureTime(
   DateTime(2026,10,14),now),DateTime(2026,11,15,9));
  expect(OccasionPreparationRules.nextFutureTime(
   DateTime(2026,11,15),now),DateTime(2026,11,15,9));
 });
 test('duplicate check is actor and occasion occurrence scoped',(){
  final rows=[{'id':'r1','planning_phase':'save',
   'occasion_instance_on':'2026-12-25','created_by':'first',
   'archived_at':null}];
  expect(OccasionPreparationRules.activeForMe(rows,'save','2026-12-25','first'),'r1');
  expect(OccasionPreparationRules.activeForMe(rows,'save','2027-12-25','first'),isNull);
  expect(OccasionPreparationRules.activeForMe(rows,'save','2026-12-25','second'),isNull);
  expect(OccasionPreparationRules.activeForMe(rows,'order','2026-12-25','first'),isNull);
 });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/occasions/occasion_budget_rules.dart';
import 'package:onespace/features/occasions/occasion_planning_insights.dart';
void main(){
 test('Over budget is prioritized over pleasant ideation',(){
  final plan={'occasion_on':'2026-12-01','annual':false,
   'budget':50,'currency':'USD'};
  final items=<Map<String,dynamic>>[
   {'status':'planned','quantity':1,'unit_price':80,'currency':'USD'}
  ];
  final b=OccasionBudgetRules.summarize(plan,items);
  final insights=OccasionPlanningInsights.suggest(
   plan:plan,budget:b,items:items,today:DateTime(2026,11,25));
  expect(insights.first.code,'over_budget');
 });
 test('With no purchases near celebration, show actionable suggestion',(){
  final plan={'occasion_on':'2026-11-20','annual':true,'currency':'USD'};
  final b=OccasionBudgetRules.summarize(plan,[]);
  final found=OccasionPlanningInsights.suggest(
   plan:plan,budget:b,items:[],today:DateTime(2026,11,13));
  expect(found.any((x)=>x.code=='approaching'),true);
  expect(found.any((x)=>x.code=='empty'&&x.action=='purchase'),true);
 });
 test('Wishlist price is not counted as actual spending',(){
  final plan={'occasion_on':'2026-12-20','annual':true,
   'budget':100,'currency':'USD'};
  final items=<Map<String,dynamic>>[
   {'status':'wish','unit_price':80,'quantity':1,'currency':'USD'}
  ];
  final b=OccasionBudgetRules.summarize(plan,items);
  expect(b.available,100);
  final found=OccasionPlanningInsights.suggest(
   plan:plan,budget:b,items:items,today:DateTime(2026,11,13));
  // R68: the "review wishes" nudge was removed (Ahmed's review).
  expect(found.any((x)=>x.code=='promote_wish'),false);
 });
}

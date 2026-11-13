import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/occasions/occasion_budget_rules.dart';
void main(){
 test('Wishlist does not spend budget; planned reserves; purchased spends',(){
  final b=OccasionBudgetRules.summarize({'budget':500,'currency':'USD'},[
   {'status':'wish','quantity':1,'unit_price':200,'currency':'USD'},
   {'status':'shortlisted','quantity':1,'unit_price':50,'currency':'USD'},
   {'status':'planned','quantity':2,'unit_price':60,'currency':'USD'},
   {'status':'purchased','quantity':1,'unit_price':80,
    'actual_unit_price':75,'currency':'USD'},
  ]);
  expect(b.wishlist,250);
  expect(b.planned,120);
  expect(b.spent,75);
  expect(b.available,305);
  expect(b.committed,195);
 });
 test('Mixed currency is not added without exchange rates',(){
  final b=OccasionBudgetRules.summarize({'budget':100,'currency':'USD'},[
   {'status':'planned','quantity':1,'unit_price':50,'currency':'SAR'},
   {'status':'planned','quantity':1,'unit_price':30,'currency':'USD'},
  ]);
  expect(b.planned,30);
  expect(b.available,70);
  expect(b.foreignCurrency,1);
 });
 test('Overspending remains visible and is not artificially clamped',(){
  final b=OccasionBudgetRules.summarize({'budget':100,'currency':'USD'},[
   {'status':'purchased','quantity':2,'actual_unit_price':80,'currency':'USD'},
  ]);
  expect(b.available,-60);
  expect(b.overBudget,true);
  expect(b.progress,1);
 });
 test('Invalid price is not deducted; transparent warning count',(){
  final b=OccasionBudgetRules.summarize({'budget':100,'currency':'USD'},[
   {'status':'planned','unit_price':'invalid','quantity':1,'currency':'USD'},
   {'status':'cancelled','unit_price':100,'currency':'USD'},
  ]);
  expect(b.unpriced,1);expect(b.available,100);
 });
 test('URLs are validated without fetching private metadata',(){
  expect(OccasionBudgetRules.isHttpUrl('https://example.org/item'),true);
  expect(OccasionBudgetRules.isHttpUrl('javascript:alert(1)'),false);
 });
}

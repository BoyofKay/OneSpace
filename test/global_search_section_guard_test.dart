import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/search/global_search_rules.dart';
void main(){
 test('selected section queries only matching source table groups',(){
  expect(GlobalSearchRules.shouldSearchSection('All','Note'),true);
  expect(GlobalSearchRules.shouldSearchSection('Note','Note'),true);
  expect(GlobalSearchRules.shouldSearchSection('Note','Goal'),false);
  expect(GlobalSearchRules.shouldSearchSection('Memory','Memory'),true);
 });
 test('search escapes percent, underscore and slash without raw OR syntax',(){
  expect(GlobalSearchRules.pattern(r'100%_'),r'%100\%\_%');
  expect(GlobalSearchRules.canSearch('a'),false);
  expect(GlobalSearchRules.canSearch('hi'),true);
 });
}

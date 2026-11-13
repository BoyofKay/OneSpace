import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/search/global_search_rules.dart';
void main(){
 test('Search needs two non-space characters',(){
  expect(GlobalSearchRules.canSearch('  '),false);
  expect(GlobalSearchRules.canSearch(' A '),false);
  expect(GlobalSearchRules.canSearch('Ab'),true);
 });
 test('Literal ILIKE wildcards are escaped',(){
  expect(GlobalSearchRules.pattern('50%_off'),r'%50\%\_off%');
  expect(GlobalSearchRules.pattern(r'A\B'),r'%A\\B%');
 });
 test('Long searches cap input before network',(){
  expect(GlobalSearchRules.normalize('a'*125).length,100);
 });
 test('Invalid destination never yields a navigation ID',(){
  expect(GlobalSearchRules.destinationId({'trip_id':null},'trip_id'),isNull);
  expect(GlobalSearchRules.destinationId({'trip_id':' '},'trip_id'),isNull);
  expect(GlobalSearchRules.destinationId({'trip_id':'trip'},'trip_id'),'trip');
 });
}

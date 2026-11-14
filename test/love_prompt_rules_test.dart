import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/connect/love_prompt_rules.dart';

void main(){
 test('future reminder never starts in the past',(){
  final before=DateTime(2026,11,14,8,20);
  final after=DateTime(2026,11,14,9,20);
  expect(LovePromptRules.nextTime(before,9),DateTime(2026,11,14,9));
  expect(LovePromptRules.nextTime(after,9),DateTime(2026,11,15,9));
 });
 test('local tomorrow rolls calendar boundaries',(){
  expect(LovePromptRules.nextTime(DateTime(2026,12,31,22),21),
    DateTime(2027,1,1,21));
 });
 test('every category has a non-empty gentle self prompt',(){
  for(final kind in ['any','hug','miss_you','thinking','smile','morning',
    'goodnight','proud','support','thanks','lucky','miss_together',
    'miss_home','miss_kids','miss_pets']){
   expect(LovePromptRules.label(kind),isNotEmpty);
   expect(LovePromptRules.message(kind),contains('Open A little love'));
  }
 });
 test('last sent summary uses only sender history',(){
  expect(LovePromptRules.lastSentSummary(null,DateTime.utc(2026,11,14)),isNull);
  expect(LovePromptRules.lastSentSummary(
    '2026-11-12T09:00:00Z',DateTime.utc(2026,11,14,9)),
    'Last sent 2 days ago');
 });
}

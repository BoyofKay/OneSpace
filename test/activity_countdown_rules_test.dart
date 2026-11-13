import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/coordinate/activity_countdown_rules.dart';

void main(){
 test('Dates remain local, even late in the evening',(){
   final now=DateTime(2026,11,13,23,30);
   expect(ActivityCountdownRules.summary('2026-11-14',now:now),'Tomorrow!');
   expect(ActivityCountdownRules.summary('2026-11-13',now:now),'Today is the day!');
   expect(ActivityCountdownRules.summary('2026-11-10',now:now),'3 days since');
 });
 test('Annual milestones advance to the next year',(){
   expect(ActivityCountdownRules.remaining('2020-11-10',
     repeatYearly:true,now:DateTime(2026,11,13)),362);
 });
 test('Feb 29 annual milestone occurs Feb 28 in a non-leap year',(){
   expect(ActivityCountdownRules.target('2024-02-29',
     repeatYearly:true,now:DateTime(2027,2,27)),DateTime(2027,2,28));
 });
 test('Invalid dates are not silently normalized',(){
   expect(ActivityCountdownRules.parseDate('2026-13-01'),isNull);
   expect(ActivityCountdownRules.parseDate('2026-02-30'),isNull);
   expect(ActivityCountdownRules.summary('',now:DateTime(2026,11,13)),
     'Choose a milestone date');
 });
}

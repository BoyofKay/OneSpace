import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/checkins/checkin_acknowledgement_rules.dart';

void main(){
 test('only the sender can acknowledge an answered request',(){
  final row={'id':'r','sender_id':'a','recipient_id':'b',
   'responded_at':'2026-11-14T09:00:00Z'};
  expect(CheckinAcknowledgementRules.canAcknowledge(row,'a'),true);
  expect(CheckinAcknowledgementRules.canAcknowledge(row,'b'),false);
  expect(CheckinAcknowledgementRules.canAcknowledge(row,null),false);
  row['responded_at']=null;
  expect(CheckinAcknowledgementRules.canAcknowledge(row,'a'),false);
 });
 test('acknowledgment maps to the exact request only',(){
  final rows=[
   {'request_id':'a','kind':'hug'},
   {'request_id':'b','kind':'heart'},
  ];
  expect(CheckinAcknowledgementRules.forRequest(rows,'a')?['kind'],'hug');
  expect(CheckinAcknowledgementRules.forRequest(rows,'x'),isNull);
  expect(CheckinAcknowledgementRules.label('heart'),'Sending love');
  expect(CheckinAcknowledgementRules.label('thank_you'),
   'Thank you for sharing');
  expect(CheckinAcknowledgementRules.label('hug'),'Sending a hug');
  expect(CheckinAcknowledgementRules.label('unknown'),isNull);
 });
}

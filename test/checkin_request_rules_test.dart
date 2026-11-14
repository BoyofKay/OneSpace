import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/checkins/checkin_request_rules.dart';

Map<String,dynamic> request(String id,{
 String sender='a',String recipient='b',
 String? expiresAt, String? respondedAt,
 String requestedAt='2026-11-14T08:00:00Z',
})=>{'id':id,'sender_id':sender,'recipient_id':recipient,
 'expires_at':expiresAt,'responded_at':respondedAt,
 'requested_at':requestedAt};

void main(){
 final now=DateTime.utc(2026,11,14,12);
 test('new pending request expires at exact UTC instant',(){
  final r=request('1',expiresAt:'2026-11-14T12:00:00+00:00');
  expect(CheckinRequestRules.status(r,now),CheckinRequestRules.expired);
  expect(CheckinRequestRules.canRespond(r,'b',now),false);
  expect(CheckinRequestRules.status(r,now.subtract(
    const Duration(microseconds:1))),CheckinRequestRules.pending);
 });
 test('answered takes precedence even when deadline has passed',(){
  final r=request('1',expiresAt:'2026-11-13T00:00:00Z',
   respondedAt:'2026-11-12T00:00:00Z');
  expect(CheckinRequestRules.status(r,now),CheckinRequestRules.answered);
 });
 test('older legacy request without expiry stays answerable',(){
  final r=request('1');
  expect(CheckinRequestRules.status(r,now),CheckinRequestRules.pending);
  expect(CheckinRequestRules.canRespond(r,'b',now),true);
  expect(CheckinRequestRules.canRespond(r,'a',now),false);
  expect(CheckinRequestRules.expiryHint(r,now),'No response deadline');
 });
 test('pending queues are separated by current recipient',(){
  final rows=[
   request('1',sender:'a',recipient:'b'),
   request('2',sender:'b',recipient:'a'),
   request('3',expiresAt:'2026-11-13T00:00:00Z'),
   request('4',respondedAt:'2026-11-14T10:00:00Z'),
  ];
  expect(CheckinRequestRules.count(rows,'to_answer','b',now),1);
  expect(CheckinRequestRules.count(rows,'waiting','b',now),1);
  expect(CheckinRequestRules.count(rows,'history','b',now),2);
  expect(CheckinRequestRules.filter(rows,'to_answer','b',now)
   .single['id'],'1');
 });
 test('expiry hints reflect remaining time without guessing',(){
  expect(CheckinRequestRules.expiryHint(
   request('1',expiresAt:'2026-11-16T12:01:00Z'),now),
   '3 days remaining');
  expect(CheckinRequestRules.expiryHint(
   request('1',expiresAt:'2026-11-15T00:00:00Z'),now),
   'Less than a day remaining');
 });
 test('timeline sorted by timestamp independently of input order',(){
  final rows=[
   request('old',requestedAt:'2026-11-11T12:00:00Z'),
   request('new',requestedAt:'2026-11-14T12:00:00Z'),
  ];
  final sorted=CheckinRequestRules.filter(rows,'all','b',now);
  expect(sorted.first['id'],'new');
  expect(rows.first['id'],'old');
 });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/world/phone_contact_bridge.dart';
import 'package:onespace/features/world/world_contact_entry.dart';

void main(){
 test('Android selected contact fields become a reviewable contact, not a silent sync',(){
  final selected=PhoneContactBridge.fromMap({
   'person':'Alex Example',
   'phone':'+1 (215) 555-0102',
   'email':'alex@example.com',
   'company':'Example Inc',
   'role':'Planner',
   'website':'https://example.com',
   'address':'Pennsylvania, USA',
  });
  expect(selected.validate(),isNull);
  expect(selected.dialableNumber,'+12155550102');
  expect(selected.toPayload()['company'],'Example Inc');
  expect(selected.toPayload()['role'],'Planner');
  expect(selected.toPayload()['website'],'https://example.com');
  expect(selected.toPayload()['phone'],contains('215'));
 });
 test('Imported metadata is searchable in saved OneSpace cards',(){
  final entry=WorldContactEntry.fromDirect({
   'id':'contact','label':'Alex','visibility':'private',
   'payload':{
    'contact_name':'Alex',
    'company':'Example Inc','role':'Planner',
    'website':'https://example.com',
   },
  });
  expect(entry.matches('EXAMPLE INC'),isTrue);
  expect(entry.matches('planner'),isTrue);
  expect(entry.matches('example.com'),isTrue);
  expect(entry.visibility,'private');
 });
 test('Missing optional phone fields do not invent contact data',(){
  final selected=PhoneContactBridge.fromMap({'person':'Alex'});
  expect(selected.phone,isEmpty);
  expect(selected.email,isEmpty);
  expect(selected.validate(),isNull);
 });
}

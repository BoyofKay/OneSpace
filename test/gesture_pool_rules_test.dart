import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/connect/gesture_pool_rules.dart';

void main(){
 test('Built-in and my personal gesture variants form one pool',(){
  final pool=GesturePoolRules.activeMessages(
   kind:'hug',builtIn:['one','two','three'],
   overrides:[{'kind':'hug','message_index':1,'message':'edited','disabled':false}],
   custom:[{'kind':'hug','message':'new'}, {'kind':'morning','message':'skip'}]);
  expect(pool,['one','edited','three','new']);
 });
 test('Disabled presets are not sent and duplicate variants are collapsed',(){
  final pool=GesturePoolRules.activeMessages(
   kind:'support',builtIn:['support one','support two'],
   overrides:[{'kind':'support','message_index':0,'message':'support one','disabled':true}],
   custom:[{'kind':'support','message':'support two'}]);
  expect(pool,['support two']);
 });
 test('13 built-in ritual choices, including ten server phrases, share editable indices',(){
  final builtIn=List.generate(13,(i)=>'choice $i');
  final active=GesturePoolRules.activeMessages(
   kind:'morning',builtIn:builtIn,
   overrides:[
    {'kind':'morning','message_index':12,'message':'customized server phrase','disabled':false},
    {'kind':'morning','message_index':3,'message':'choice 3','disabled':true},
   ],
   custom:[{'kind':'morning','message':'my additional morning thought'}]);
  expect(active.length,13);
  expect(active,contains('customized server phrase'));
  expect(active,contains('my additional morning thought'));
  expect(active,isNot(contains('choice 3')));
  expect(active,isNot(contains('choice 12')));
 });
 test('Empty pools are permitted; caller must not send',(){
  final pool=GesturePoolRules.activeMessages(
   kind:'thinking',builtIn:['x'],
   overrides:[{'kind':'thinking','message_index':0,'message':'x','disabled':true}],
   custom:[]);
  expect(pool,isEmpty);
 });
}

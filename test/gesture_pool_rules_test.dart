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
 test('Empty pools are permitted; caller must not send',(){
  final pool=GesturePoolRules.activeMessages(
   kind:'thinking',builtIn:['x'],
   overrides:[{'kind':'thinking','message_index':0,'message':'x','disabled':true}],
   custom:[]);
  expect(pool,isEmpty);
 });
}

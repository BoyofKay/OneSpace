import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onespace/features/plans/checklist_readout_sheet.dart';
import 'package:onespace/features/plans/checklist_speech_bridge.dart';

void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 final calls=<MethodCall>[];
 setUp((){
  calls.clear();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
   .setMockMethodCallHandler(ChecklistSpeechBridge.channel,(method)async{
    calls.add(method);
    return null;
   });
 });
 tearDown((){
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
   .setMockMethodCallHandler(ChecklistSpeechBridge.channel,null);
 });
 Widget subject()=>MaterialApp(home:Scaffold(body:ChecklistReadoutSheet(
   listTitle:'Morning routine',
   items:const [
    {'id':'a','title':'Wallet','archived_at':null},
    {'id':'b','title':'Keys','archived_at':null},
    {'id':'c','title':'Past','archived_at':'2026-01-01'},
   ],
   ownChecks:const {'a':{'completed':true},'b':{'completed':false}},
  )));

 testWidgets('defaults to unchecked items and asks native speech once',(tester)async{
  await tester.pumpWidget(subject());
  expect(find.text('Keys'),findsOneWidget);
  expect(find.text('Wallet'),findsNothing);
  await tester.tap(find.text('Read this checklist aloud'));
  await tester.pump();
  final utterance=calls.where((c)=>c.method=='speak').single;
  final words=(utterance.arguments as Map)['text'] as String;
  expect(words,contains('Keys'));
  expect(words,contains('Morning routine'));
  expect(words, isNot(contains('Wallet')));
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  expect(calls.any((c)=>c.method=='stop'),true);
 });
 testWidgets('all mode includes completed and allows next step',(tester)async{
  await tester.pumpWidget(subject());
  await tester.tap(find.text('All items'));
  await tester.pump();
  expect(find.text('Wallet'),findsOneWidget);
  expect(find.text('Step 1 of 2'),findsOneWidget);
  await tester.tap(find.byTooltip('Next step'));
  await tester.pump();
  expect(find.text('Step 2 of 2'),findsOneWidget);
  final spoken=calls.where((c)=>c.method=='speak').last;
  expect((spoken.arguments as Map)['text'],contains('Keys'));
 });
}

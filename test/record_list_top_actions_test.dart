import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onespace/core/record_list_top_actions.dart';

void main(){
 const group=FilterGroupSpec(id:'who',label:'Who can see',
  options:{'all':'All','private':'Only me'},selected:'all',defaultValue:'all');

 testWidgets('Status is a choice and nothing changes until Apply',(tester)async{
  var removed=false;
  Map<String,String>? applied;
  await tester.pumpWidget(MaterialApp(home:Scaffold(appBar:AppBar(
   actions:[RecordListTopActions(showHistory:false,
    onToggleHistory:()=>removed=!removed,groups:const [group],
    onApply:(v)=>applied=v)]))));
  await tester.tap(find.byTooltip('Filters'));
  await tester.pumpAndSettle();
  expect(find.text('Status'),findsOneWidget);
  expect(find.byType(CheckboxListTile),findsNothing);
  expect(find.byType(SwitchListTile),findsNothing);
  await tester.tap(find.text('Removed'));
  await tester.tap(find.text('Only me'));
  await tester.pump();
  expect(removed,isFalse);
  await tester.tap(find.text('Apply'));
  await tester.pumpAndSettle();
  expect(removed,isTrue);
  expect(applied,{'who':'private'});
 });

 testWidgets('Clear restores defaults and closes the panel',(tester)async{
  Map<String,String>? applied;
  await tester.pumpWidget(MaterialApp(home:Scaffold(appBar:AppBar(
   actions:[RecordListTopActions(showHistory:false,onToggleHistory:(){},
    groups:const [FilterGroupSpec(id:'who',label:'Who can see',
     options:{'all':'All','private':'Only me'},selected:'private',defaultValue:'all')],
    onApply:(v)=>applied=v)]))));
  await tester.tap(find.byTooltip('Filters (on)'));
  await tester.pumpAndSettle();
  expect(find.byType(BottomSheet),findsNothing);
  await tester.tap(find.text('Clear'));
  await tester.pumpAndSettle();
  expect(applied,{'who':'all'});
  expect(find.text('Who can see'),findsNothing);
 });

 testWidgets('clock appears only when the screen has a change log',(tester)async{
  await tester.pumpWidget(MaterialApp(home:Scaffold(appBar:AppBar(
   actions:[RecordListTopActions(showHistory:false,onToggleHistory:(){},
    historyKinds:const ['note'])]))));
  expect(find.byTooltip('Change log'),findsOneWidget);
  await tester.pumpWidget(MaterialApp(home:Scaffold(appBar:AppBar(
   actions:[RecordListTopActions(showHistory:false,onToggleHistory:(){})]))));
  expect(find.byTooltip('Change log'),findsNothing);
 });

 test('showing line lists Removed and active groups',(){
  expect(FilterGroupSpec.showing(const [group],removed:true),['Removed']);
  expect(FilterGroupSpec.showing(const [FilterGroupSpec(id:'w',label:'W',
   options:{'all':'All','private':'Only me'},selected:'private',defaultValue:'all')]),['Only me']);
 });
}

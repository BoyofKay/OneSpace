import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onespace/core/record_list_top_actions.dart';

void main(){
 testWidgets('Removed is a status filter applied from the panel',(tester)async{
  var removed=false;
  await tester.pumpWidget(MaterialApp(home:Scaffold(appBar:AppBar(
   actions:[RecordListTopActions(showHistory:false,
    onToggleHistory:()=>removed=!removed)]))));
  await tester.tap(find.byTooltip('Filters'));
  await tester.pumpAndSettle();
  expect(find.text('Status'.toUpperCase()),findsOneWidget);
  await tester.tap(find.text('Removed'));
  await tester.pump();
  expect(removed,isFalse,reason:'nothing changes until Apply');
  await tester.tap(find.text('Apply'));
  await tester.pumpAndSettle();
  expect(removed,isTrue);
 });
 testWidgets('screen filters open in the drop-down panel',(tester)async{
  var cleared=false;
  await tester.pumpWidget(MaterialApp(home:Scaffold(
   appBar:AppBar(actions:[RecordListTopActions(
    showHistory:false,onToggleHistory:(){},
    onClearFilters:()=>cleared=true,
    filters:(_)=>const Text('Status filter'))]))));
  await tester.tap(find.byTooltip('Filters'));
  await tester.pumpAndSettle();
  expect(find.text('Status filter'),findsOneWidget);
  expect(find.byType(BottomSheet),findsNothing);
  await tester.tap(find.text('Clear'));
  await tester.pumpAndSettle();
  expect(cleared,isTrue);
  expect(find.text('Status filter'),findsNothing);
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
}

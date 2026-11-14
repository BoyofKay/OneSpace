import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onespace/features/plans/task_checklist_panel.dart';

Widget expandedChecklist({
 required Stream<List<Map<String,dynamic>>> items,
 required Stream<List<Map<String,dynamic>>> checks,
 String title='My checklist',
}) => MaterialApp(home:Scaffold(
 body:_ChecklistExpansionHarness(items:items,checks:checks,title:title),
));

class _ChecklistExpansionHarness extends StatefulWidget{
 const _ChecklistExpansionHarness({
  required this.items,required this.checks,required this.title,
 });
 final Stream<List<Map<String,dynamic>>> items,checks;
 final String title;
 @override State<_ChecklistExpansionHarness> createState()=>
  _ChecklistExpansionHarnessState();
}
class _ChecklistExpansionHarnessState extends State<_ChecklistExpansionHarness>{
 bool expanded=false;
 @override Widget build(BuildContext context)=>ListView(children:[
  // Deliberately reproduce the old PageStorage ancestor. The nested
  // text input must not interpret ExpansionTile's bool as a double offset.
  ExpansionTile(key:const PageStorageKey<String>('todo-test'),
   title:Text(widget.title),
   onExpansionChanged:(value)=>setState(()=>expanded=value),
   children:[if(expanded)TaskChecklistPanel(
    taskId:'parent',recurrence:'none',rule:const {},
    canManage:true,canComplete:false,
    testViewerId:'first-user',
    testItemsStream:widget.items,testChecksStream:widget.checks,
   )]),
 ]);
}

Map<String,dynamic> item(String id,String title,{String? oldTarget}) =>
 <String,dynamic>{
  'id':id,'task_id':'parent','title':title,'archived_at':null,
  'legacy_target_date':oldTarget,
 };

void main(){
 testWidgets('new checklist expands and renders actual subtasks without an exception',
  (tester)async{
  await tester.pumpWidget(expandedChecklist(
   items:Stream.value([item('a','Shop for groceries'),item('b','Plan dinner')]),
   checks:Stream.value(const <Map<String,dynamic>>[]),
  ));
  await tester.tap(find.byType(ExpansionTile));
  await tester.pumpAndSettle();
  expect(find.text('Shop for groceries'),findsOneWidget);
  expect(find.text('Plan dinner'),findsOneWidget);
  expect(find.text('0 of 2 items'),findsOneWidget);
  expect(tester.takeException(),isNull);
 });

 testWidgets('legacy target date cannot break expansion',
  (tester)async{
  await tester.pumpWidget(expandedChecklist(
   items:Stream.value([
    item('a','Old migrated item',oldTarget:'2024-09-12'),
    item('b','Old item without a date'),
   ]),
   checks:Stream.value(const <Map<String,dynamic>>[]),
   title:'Old checklist',
  ));
  await tester.tap(find.byType(ExpansionTile));
  await tester.pumpAndSettle();
  expect(find.text('Old migrated item'),findsOneWidget);
  expect(find.text('Old item without a date'),findsOneWidget);
  expect(tester.takeException(),isNull);
 });

 testWidgets('only current occurrence and current person checkmarks count',
  (tester)async{
  await tester.pumpWidget(expandedChecklist(
   items:Stream.value([item('a','First'),item('b','Second')]),
   checks:Stream.value([
    <String,dynamic>{'id':'1','item_id':'a','completed':true,
     'user_id':'first-user','cycle_date':'2000-01-01'},
    <String,dynamic>{'id':'2','item_id':'b','completed':true,
     'user_id':'other-user','cycle_date':'2000-01-01'},
    <String,dynamic>{'id':'3','item_id':'b','completed':true,
     'user_id':'first-user','cycle_date':'2026-11-14'},
   ]),
  ));
  await tester.tap(find.byType(ExpansionTile));
  await tester.pumpAndSettle();
  expect(find.text('1 of 2 items'),findsOneWidget);
  expect(tester.takeException(),isNull);
 });

 testWidgets('bad realtime feed surfaces an error rather than a red screen',
  (tester)async{
  final controller=StreamController<List<Map<String,dynamic>>>();
  await tester.pumpWidget(expandedChecklist(
    items:Stream.value([item('a','Recoverable item')]),
    checks:controller.stream,
  ));
  await tester.tap(find.byType(ExpansionTile));
  controller.addError(StateError('test transport disconnected'));
  await tester.pumpAndSettle();
  expect(find.text('Checkmarks could not synchronize.'),findsOneWidget);
  expect(tester.takeException(),isNull);
  await controller.close();
 });
}

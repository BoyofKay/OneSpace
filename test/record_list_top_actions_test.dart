import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onespace/core/record_list_top_actions.dart';

void main(){
 testWidgets('history action works in top toolbar',(tester)async{
  var history=false;
  await tester.pumpWidget(MaterialApp(home:Scaffold(appBar:AppBar(
   actions:[RecordListTopActions(showHistory:false,
    onToggleHistory:()=>history=true)]))));
  await tester.tap(find.byTooltip('Show archived history'));
  expect(history,true);
 });
 testWidgets('filters open a real action sheet',(tester)async{
  await tester.pumpWidget(MaterialApp(home:Scaffold(
   appBar:AppBar(actions:[RecordListTopActions(
    showHistory:false,onToggleHistory:(){},
    filters:(_)=>const Text('Status filter'))]))));
  await tester.tap(find.byTooltip('Filters'));
  await tester.pumpAndSettle();
  expect(find.text('Status filter'),findsOneWidget);
 });
}

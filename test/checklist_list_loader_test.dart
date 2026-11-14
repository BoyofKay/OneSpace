import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/plans/checklist_list_loader.dart';
import 'package:onespace/features/plans/task_editor_sheet.dart';

Map<String,dynamic> list(String id, {Object? migrated, Object? rule}) =>
 <String,dynamic>{
  'id':id,'title':'List $id','priority':'normal','status':'open',
  'visibility':'shared','created_by':'owner','assigned_to':null,
  'recurrence':'none','recurrence_rule':rule??<String,dynamic>{},
  'migrated_to_list':migrated,
 };

void main(){
 test('migrated legacy task rows never appear as standalone checklists',(){
  final rows=[
   list('old-1',migrated:'list-1'),
   list('old-2',migrated:'list-1'),
   list('list-1'),
   list('new-1'),
  ];
  final result=ChecklistListLoader.fromRows(rows);
  expect(result.items.map((x)=>x.id),['list-1','new-1']);
  expect(result.skippedRows,0);
 });
 test('bad rows do not bring down other checklists',(){
  final rows=[
   <String,dynamic>{'id':null,'title':'Malformed'},
   list('valid'),
   list('corrupted-rule',rule:<dynamic,dynamic>{42:'invalid','mode':'daily'}),
  ];
  final result=ChecklistListLoader.fromRows(rows);
  expect(result.skippedRows,1);
  expect(result.items.length,2);
  expect(result.items.last.rule,{'mode':'daily'});
 });
 test('old nullable fields and unusual values cannot crash the parser',(){
  final row=list('old',rule:['invalid','format']);
  row['title']=null;
  row['assigned_to']=91;
  row['target_date']=null;
  row['status']='retired_old_status';
  final result=ChecklistListLoader.fromRows([row]);
  expect(result.skippedRows,0);
  final item=result.items.single;
  expect(item.title,'Untitled checklist');
  expect(item.assignedTo,'91');
  expect(item.status,TaskStatus.open);
  expect(item.recurrence,'none');
  expect(item.rule,isEmpty);
 });
 test('legacy migrated task is not thrown away from backend',(){
  final rows=[list('old',migrated:'parent')];
  final result=ChecklistListLoader.fromRows(rows);
  expect(result.items,isEmpty);
  expect(rows.length,1);
 });
}

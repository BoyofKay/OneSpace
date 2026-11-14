import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/plans/checklist_readout_rules.dart';

void main(){
 test('reads only active, valid checklist items in server order',(){
  final items=<Map<String,dynamic>>[
   {'id':'a','title':'Wallet','archived_at':null},
   {'id':'b','title':'Keys','archived_at':null},
   {'id':'c','title':'Old item','archived_at':'2026-11-14'},
   {'id':null,'title':'Missing ID','archived_at':null},
   {'id':'d','title':'','archived_at':null},
  ];
  expect(ChecklistReadoutRules.lines(items,{}),['Wallet','Keys']);
 });
 test('remaining uses current user checkmarks, no partner state',(){
  final rows=<Map<String,dynamic>>[
   {'id':'a','title':'Wallet'},{'id':'b','title':'Phone'}];
  expect(ChecklistReadoutRules.lines(rows,{
   'a':{'completed':true},
   'b':{'completed':false},
  },remainingOnly:true),['Phone']);
 });
 test('safe empty checklist and all-complete scripts',(){
  expect(ChecklistReadoutRules.script(
   listTitle:'Morning',lines:[],remainingOnly:true),
   contains('All done'));
  expect(ChecklistReadoutRules.script(
   listTitle:'Morning',lines:['Water'],remainingOnly:false),
   contains('Item 1. Water.'));
 });
 test('truncates long or control character input',(){
  final text=ChecklistReadoutRules.clean('   Take\\n  my   \\tbag   ');
  expect(text,'Take my bag');
  expect(ChecklistReadoutRules.clean('x'.padRight(400,'x')).length,240);
 });
 test('caps long lists without downloading anything new',(){
  final items=List.generate(260,(i)=><String,dynamic>{
   'id':'$i','title':'Item $i'});
  expect(ChecklistReadoutRules.lines(items,{}).length,200);
 });
}

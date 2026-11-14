import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/notes/note_reference_rules.dart';

void main(){
 test('known kinds map only to approved source tables',(){
  expect(NoteReferenceRules.table('task'),'tasks');
  expect(NoteReferenceRules.table('event'),'space_events');
  expect(NoteReferenceRules.table('occasion'),'occasion_plans');
  expect(NoteReferenceRules.table('experience'),'shared_experiences');
  expect(NoteReferenceRules.table('private_message'),isNull);
 });
 test('shared note cannot offer private surprise or checklist in picker',(){
  final rows=<Map<String,dynamic>>[
   {'id':'a','title':'Surprise','visibility':'private','archived_at':null},
   {'id':'b','title':'Shared birthday','visibility':'shared','archived_at':null},
   {'id':'c','title':'Archived','visibility':'shared','archived_at':'2026-11-14'},
  ];
  final shared=NoteReferenceRules.available(rows,noteVisibility:'shared',kind:'occasion');
  expect(shared.map((x)=>x['id']),['b']);
  final private=NoteReferenceRules.available(rows,noteVisibility:'private',kind:'occasion');
  expect(private.map((x)=>x['id']),['a','b']);
 });
 test('no ghost links without a visible source object',(){
  expect(NoteReferenceRules.canOpen(null),false);
  expect(NoteReferenceRules.canOpen({'title':'unavailable'}),false);
  expect(NoteReferenceRules.canOpen({'id':'valid','title':'Live'}),true);
 });
}

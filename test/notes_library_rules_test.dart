import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/notes/notes_library_rules.dart';

void main(){
 final notes=<Map<String,dynamic>>[
  {'id':'1','title':'Our groceries','body':'Milk','visibility':'shared',
   'pinned':false,'updated_at':'2026-11-12T00:00:00Z','archived_at':null},
  {'id':'2','title':'Secret surprise','body':'Gift plan','visibility':'private',
   'pinned':true,'updated_at':'2026-11-11T00:00:00Z','archived_at':null},
  {'id':'3','title':'Old notes','body':'Archived','visibility':'shared',
   'pinned':false,'updated_at':'2026-10-01T00:00:00Z',
   'archived_at':'2026-11-13T00:00:00Z'},
 ];
 test('search matches title or body without modifying any input',(){
  expect(NotesLibraryRules.visible(notes,query:'milk').single['id'],'1');
  expect(NotesLibraryRules.visible(notes,query:'SURPRISE').single['id'],'2');
  expect(notes.length,3);
 });
 test('private scope and archived visibility remain independent',(){
  expect(NotesLibraryRules.visible(notes,scope:'private').length,1);
  expect(NotesLibraryRules.visible(notes,scope:'shared').length,1);
  expect(NotesLibraryRules.visible(notes,showArchived:true).length,3);
 });
 test('pinned notes first; malformed timestamps never crash sorting',(){
  final result=NotesLibraryRules.visible(notes);
  expect(result.first['id'],'2');
  final corrupt=<Map<String,dynamic>>[{'id':'x','updated_at':null}];
  expect(NotesLibraryRules.visible(corrupt).length,1);
 });
}

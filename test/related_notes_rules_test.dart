import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/notes/related_notes_rules.dart';

void main(){
 test('backlinks include only authorized fetched IDs',(){
  final rows=<Map<String,dynamic>>[
   {'id':'private','title':'Secret'},
   {'id':'shared','title':'Plan'},
  ];
  expect(RelatedNotesRules.visible(rows,['shared']).map((x)=>x['id']),
   ['shared']);
 });
 test('source uses pinned order, then timestamp',(){
  final rows=<Map<String,dynamic>>[
   {'id':'a','title':'Old','pinned':false,'updated_at':'2026-10-01'},
   {'id':'b','title':'Important','pinned':true,'updated_at':'2026-09-01'},
  ];
  expect(RelatedNotesRules.visible(rows,['a','b']).first['id'],'b');
 });
 test('no reference or no valid title means no ghost backlinks',(){
  expect(RelatedNotesRules.visible([{'id':'a','title':''}],['a']),isEmpty);
  expect(RelatedNotesRules.visible([{'id':'a','title':'Hi'}],[]),isEmpty);
 });
}

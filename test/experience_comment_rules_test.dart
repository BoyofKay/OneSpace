import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/connect/experience_comment_rules.dart';

Map<String,dynamic> entry(String author,String text,{bool retracted=false})=>
 {'created_by':author,'body':text,'archived_at':retracted?'2026-11-14T00:00:00Z':null};

void main(){
 test('only the owner can edit or retract an active comment',(){
  final mine=entry('a','Together again');
  expect(ExperienceCommentRules.canEdit(mine,'a'),true);
  expect(ExperienceCommentRules.canRetract(mine,'b'),false);
  expect(ExperienceCommentRules.canEdit(mine,null),false);
 });
 test('retracted comments are owner-restorable but never editable',(){
  final old=entry('a','A private retracted thought',retracted:true);
  expect(ExperienceCommentRules.canEdit(old,'a'),false);
  expect(ExperienceCommentRules.canRestore(old,'a'),true);
  expect(ExperienceCommentRules.canRestore(old,'b'),false);
  expect(ExperienceCommentRules.visible([old],'b',showMyRetracted:true),isEmpty);
  expect(ExperienceCommentRules.visible([old],'a',showMyRetracted:true),hasLength(1));
 });
 test('retracted text is absent from normal conversation and search',(){
  final rows=[
   entry('a','Movie date on Friday'),
   entry('b','A book night'),
   entry('a','Movie retracted words',retracted:true),
   entry('b','Movie partner retracted',retracted:true),
  ];
  expect(ExperienceCommentRules.visible(rows,'a'),hasLength(2));
  expect(ExperienceCommentRules.visible(rows,'a',query:'movie date'),hasLength(1));
  expect(ExperienceCommentRules.visible(rows,'a',showMyRetracted:true,query:'movie'),
   hasLength(2));
  expect(ExperienceCommentRules.visible(rows,'b',showMyRetracted:true,query:'retracted'),
   hasLength(1));
 });
}

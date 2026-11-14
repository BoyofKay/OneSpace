import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/core/record_collection_search_rules.dart';

void main(){
 test('search terms can match different authorized metadata fields',(){
  final trip=<String,dynamic>{
   'title':'Our summer reunion','origin':'Riyadh',
   'destination':'Philadelphia','notes':'Visit family'};
  expect(RecordCollectionSearchRules.matches(trip,
   'riYADH family',fields:['title','origin','destination','notes']),true);
  expect(RecordCollectionSearchRules.matches(trip,
   'visiting',fields:['title','origin','destination','notes']),false);
 });
 test('queries do not include fields that screen did not authorize',(){
  final note=<String,dynamic>{
   'title':'Celebration','notes':'Secret gift',
   'hidden_payload':'Never searchable in this context'};
  expect(RecordCollectionSearchRules.matches(note,'Never',
   fields:['title','notes']),false);
  expect(RecordCollectionSearchRules.matches(note,'Secret gift',
   fields:['title','notes']),true);
 });
 test('history view displays only archived and active view only active',(){
  expect(RecordCollectionSearchRules.inHistory(
   {'archived_at':null},false),true);
  expect(RecordCollectionSearchRules.inHistory(
   {'archived_at':'2026-11-14'},false),false);
  expect(RecordCollectionSearchRules.inHistory(
   {'archived_at':'2026-11-14'},true),true);
  expect(RecordCollectionSearchRules.inHistory(
   {'archived_at':null},true),false);
 });
 test('empty search and nullable metadata cannot throw',(){
  expect(RecordCollectionSearchRules.matches(
   <String,dynamic>{'title':null},'  ',fields:['title']),true);
  expect(RecordCollectionSearchRules.matches(
   <String,dynamic>{},'unknown',fields:['title']),false);
 });
}

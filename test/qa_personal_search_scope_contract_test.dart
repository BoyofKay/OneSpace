import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// QA: personal Activities, Memories, Activity tags and Calendar events must be
/// searchable, including by a solo account. Couple-only sections are skipped
/// without a relationship instead of failing the whole search.
void main(){
 final source=File('lib/features/search/global_search_screen.dart').readAsStringSync();
 test('personal-capable sections are not filtered by couple space in QA',(){
  expect(source,contains("own(db.from('activities')"));
  expect(source,contains("own(db.from('memories')"));
  expect(source,contains("own(db.from('space_events')"));
  expect(source,contains("own(db.from('saved_contacts')"));
  expect(source,contains("activities!inner(archived_at)"));
  expect(source,isNot(contains("throw StateError('No current shared space')")));
 });
 test('couple-only sections are skipped when there is no relationship',(){
  for(final table in ['couple_letters','shared_trips','shared_experiences',
    'trip_items','trip_attachments','occasion_plans','items_to_sort']){
   expect(source,contains("id==null?none:db.from('$table')"),reason:table);
  }
 });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/memories/scrapbook_templates.dart';

void main(){
 test('R70: 22 scrapbook templates with unique stable keys and 1–4 photo slots',(){
  final designs=ScrapbookTemplates.designs;
  expect(designs.length,22);
  expect(designs.map((x)=>x.key).toSet().length,22);
  const layouts={'pair_tilted','hero_two','left_three','two_top_one','grid4','strip4','single','miles_apart','hero_three','postcard'};
  for(final d in designs){
   expect(d.photoCount,inInclusiveRange(1,4));
   expect(layouts.contains(d.layout),isTrue,reason:d.key);
   expect(ScrapbookTemplates.get(d.key).name,d.name);
  }
 });
 test('Unknown saved template safely falls back to first design',(){
  expect(ScrapbookTemplates.get('retired_template').key,'polaroid_letters');
 });
 test('Scrapbook title validates empty and oversized values',(){
  expect(ScrapbookTemplates.validateTitle('  '),isNotNull);
  expect(ScrapbookTemplates.validateTitle('Our first chapter'),isNull);
  expect(ScrapbookTemplates.validateTitle(List.filled(121,'x').join()),isNotNull);
 });
 test('Scrapbook dates use the same local calendar representation',(){
  expect(ScrapbookTemplates.compactDate(DateTime(2026,11,14)),'2026-11-14');
 });
}

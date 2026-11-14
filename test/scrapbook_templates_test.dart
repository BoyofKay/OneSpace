import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/memories/scrapbook_templates.dart';

void main(){
 test('All scrapbook templates have unique stable keys and 2–3 photo slots',(){
  final designs=ScrapbookTemplates.designs;
  expect(designs.length,4);
  expect(designs.map((x)=>x.key).toSet().length,4);
  for(final d in designs){
   expect(d.photoCount,inInclusiveRange(2,3));
   expect(ScrapbookTemplates.get(d.key).name,d.name);
  }
 });
 test('Unknown saved template safely falls back to first design',(){
  expect(ScrapbookTemplates.get('retired_template').key,'polaroid_letters');
 });
 test('Scrapbook title validates empty and oversized values',(){
  expect(ScrapbookTemplates.validateTitle('  '),isNotNull);
  expect(ScrapbookTemplates.validateTitle('Our first chapter'),isNull);
  expect(ScrapbookTemplates.validateTitle('x'*121),isNotNull);
 });
 test('Scrapbook dates use the same local calendar representation',(){
  expect(ScrapbookTemplates.compactDate(DateTime(2026,11,14)),'2026-11-14');
 });
}

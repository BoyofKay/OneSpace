import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/memories/memory_photo_layout_rules.dart';

void main(){
 test('Every scrapbook layout is a configured preset',(){
  expect(MemoryPhotoLayoutRules.allowed,
   containsAll(['grid','feature','polaroid','overlap']));
 });
 test('Layout selection falls back without leaking old data',(){
  expect(MemoryPhotoLayoutRules.safe('unknown'),'grid');
  expect(MemoryPhotoLayoutRules.safe('polaroid'),'polaroid');
 });
}

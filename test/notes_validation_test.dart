import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/notes/note_draft_rules.dart';

void main(){
 group('Collaborative note validation',(){
  test('accepts multilingual notes and an empty body',(){
   expect(NoteDraftRules.isValid(title:'خطط السفر',
    body:'Flights and accommodation'),isTrue);
   expect(NoteDraftRules.isValid(title:'Idea',body:''),isTrue);
  });
  test('rejects empty titles and oversized documents',(){
   expect(NoteDraftRules.isValid(title:'  ',body:'text'),isFalse);
   expect(NoteDraftRules.isValid(
    title:List.filled(121,'A').join(),body:'text'),isFalse);
   expect(NoteDraftRules.isValid(
    title:'Idea',body:List.filled(30001,'B').join()),isFalse);
  });
 });
}

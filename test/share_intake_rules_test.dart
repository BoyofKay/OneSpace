import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/share_in/share_intake_rules.dart';
void main(){
 test('Extract shopping link and preserve user note',(){
  final x=ShareIntakeRules.parse(
   subject:'Timer heater',text:'Check this one https://example.com/heater?color=blue\nIt has auto-shutoff');
  expect(x.title,'Timer heater');
  expect(x.link,'https://example.com/heater?color=blue');
  expect(x.note,contains('auto-shutoff'));
 });
 test('Trailing punctuation is not part of the URL',(){
  final x=ShareIntakeRules.parse(text:'Try (https://example.org/item), thanks!');
  expect(x.link,'https://example.org/item');
 });
 test('A plain message without a URL remains a valid note',(){
  final x=ShareIntakeRules.parse(text:'Ask about swimming lessons');
  expect(x.link,isEmpty);
  expect(x.note,'Ask about swimming lessons');
 });
 test('Reject non-web deep links and invalid paths',(){
  expect(ShareIntakeRules.isWebLink('file:///secret.pdf'),false);
  expect(ShareIntakeRules.isWebLink('https://example.com/a'),true);
 });
 test('External payload truncates oversized text safely',(){
  final x=ShareIntakeRules.fromExternal({'subject':'A','text':'a'*9000});
  expect(x.note.length,5000);
  expect(x.title,'A');
 });
}

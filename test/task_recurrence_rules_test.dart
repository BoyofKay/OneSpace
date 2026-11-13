import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/plans/task_recurrence_rules.dart';
void main(){
 test('Daily routines reset per local calendar date',(){
  expect(TaskRecurrenceRules.cycle('daily',DateTime(2026,11,14)),'2026-11-14');
 });
 test('Weekly routines start on Monday',(){
  expect(TaskRecurrenceRules.cycle('weekly',DateTime(2026,11,14)),'2026-11-09');
 });
 test('Monthly, yearly routines preserve history by cycle',(){
  expect(TaskRecurrenceRules.cycle('monthly',DateTime(2026,11,14)),'2026-11-01');
  expect(TaskRecurrenceRules.cycle('yearly',DateTime(2026,11,14)),'2026-01-01');
  expect(TaskRecurrenceRules.cycle('none',DateTime(2026,11,14)),'2000-01-01');
 });
}

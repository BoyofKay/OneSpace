import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/plans/checklist_schedule.dart';

void main(){
 test('Selected weekdays create a fresh independent cycle on each chosen day',(){
  const rule={'mode':'selected_weekdays','weekdays':[1,4],'anchor':'2026-11-01'};
  expect(ChecklistSchedule.occurs('daily',rule,DateTime(2026,11,16)),true);
  expect(ChecklistSchedule.occurs('daily',rule,DateTime(2026,11,17)),false);
  expect(ChecklistSchedule.occurs('daily',rule,DateTime(2026,11,19)),true);
  expect(ChecklistSchedule.cycle('daily',rule,DateTime(2026,11,16)),'2026-11-16');
  expect(ChecklistSchedule.cycle('daily',rule,DateTime(2026,11,19)),'2026-11-19');
 });
 test('Weekend / working day routines are separate from visibility',(){
  const w={'mode':'weekends'};
  const working={'mode':'workdays'};
  expect(ChecklistSchedule.occurs('daily',w,DateTime(2026,11,14)),true);
  expect(ChecklistSchedule.occurs('daily',w,DateTime(2026,11,16)),false);
  expect(ChecklistSchedule.occurs('daily',working,DateTime(2026,11,15),
   workDays:[7,1,2,3,4]),true);
 });
 test('Every N days and weeks use anchored recurrence, not app-open date',(){
  const days={'mode':'every_n_days','interval':3,'anchor':'2026-11-01'};
  expect(ChecklistSchedule.occurs('daily',days,DateTime(2026,11,4)),true);
  expect(ChecklistSchedule.occurs('daily',days,DateTime(2026,11,5)),false);
  const weeks={'mode':'every_n_weeks','interval':2,'anchor':'2026-11-02',
   'weekdays':[1,3]};
  expect(ChecklistSchedule.occurs('daily',weeks,DateTime(2026,11,16)),true);
  expect(ChecklistSchedule.occurs('daily',weeks,DateTime(2026,11,9)),false);
 });
 test('Month days and exceptions respect skipped dates',(){
  const rule={'mode':'month_days','month_days':[1,-1],
   'anchor':'2026-01-01','exclude_dates':['2026-11-01']};
  expect(ChecklistSchedule.occurs('daily',rule,DateTime(2026,11,1)),false);
  expect(ChecklistSchedule.occurs('daily',rule,DateTime(2026,11,30)),true);
 });
 test('Days off and observed US holidays can suppress occurrences',(){
  const p={'mode':'daily','skip_personal_days_off':true};
  expect(ChecklistSchedule.occurs('daily',p,DateTime(2026,11,14),
   personalDayOff:true),false);
  const h={'mode':'daily','skip_us_holidays':true};
  expect(ChecklistSchedule.usFederalHoliday(DateTime(2026,11,26)),true);
  expect(ChecklistSchedule.occurs('daily',h,DateTime(2026,11,26),
   usHoliday:true),false);
 });
 test('Configured IANA zones can differ from the phone locale',(){
  expect(ChecklistSchedule.validTimeZone('America/New_York'),true);
  expect(ChecklistSchedule.validTimeZone('Not/A_Timezone'),false);
  final utc=DateTime.utc(2026,11,15,1);
  expect(ChecklistSchedule.day(
   ChecklistSchedule.localNow(utc,'America/New_York')),'2026-11-14');
  expect(ChecklistSchedule.day(
   ChecklistSchedule.localNow(utc,'Asia/Riyadh')),'2026-11-15');
 });
}

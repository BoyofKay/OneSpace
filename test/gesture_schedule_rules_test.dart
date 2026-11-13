import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/connect/gesture_schedule_rules.dart';

void main(){
 test('No schedules deliver without the partner opting in',(){
   final partner={'time_zone':'America/New_York',
     'sleep_end_local':'07:00:00','receive_automatic_gestures':false};
   expect(GestureScheduleRules.isReady('morning',partner),isFalse);
   expect(GestureScheduleRules.prerequisite('morning',partner),
     contains('allow automatic'));
 });
 test('Morning and bedtime require each recipient setting',(){
   final partner={'time_zone':'America/New_York',
     'sleep_end_local':'07:00:00','sleep_start_local':'22:00:00','receive_automatic_gestures':true};
   expect(GestureScheduleRules.isReady('morning',partner),isTrue);
   expect(GestureScheduleRules.isReady('goodnight',partner),isTrue);
   partner.remove('sleep_start_local');
   expect(GestureScheduleRules.isReady('goodnight',partner),isFalse);
   expect(GestureScheduleRules.isReady('morning',partner),isFalse);
 });
 test('After-work requires workdays and recipient local work end',(){
   final partner={'time_zone':'Asia/Riyadh',
     'work_end_local':'17:00:00','work_days':[7,1,2,3,4],
     'sleep_start_local':'22:00:00','sleep_end_local':'07:00:00',
     'receive_automatic_gestures':true};
   expect(GestureScheduleRules.isReady('after_work',partner),isTrue);
   partner['work_days']=[];
   expect(GestureScheduleRules.isReady('after_work',partner),isFalse);
 });
 test('Unknown time zone and unknown ritual are not ready',(){
   expect(GestureScheduleRules.isReady('morning',{'receive_automatic_gestures':true}),isFalse);
   expect(GestureScheduleRules.isReady('other',{
     'time_zone':'Asia/Riyadh','receive_automatic_gestures':true}),isFalse);
 });
}

/// Display-side readiness only. The database scheduler rechecks consent,
/// membership, local time, schedules and sleep hours for every delivery.
class GestureScheduleRules {
 const GestureScheduleRules._();
 static bool isReady(String moment,Map<String,dynamic>? partner){
   if(partner==null||partner['receive_automatic_gestures']!=true ||
      (partner['time_zone']?.toString().isNotEmpty!=true)){
     return false;
   }
   if(moment=='morning'){
     return partner['sleep_end_local']!=null;
   }
   if(moment=='goodnight'){
     return partner['sleep_start_local']!=null;
   }
   if(moment=='after_work'){
     return partner['work_end_local']!=null &&
       (partner['work_days'] is List) &&
       (partner['work_days'] as List).isNotEmpty;
   }
   return false;
 }
 static String prerequisite(String moment,Map<String,dynamic>? partner){
   if(partner==null)return 'Waiting for partner schedule information';
   if(partner['receive_automatic_gestures']!=true){
     return 'Waiting for your partner to allow automatic gestures';
   }
   if(partner['time_zone']?.toString().isNotEmpty!=true){
     return 'Waiting for their phone time zone';
   }
   if(moment=='morning'&&partner['sleep_end_local']==null){
     return 'Waiting for their wake-up time';
   }
   if(moment=='goodnight'&&partner['sleep_start_local']==null){
     return 'Waiting for their bedtime';
   }
   if(moment=='after_work'&&
     (partner['work_end_local']==null ||
       partner['work_days'] is! List ||
       (partner['work_days'] as List).isEmpty)){
     return 'Waiting for their work schedule';
   }
   return 'Ready';
 }
}

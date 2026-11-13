/// Pure local calendar dates: never convert birthdays or reunions via UTC.
/// For annual Feb 29 dates, display Feb 28 in non-leap years.
class ActivityCountdownRules {
 const ActivityCountdownRules._();

 static DateTime? parseDate(String? raw){
   if(raw==null||!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw))return null;
   final parts=raw.split('-').map(int.parse).toList();
   final y=parts[0],m=parts[1],d=parts[2];
   if(y<1||m<1||m>12||d<1||d>31)return null;
   final date=DateTime(y,m,d);
   if(date.year!=y||date.month!=m||date.day!=d)return null;
   return date;
 }
 static DateTime _yearly(int year,int month,int day){
   final last=DateTime(year,month+1,0).day;
   return DateTime(year,month,day>last?last:day);
 }
 static DateTime? target(String? value,{
   bool repeatYearly=false,required DateTime now,
 }){
   final base=parseDate(value);
   if(base==null)return null;
   if(!repeatYearly)return base;
   final today=DateTime(now.year,now.month,now.day);
   var occurrence=_yearly(today.year,base.month,base.day);
   if(occurrence.isBefore(today)){
     occurrence=_yearly(today.year+1,base.month,base.day);
   }
   return occurrence;
 }
 static int? remaining(String? value,{
   bool repeatYearly=false,required DateTime now,
 }){
   final day=target(value,repeatYearly:repeatYearly,now:now);
   if(day==null)return null;
   return day.difference(DateTime(now.year,now.month,now.day)).inDays;
 }
 static String summary(String? value,{
   bool repeatYearly=false,required DateTime now,
 }){
   final days=remaining(value,repeatYearly:repeatYearly,now:now);
   if(days==null)return 'Choose a milestone date';
   if(days==0)return 'Today is the day!';
   if(days==1)return 'Tomorrow!';
   if(days>1)return days.toString()+' days to go';
   if(days==-1)return 'Yesterday';
   return (-days).toString()+' days since';
 }
}

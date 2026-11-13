class TaskRecurrenceRules {
 const TaskRecurrenceRules._();
 static String day(DateTime v)=>
  '${v.year.toString().padLeft(4,'0')}-${v.month.toString().padLeft(2,'0')}-${v.day.toString().padLeft(2,'0')}';
 static DateTime cycleStart(String recurrence,DateTime date){
  final d=DateTime(date.year,date.month,date.day);
  switch(recurrence){
   case 'daily':return d;
   case 'weekly':return d.subtract(Duration(days:d.weekday-1));
   case 'monthly':return DateTime(d.year,d.month,1);
   case 'yearly':return DateTime(d.year,1,1);
   default:return DateTime(2000,1,1);
  }
 }
 static String cycle(String recurrence,DateTime date)=>day(cycleStart(recurrence,date));
}

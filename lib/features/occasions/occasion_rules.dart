import '../calendar/calendar_rules.dart';

/// All occasion dates are calendar days, not UTC timestamps.
class OccasionRules {
 const OccasionRules._();

 static DateTime? nextDate({
  required DateTime original,
  required bool annual,
  required DateTime today,
 }){
  final source=CalendarRules.day(original);
  final base=CalendarRules.day(today);
  if(!annual)return source.isBefore(base)?null:source;
  for(var y=base.year;y<=2100;y++){
   final last=DateTime(y,source.month+1,0).day;
   // Feb 29 becomes Feb 28 in a non-leap year instead of disappearing.
   final date=DateTime(y,source.month,source.day>last?last:source.day);
   if(!date.isBefore(base))return date;
  }
  return null;
 }

 static int? daysUntil(DateTime? date,DateTime today) =>
   date==null?null:CalendarRules.calendarDaysUntil(
     CalendarRules.day(today),CalendarRules.day(date));

 /// Date arithmetic must use calendar fields, not 24-hour durations,
 /// because local daylight-saving transitions are not always 24 hours long.
 static DateTime? prepStart(DateTime? next,int days){
  if(next==null)return null;
  return DateTime(next.year,next.month,next.day-days);
 }

 static String countdown(DateTime? date,DateTime today){
  final days=daysUntil(date,today);
  if(days==null)return 'Past occasion';
  if(days==0)return 'Today';
  if(days==1)return 'Tomorrow';
  return 'In '+days.toString()+' days';
 }

 static Map<String,double> estimatedByCurrency(List<Map<String,dynamic>> rows){
  final total=<String,double>{};
  for(final row in rows){
   if(row['archived_at']!=null)continue;
   final n=row['estimated_cost'];
   final cost=n is num?n.toDouble():double.tryParse(n?.toString()??'');
   if(cost==null||!cost.isFinite||cost<0)continue;
   final currency=(row['currency']??'USD').toString().toUpperCase();
   if(!RegExp(r'^[A-Z]{3}$').hasMatch(currency))continue;
   total[currency]=(total[currency]??0)+cost;
  }
  return total;
 }
}

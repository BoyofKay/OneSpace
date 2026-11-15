import '../calendar/calendar_rules.dart';

/// Date-only travel countdowns and currency-safe budget summaries.
class TripRules {
 const TripRules._();

 /// R67: the status is automatic (set by the database); this only mirrors it
 /// for the screen so a trip shows Traveling/Completed on the right day even
 /// before the hourly refresh.
 static String status(Map<String,dynamic> trip,DateTime today){
  final stored=(trip['status']??'planning').toString();
  if(stored=='cancelled')return 'cancelled';
  final day=CalendarRules.day(today);
  final start=DateTime.tryParse((trip['start_on']??'').toString());
  final end=DateTime.tryParse((trip['end_on']??'').toString())??start;
  if(end!=null&&end.isBefore(day))return 'completed';
  if(start!=null&&!start.isAfter(day))return 'traveling';
  return stored=='booked'?'booked':'planning';
 }

 /// Display words for each status.
 static const statusLabels=<String,String>{
  'planning':'Planning','booked':'Booked','traveling':'Traveling',
  'completed':'Past','cancelled':'Cancelled',
 };

 /// ["2 adults", "1 child"] (empty when nobody is counted).
 static List<String> passengers(Map<String,dynamic> trip){
  int n(String k)=>(trip[k] as num?)?.toInt()??0;
  final a=n('adults'),c=n('children'),i=n('infants');
  return [
   if(a>0)'$a ${a==1?'adult':'adults'}',
   if(c>0)'$c ${c==1?'child':'children'}',
   if(i>0)'$i ${i==1?'infant':'infants'}',
  ];
 }

 static int? daysUntil(DateTime? departure,DateTime today){
  if(departure==null)return null;
  return CalendarRules.calendarDaysUntil(
   CalendarRules.day(today),CalendarRules.day(departure));
 }

 static String countdownLabel(DateTime? departure,DateTime today){
  final days=daysUntil(departure,today);
  if(days==null)return 'Departure date not set';
  if(days==0)return 'Departure is today';
  if(days==1)return 'One day until departure';
  if(days>1)return days.toString()+' days until departure';
  if(days == -1)return 'Departure was yesterday';
  return 'Departure was '+(-days).toString()+' days ago';
 }

 /// Different currencies must never be added together.
 static Map<String,double> sumByCurrency(List<Map<String,dynamic>> items){
  final totals=<String,double>{};
  for(final item in items){
   if(item['archived_at']!=null)continue;
   final raw=item['estimated_cost'];
   if(raw==null)continue;
   final amount=raw is num?raw.toDouble():double.tryParse(raw.toString());
   if(amount==null||!amount.isFinite||amount<0)continue;
   final currency=(item['currency']??'USD').toString().toUpperCase();
   if(!RegExp(r'^[A-Z]{3}$').hasMatch(currency))continue;
   totals[currency]=(totals[currency]??0)+amount;
  }
  return totals;
 }

 static String formatTotals(Map<String,double> totals){
  if(totals.isEmpty)return 'No estimated costs';
  final codes=totals.keys.toList()..sort();
  return codes.map((code)=>code+' '+totals[code]!.toStringAsFixed(2)).join(' · ');
 }
}

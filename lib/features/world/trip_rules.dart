import '../calendar/calendar_rules.dart';

/// Date-only travel countdowns and currency-safe budget summaries.
class TripRules {
 const TripRules._();

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

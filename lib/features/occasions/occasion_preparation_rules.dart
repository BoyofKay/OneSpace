import 'package:onespace/l10n/phrases.dart';
import '../calendar/calendar_rules.dart';
import 'occasion_rules.dart';

/// Local, transparent preparation suggestions. No reminders are created
/// unless a user explicitly chooses to save one.
class OccasionPreparationStep {
 const OccasionPreparationStep({
  required this.phase,required this.title,required this.description,
  required this.suggestedDate,required this.occasionDate,
 });
 final String phase,title,description;
 final DateTime suggestedDate,occasionDate;
 String get dateLabel=>CalendarRules.sqlDate(suggestedDate);
}

class OccasionPreparationRules {
 const OccasionPreparationRules._();
 static const phases=['save','research','order','prepare'];

 static List<OccasionPreparationStep> steps({
  required Map<String,dynamic> plan,
  required DateTime today,
 }) {
  final original=DateTime.tryParse((plan['occasion_on']??'').toString());
  if(original==null)return const [];
  final next=OccasionRules.nextDate(
   original:original,annual:plan['annual']==true,today:today);
  if(next==null)return const [];
  final savingDays=_lead(plan['saving_lead_days'],60);
  final researchDays=_lead(plan['prep_lead_days'],30);
  // Ordering happens before the final preparations and is only a default.
  // Actual shipping dates should be reviewed in the gift comparison planner.
  final orderDays=researchDays>=14?14:researchDays;
  final preparationDays=researchDays>=3?3:researchDays;
  final label=(plan['title']??'').toString().trim();
  final name=label.isEmpty?tt('the occasion'):label;
  // UAT 26 Nov 2026: saved in the app language (they become reminders).
  String f(String template)=>tt(template).replaceFirst('{}',name);
  OccasionPreparationStep step(String phase,String title,String details,int days)=>
   OccasionPreparationStep(phase:phase,title:title,description:details,
    suggestedDate:OccasionRules.prepStart(next,days)!,
    occasionDate:next);
  return [
   step('save',f('Set money aside for {}'),
    tt('Check your budget and set aside what you need.'),savingDays),
   step('research',f('Research choices for {}'),
    tt('Compare ideas, prices, preferences, reviews and sellers.'),researchDays),
   step('order',f('Review ordering deadlines for {}'),
    tt('Check actual shipping estimates before placing an order.'),orderDays),
   step('prepare',f('Final preparations for {}'),
    tt('Check arrivals, wrapping, reservations and any missing supplies.'),preparationDays),
  ];
 }

 static int _lead(Object? value,int fallback){
  final n=value is num?value.toInt():int.tryParse(value?.toString()??'');
  return n==null?fallback:n.clamp(0,365);
 }

 static String dateOnly(DateTime date)=>CalendarRules.sqlDate(date);
 static String? activeForMe(
  Iterable<Map<String,dynamic>> existing,
  String phase,String instanceOn,String? userId,
 ){
  if(userId==null)return null;
  for(final row in existing){
   if(row['planning_phase']==phase&&
    row['occasion_instance_on']==instanceOn&&
    row['created_by']==userId&&row['archived_at']==null){
    return row['id']?.toString();
   }
  }
  return null;
 }

 static DateTime nextFutureTime(DateTime suggested,DateTime now){
  var candidate=DateTime(suggested.year,suggested.month,suggested.day,9);
  if(!candidate.isAfter(now.add(const Duration(minutes:2)))){
   final tomorrow=DateTime(now.year,now.month,now.day+1,9);
   candidate=tomorrow;
  }
  return candidate;
 }
}

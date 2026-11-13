import '../features/calendar/calendar_rules.dart';
import '../features/occasions/occasion_rules.dart';
import 'onespace_appearance.dart';

/// Stateless and local: caller must supply only RLS-authorized occasion rows.
class OccasionThemeResolver {
 const OccasionThemeResolver._();
 static SeasonChoice? forDate(List<Map<String,dynamic>> visible,DateTime today){
  final now=CalendarRules.day(today);
  var birthday=false;
  for(final row in visible){
   if(row['archived_at']!=null||row['status']=='cancelled')continue;
   final kind=(row['kind']??'').toString();
   if(kind!='anniversary'&&kind!='birthday')continue;
   final origin=DateTime.tryParse((row['occasion_on']??'').toString());
   if(origin==null)continue;
   final next=OccasionRules.nextDate(
    original:origin,annual:row['annual']==true,today:now);
   if(next==null||CalendarRules.calendarDaysUntil(now,next)!=0)continue;
   if(kind=='anniversary')return SeasonChoice.anniversary;
   birthday=true;
  }
  return birthday?SeasonChoice.birthday:null;
 }
}

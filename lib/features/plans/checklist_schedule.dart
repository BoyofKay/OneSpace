import 'package:timezone/data/latest_all.dart' as tzdb;
import 'package:timezone/timezone.dart' as tz;

/// Deterministic local-day schedule decisions; checking off an item never
/// deletes yesterday's state. The partner's phone (or explicit IANA timezone)
/// provides calendar-day boundaries, including DST.
class ChecklistSchedule {
 const ChecklistSchedule._();
 static bool _zoneReady=false;
 static bool validTimeZone(String input){
  try{
   if(!_zoneReady){tzdb.initializeTimeZones();_zoneReady=true;}
   tz.getLocation(input);
   return true;
  }catch(_){return false;}
 }
 static DateTime nextLocalMidnight(DateTime now,String? zone){
  if(zone==null||zone.isEmpty){
   final local=now.toLocal();
   return DateTime(local.year,local.month,local.day+1);
  }
  try{
   if(!_zoneReady){tzdb.initializeTimeZones();_zoneReady=true;}
   final location=tz.getLocation(zone);
   final local=tz.TZDateTime.from(now.toUtc(),location);
   return tz.TZDateTime(location,local.year,local.month,local.day+1).toLocal();
  }catch(_){
   final local=now.toLocal();
   return DateTime(local.year,local.month,local.day+1);
  }
 }
 static DateTime localNow(DateTime instant,String? timezone){
  if(timezone==null||timezone.isEmpty)return instant.toLocal();
  try{
   if(!_zoneReady){tzdb.initializeTimeZones();_zoneReady=true;}
   return tz.TZDateTime.from(instant.toUtc(),tz.getLocation(timezone));
  }catch(_){return instant.toLocal();}
 }
 static String day(DateTime d)=>'${d.year.toString().padLeft(4,'0')}-'
  '${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
 static DateTime _anchor(Map<String,dynamic> r,DateTime d)=>
  DateTime.tryParse(r['anchor']?.toString()??'')??DateTime(d.year,d.month,d.day);
 static int _interval(Map<String,dynamic> r){
  final n=(r['interval'] as num?)?.toInt()??1;
  return n.clamp(1,365);
 }
 static List<int> _days(dynamic v){
  if(v is! List)return [];
  return v.whereType<num>().map((n)=>n.toInt()).toList();
 }
 static String mode(Map<String,dynamic> rule,String recurrence)=>
  (rule['mode']??recurrence).toString();
 static bool occurs(String recurrence,Map<String,dynamic> rule,
  DateTime local,{bool personalDayOff=false,bool usHoliday=false,
  List<int>? workDays}){
  final d=DateTime(local.year,local.month,local.day);
  final dates=(rule['exclude_dates'] as List? ??const []).map((x)=>x.toString());
  if(dates.contains(day(d)))return false;
  if(rule['skip_personal_days_off']==true&&personalDayOff)return false;
  // R66: "Skip public holidays" uses the country of the person the list
  // belongs to (usHoliday carries that answer; older lists said US only).
  if((rule['skip_us_holidays']==true||rule['skip_public_holidays']==true)&&usHoliday)return false;
  final until=DateTime.tryParse(rule['until']?.toString()??'');
  if(until!=null&&d.isAfter(DateTime(until.year,until.month,until.day)))return false;
  final start=_anchor(rule,d);
  if(d.isBefore(start))return false;
  final elapsed=DateTime.utc(d.year,d.month,d.day)
   .difference(DateTime.utc(start.year,start.month,start.day)).inDays;
  final every=_interval(rule);
  switch(mode(rule,recurrence)){
   case 'none':return true;
   case 'daily':return true;
   case 'weekly':return true;
   case 'monthly':return true;
   case 'yearly':return true;
   case 'weekdays':return d.weekday<=5;
   case 'weekends':return d.weekday>=6;
   case 'workdays':return (workDays??[1,2,3,4,5]).contains(d.weekday);
   case 'selected_weekdays':return _days(rule['weekdays']).contains(d.weekday);
   case 'every_n_days':return elapsed%every==0;
   case 'every_n_weeks':
    final week=d.subtract(Duration(days:d.weekday-1));
    final anchorWeek=start.subtract(Duration(days:start.weekday-1));
    final elapsedWeeks=DateTime.utc(week.year,week.month,week.day)
      .difference(DateTime.utc(anchorWeek.year,anchorWeek.month,anchorWeek.day)).inDays~/7;
    return elapsedWeeks>=0&&elapsedWeeks%every==0&&
      (_days(rule['weekdays']).isEmpty?
       d.weekday==start.weekday:_days(rule['weekdays']).contains(d.weekday));
   case 'month_days':
    final days=_days(rule['month_days']);
    final end=DateTime(d.year,d.month+1,0).day;
    return days.contains(d.day)||(days.contains(-1)&&d.day==end);
   default:return true;
  }
 }
 static String cycle(String recurrence,Map<String,dynamic> rule,DateTime local){
  final d=DateTime(local.year,local.month,local.day);
  // Advance once per selected scheduled day instead of permanently ticking
  // all Mondays in a month or both partners' independent daily occurrences.
  switch(mode(rule,recurrence)){
   case 'weekdays':case 'weekends':case 'workdays':
   case 'selected_weekdays':case 'every_n_days':
   case 'every_n_weeks':case 'month_days':
    return day(d);
   case 'weekly':
    return day(d.subtract(Duration(days:d.weekday-1)));
   case 'monthly':return day(DateTime(d.year,d.month,1));
   case 'yearly':return day(DateTime(d.year,1,1));
   case 'daily':return day(d);
   default:return '2000-01-01';
  }
 }
 /// R66: holiday country from a profile time zone (Saudi, Egypt, US).
 static String? countryForTimeZone(String? zone){
  if(zone==null||zone.isEmpty)return null;
  if(zone=='Asia/Riyadh')return 'SA';
  if(zone=='Africa/Cairo')return 'EG';
  if(zone.startsWith('America/')||zone.startsWith('US/')||zone=='Pacific/Honolulu')return 'US';
  return null;
 }
 static bool usFederalHoliday(DateTime d){
  // Observed New Year / Christmas / Independence / Juneteenth / Veterans.
  DateTime observed(int y,int m,int day){
   final date=DateTime(y,m,day);
   if(date.weekday==6)return date.subtract(const Duration(days:1));
   if(date.weekday==7)return date.add(const Duration(days:1));
   return date;
  }
  DateTime nth(int y,int m,int weekday,int n){
   final first=DateTime(y,m,1);
   return first.add(Duration(days:(weekday-first.weekday+7)%7+(n-1)*7));
  }
  DateTime last(int y,int m,int weekday){
   final end=DateTime(y,m+1,0);
   return end.subtract(Duration(days:(end.weekday-weekday+7)%7));
  }
  final key=day(d),y=d.year;
  final holidays=<DateTime>[
   observed(y,1,1),observed(y+1,1,1),observed(y-1,1,1),
   nth(y,1,1,3),nth(y,2,1,3),last(y,5,1),
   observed(y,6,19),observed(y,7,4),
   nth(y,9,1,1),nth(y,10,1,2),observed(y,11,11),
   nth(y,11,4,4),observed(y,12,25),
  ];
  return holidays.any((x)=>day(x)==key);
 }
}

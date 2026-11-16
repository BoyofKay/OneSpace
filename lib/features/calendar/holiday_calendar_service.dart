import 'dart:convert';
import 'package:http/http.dart' as http;
import 'calendar_rules.dart';

class HolidayDay{
 const HolidayDay({required this.date,required this.name,
  required this.country,required this.source});
 final DateTime date;
 final String name,country,source;
 String get dayKey=>CalendarRules.sqlDate(date);
}

class HolidayCatalog{
 const HolidayCatalog._();
 static const countryNames={
  'SA':'Saudi Arabia',
  'EG':'Egypt',
  'AE':'United Arab Emirates',
  'US':'United States',
  'GB':'United Kingdom',
  'CA':'Canada',
 };
 /// R69: countries whose holidays are built into the app (no network).
 static const builtIn={'SA','EG','AE'};
 static String label(String code)=>countryNames[code]??code;

 /// R69: expected Islamic dates (Umm al-Qura), 2025–2030. They depend on
 /// the moon sighting and can move by a day; the name says "(expected)".
 static const _ramadan={2025:'03-01',2026:'02-18',2027:'02-08',2028:'01-28',2029:'01-16',2030:'01-06'};
 static const _fitr={2025:'03-30',2026:'03-20',2027:'03-09',2028:'02-26',2029:'02-14',2030:'02-04'};
 static const _adha={2025:'06-06',2026:'05-27',2027:'05-16',2028:'05-05',2029:'04-24',2030:'04-13'};
 static const _hijriNewYear={2025:'06-26',2026:'06-16',2027:'06-06',2028:'05-25',2029:'05-14',2030:'05-04'};
 static const _mawlid={2025:'09-04',2026:'08-25',2027:'08-14',2028:'08-03',2029:'07-24',2030:'07-13'};

 static DateTime? _md(Map<int,String> table,int year){
  final v=table[year];
  if(v==null)return null;
  final p=v.split('-');
  return DateTime(year,int.parse(p[0]),int.parse(p[1]));
 }

 static List<HolidayDay> _islamic(int year,String country,{bool mawlid=false,bool newYear=true,bool arafat=false}){
  const src='Umm al-Qura calendar (expected; may move by a day)';
  final out=<HolidayDay>[];
  void add(DateTime? d,String name){if(d!=null)out.add(HolidayDay(date:d,name:name,country:country,source:src));}
  add(_md(_ramadan,year),'Ramadan begins (expected)');
  add(_md(_fitr,year),'Eid al-Fitr (expected)');
  final adha=_md(_adha,year);
  if(arafat&&adha!=null)add(adha.subtract(const Duration(days:1)),'Day of Arafah (expected)');
  add(adha,'Eid al-Adha (expected)');
  if(newYear)add(_md(_hijriNewYear,year),'Islamic New Year (expected)');
  if(mawlid)add(_md(_mawlid,year),"Prophet's Birthday (expected)");
  return out;
 }

 /// Orthodox Easter (Julian computus, shown in the Gregorian calendar).
 static DateTime orthodoxEaster(int year){
  final a=year%4,b=year%7,c=year%19;
  final d=(19*c+15)%30,e=(2*a+4*b-d+34)%7;
  final month=(d+e+114)~/31,day=((d+e+114)%31)+1;
  return DateTime(year,month,day).add(const Duration(days:13));
 }

 static List<HolidayDay> saudiCivicDays(int year)=>[
  HolidayDay(date:DateTime(year,2,22),name:'Founding Day',country:'SA',
   source:'Saudi official government'),
  HolidayDay(date:DateTime(year,9,23),name:'Saudi National Day',country:'SA',
   source:'Saudi official government'),
 ];

 /// R69: the built-in calendar for a country and year.
 static List<HolidayDay> builtInDays(int year,String country){
  final out=<HolidayDay>[];
  HolidayDay fixed(int m,int d,String name,String src)=>
   HolidayDay(date:DateTime(year,m,d),name:name,country:country,source:src);
  switch(country){
   case 'SA':
    out..addAll(saudiCivicDays(year))..addAll(_islamic(year,'SA',newYear:false,arafat:true));
   case 'EG':
    const src='Egypt official holidays';
    out.addAll([
     fixed(1,7,'Coptic Christmas',src),fixed(1,25,'Revolution Day (January 25)',src),
     fixed(4,25,'Sinai Liberation Day',src),fixed(5,1,'Labour Day',src),
     fixed(6,30,'June 30 Revolution',src),fixed(7,23,'Revolution Day (July 23)',src),
     fixed(10,6,'Armed Forces Day',src),
     HolidayDay(date:orthodoxEaster(year).add(const Duration(days:1)),name:'Sham el-Nessim',country:'EG',source:src),
    ]);
    out.addAll(_islamic(year,'EG',mawlid:true));
   case 'AE':
    const src='UAE official holidays';
    out.addAll([fixed(1,1,"New Year's Day",src),fixed(12,1,'Commemoration Day',src),
     fixed(12,2,'UAE National Day',src)]);
    out.addAll(_islamic(year,'AE',arafat:true));
  }
  out.sort((a,b)=>a.date.compareTo(b.date));
  return out;
 }

 /// The country a time zone points to (used to turn on holidays by itself).
 static String? countryForTimeZone(String? zone){
  if(zone==null||zone.isEmpty)return null;
  const map={'Asia/Riyadh':'SA','Africa/Cairo':'EG','Asia/Dubai':'AE','Europe/London':'GB',
   'America/Toronto':'CA','America/Vancouver':'CA','America/Montreal':'CA','America/Edmonton':'CA',
   'America/Winnipeg':'CA','America/Halifax':'CA'};
  final hit=map[zone];
  if(hit!=null)return hit;
  if(zone.startsWith('America/')||zone.startsWith('US/')||zone=='Pacific/Honolulu')return 'US';
  return null;
 }
 /// Avoid invented lunar-calendar dates, which depend on announcements.
 static List<HolidayDay> parseNager(String body,String country,int year){
  final raw=jsonDecode(body);
  if(raw is! List)throw const FormatException('Invalid holiday response');
  final found=<HolidayDay>[];
  for(final item in raw){
   if(item is! Map)continue;
   final date=DateTime.tryParse((item['date']??'').toString());
   final name=(item['name']??item['localName']??'').toString().trim();
   if(date==null||date.year!=year||name.isEmpty)continue;
   if(item['nationalHoliday']!=true&&item['global']!=true)continue;
   final rawKinds=item['holidayTypes']??item['types'];
   final kinds=rawKinds is List?rawKinds.map((v)=>v.toString()).toList():<String>[];
   if(kinds.isNotEmpty&&!kinds.contains('Public'))continue;
   found.add(HolidayDay(
    date:DateTime(date.year,date.month,date.day),
    name:name,country:country,
    source:'Nager.Holidays public-holiday calendar'));
  }
  return found;
 }
}

class HolidayCalendarService{
 HolidayCalendarService({http.Client? client}):_client=client??http.Client(),
  _ownsClient=client==null;
 final http.Client _client;
 final bool _ownsClient;
 final Map<String,List<HolidayDay>> _cache={};
 final Map<String,DateTime> _cachedAt={};
 void close(){if(_ownsClient)_client.close();}

 Future<HolidayLoadResult> forYearDetailed(int year,Set<String> countryCodes)async{
  if(year<2000||year>2100)return const HolidayLoadResult([],[]);
  final codes=countryCodes.where(HolidayCatalog.countryNames.containsKey).toList();
  final results=await Future.wait(codes.map((code)async{
   try{
    final items=await _countryYear(year,code);
    return (code:code,items:items,failed:false);
   }catch(_){
    return (code:code,items:<HolidayDay>[],failed:true);
   }
  }));
  final all=results.expand((x)=>x.items).toList()
   ..sort((a,b)=>a.date.compareTo(b.date));
  return HolidayLoadResult(all,[
   for(final x in results)if(x.failed)x.code,
  ]);
 }
 Future<List<HolidayDay>> forYear(int year,Set<String> countryCodes) async =>
   (await forYearDetailed(year,countryCodes)).days;

 Future<List<HolidayDay>> _countryYear(int year,String country)async{
  if(HolidayCatalog.builtIn.contains(country))return HolidayCatalog.builtInDays(year,country);
  final key='$year/$country';
  if(_cache.containsKey(key)&&DateTime.now().difference(_cachedAt[key]!)<
      const Duration(days:7))return _cache[key]!;
  // R69: Nager.Date (public, no key). The v3 address is the long-standing
  // one; the v4 address is tried if it fails.
  http.Response? response;
  for(final endpoint in [
   Uri.https('date.nager.at','/api/v3/PublicHolidays/$year/$country'),
   Uri.https('nagerholidays.com','/api/v4/Holidays/$country/$year'),
  ]){
   try{
    final r=await _client.get(endpoint).timeout(const Duration(seconds:7));
    if(r.statusCode==200){response=r;break;}
   }catch(_){}
  }
  if(response==null){
   throw HolidayFetchException('Holiday source unavailable for '+HolidayCatalog.label(country)+'.');
  }
  final days=HolidayCatalog.parseNager(response.body,country,year);
  _cache[key]=days;_cachedAt[key]=DateTime.now();
  return days;
 }
}

class HolidayFetchException implements Exception{
 const HolidayFetchException(this.message);
 final String message;
 @override String toString()=>message;
}

class HolidayLoadResult{
 const HolidayLoadResult(this.days,this.unavailableCountries);
 final List<HolidayDay> days;
 final List<String> unavailableCountries;
}

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
  'US':'United States',
  'EG':'Egypt',
  'SA':'Saudi Arabia',
 };
 static String label(String code)=>countryNames[code]??code;
 static List<HolidayDay> saudiCivicDays(int year)=>[
  HolidayDay(date:DateTime(year,2,22),name:'Founding Day',country:'SA',
   source:'Saudi official government'),
  HolidayDay(date:DateTime(year,9,23),name:'Saudi National Day',country:'SA',
   source:'Saudi official government'),
 ];
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

 Future<List<HolidayDay>> forYear(int year,Set<String> countryCodes)async{
  if(year<2000||year>2100)return [];
  final codes=countryCodes.where(HolidayCatalog.countryNames.containsKey).toList();
  final all=await Future.wait(codes.map((c)=>_countryYear(year,c)));
  return all.expand((l)=>l).toList()
   ..sort((a,b)=>a.date.compareTo(b.date));
 }
 Future<List<HolidayDay>> _countryYear(int year,String country)async{
  if(country=='SA')return HolidayCatalog.saudiCivicDays(year);
  final key='$year/$country';
  if(_cache.containsKey(key)&&DateTime.now().difference(_cachedAt[key]!)<
      const Duration(days:7))return _cache[key]!;
  final endpoint=Uri.https('nagerholidays.com','/api/v4/Holidays/$country/$year');
  final response=await _client.get(endpoint).timeout(const Duration(seconds:7));
  if(response.statusCode!=200){
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

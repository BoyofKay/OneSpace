import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:onespace/features/calendar/holiday_calendar_service.dart';
void main(){
 test('Saudi civic days are date-only; no invented Eid dates',(){
  final days=HolidayCatalog.saudiCivicDays(2027);
  expect(days.map((x)=>x.dayKey),['2027-02-22','2027-09-23']);
  expect(days.every((x)=>x.country=='SA'),true);
 });
 test('Holiday feed ignores subdivision-only dates and optional observances',(){
  final result=HolidayCatalog.parseNager(
   '[{"date":"2026-11-26","name":"Thanksgiving","global":true,"types":["Public"]},'
   '{"date":"2026-11-27","name":"State day","global":false,"types":["Public"]},'
   '{"date":"2026-12-01","name":"Optional","global":true,"types":["Observance"]}]',
   'US',2026);
  expect(result.length,1);
  expect(result.single.name,'Thanksgiving');
 });
 test('Nager v4 response includes only national public holidays',(){
  final result=HolidayCatalog.parseNager(
   '[{"date":"2026-12-25","name":"Christmas Day","nationalHoliday":true,'
   '"holidayTypes":["Public"]},{"date":"2026-12-26","name":"Regional holiday",'
   '"nationalHoliday":false,"holidayTypes":["Public"]}]','US',2026);
  expect(result.map((e)=>e.name),['Christmas Day']);
 });
 test('One provider outage does not hide other country holidays',()async{
  final client=MockClient((request)async{
   if(request.url.path.contains('/US/')){
    return http.Response('[{"date":"2026-11-26","name":"Thanksgiving",'
      '"nationalHoliday":true,"holidayTypes":["Public"]}]',200);
   }
   return http.Response('Unavailable',503);
  });
  final service=HolidayCalendarService(client:client);
  final result=await service.forYearDetailed(2026,{'US','EG','SA'});
  expect(result.unavailableCountries,['EG']);
  expect(result.days.any((d)=>d.country=='US'),true);
  expect(result.days.where((d)=>d.country=='SA').length,2);
 });
 test('Wrong-year entries cannot leak into calendar overlay',(){
  expect(HolidayCatalog.parseNager(
   '[{"date":"2027-01-01","name":"New Year","global":true,"types":["Public"]}]',
   'US',2026),isEmpty);
 });
}

import 'package:flutter_test/flutter_test.dart';
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
 test('Wrong-year entries cannot leak into calendar overlay',(){
  expect(HolidayCatalog.parseNager(
   '[{"date":"2027-01-01","name":"New Year","global":true,"types":["Public"]}]',
   'US',2026),isEmpty);
 });
}

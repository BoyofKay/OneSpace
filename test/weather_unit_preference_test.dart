import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/core/weather_unit_preference.dart';
void main(){
 test('Weather display converts Celsius to Fahrenheit, without mutating source',(){
  expect(WeatherUnitPreference.convert(0,true),32);
  expect(WeatherUnitPreference.convert(25,true),77);
  expect(WeatherUnitPreference.convert(20,false),20);
 });
}

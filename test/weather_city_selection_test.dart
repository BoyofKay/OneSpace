import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/core/device_weather_service.dart';
import 'package:onespace/core/shared_weather.dart';

void main(){
  test('city selection distinguishes same-name places by region and country',(){
    final city=WeatherCity.fromJson({
      'id':108410,'name':'Springfield','admin1':'Massachusetts',
      'country':'United States','latitude':42.1015,'longitude':-72.5898,
    });
    expect(city.label,'Springfield, Massachusetts, United States');
    expect(city.latitude,42.1015);
  });
  test('a malformed remote search result is safely ignored',(){
    expect(DeviceWeatherService.tryCity({'id':'oops'}),isNull);
    expect(DeviceWeatherService.tryCity({
      'id':2,'name':'x','latitude':94,'longitude':20,
    }),isNull);
  });
  test('forecast updates carry only public selected-city coordinates',(){
    final city=WeatherCity.fromJson({
      'id':777,'name':'Riyadh','country':'Saudi Arabia',
      'latitude':24.6877,'longitude':46.7219,
    });
    final weather=SharedWeather.fromResponse({
      'current':{'temperature_2m':32.1,'weather_code':1},
    },city:city.label,now:DateTime.utc(2026,11,13));
    final selected=SelectedCityWeather(
      current:weather,high:35,low:22,rainPct:10);
    final profile=selected.toProfile(city);
    expect(profile['weather_city_id'],777);
    expect(profile['weather_city_lat'],24.6877);
    expect(profile['city_name'],'Riyadh, Saudi Arabia');
    expect(profile['weather_high_c'],35);
    expect(profile['weather_rain_pct'],10);
    expect(profile['gps'],isNull);
    expect(profile['precise_location'],isNull);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/core/shared_weather.dart';

void main() {
  test('rounds weather coordinates to a coarse grid before network requests', () {
    expect(SharedWeather.coarseCoordinate(24.7136), 24.7);
    expect(SharedWeather.coarseCoordinate(46.6753), 46.7);
    expect(SharedWeather.coarseCoordinate(-75.386), -75.4);
  });

  test('only a general city and country are kept', () {
    expect(SharedWeather.cityFromParts(
      locality:'Riyadh', administrativeArea:'Riyadh Region',
      country:'Saudi Arabia'),'Riyadh, Saudi Arabia');
    expect(SharedWeather.cityFromParts(
      locality:'', administrativeArea:'Pennsylvania',
      country:'United States'),'Pennsylvania, United States');
    expect(SharedWeather.cityFromParts(), isNull);
  });

  test('models current weather without coordinates or postal address', () {
    final observation = DateTime.utc(2026,11,13,9);
    final value = SharedWeather.fromResponse({
      'latitude':24.7,
      'longitude':46.7,
      'current':{'temperature_2m':28.56,'weather_code':2},
    },city:'Riyadh, Saudi Arabia',now:observation);
    expect(value.temperatureC,28.6);
    expect(SharedWeather.condition(value.code),'Partly cloudy');
    final payload=value.toProfileUpdate();
    expect(payload['city_weather_shared'],isTrue);
    expect(payload['city_name'],'Riyadh, Saudi Arabia');
    expect(payload['latitude'],isNull);
    expect(payload['longitude'],isNull);
    expect(payload['street'],isNull);
    expect(payload['weather_updated_at'],observation.toIso8601String());
  });

  test('invalid weather data is rejected rather than shown as live', () {
    final now=DateTime.utc(2026);
    expect(() => SharedWeather.fromResponse({
      'current':{'temperature_2m':999,'weather_code':0},
    },city:null,now:now),throwsFormatException);
    expect(() => SharedWeather.fromResponse({
      'current':{'temperature_2m':22.4,'weather_code':-4},
    },city:null,now:now),throwsFormatException);
    expect(() => SharedWeather.fromResponse({
      'error':'provider unavailable',
    },city:null,now:now),throwsFormatException);
  });

  test('condition lookup covers common rainfall and storms', () {
    expect(SharedWeather.condition(0),'Clear sky');
    expect(SharedWeather.condition(63),'Rain');
    expect(SharedWeather.condition(95),'Thunderstorm');
    expect(SharedWeather.condition(3),'Overcast');
  });
}

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'shared_weather.dart';

/// Open-Meteo city search, based on GeoNames locality records.
class WeatherCity {
  const WeatherCity({
    required this.id,required this.name,required this.country,
    required this.latitude,required this.longitude,
    this.region,
  });
  final int id;
  final String name;
  final String country;
  final String? region;
  final double latitude;
  final double longitude;

  String get label => [
    name,
    if (region != null && region!.isNotEmpty) region!,
    country,
  ].where((p)=>p.trim().isNotEmpty).join(', ');

  factory WeatherCity.fromJson(Map<String,dynamic> value) {
    final lat=value['latitude'],lon=value['longitude'],id=value['id'];
    if (id is! num || lat is! num || lon is! num ||
        !lat.toDouble().isFinite || !lon.toDouble().isFinite ||
        lat < -90 || lat > 90 || lon < -180 || lon > 180) {
      throw const FormatException('Invalid weather city');
    }
    return WeatherCity(
      id:id.toInt(),name:value['name']?.toString()??'',
      country:value['country']?.toString()??'',
      region:value['admin1']?.toString(),
      latitude:lat.toDouble(),longitude:lon.toDouble(),
    );
  }
}

class SelectedCityWeather {
  const SelectedCityWeather({required this.current,required this.high,
    required this.low,required this.rainPct});
  final SharedWeather current;
  final double? high,low;
  final int? rainPct;
  Map<String,dynamic> toProfile(WeatherCity city) => {
    ...current.toProfileUpdate(),
    'weather_city_id':city.id,
    'weather_city_lat':city.latitude,
    'weather_city_lon':city.longitude,
    'weather_high_c':high,
    'weather_low_c':low,
    'weather_rain_pct':rainPct,
  };
}

class DeviceWeatherService {
  const DeviceWeatherService._();
  static DateTime? _lastAttempt;
  static bool _refreshing=false;

  static Future<List<WeatherCity>> search(String input) async {
    final name=input.trim();
    if (name.length<2 || name.length>100) return const [];
    final url=Uri.https('geocoding-api.open-meteo.com','/v1/search',{
      'name':name,'count':'12','language':'en','format':'json',
    });
    final response=await http.get(url).timeout(const Duration(seconds:12));
    if (response.statusCode!=200 || response.body.length>100000) {
      throw StateError('City search unavailable');
    }
    final json=jsonDecode(response.body);
    if (json is! Map) throw const FormatException('Invalid city search');
    final entries=json['results'];
    if (entries is! List) return const [];
    return [
      for (final entry in entries)
        if (entry is Map<String,dynamic>)
          tryCity(entry),
    ].whereType<WeatherCity>().toList();
  }

  static WeatherCity? tryCity(Map<String,dynamic> row) {
    try {return WeatherCity.fromJson(row);} catch (_) {return null;}
  }

  static Future<SelectedCityWeather> _forecast(WeatherCity city) async {
    final url=Uri.https('api.open-meteo.com','/v1/forecast',{
      'latitude':city.latitude.toStringAsFixed(4),
      'longitude':city.longitude.toStringAsFixed(4),
      'current':'temperature_2m,weather_code',
      'daily':'temperature_2m_max,temperature_2m_min,precipitation_probability_max',
      'timezone':'auto','forecast_days':'1',
    });
    final response=await http.get(url).timeout(const Duration(seconds:12));
    if (response.statusCode!=200 || response.body.length>50000) {
      throw StateError('Weather is temporarily unavailable');
    }
    final json=jsonDecode(response.body);
    if (json is! Map<String,dynamic>) throw const FormatException('Invalid forecast');
    final now=DateTime.now().toUtc();
    final weather=SharedWeather.fromResponse(json,city:city.label,now:now);
    final daily=json['daily'] as Map?;
    double? number(String key) {
      final entries=daily?[key];
      final n=entries is List && entries.isNotEmpty ? entries.first : null;
      return n is num && n.toDouble().isFinite ? n.toDouble() : null;
    }
    final rain=number('precipitation_probability_max');
    return SelectedCityWeather(
      current:weather,high:number('temperature_2m_max'),
      low:number('temperature_2m_min'),
      rainPct:rain?.round().clamp(0,100).toInt(),
    );
  }

  static Future<SelectedCityWeather> selectCity(
    SupabaseClient db,WeatherCity city,
  ) async {
    final id=db.auth.currentUser?.id;
    if(id==null)throw StateError('Sign in first');
    final result=await _forecast(city);
    await db.from('profiles').update(result.toProfile(city)).eq('id',id);
    _lastAttempt=DateTime.now();
    return result;
  }

  /// Turns off shared weather and clears the last readings; doesn't require
  /// permission changes and doesn't erase the person's chosen city.
  static Future<void> disable(SupabaseClient db) async {
    final id=db.auth.currentUser?.id;
    if(id==null)throw StateError('Sign in first');
    await db.from('profiles').update({
      'city_weather_shared':false,
      'temperature_c':null,'weather_code':null,
      'weather_updated_at':null,'weather_high_c':null,
      'weather_low_c':null,'weather_rain_pct':null,
      'weather_city_id':null,'weather_city_lat':null,
      'weather_city_lon':null,'city_name':null,
    }).eq('id',id);
  }

  static Future<bool> refreshIfEnabled(SupabaseClient db) async {
    if(_refreshing)return false;
    final now=DateTime.now();
    if(_lastAttempt!=null &&
       now.difference(_lastAttempt!)<const Duration(minutes:45)) { return false; }
    _refreshing=true;
    _lastAttempt=now;
    try {
      final id=db.auth.currentUser?.id;
      if(id==null)return false;
      final rows=await db.from('profiles').select(
        'weather_city_id,weather_city_lat,weather_city_lon,city_name,city_weather_shared',
      ).eq('id',id).limit(1);
      if(rows.isEmpty)return false;
      final p=rows.first;
      if(p['city_weather_shared']!=true)return false;
      final cityId=p['weather_city_id'];
      final lat=p['weather_city_lat'],lon=p['weather_city_lon'];
      if(cityId is! num || lat is! num || lon is! num)return false;
      final city=WeatherCity(
        id:cityId.toInt(),latitude:lat.toDouble(),longitude:lon.toDouble(),
        name:p['city_name']?.toString()??'Selected city',country:'',
      );
      final weather=await _forecast(city);
      await db.from('profiles').update({
        'temperature_c':weather.current.temperatureC,
        'weather_code':weather.current.code,
        'weather_updated_at':weather.current.observedAt.toIso8601String(),
        'weather_high_c':weather.high,'weather_low_c':weather.low,
        'weather_rain_pct':weather.rainPct,
      }).eq('id',id);
      return true;
    }catch(_){
      return false;
    }finally{_refreshing=false;}
  }
}

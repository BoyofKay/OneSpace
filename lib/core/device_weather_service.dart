import 'dart:convert';

import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'shared_weather.dart';

/// A single foreground, opt-in city/weather refresh. No tracking stream,
/// no background permission and no raw coordinates uploaded to Supabase.
class DeviceWeatherService {
  const DeviceWeatherService._();

  static DateTime? _lastAttempt;
  static bool _refreshing = false;

  static Future<void> disable(SupabaseClient db) async {
    final userId = db.auth.currentUser?.id;
    if (userId == null) throw StateError('Sign in first.');
    await db.from('profiles').update({
      'city_weather_shared': false,
      'city_name': null,
      'temperature_c': null,
      'weather_code': null,
      'weather_updated_at': null,
    }).eq('id', userId);
  }

  /// Enabling requires a deliberate explanation/consent on the calling screen,
  /// then the operating system's own location permission request.
  static Future<SharedWeather> enable(SupabaseClient db) async {
    final weather = await _fetch(requestPermission: true);
    await _save(db, weather);
    _lastAttempt = DateTime.now();
    return weather;
  }

  /// An already consenting user can be refreshed while the app is open.
  /// Never presents the Android permission prompt silently.
  static Future<bool> refreshIfEnabled(SupabaseClient db) async {
    if (_refreshing) return false;
    final now = DateTime.now();
    if (_lastAttempt != null &&
        now.difference(_lastAttempt!) < const Duration(minutes: 45)) {
      return false;
    }
    _refreshing = true;
    _lastAttempt = now;
    try {
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        // Once permission is revoked, no old shared location remains visible.
        await disable(db);
        return true;
      }
      await _save(db, await _fetch(requestPermission: false));
      return true;
    } catch (_) {
      // Weather outages don't block Today. A timestamp marks stale weather.
      return false;
    } finally {
      _refreshing = false;
    }
  }

  static Future<void> _save(SupabaseClient db, SharedWeather weather) async {
    final id = db.auth.currentUser?.id;
    if (id == null) throw StateError('Sign in first.');
    await db.from('profiles')
        .update(weather.toProfileUpdate()).eq('id',id);
  }

  static Future<SharedWeather> _fetch({
    required bool requestPermission,
  }) async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      throw StateError('Turn on phone Location services to show city/weather.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied && requestPermission) {
      permission = await Geolocator.requestPermission();
    }
    if (permission != LocationPermission.whileInUse &&
        permission != LocationPermission.always) {
      throw StateError('Location access was not granted.');
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.low,
        timeLimit: Duration(seconds: 18),
      ),
    );
    // Geocoding stays on the phone's platform. Never store street/postal code.
    String? city;
    try {
      final places = await Geocoding()
          .placemarkFromCoordinates(position.latitude,position.longitude)
          .timeout(const Duration(seconds: 8));
      if (places.isNotEmpty) {
        city = SharedWeather.cityFromParts(
          locality: places.first.locality,
          administrativeArea: places.first.administrativeArea,
          country: places.first.country,
        );
      }
    } catch (_) {
      // Weather can still work when device reverse-geocoding is unavailable.
    }

    // Send only an approximately 10km-grid coordinate to the provider.
    // The exact phone position is never sent to the weather provider.
    final lat = SharedWeather.coarseCoordinate(position.latitude);
    final lon = SharedWeather.coarseCoordinate(position.longitude);
    final uri = Uri.https('api.open-meteo.com','/v1/forecast',{
      'latitude': lat.toStringAsFixed(1),
      'longitude': lon.toStringAsFixed(1),
      'current': 'temperature_2m,weather_code',
      'timezone': 'auto',
      'forecast_days': '1',
    });
    final response = await http.get(uri)
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200 || response.body.length > 50000) {
      throw StateError('Weather service is temporarily unavailable.');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String,dynamic>) {
      throw const FormatException('Unexpected weather response.');
    }
    return SharedWeather.fromResponse(
      decoded,city:city,now:DateTime.now(),
    );
  }
}

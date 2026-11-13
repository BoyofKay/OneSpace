/// Sanitizes the city-level summary shared with the other partner.
/// GPS coordinates and exact street addresses must never appear in payloads.
class SharedWeather {
  const SharedWeather({
    required this.city,
    required this.temperatureC,
    required this.code,
    required this.observedAt,
  });

  final String? city;
  final double temperatureC;
  final int code;
  final DateTime observedAt;

  static String? cityFromParts({
    String? locality,
    String? administrativeArea,
    String? country,
  }) {
    String? safe(String? value) {
      final text = value?.trim() ?? '';
      if (text.isEmpty) return null;
      return text.replaceAll(RegExp(r'[\n\r\t]'), ' ')
          .substring(0, text.length > 60 ? 60 : text.length);
    }
    final place = safe(locality) ?? safe(administrativeArea);
    final nation = safe(country);
    if (place == null) return nation;
    final joined = nation == null || nation.toLowerCase() == place.toLowerCase()
        ? place : '$place, $nation';
    return joined.length <= 120 ? joined : joined.substring(0,120);
  }

  static double coarseCoordinate(double raw) =>
      (raw * 10).roundToDouble() / 10;

  static String condition(int code) => switch (code) {
    0 => 'Clear sky',
    1 || 2 => 'Partly cloudy',
    3 => 'Overcast',
    45 || 48 => 'Fog',
    51 || 53 || 55 || 56 || 57 => 'Drizzle',
    61 || 63 || 65 || 66 || 67 => 'Rain',
    71 || 73 || 75 || 77 => 'Snow',
    80 || 81 || 82 => 'Rain showers',
    85 || 86 => 'Snow showers',
    95 || 96 || 99 => 'Thunderstorm',
    _ => 'Weather',
  };

  static SharedWeather fromResponse(Map<String, dynamic> payload, {
    required String? city,
    required DateTime now,
  }) {
    final current = payload['current'];
    if (current is! Map) {
      throw const FormatException('No current weather returned.');
    }
    final tempRaw = current['temperature_2m'];
    final codeRaw = current['weather_code'];
    final temp = tempRaw is num ? tempRaw.toDouble() : null;
    final code = codeRaw is num ? codeRaw.toInt() : null;
    if (temp == null || !temp.isFinite || temp < -100 || temp > 65 ||
        code == null || code < 0 || code > 99) {
      throw const FormatException('Invalid weather readings.');
    }
    return SharedWeather(
      city: city,
      temperatureC: (temp * 10).roundToDouble() / 10,
      code: code,
      observedAt: now.toUtc(),
    );
  }

  Map<String, dynamic> toProfileUpdate() => {
    'city_weather_shared': true,
    'city_name': city,
    'temperature_c': temperatureC,
    'weather_code': code,
    'weather_updated_at': observedAt.toIso8601String(),
  };
}

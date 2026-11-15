import 'package:flutter/services.dart' show rootBundle;

/// R67: one airport, by its IATA code (the same 3 letters Google Flights uses).
class Airport {
  const Airport(this.code, this.city, this.name, this.country, {this.large = false});
  final String code, city, name, country;
  final bool large;

  /// "RUH · Riyadh" (short, for chips and titles).
  String get short => city.isEmpty ? code : '$code · $city';

  /// "Riyadh — King Khalid International Airport (RUH)".
  String get long => '${city.isEmpty ? name : '$city — $name'} ($code)';
}

/// R67: the bundled airport list (OurAirports, airports with scheduled
/// service). Loaded once, searched on the phone.
class Airports {
  Airports._();
  static List<Airport>? _all;
  static Map<String, Airport> _byCode = const {};

  static Future<List<Airport>> load() async {
    final ready = _all;
    if (ready != null) return ready;
    final text = await rootBundle.loadString('assets/airports.txt');
    final list = parse(text);
    _all = list;
    _byCode = {for (final a in list) a.code: a};
    return list;
  }

  /// Parses "CODE|city|name|country|l/m" lines (comments start with #).
  static List<Airport> parse(String text) {
    final out = <Airport>[];
    for (final line in text.split('\n')) {
      if (line.isEmpty || line.startsWith('#')) continue;
      final p = line.split('|');
      if (p.length < 4 || !RegExp(r'^[A-Z]{3}$').hasMatch(p[0])) continue;
      out.add(Airport(p[0], p[1], p[2], p[3], large: p.length > 4 && p[4] == 'l'));
    }
    return out;
  }

  /// The airport for a code, once [load] has run.
  static Airport? byCode(String? code) => code == null ? null : _byCode[code.trim().toUpperCase()];

  /// True for a 3-letter code (what we store for flight trips).
  static bool isCode(String? value) => value != null && RegExp(r'^[A-Z]{3}$').hasMatch(value.trim());

  /// "RUH · Riyadh" when known, otherwise the text as typed.
  static String label(String? value) {
    final v = (value ?? '').trim();
    return byCode(v)?.short ?? v;
  }

  /// Best matches for what was typed: exact code first, then city, then name.
  static List<Airport> search(List<Airport> all, String query, {int limit = 12}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    int rank(Airport a) {
      final code = a.code.toLowerCase(), city = a.city.toLowerCase(), name = a.name.toLowerCase();
      if (code == q) return 0;
      if (city == q) return a.large ? 1 : 2;
      if (city.startsWith(q)) return a.large ? 3 : 4;
      if (code.startsWith(q)) return 5;
      if (name.contains(q)) return a.large ? 6 : 7;
      if (city.contains(q)) return 8;
      return 99;
    }
    final hits = <(int, Airport)>[];
    for (final a in all) {
      final r = rank(a);
      if (r < 99) hits.add((r, a));
    }
    hits.sort((x, y) => x.$1 != y.$1 ? x.$1.compareTo(y.$1) : x.$2.code.compareTo(y.$2.code));
    return [for (final h in hits.take(limit)) h.$2];
  }
}

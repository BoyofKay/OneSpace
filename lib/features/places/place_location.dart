import 'dart:convert';

import 'package:http/http.dart' as http;
import '../../core/error_reporter.dart';

/// R78: where a place is on the map.
class PlaceLocation {
  const PlaceLocation(this.latitude, this.longitude, {this.label = ''});
  final double latitude, longitude;
  final String label;

  bool get valid => latitude.abs() <= 90 && longitude.abs() <= 180 && !(latitude == 0 && longitude == 0);
}

/// What a link shared from Google Maps / Apple Maps / Waze tells us.
class MapsLinkRules {
  const MapsLinkRules._();
  static final _number = r'(-?\d{1,3}\.\d+)';
  static final _patterns = [
    RegExp('!3d$_number!4d$_number'),            // google …/data=!3d24.7!4d46.6 (the pin itself)
    RegExp('@$_number,$_number'),                // google …/@24.7,46.6,17z
    RegExp('[?&](?:q|ll|query|daddr|sll)=$_number,(?:%20|\\+|\\s)?$_number'), // ?q=24.7,46.6 / apple ll=
    RegExp('geo:$_number,$_number'),
    RegExp('/search/$_number,(?:\\+)?$_number'),
  ];

  static bool isMapsLink(String url) {
    final u = url.toLowerCase();
    return u.contains('maps.app.goo.gl') || u.contains('goo.gl/maps') || u.contains('google.com/maps')
      || u.contains('maps.google.') || u.contains('maps.apple.') || u.contains('waze.com') || u.startsWith('geo:');
  }

  /// Coordinates written in the link, if any.
  static PlaceLocation? coordinates(String url) {
    final decoded = Uri.decodeFull(url);
    for (final p in _patterns) {
      final m = p.firstMatch(decoded);
      if (m == null) continue;
      final loc = PlaceLocation(double.parse(m.group(1)!), double.parse(m.group(2)!));
      if (loc.valid) return loc;
    }
    return null;
  }

  /// The place's name in a Google Maps link (…/maps/place/Café+Name/@…).
  static String? nameIn(String url) {
    final m = RegExp(r'/maps/place/([^/@?]+)').firstMatch(url);
    if (m == null) return null;
    final name = Uri.decodeComponent(m.group(1)!.replaceAll('+', ' ')).trim();
    return name.isEmpty || RegExp(r'^-?\d').hasMatch(name) ? null : name;
  }

  /// A shared Google Maps text is usually "Name\nAddress\nhttps://maps.app.goo.gl/…".
  static ({String name, String address, String link}) splitShare(String title, String note, String link) {
    final lines = [title, ...note.split('\n')].map((l) => l.trim())
      .where((l) => l.isNotEmpty && !l.startsWith('http') && l != link).toList();
    final name = lines.isEmpty ? '' : lines.first;
    final address = lines.length > 1 ? lines.sublist(1).join(', ') : '';
    return (name: name, address: address, link: link);
  }
}

/// Looks up coordinates: first in the link (following short links), then by
/// name with OpenStreetMap's search. Never throws.
class PlaceLocator {
  const PlaceLocator._();
  // OpenStreetMap policy: name the app and give a contact.
  static const _agent = {'User-Agent': 'OneSpaceApp/0.1 (+https://onespace.live; contact: support@onespace.live)'};

  static Future<String> expand(String url) async {
    var current = url;
    final client = http.Client();
    try {
      for (var i = 0; i < 5; i++) {
        final req = http.Request('GET', Uri.parse(current))..followRedirects = false;
        req.headers.addAll(_agent);
        final res = await client.send(req).timeout(const Duration(seconds: 8));
        final next = res.headers['location'];
        await res.stream.drain<void>();
        if (next == null || res.statusCode < 300 || res.statusCode >= 400) break;
        current = Uri.parse(current).resolve(next).toString();
      }
    } catch (_) {
      // Keep what we have.
    } finally {
      client.close();
    }
    return current;
  }

  static Future<PlaceLocation?> fromLink(String link) async {
    if (link.trim().isEmpty) return null;
    final direct = MapsLinkRules.coordinates(link);
    if (direct != null) return direct;
    if (!MapsLinkRules.isMapsLink(link)) return null;
    final full = await expand(link.trim());
    return MapsLinkRules.coordinates(full);
  }

  /// OpenStreetMap search ("Café Name, Riyadh, Saudi Arabia").
  static Future<PlaceLocation?> search(String query) async {
    final q = query.trim();
    if (q.length < 3) return null;
    try {
      final res = await http.get(Uri.https('nominatim.openstreetmap.org', '/search',
        {'q': q, 'format': 'jsonv2', 'limit': '1'}), headers: _agent).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) {
        ErrorReporter.report('Place search failed: HTTP ${res.statusCode}', StackTrace.current, context: 'place search');
        return null;
      }
      final list = jsonDecode(res.body) as List;
      if (list.isEmpty) return null;
      final hit = list.first as Map;
      final loc = PlaceLocation(double.parse(hit['lat'].toString()), double.parse(hit['lon'].toString()),
        label: (hit['display_name'] ?? '').toString());
      return loc.valid ? loc : null;
    } catch (_) {
      return null;
    }
  }

  /// Link first, then the name with city and country.
  static Future<PlaceLocation?> locate({String link = '', required String name, String city = '', String country = ''}) async {
    final fromLink = await PlaceLocator.fromLink(link);
    if (fromLink != null) return fromLink;
    final parts = [name, city, country].map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
    final exact = await search(parts.join(', '));
    if (exact != null) return exact;
    // A small café may not be known by name: fall back to the city.
    if (city.trim().isNotEmpty) return search([city, country].where((x) => x.trim().isNotEmpty).join(', '));
    return null;
  }
}

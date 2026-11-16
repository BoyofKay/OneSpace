import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/counters/counters_screen.dart';
import 'package:onespace/features/places/place_location.dart';
import 'package:onespace/features/share_in/share_intake_rules.dart';
import 'package:onespace/features/share_in/share_suggestions.dart';

void main() {
  test('coordinates in Google / Apple map links', () {
    final pin = MapsLinkRules.coordinates(
      'https://www.google.com/maps/place/Caf%C3%A9+Bateel/@24.6995,46.6837,17z/data=!3m1!4b1!4m6!3m5!1s0x0:0x0!8m2!3d24.69951!4d46.68625');
    expect(pin!.latitude, closeTo(24.69951, 1e-6));
    expect(pin.longitude, closeTo(46.68625, 1e-6));
    expect(MapsLinkRules.coordinates('https://maps.apple.com/?ll=21.4225,39.8262&q=Mecca')!.latitude, closeTo(21.4225, 1e-6));
    expect(MapsLinkRules.coordinates('https://maps.google.com/?q=30.0444,31.2357')!.longitude, closeTo(31.2357, 1e-6));
    expect(MapsLinkRules.coordinates('https://maps.app.goo.gl/AbCdEf'), isNull);
    expect(MapsLinkRules.nameIn('https://www.google.com/maps/place/Caf%C3%A9+Bateel/@24.69,46.68,17z'), 'Café Bateel');
  });

  test('a shared Google Maps text', () {
    final p = MapsLinkRules.splitShare('Café Bateel', 'King Fahd Rd, Riyadh\nhttps://maps.app.goo.gl/x', 'https://maps.app.goo.gl/x');
    expect(p.name, 'Café Bateel');
    expect(p.address, 'King Fahd Rd, Riyadh');
  });

  test('maps links suggest our places first', () {
    final s = ShareSuggestions.forShare(const IncomingShare(title: 'Café', link: 'https://maps.app.goo.gl/x', note: ''));
    expect(s.first, ShareDestination.placeWishlist);
    expect(s, contains(ShareDestination.placeVisited));
  });

  test('a yearly counter shows the day itself and its next anniversary', () {
    final points = CountersRules.fromRow({'id': 'w', 'title': 'Wedding', 'on_date': '2021-05-01', 'yearly': true,
      'created_at': '2021-04-01T00:00:00Z'});
    expect(points.length, 2);
    expect(points.first.yearly, isFalse);
    expect(points.first.original, 'yearly:w');
    final anniversary = points.last;
    expect(anniversary.id, 'yearly:w');
    expect(anniversary.target(DateTime(2026, 11, 16)), DateTime(2027, 5, 1));
    expect(anniversary.occasionLabel(DateTime(2026, 11, 16)), '6th anniversary');
    // The year from the last anniversary: 1 May 2026 → 1 May 2027.
    expect(anniversary.progress(DateTime(2026, 11, 16))!, closeTo(199 / 365, 0.01));
  });

  test('ordinals, age bars and progress', () {
    expect([1, 2, 3, 4, 11, 12, 13, 21, 22, 101].map(CountersRules.ordinal),
      ['1st', '2nd', '3rd', '4th', '11th', '12th', '13th', '21st', '22nd', '101st']);
    final today = DateTime(2026, 11, 16);
    expect(CountersRules.ageShare(DateTime(2020, 11, 16), DateTime(2020, 11, 16), today), 1.0);
    expect(CountersRules.ageShare(DateTime(2023, 11, 16), DateTime(2020, 11, 16), today), closeTo(.5, .01));
    final trip = CounterPoint(id: 't', title: 'Trip', date: DateTime(2026, 12, 16), start: DateTime(2026, 10, 17));
    expect(trip.progress(today)!, closeTo(30 / 60, .01));
    expect(CounterPoint(id: 'p', title: 'Past', date: DateTime(2020, 1, 1)).progress(today), isNull);
  });
}

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/trips/airports.dart';
import 'package:onespace/features/trips/flight_links.dart';

void main() {
  final all = Airports.parse('# x\nRUH|Riyadh|King Khalid International Airport|SA|l\n'
    'PHL|Philadelphia|Philadelphia International Airport|US|l\nULH|Al-Ula|Al-Ula International Airport|SA|m\n'
    'CAI|Cairo|Cairo International Airport|EG|l\n');
  bool known(String c) => all.any((a) => a.code == c);
  String? city(String name) {
    final hits = Airports.search(all, name, limit: 1);
    return hits.isEmpty ? null : hits.first.code;
  }

  test('airport search: code, city, name', () {
    expect(Airports.search(all, 'ruh').first.code, 'RUH');
    expect(Airports.search(all, 'phila').first.code, 'PHL');
    expect(Airports.search(all, 'ula').first.code, 'ULH');
    expect(Airports.search(all, ''), isEmpty);
    expect(Airports.isCode('RUH'), isTrue);
    expect(Airports.isCode('Riyadh'), isFalse);
  });

  test('Google Flights search link is filled in', () {
    final u = FlightLinks.googleFlights(from: 'RUH', to: 'PHL',
      depart: DateTime(2026, 12, 20), back: DateTime(2027, 1, 5), adults: 2, children: 1);
    expect(u.host, 'www.google.com');
    expect(u.queryParameters['q'],
      'Flights from RUH to PHL on 2026-12-20 through 2027-01-05 for 2 adults and 1 child');
    final one = FlightLinks.googleFlights(from: 'RUH', to: 'CAI', depart: DateTime(2026, 12, 1),
      back: DateTime(2026, 12, 9), oneWay: true);
    expect(one.queryParameters['q'], 'Flights from RUH to CAI on 2026-12-01 one way for 1 adult');
  });

  test('reads a Google Flights tfs link', () {
    // A minimal protobuf-like payload: date, then airports, for two legs.
    final bytes = <int>[0x1a, 0x1e, 0x12, 0x0a, ...latin1.encode('2026-12-20'), 0x6a, 0x07, 0x08, 0x01,
      0x12, 0x03, ...latin1.encode('RUH'), 0x72, 0x07, 0x08, 0x01, 0x12, 0x03, ...latin1.encode('PHL'),
      0x1a, 0x1e, 0x12, 0x0a, ...latin1.encode('2027-01-05'), 0x6a, 0x07, 0x08, 0x01,
      0x12, 0x03, ...latin1.encode('PHL'), 0x72, 0x07, 0x08, 0x01, 0x12, 0x03, ...latin1.encode('RUH')];
    final tfs = base64Url.encode(bytes).replaceAll('=', '');
    final d = FlightLinks.parse('https://www.google.com/travel/flights/booking?tfs=$tfs&hl=en');
    expect(d.origin, 'RUH');
    expect(d.destination, 'PHL');
    expect(d.departure, DateTime(2026, 12, 20));
    expect(d.returnOn, DateTime(2027, 1, 5));
    expect(d.provider, 'Google Flights');
  });

  test('reads shared flight text', () {
    final d = FlightLinks.parse(
      'Saudia flight from Riyadh to Philadelphia · Sat, Dec 20 – Mon, Jan 5 · 1 stop · SAR 4,250 '
      'https://www.google.com/travel/flights/s/abc123',
      today: DateTime(2026, 11, 16), isAirport: known, cityCode: city);
    expect(d.origin, 'RUH');
    expect(d.destination, 'PHL');
    expect(d.departure, DateTime(2026, 12, 20));
    expect(d.returnOn, DateTime(2027, 1, 5));
    expect(d.airline, 'Saudia');
    expect(d.currency, 'SAR');
    expect(d.price, 4250);
    expect(d.stops, 1);
    expect(d.title, 'RUH → PHL · Saudia');
  });

  test('codes in the text and a dollar price', () {
    final d = FlightLinks.parse('RUH to CAI nonstop, flynas, \$312 on 2026-12-01',
      isAirport: known);
    expect(d.origin, 'RUH');
    expect(d.destination, 'CAI');
    expect(d.stops, 0);
    expect(d.currency, 'USD');
    expect(d.price, 312);
    expect(d.airline, 'flynas');
    expect(d.departure, DateTime(2026, 12, 1));
  });
}

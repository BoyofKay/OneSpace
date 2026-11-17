import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/counters/counter_sources.dart';
import 'package:onespace/features/settings/special_dates.dart';

void main() {
  test('dates are only prepared as counter drafts, never auto-created', () {
    final event = CounterSource.event({
      'id': 'event-1', 'title': 'Concert',
      'event_date': '2026-12-20', 'recurrence': 'none',
      'visibility': 'private',
    });
    expect(event, isNotNull);
    expect(event!.title, 'Concert');
    expect(event.date, DateTime(2026, 12, 20));
    expect(event.prefill['visibility'], 'private');
    expect(event.prefill['on_date'], '2026-12-20');
    expect(CounterSource.event({'id': 'no-date', 'title': 'Undated'}), isNull);
    expect(CounterSource.trip({'id': 'no-date', 'title': 'Tentative'}), isNull);
    expect(CounterSource.flight({'id': 'no-date'}), isNull);
  });

  test('annual occasion and special date remain annual only when chosen', () {
    final occasion = CounterSource.occasion({
      'id': 'occasion-1', 'title': 'Our anniversary',
      'occasion_on': '2020-04-23', 'annual': true, 'visibility': 'shared',
    });
    expect(occasion!.prefill['yearly'], true);
    expect(occasion.prefill['category'], 'love');
    final special = CounterSource.special(
      const SpecialDate(id: 'birthday-1', kind: 'birthday',
        personId: 'anyone', month: 1, day: 2, year: 1970), null);
    expect(special.prefill['yearly'], true);
    expect(special.prefill['on_date'], '1970-01-02');
  });

  test('trip and flight copies have departure dates, and flight privacy is inherited', () {
    final trip = CounterSource.trip({
      'id': 'trip-1', 'title': 'Weekend away',
      'start_on': '2026-12-24', 'visibility': 'shared',
    });
    final flight = CounterSource.flight({
      'id': 'flight-1', 'title': 'LHR - JFK',
      'departure_on': '2026-12-24',
    }, shared: false);
    expect(trip!.prefill['on_date'], '2026-12-24');
    expect(flight!.prefill['visibility'], 'private');
    expect(flight.prefill['yearly'], false);
    final itinerary = CounterSource.itinerary({
      'id': 'itinerary-1', 'title': 'Morning departure',
      'kind': 'flight', 'local_date': '2026-12-26',
    });
    expect(itinerary!.prefill['on_date'], '2026-12-26');
    expect(itinerary.prefill['category'], 'travel');
  });

  test('no reunion dates exist in source when those values are blank', () {
    expect(CounterSource.meeting({'last_met_on': null}, 'last'), isNull);
    expect(CounterSource.meeting({'next_meet_on': null}, 'next'), isNull);
  });
}

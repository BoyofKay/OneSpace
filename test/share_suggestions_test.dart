import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/share_in/share_intake_rules.dart';
import 'package:onespace/features/share_in/share_suggestions.dart';

void main() {
  IncomingShare share(String text) => ShareIntakeRules.parse(text: text);

  test('B-16: an Amazon link suggests gift idea and Activity option', () {
    final s = share('Look https://www.amazon.com/dp/B0TEST heater');
    expect(ShareSuggestions.kindOf(s), ShareContentKind.shop);
    expect(ShareSuggestions.forShare(s).take(2),
        [ShareDestination.giftIdea, ShareDestination.activityOption]);
  });

  test('media, travel and maps links', () {
    expect(ShareSuggestions.forShare(share('https://youtu.be/abc')).first,
        ShareDestination.experience);
    expect(ShareSuggestions.forShare(share('https://www.booking.com/hotel/x')).first,
        ShareDestination.trip);
    expect(ShareSuggestions.forShare(share(
        'RUH to PHL https://www.google.com/travel/flights/booking?tfs=abc')).first,
        ShareDestination.flightOption);
    expect(ShareSuggestions.kindOf(share('https://www.skyscanner.net/transport/flights/ruh/phl/')),
        ShareContentKind.flight);
    expect(ShareSuggestions.kindOf(share('https://maps.app.goo.gl/xyz')),
        ShareContentKind.maps);
  });

  test('unknown site and plain text', () {
    expect(ShareSuggestions.forShare(share('https://example.org/article')).first,
        ShareDestination.newActivity);
    expect(ShareSuggestions.forShare(share('Call the plumber tomorrow at 5pm')).first,
        ShareDestination.reminder);
    expect(ShareSuggestions.forShare(share('We may need more shelves')).first,
        ShareDestination.note);
  });

  test('More… lists every other destination once', () {
    final s = share('https://www.amazon.com/dp/B0TEST');
    final all = [...ShareSuggestions.forShare(s), ...ShareSuggestions.more(s)];
    expect(all.toSet().length, ShareDestination.values.length);
  });

  test('items older than 30 days are flagged gently', () {
    final now = DateTime(2026, 11, 15);
    expect(ShareSuggestions.isStale(DateTime(2026, 10, 1), now), isTrue);
    expect(ShareSuggestions.isStale(DateTime(2026, 11, 1), now), isFalse);
  });
}

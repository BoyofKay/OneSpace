import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/core/status_look.dart';

void main() {
  test('spec 2.6 status families', () {
    for (final s in ['completed', 'celebrated', 'enjoyed', 'purchased', 'booked', 'registered']) {
      expect(StatusLook.isCompleted(s), isTrue, reason: s);
    }
    expect(StatusLook.isCancelled('cancelled'), isTrue);
    expect(StatusLook.isMissed('missed'), isTrue);
    expect(StatusLook.isFinal('planning'), isFalse);
    expect(StatusLook.mark('open'), isNull);
    expect(StatusLook.mark('completed'), isNotNull);
  });
}

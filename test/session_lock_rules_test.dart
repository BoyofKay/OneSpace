import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/auth/session_lock_rules.dart';

void main() {
  final t0 = DateTime.utc(2026, 11, 12, 10);
  test('Five minutes without user input requires unlock', () {
    expect(SessionLockRules.idleExpired(t0,
        t0.add(const Duration(minutes: 4, seconds: 59))), isFalse);
    expect(SessionLockRules.idleExpired(t0,
        t0.add(const Duration(minutes: 5))), isTrue);
  });
  test('A return after 30 background seconds requires unlock', () {
    expect(SessionLockRules.backgroundExpired(t0,
        t0.add(const Duration(seconds: 29))), isFalse);
    expect(SessionLockRules.backgroundExpired(t0,
        t0.add(const Duration(seconds: 30))), isTrue);
  });
}

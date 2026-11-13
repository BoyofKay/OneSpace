import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/auth/session_lock_rules.dart';

void main() {
  final t0 = DateTime.utc(2026, 11, 12, 10);
  test('Thirty minutes without user input requires unlock', () {
    expect(SessionLockRules.idleExpired(t0,
        t0.add(const Duration(minutes: 29, seconds: 59))), isFalse);
    expect(SessionLockRules.idleExpired(t0,
        t0.add(const Duration(minutes: 30))), isTrue);
  });
  test('A return after 5 background minutes requires unlock', () {
    expect(SessionLockRules.backgroundExpired(t0,
        t0.add(const Duration(minutes: 4, seconds: 59))), isFalse);
    expect(SessionLockRules.backgroundExpired(t0,
        t0.add(const Duration(minutes: 5))), isTrue);
  });
}

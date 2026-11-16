import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/notifications/notification_context.dart';
import 'package:onespace/features/connect/gesture_pool_rules.dart';

void main() {
  test('notification categories', () {
    expect(NotificationCategories.of({'kind': 'gesture'}), 'love');
    expect(NotificationCategories.of({'kind': 'message', 'object_kind': 'activity'}), 'talk');
    expect(NotificationCategories.of({'kind': 'created', 'object_kind': 'memory'}), 'memories');
    expect(NotificationCategories.of({'kind': 'created', 'object_kind': 'trip'}), 'plans');
    expect(NotificationCategories.matches({'read_at': null}, 'unread'), isTrue);
  });

  test('day groups', () {
    final now = DateTime(2026, 11, 16, 9);
    expect(notificationDay(DateTime(2026, 11, 16, 1).toUtc().toIso8601String(), now: now), 'Today');
    expect(notificationDay(DateTime(2026, 11, 15, 20).toUtc().toIso8601String(), now: now), 'Yesterday');
    expect(notificationDay(DateTime(2026, 11, 12).toUtc().toIso8601String(), now: now), 'Earlier this week');
    expect(notificationDay(DateTime(2026, 10, 1).toUtc().toIso8601String(), now: now), 'Earlier');
  });

  test('living together: no "from miles away" messages are picked', () {
    final pool = GesturePoolRules.activeMessages(kind: 'goodnight', builtIn: const [
      'A goodnight hug from miles away.',
      'Sweet dreams. You are loved more than words.',
      'Morning hugs, delivered across the distance.',
    ], overrides: const [], custom: const [], together: true);
    expect(pool, ['Sweet dreams. You are loved more than words.']);
    expect(GesturePoolRules.activeMessages(kind: 'x', builtIn: const ['A goodnight hug from miles away.'],
      overrides: const [], custom: const []).length, 1);
  });
}

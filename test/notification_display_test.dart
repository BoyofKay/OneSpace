import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onespace/features/notifications/notifications_screen.dart';

void main() {
  group('notificationAge', () {
    final now = DateTime(2026, 11, 15, 13, 0);
    String age(DateTime at) =>
        notificationAge(at.toUtc().toIso8601String(), now: now);

    test('recent times', () {
      expect(age(now.subtract(const Duration(seconds: 20))), 'Just now');
      expect(age(now.subtract(const Duration(minutes: 5))), '5 min ago');
      expect(age(now.subtract(const Duration(hours: 3))), '3 h ago');
    });

    test('days and older dates', () {
      expect(age(DateTime(2026, 11, 14, 9, 0)), 'Yesterday');
      expect(age(DateTime(2026, 11, 11, 9, 0)), '4 days ago');
      expect(age(DateTime(2026, 10, 2, 9, 0)), '2/10/2026');
    });

    test('missing or broken values give no label', () {
      expect(notificationAge(null), '');
      expect(notificationAge('not a date'), '');
    });
  });

  group('notificationIcon', () {
    test('chat messages and changes', () {
      expect(notificationIcon({'kind': 'message', 'object_kind': 'activity'}),
          Icons.chat_bubble_outline);
      expect(notificationIcon({'kind': 'change', 'action': 'moved', 'object_kind': 'calendar'}),
          Icons.event_repeat_outlined);
      expect(notificationIcon({'kind': 'change', 'action': 'removed', 'object_kind': 'memory'}),
          Icons.delete_outline);
    });

    test('new items follow their type', () {
      expect(notificationIcon({'kind': 'created', 'object_kind': 'task'}),
          Icons.checklist_outlined);
      expect(notificationIcon({'kind': 'created', 'object_kind': 'memory'}),
          Icons.photo_album_outlined);
      expect(notificationIcon({'kind': 'reminder', 'object_kind': 'reminder'}),
          Icons.alarm_outlined);
    });
  });
}

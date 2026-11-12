import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/plans/plans_screen.dart';

void main() {
  group('Shared task model', () {
    test('maps persisted task fields correctly', () {
      final task = SharedTask.fromMap({
        'id': 'task-one',
        'title': 'Plan our next call',
        'priority': 'high',
        'status': 'open',
        'target_date': '2026-11-21',
      });
      expect(task.id, 'task-one');
      expect(task.title, 'Plan our next call');
      expect(task.priority, TaskPriority.high);
      expect(task.status, TaskStatus.open);
      expect(task.targetDate, '2026-11-21');
    });

    test('recognizes completed and cancelled history', () {
      final complete = SharedTask.fromMap({
        'id': '2',
        'title': 'Book dinner',
        'priority': 'normal',
        'status': 'completed',
        'target_date': null,
      });
      final cancelled = SharedTask.fromMap({
        'id': '3',
        'title': 'Old plan',
        'priority': 'low',
        'status': 'cancelled',
        'target_date': null,
      });
      expect(complete.status, TaskStatus.completed);
      expect(cancelled.status, TaskStatus.cancelled);
    });
  });
}

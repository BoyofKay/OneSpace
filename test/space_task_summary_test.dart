import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/spaces/space_task_summary.dart';

void main() {
  test('Home task totals respect private and shared scopes', () {
    final summary = SpaceTaskSummary.fromRows([
      {'visibility': 'shared', 'status': 'open', 'assigned_to': 'me'},
      {'visibility': 'shared', 'status': 'open', 'assigned_to': 'other'},
      {'visibility': 'shared', 'status': 'completed', 'assigned_to': 'me'},
      {'visibility': 'private', 'status': 'open', 'assigned_to': null, 'created_by': 'me'},
      {'visibility': 'private', 'status': 'open', 'assigned_to': null, 'created_by': 'other'},
      {'visibility': 'private', 'status': 'cancelled', 'assigned_to': null},
      {'visibility': 'shared', 'status': 'cancelled', 'assigned_to': null},
    ], 'me');

    expect(summary.openShared, 2);
    expect(summary.assignedToMe, 1);
    expect(summary.myPrivate, 1);
    expect(summary.completedShared, 1);
  });

  test('Empty space has zero task counts', () {
    final summary = SpaceTaskSummary.fromRows([], 'me');
    expect(summary.openShared, 0);
    expect(summary.myPrivate, 0);
    expect(summary.assignedToMe, 0);
    expect(summary.completedShared, 0);
  });
}

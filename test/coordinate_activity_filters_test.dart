import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/coordinate/coordinate_activity_filters.dart';

void main() {
  final now = DateTime(2026, 11, 13);
  Map<String, dynamic> item(
      String title, String stage, String priority, String? due,
      {String? archivedAt}) => {
    'title': title,
    'body': 'Important details',
    'stage': stage,
    'priority': priority,
    'due_on': due,
    'archived_at': archivedAt,
  };

  test('active and finished are mutually exclusive', () {
    final items = [
      item('Research', 'exploring', 'normal', null),
      item('Ordered', 'purchased', 'normal', null),
      item('Done', 'completed', 'normal', null),
      item('Cancelled', 'cancelled', 'normal', null),
    ];
    expect(CoordinateActivityFilters.count(
        items, CoordinateActivityView.active, now), 2);
    expect(CoordinateActivityFilters.count(
        items, CoordinateActivityView.finished, now), 2);
  });

  test('attention means high priority or due within a week', () {
    final items = [
      item('Urgent', 'exploring', 'urgent', null),
      item('Soon', 'exploring', 'normal', '2026-11-20'),
      item('Overdue', 'comparing', 'normal', '2026-11-01'),
      item('Later', 'exploring', 'normal', '2026-11-21'),
      item('Finished', 'completed', 'urgent', '2026-11-13'),
      item('Hidden', 'exploring', 'urgent', null,
        archivedAt: '2026-11-10T10:00:00Z'),
    ];
    final result = CoordinateActivityFilters.visible(
      items, CoordinateActivityView.attention, '', now);
    expect(result.map((e) => e['title']).toList(),
        ['Urgent', 'Soon', 'Overdue']);
  });

  test('searches Activity title and body case-insensitively', () {
    final items = [
      item('Gymnastics', 'exploring', 'normal', null),
      item('Buy heater', 'exploring', 'normal', null),
    ];
    expect(CoordinateActivityFilters.visible(
        items, CoordinateActivityView.active, '  HEATER ', now).length, 1);
    expect(CoordinateActivityFilters.visible(
        items, CoordinateActivityView.active, 'DETAILS', now).length, 2);
  });

  test('all includes archived while active and finished do not', () {
    final items = [
      item('Archived', 'completed', 'normal', null,
          archivedAt: '2026-11-12T10:00:00Z'),
    ];
    expect(CoordinateActivityFilters.count(
        items, CoordinateActivityView.all, now), 1);
    expect(CoordinateActivityFilters.count(
        items, CoordinateActivityView.finished, now), 0);
  });
}

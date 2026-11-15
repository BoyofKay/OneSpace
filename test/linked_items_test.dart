import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/core/linked_items.dart';

void main() {
  test('parses linked items, drops unknown kinds, sorts by type', () {
    final items = LinkedItem.parseAll([
      {'kind': 'reminder', 'id': 'r1', 'title': 'Leave for the airport', 'link_id': 'l1'},
      {'kind': 'trip', 'id': 't1', 'title': 'Paris', 'link_id': 'l2'},
      {'kind': 'goal', 'id': 'g1', 'title': 'Old goal'},
      {'kind': 'task', 'id': 'k1', 'title': '', 'link_id': null},
    ]);
    expect(items.map((i) => i.kind), [LinkKind.trip, LinkKind.reminder, LinkKind.task]);
    expect(items.last.title, 'To-do');
    expect(items.last.linkId, isNull);
  });

  test('create from this: common actions first, then type-specific', () {
    expect(CreateFromAction.forKind(LinkKind.trip).map((a) => a.label), [
      'Create reminder', 'Add to calendar', 'Make a to-do', 'Add a note',
      'Leave-for-airport reminder', 'Online check-in reminder']);
    expect(CreateFromAction.forKind(LinkKind.activity).last, CreateFromAction.turnIntoTrip);
    expect(CreateFromAction.forKind(LinkKind.occasion).last, CreateFromAction.preparation);
    expect(CreateFromAction.forKind(LinkKind.note).length, 4);
  });

  test('B-17: trip reminders are pre-filled with title and date', () {
    final start = DateTime(2026, 12, 3);
    expect(CreateFromAction.leaveForAirport.titleFor('Paris'), 'Leave for the airport · Paris');
    expect(CreateFromAction.leaveForAirport.dueFor(start), DateTime(2026, 12, 3, 6));
    expect(CreateFromAction.checkIn.dueFor(start), DateTime(2026, 12, 2, 9));
    expect(CreateFromAction.preparation.dueFor(start), DateTime(2026, 11, 26, 9));
    expect(CreateFromAction.reminder.dueFor(null), isNull);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/coordinate/new_activity_screen.dart';
import 'package:onespace/features/quick_add/quick_add_sheet.dart';

void main() {
  test('an empty draft is never saved', () {
    expect(const NewActivityDraft(title: '   ').canSave, isFalse);
    expect(const NewActivityDraft(title: 'Heater').canSave, isTrue);
  });

  test('insert carries visibility and optional date', () {
    final row = NewActivityDraft(title: ' Heater ', details: 'x',
        shared: false, dueOn: DateTime(2026, 11, 20)).toInsert('s1');
    expect(row, {'space_id': 's1', 'title': 'Heater', 'body': 'x',
        'visibility': 'private', 'due_on': '2026-11-20'});
    expect(const NewActivityDraft(title: 'A').toInsert('s').containsKey('due_on'), isFalse);
  });

  test('QA personal Activity has account ownership, never couple space', () {
    const personal = NewActivityDraft(title: 'Private plan', shared: false);
    final own = personal.toInsert('relationship-space', ownerId: 'account-id');
    expect(own['private_space_id'], 'account-id');
    expect(own.containsKey('space_id'), isFalse);
    expect(own['visibility'], 'private');

    const together = NewActivityDraft(title: 'Our plan', shared: true);
    final pair = together.toInsert('relationship-space', ownerId: 'account-id');
    expect(pair['space_id'], 'relationship-space');
    expect(pair.containsKey('private_space_id'), isFalse);
  });

  test('purpose outline never overwrites typed details', () {
    expect(NewActivityDraft.detailsFor(ActivityPurpose.buy, ''),
        ActivityPurpose.buy.outline);
    expect(NewActivityDraft.detailsFor(ActivityPurpose.decide, ActivityPurpose.buy.outline),
        ActivityPurpose.decide.outline);
    expect(NewActivityDraft.detailsFor(ActivityPurpose.decide, 'my own words'),
        'my own words');
  });

  test('purposes pre-add open steps; a plain note adds none', () {
    final rows = ActivityPurpose.planEvent.sectionsFor('a1');
    expect(rows.length, ActivityPurpose.planEvent.steps.length);
    expect(rows.first, {'activity_id': 'a1', 'kind': 'step',
        'label': 'Set the date and place', 'payload': {'value': '', 'status': 'open'}});
    expect(ActivityPurpose.note.sectionsFor('a1'), isEmpty);
  });

  test('quick add offers the same places as share-in (R71), in order', () {
    expect(QuickAddKind.values.map((k) => k.label).toList(), [
      'Reminder', 'To-do', 'Event', 'Note', 'Something to research',
      'Gift idea', 'Trip', 'Story', 'Daily feeling', 'Letter']);
  });
}

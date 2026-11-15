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

  test('purpose outline never overwrites typed details', () {
    expect(NewActivityDraft.detailsFor(ActivityPurpose.buy, ''),
        ActivityPurpose.buy.outline);
    expect(NewActivityDraft.detailsFor(ActivityPurpose.decide, ActivityPurpose.buy.outline),
        ActivityPurpose.decide.outline);
    expect(NewActivityDraft.detailsFor(ActivityPurpose.decide, 'my own words'),
        'my own words');
  });

  test('quick add offers the eight spec choices in order', () {
    expect(QuickAddKind.values.map((k) => k.label).toList(), [
      'Reminder', 'To-do', 'Event', 'Note', 'Something to research',
      'Gift idea', 'Trip', 'Memory']);
  });
}

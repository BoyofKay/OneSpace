import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/connect/experience_picker_rules.dart';

Map<String, dynamic> item(String id, String name, {
  String category = 'movie',
  String status = 'suggested',
  String? date,
  String? archived,
}) => {
  'id': id, 'title': name, 'category': category, 'status': status,
  'planned_on': date, 'archived_at': archived,
};

void main() {
  test('only active unfinished records appear, scoped to category', () {
    final rows = [
      item('1', 'Movie'),
      item('2', 'Finished', status: 'enjoyed'),
      item('3', 'Archived', archived: '2026-11-01T00:00:00Z'),
      item('4', 'Book', category: 'book'),
      item('5', '   '),
    ];
    expect(ExperiencePickerRules.shortlist(rows).map((x) => x['id']),
        ['4', '1']);
    expect(ExperiencePickerRules.shortlist(rows, category: 'movie')
        .map((x) => x['id']), ['1']);
  });

  test('planned ideas sort by date before suggestions', () {
    final rows = [
      item('a', 'Alpha'),
      item('b', 'Future', status: 'planned', date: '2026-12-10'),
      item('c', 'Soon', status: 'planned', date: '2026-11-18'),
      item('d', 'Unscheduled', status: 'planned'),
    ];
    expect(ExperiencePickerRules.shortlist(rows).map((x) => x['id']),
        ['c', 'b', 'd', 'a']);
    expect(rows.first['id'], 'a', reason: 'must not mutate caller list');
  });

  test('a pick is reproducible across local time zones', () {
    final rows = ExperiencePickerRules.shortlist([
      item('a', 'A'), item('b', 'B'), item('c', 'C'),
    ]);
    final sameInstantUtc = DateTime.utc(2026, 11, 14, 23, 0);
    final local = sameInstantUtc.toLocal();
    expect(ExperiencePickerRules.pick(rows, now: sameInstantUtc)?['id'],
        ExperiencePickerRules.pick(rows, now: local)?['id']);
    final base = ExperiencePickerRules.pick(rows, now: sameInstantUtc);
    final following = ExperiencePickerRules.pick(rows,
        now: sameInstantUtc, offset: 1);
    expect(following?['id'], isNot(base?['id']));
    expect(ExperiencePickerRules.pick(rows, now: sameInstantUtc, offset: 3),
        same(base));
  });

  test('empty list is safe and counts ignore archived records', () {
    expect(ExperiencePickerRules.pick([]), isNull);
    expect(ExperiencePickerRules.count([
      item('a', 'A', status: 'planned'),
      item('b', 'B', status: 'planned', archived: '2026-11-10'),
      item('c', 'C', status: 'enjoyed'),
    ], 'planned'), 1);
  });

  test('completion actions reflect the media type', () {
    expect(ExperiencePickerRules.completionAction('movie'), 'Mark watched');
    expect(ExperiencePickerRules.completionAction('show'), 'Mark watched');
    expect(ExperiencePickerRules.completionAction('music'), 'Mark listened');
    expect(ExperiencePickerRules.completionAction('book'), 'Mark read');
    expect(ExperiencePickerRules.completionAction('game'), 'Mark played');
    expect(ExperiencePickerRules.completionAction('other'), 'Mark enjoyed');
    expect(ExperiencePickerRules.completionAction('future-type'), 'Mark enjoyed');
    expect(ExperiencePickerRules.completionState('book'), 'Read');
    expect(ExperiencePickerRules.completionState('show'), 'Watched');
  });

  test('date-only formatting does not turn the chosen day into UTC', () {
    expect(ExperiencePickerRules.dateOnly(DateTime(2026, 1, 2, 23, 59)),
        '2026-01-02');
    expect(ExperiencePickerRules.dateOnly(DateTime(2031, 12, 31)),
        '2031-12-31');
  });
}

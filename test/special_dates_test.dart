import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/settings/special_dates.dart';

void main() {
  const kay = SpecialDate(id: '1', kind: 'birthday', personId: 'k', month: 3, day: 14, year: 1985);
  const us = SpecialDate(id: '2', kind: 'anniversary', month: 6, day: 1, year: 2019);
  const leap = SpecialDate(id: '3', kind: 'custom', title: 'Leap day', month: 2, day: 29);
  String name(String? id) => id == 'k' ? 'Kandice' : '';

  test('labels', () {
    expect(SpecialDateRules.label(kay, name), "Kandice's birthday");
    expect(SpecialDateRules.label(const SpecialDate(id: 'x', kind: 'birthday', personId: 'me', month: 1, day: 2), name), 'My birthday');
    expect(SpecialDateRules.label(us, name), 'Our anniversary');
    expect(SpecialDateRules.label(leap, name), 'Leap day');
  });

  test('next date and milestones', () {
    final today = DateTime(2026, 11, 16);
    expect(SpecialDateRules.nextOn(kay, today), DateTime(2027, 3, 14));
    expect(SpecialDateRules.milestone(kay, DateTime(2027, 3, 14)), 'turns 42');
    expect(SpecialDateRules.milestone(us, DateTime(2027, 6, 1)), '8 years');
    expect(SpecialDateRules.nextOn(leap, today), DateTime(2027, 2, 28));
    expect(SpecialDateRules.milestone(leap, DateTime(2027, 2, 28)), isNull);
    expect(SpecialDateRules.occasionKind(us), 'anniversary');
  });
}

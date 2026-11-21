import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/calendar/couple_day_view.dart';

void main() {
  test('overlapping events for one person sit side by side in their lane', () {
    final l = CoupleDayLanes.assign([
      (top: 0, bottom: 100, col: 0),
      (top: 50, bottom: 150, col: 0),
      (top: 200, bottom: 250, col: 0),
    ]);
    expect(l[0], (left: 0.0, width: .25));
    expect(l[1], (left: .25, width: .25));
    expect(l[2], (left: 0.0, width: .5));
  });
  test('my events and my partner\'s events keep their own lanes', () {
    final l = CoupleDayLanes.assign([
      (top: 0, bottom: 100, col: 0),
      (top: 0, bottom: 100, col: 1),
    ]);
    expect(l[0], (left: 0.0, width: .5));
    expect(l[1], (left: .5, width: .5));
  });
  test('only me left, both of us in the middle, only partner right', () {
    final l = CoupleDayLanes.assign([
      (top: 0, bottom: 100, col: -1),
      (top: 20, bottom: 80, col: 0),
      (top: 40, bottom: 120, col: 1),
    ]);
    expect(l[1].left, 0);
    expect(l[1].width, closeTo(1 / 3, 1e-9));
    expect(l[0].left, closeTo(1 / 3, 1e-9));
    expect(l[0].width, closeTo(1 / 3, 1e-9));
    expect(l[2].left, closeTo(2 / 3, 1e-9));
  });
  test('both of us with only my event takes the rest of the width', () {
    final l = CoupleDayLanes.assign([
      (top: 0, bottom: 100, col: -1),
      (top: 20, bottom: 80, col: 0),
    ]);
    expect(l[1].width, closeTo(1 / 3, 1e-9));
    expect(l[0].left, closeTo(1 / 3, 1e-9));
    expect(l[0].left + l[0].width, closeTo(1, 1e-9));
  });
  test('a lone both-of-us event spans the whole day area', () {
    final l = CoupleDayLanes.assign([(top: 0, bottom: 100, col: -1)]);
    expect(l[0], (left: 0.0, width: 1.0));
  });
  test('one person space uses the whole width', () {
    final l = CoupleDayLanes.assign([(top: 0, bottom: 100, col: 0)], columns: 1);
    expect(l[0], (left: 0.0, width: 1.0));
  });
}

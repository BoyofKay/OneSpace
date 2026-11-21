import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/calendar/couple_day_view.dart';

void main() {
  test('overlapping events in one column sit side by side', () {
    final l = CoupleDayLanes.assign([
      (top: 0, bottom: 100, col: 0),
      (top: 50, bottom: 150, col: 0),
      (top: 200, bottom: 250, col: 0),
    ]);
    expect(l[0].count, 2);
    expect(l[1].index, 1);
    expect(l[2].count, 1);
  });
  test('different people do not clash; both-of-us events clash with everyone', () {
    final l = CoupleDayLanes.assign([
      (top: 0, bottom: 100, col: 0),
      (top: 0, bottom: 100, col: 1),
    ]);
    expect(l[0].count, 1);
    expect(l[1].count, 1);
    final m = CoupleDayLanes.assign([
      (top: 0, bottom: 100, col: -1),
      (top: 50, bottom: 120, col: 1),
    ]);
    expect(m[0].full, isTrue);
    expect(m[0].count, 2);
    expect(m[1].index, 1);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/coordinate/activity_detail_screen.dart';
import 'package:onespace/l10n/phrases.dart';

void main() {
  test('Activity priority words are priorities, not moods (UAT round 2)', () {
    OneSpacePhrases.lang = 'ar';
    expect(ActivityScreenWords.word('low'), 'منخفضة');
    expect(ActivityScreenWords.word('urgent'), 'عاجلة');
    expect(ActivityScreenWords.word('registered'), 'تم الحجز أو التسجيل');
    OneSpacePhrases.lang = 'en';
    expect(ActivityScreenWords.word('low'), 'Low');
    expect(ActivityScreenWords.word('on_hold'), 'On hold');
  });
}

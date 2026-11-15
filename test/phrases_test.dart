import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/l10n/phrases.dart';
import 'package:onespace/l10n/phrases_ar.dart';

void main() {
  tearDown(() => OneSpacePhrases.lang = 'en');

  test('English stays English', () {
    OneSpacePhrases.lang = 'en';
    expect(tt('Save'), 'Save');
  });

  test('Arabic phrases, with punctuation and spacing kept', () {
    OneSpacePhrases.lang = 'ar';
    expect(tt('Save'), 'حفظ');
    expect(tt('Showing'), 'المعروض');
    expect(tt('Cancel'), 'إلغاء');
    expect(tt('Overdue · '), 'متأخر · ');
    expect(tt('Could not update'), 'تعذّر التحديث');
    expect(tt('Booked'), 'محجوزة');
  });

  test('unknown text and user content pass through', () {
    OneSpacePhrases.lang = 'ar';
    expect(tt('Kay’s groceries'), 'Kay’s groceries');
    expect(tt(''), '');
  });

  test('every Arabic phrase is filled in', () {
    for (final e in arPhrases.entries) {
      expect(e.value.trim(), isNotEmpty, reason: e.key);
    }
    expect(arPhrases.length, greaterThan(1200));
  });
}

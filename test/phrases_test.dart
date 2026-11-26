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

  test('sentence patterns translate with their parts', () {
    OneSpacePhrases.lang = 'ar';
    expect(tt('Every 3 days'), 'كل 3 أيام');
    expect(tt('Your space with Kay'), 'مساحتك مع Kay');
    expect(tt('Remove “Groceries”?'), 'حذف «Groceries»؟');
    // User text is never half-translated by a loose pattern.
    expect(tt('Add milk to the list'), 'Add milk to the list');
    expect(tt('Lord of the Rings'), 'Lord of the Rings');
    // R73: lines joined with " · " are translated piece by piece.
    expect(tt('Kay · Planning · In 3 days'), 'Kay · ${arPhrases['Planning']} · بعد 3 أيام');
    expect(tt('Lord of the Rings · Kay'), 'Lord of the Rings · Kay');
  });

  test('closed-testing workflow and support labels are translated', () {
    OneSpacePhrases.lang = 'ar';
    for (final phrase in [
      'Invite my partner', 'Resend email — same code', 'Revoke invitation',
      'Confirm your email address', 'Change password', 'My Space',
      'Delete your account?', 'Delete shared content permanently',
      'Daily selfies', 'Search the map', 'Frankfurt API round trip',
      'Seoul API round trip', 'Environment', 'No timings collected yet.',
    ]) {
      expect(tt(phrase), isNot(phrase), reason: phrase);
      expect(tt(phrase), contains(RegExp(r'[\u0600-\u06ff]')), reason: phrase);
    }
  });

  test('every Arabic phrase is filled in', () {
    for (final e in arPhrases.entries) {
      expect(e.value.trim(), isNotEmpty, reason: e.key);
    }
    expect(arPhrases.length, greaterThan(1200));
  });
}

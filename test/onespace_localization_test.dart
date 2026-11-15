import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/l10n/onespace_strings.dart';

void main() {
  test('OneSpace uses the approved brand tagline in both locales', () {
    expect(OneSpaceStrings.forLanguage('en', 'tagline'), 'Two of us, One Space');
    expect(OneSpaceStrings.forLanguage('ar', 'tagline'), 'Two of us, One Space');
  });

  test('English and Arabic have matching translation keys', () {
    expect(OneSpaceStrings.ar.keys.toSet(), OneSpaceStrings.en.keys.toSet());
  });

  test('Arabic interface copy is available and English fallback is stable', () {
    expect(OneSpaceStrings.forLanguage('ar', 'signIn'), 'تسجيل الدخول');
    expect(OneSpaceStrings.forLanguage('ar', 'private'), 'خاصة');
    expect(OneSpaceStrings.forLanguage('en', 'private'), 'Private');
    expect(OneSpaceStrings.forLanguage('fr', 'signIn'), 'Sign in');
  });
}

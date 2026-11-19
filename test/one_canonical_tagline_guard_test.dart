import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/core/onespace_brand.dart';
import 'package:onespace/l10n/onespace_strings.dart';

void main() {
  test('OneSpace uses the founder-approved tagline in both app languages', () {
    expect(OneSpaceStrings.forLanguage('en', 'tagline'), OneSpaceBrand.tagline);
    expect(OneSpaceStrings.forLanguage('ar', 'tagline'), OneSpaceBrand.tagline);
    expect(OneSpaceBrand.tagline, 'Two of Us. One Space');
  });
  test('Theme previews reuse one approved brand constant', () {
    const paths = [
      'lib/theme/theme_concept_card.dart',
      'lib/theme/appearance_settings_screen.dart',
    ];
    for (final path in paths) {
      expect(File(path).readAsStringSync(), contains('OneSpaceBrand.tagline'),
          reason: path);
    }
  });
  test('No abandoned slogans in app, email or documentation sources', () {
    final rejected = RegExp(r'one life[.,]?\s*two places', caseSensitive: false);
    for (final folder in [
      Directory('lib'),
      Directory('docs'),
      Directory('supabase/email-templates'),
      Directory('supabase/functions'),
    ]) {
      for (final entity in folder.listSync(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final path = entity.path;
        if (!RegExp(r'\.(dart|md|html|ts|mjs)$').hasMatch(path)) continue;
        final content = entity.readAsStringSync();
        expect(rejected.hasMatch(content), false, reason: path);
      }
    }
  });
  test('Active email and UI sources do not contain unapproved alternatives', () {
    final wrong = ['One Life.', 'Two Places.', 'One Space.'].join(' ');
    final obsolete = ['Two of us,', 'One Space'].join(' ');
    const paths = [
      'lib/main.dart',
      'lib/l10n/onespace_strings.dart',
      'lib/l10n/phrases_ar.dart',
      'supabase/email-templates/confirmation.html',
      'supabase/email-templates/password_recovery.html',
      'supabase/functions/onespace-send-invitation/index.ts',
    ];
    for (final path in paths) {
      final content = File(path).readAsStringSync();
      expect(content.contains(wrong), false, reason: path);
      expect(content.contains(obsolete), false, reason: path);
    }
  });
}

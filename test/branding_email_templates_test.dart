import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('signup, recovery and invitation source share founder-approved branding', () {
    const sourcePaths = [
      'supabase/email-templates/confirmation.html',
      'supabase/email-templates/password_recovery.html',
      'supabase/functions/onespace-send-invitation/index.ts',
    ];
    for (final path in sourcePaths) {
      final source = File(path).readAsStringSync();
      expect(source, contains('Two of Us. One Space'), reason: path);
      expect(source, isNot(contains('One Life. Two Places. One Space.')), reason: path);
      expect(source, contains('https://raw.githubusercontent.com/BoyofKay/onespace-app/main/assets/icon-512.png'), reason: path);
    }
    final confirm = File(sourcePaths[0]).readAsStringSync();
    final recovery = File(sourcePaths[1]).readAsStringSync();
    expect(confirm, contains('{{ .Email }}'));
    for (final html in [confirm, recovery]) {
      expect(html, contains('{{ .ConfirmationURL }}'));
      expect(html, contains('mailto:support@onespace.live'));
    }
  });
}

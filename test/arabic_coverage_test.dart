import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/l10n/phrases.dart';

/// 26 Nov 2026: every text the app passes to tt('…') has an Arabic phrase.
/// New English text without Arabic fails here, so the Arabic app stays complete.
void main() {
  test('Every tt() text in the app has Arabic', () {
    OneSpacePhrases.lang = 'ar';
    // Brand, language names (always shown in their own language) and codes stay as written.
    const allowed = {'OneSpace', 'English', 'EN', 'AR', 'العربية (Arabic)', '14A', 'USD'};
    final literal = RegExp(r"""\btt\(\s*'((?:[^'\\\n]|\\.)*)'\s*[,)]""");
    final missing = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart') || f.path.contains('/l10n/')) continue;
      for (final m in literal.allMatches(f.readAsStringSync())) {
        final en = m.group(1)!.replaceAll(r"\'", "'");
        if (en.contains(r'$') || !RegExp('[A-Za-z]').hasMatch(en) || allowed.contains(en)) continue;
        if (tt(en) == en) missing.add('${f.path}: $en');
      }
    }
    OneSpacePhrases.lang = 'en';
    expect(missing, isEmpty, reason: missing.take(20).join('\n'));
  });
}

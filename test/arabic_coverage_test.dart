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

  test('Texts written across several lines inside tt() also have Arabic (UAT 26 Nov 2026)', () {
    OneSpacePhrases.lang = 'ar';
    // tt('First part '
    //    'second part'): adjacent pieces form one text; the first check only saw the first piece.
    final joined = RegExp(r"""\btt\(\s*((?:'(?:[^'\\\n]|\\.)*'\s*){2,})[,)]""");
    final piece = RegExp(r"""'((?:[^'\\\n]|\\.)*)'""");
    final missing = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart') || f.path.contains('/l10n/')) continue;
      for (final m in joined.allMatches(f.readAsStringSync())) {
        final en = piece.allMatches(m.group(1)!).map((p) => p.group(1)!).join().replaceAll(r"\'", "'");
        if (en.contains(r'$') || !RegExp('[A-Za-z]').hasMatch(en)) continue;
        if (tt(en) == en) missing.add('${f.path}: $en');
      }
    }
    OneSpacePhrases.lang = 'en';
    expect(missing, isEmpty, reason: missing.take(30).join('\n'));
  });

  test('Required labels, server reasons and notices are translated (UAT 26 Nov 2026)', () {
    OneSpacePhrases.lang = 'ar';
    expect(tt('Date *'), endsWith(' *'));
    expect(tt('Date *'), isNot(contains('Date')));
    expect(tt('Overdue to-do'), isNot('Overdue to-do'));
    expect(tt('You removed Sam'), contains('Sam'));
    expect(tt('You removed Sam'), isNot(contains('You removed')));
    expect(tt('Planning intelligence'), 'التخطيط الذكي');
    expect(tt('{} updates you have already seen').replaceFirst('{}', '3'), contains('3'));
    OneSpacePhrases.lang = 'en';
    expect(tt('Date *'), 'Date *');
  });

  test('Both texts of tt(condition ? A : B) have Arabic (UAT 26 Nov 2026)', () {
    OneSpacePhrases.lang = 'ar';
    final choice = RegExp(r"""\btt\(([^()\n;]*\?[^()\n;]*)\)""");
    final piece = RegExp(r"""'((?:[^'\\\n]|\\.)*)'""");
    final missing = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart') || f.path.contains('/l10n/')) continue;
      for (final m in choice.allMatches(f.readAsStringSync())) {
        for (final p in piece.allMatches(m.group(1)!)) {
          final en = p.group(1)!.replaceAll(r"\'", "'");
          // Skip codes, ids and pieces of ${…} or "…" expressions the simple pattern cuts apart.
          if (en.contains(r'$') || en.contains('}') || en.contains('"') || en == 'PDF' ||
              !RegExp('[A-Za-z]{2}').hasMatch(en) || RegExp(r'^[a-z_]+$').hasMatch(en)) continue;
          if (tt(en) == en) missing.add('${f.path}: $en');
        }
      }
    }
    OneSpacePhrases.lang = 'en';
    expect(missing, isEmpty, reason: missing.take(40).join('\n'));
  });
}

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/finances/fin_data.dart';
import 'package:onespace/features/finances/fin_widgets.dart';
import 'package:onespace/l10n/phrases.dart';

/// 28 Nov 2026 (D97, D110+): Finances passes many texts to widgets that
/// translate them inside (choice chips, section titles, add-button options),
/// which the general tt('…') check cannot see. Every English text literal
/// in lib/features/finances must have Arabic.
void main() {
  test('Every Finances text has Arabic', () {
    OneSpacePhrases.lang = 'ar';
    final literal = RegExp(r"'((?:[^'\\\n]|\\.)*)'");
    final missing = <String>{};
    for (final f in Directory('lib/features/finances').listSync().whereType<File>()) {
      // Programmer errors (exceptions) never reach the screen.
      final lines = f.readAsLinesSync().where((l) => !l.contains('Exception(') && !l.contains('Error(')).join('\n');
      for (final m in literal.allMatches(lines)) {
        final en = m.group(1)!.replaceAll(r"\'", "'");
        // Only sentences and labels: start with a capital, a digit or {}, contain a lower-case letter.
        if (!RegExp(r'^[A-Z0-9{]').hasMatch(en) || !RegExp('[a-z]').hasMatch(en)) continue;
        if (en.contains(r'$') || en.contains('_') || en.contains('::') || en.contains('://')) continue;
        if (const {'USD', 'OneSpace'}.contains(en)) continue;
        if (tt(en) == en) missing.add('${f.path}: $en');
      }
    }
    for (final en in [...frequencyLabels.values, ...finBuiltInCategories.values]) {
      if (tt(en) == en) missing.add('label: $en');
    }
    OneSpacePhrases.lang = 'en';
    expect(missing, isEmpty, reason: missing.join('\n'));
  });

  test('Reminder texts keep the item name and never an amount (A19)', () {
    OneSpacePhrases.lang = 'ar';
    expect(tt('Payment due soon: {}').replaceFirst('{}', 'Car'), contains('Car'));
    expect(tt('Did {} get paid?').replaceFirst('{}', 'Rent'), contains('Rent'));
    expect(tt('{} of {} paid').replaceFirst('{}', '3').replaceFirst('{}', '12'), allOf(contains('3'), contains('12')));
    OneSpacePhrases.lang = 'en';
  });
}

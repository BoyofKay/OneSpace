import 'package:material_ui/material_ui.dart';
import 'package:onespace/l10n/phrases.dart';

import 'counter_sources.dart';
import 'counters_screen.dart';

/// A menu action never saves a counter silently: it opens the normal full
/// editor with a copy of the source date for the user to review and Save.
class CounterSourceActions {
  const CounterSourceActions._();

  static Future<void> open(BuildContext context, String spaceId, CounterSource? source) async {
    if (source == null) return;
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => CounterEditor(spaceId: spaceId, source: source)));
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tt('Counter added.'))));
    }
  }
}

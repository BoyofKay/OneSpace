import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onespace/core/current_space_cache.dart';
import 'package:onespace/core/form_kit.dart';

/// QA: alone in a space, new content defaults to "Only me" and "Shared" is
/// unavailable; once a partner joins, Shared stays the default.
void main() {
  Future<MetaValues?> pump(WidgetTester tester, bool? paired) async {
    CurrentSpaceCache.paired.value = paired;
    MetaValues? changed;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: MetaStrip(
      value: const MetaValues(shared: true),
      showBelongs: false, showDate: false,
      onChanged: (v) => changed = v))));
    await tester.pump();
    return changed;
  }

  testWidgets('solo space switches new content to Only me', (tester) async {
    final changed = await pump(tester, false);
    expect(changed?.shared, false);
  });
  testWidgets('paired space keeps Shared as the default', (tester) async {
    final changed = await pump(tester, true);
    expect(changed, isNull);
  });
}

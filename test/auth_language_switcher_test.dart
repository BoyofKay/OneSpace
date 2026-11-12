import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onespace/features/auth/auth_language_switcher.dart';

void main() {
  testWidgets('Language switch is compact and anchored to the corner',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: AuthLanguageSwitcher()),
    ));
    expect(find.text('EN'), findsOneWidget);
    expect(find.text('AR'), findsOneWidget);
    final row = tester.widget<Row>(find.byType(Row).last);
    expect(row.mainAxisSize, MainAxisSize.min);
  });
}

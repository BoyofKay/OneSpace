import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/plans/plans_screen.dart';

void main() {
  testWidgets('Plans preview can create and complete a task', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: PlansScreen()),
    ));
    expect(find.text('Plans & tasks'), findsOneWidget);
    expect(find.text('No tasks yet'), findsOneWidget);

    await tester.tap(find.text('Add task'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Plan our next call');
    await tester.tap(find.text('Save task'));
    await tester.pumpAndSettle();

    expect(find.text('Plan our next call'), findsOneWidget);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    expect(find.text('0 open • 1 total'), findsOneWidget);
  });
}

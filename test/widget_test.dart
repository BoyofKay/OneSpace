import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/main.dart';

void main() {
  testWidgets('OneSpace shows dashboard and working Plans tab', (tester) async {
    await tester.pumpWidget(const OneSpaceApp());
    expect(find.text('OneSpace'), findsOneWidget);
    expect(find.text('Our Space'), findsOneWidget);

    await tester.tap(find.text('Plans'));
    await tester.pumpAndSettle();
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

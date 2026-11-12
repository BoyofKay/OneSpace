import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/main.dart';

void main() {
  testWidgets('OneSpace shell shows home and navigation', (tester) async {
    await tester.pumpWidget(const OneSpaceApp());
    expect(find.text('OneSpace'), findsOneWidget);
    expect(find.text('Our Space'), findsOneWidget);
    expect(find.text('Plans'), findsOneWidget);
    await tester.tap(find.text('Plans'));
    await tester.pumpAndSettle();
    expect(find.text('Back to home'), findsOneWidget);
  });
}

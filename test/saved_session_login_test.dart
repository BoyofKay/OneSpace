import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onespace/features/auth/saved_session_login.dart';

void main() {
  testWidgets('Saved session never starts a phone prompt on screen open',
      (tester) async {
    var unlocked = 0;
    var switchCount = 0;

    await tester.pumpWidget(MaterialApp(
      home: SavedSessionLogin(
        email: 'preview@example.test',
        onUnlocked: () => unlocked++,
        onSwitchAccount: () async { switchCount++; },
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('preview@example.test'), findsOneWidget);
    expect(find.byKey(const Key('savedSessionFingerprint')), findsOneWidget);
    expect(find.byKey(const Key('savedSessionSignIn')), findsOneWidget);
    expect(find.text('Continue with password'), findsOneWidget);
    expect(find.textContaining('Phone unlock is unavailable'), findsNothing);
    expect(unlocked, 0);

    await tester.tap(find.text('Switch account'));
    await tester.pump();
    expect(switchCount, 1);
  });

  testWidgets('Saved session explains phone-PIN and password alternatives',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SavedSessionLogin(
        email: 'other@example.test',
        onUnlocked: () {},
        onSwitchAccount: () async {},
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('screen-lock PIN also works'), findsOneWidget);
    expect(find.textContaining('Your session is saved'), findsOneWidget);
  });
}

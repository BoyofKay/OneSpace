import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onespace/features/auth/password_recovery_screen.dart';

void main() {
  testWidgets('Recovery request rejects invalid email before networking',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ForgotPasswordScreen(initialEmail: 'not-an-email'),
      ),
    );
    expect(find.text('Forgot your password?'), findsOneWidget);
    await tester.tap(find.text('Send recovery link'));
    await tester.pump();
    expect(find.text('Enter a valid email address.'), findsOneWidget);
  });

  testWidgets('Recovered account needs a matching 8-character password',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: ResetPasswordScreen()),
    );
    expect(
      find.text('Your current password remains valid until the new one is successfully saved.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Update password'));
    await tester.pump();
    expect(find.text('Use at least 8 characters.'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'long-enough-password');
    await tester.enterText(find.byType(TextField).last, 'different-password');
    await tester.tap(find.text('Update password'));
    await tester.pump();
    expect(find.text('Passwords do not match.'), findsOneWidget);
  });
}

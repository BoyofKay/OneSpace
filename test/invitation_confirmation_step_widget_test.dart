import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onespace/features/auth/auth_gate.dart';

void main() {
  testWidgets('New signup gets a dedicated confirmation screen, not signup fields',
      (tester) async {
    var resendCount = 0;
    var signInCount = 0;
    var changeEmailCount = 0;
    await tester.pumpWidget(MaterialApp(home: ConfirmEmailStep(
      email: 'invitee@example.com',
      pendingInvitation: true,
      loading: false,
      message: null,
      error: null,
      onResend: () => resendCount++,
      onSignIn: () => signInCount++,
      onDifferentEmail: () => changeEmailCount++,
    )));
    expect(find.text('Confirm your email address'), findsOneWidget);
    expect(find.text('invitee@example.com'), findsOneWidget);
    expect(find.textContaining('Your partner’s invitation is safely kept'),
      findsOneWidget);
    expect(find.text('Create account'), findsNothing);
    await tester.tap(find.byKey(const Key('confirmationResend')));
    expect(resendCount, 1);
    await tester.tap(find.byKey(const Key('confirmationContinueToSignIn')));
    expect(signInCount, 1);
    await tester.ensureVisible(find.text('Use a different email address'));
    await tester.tap(find.text('Use a different email address'));
    expect(changeEmailCount, 1);
  });
}

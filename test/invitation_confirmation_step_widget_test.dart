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
    // The small simulated screen scrolls: buttons below the fold are
    // intentionally lazy-built by ListView, so finders need to scroll first.
    await tester.scrollUntilVisible(
      find.byKey(const Key('confirmationResend')), 220,
      scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const Key('confirmationResend')));
    expect(resendCount, 1);
    await tester.scrollUntilVisible(
      find.byKey(const Key('confirmationContinueToSignIn')), -220,
      scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const Key('confirmationContinueToSignIn')));
    expect(signInCount, 1);
    await tester.scrollUntilVisible(
      find.text('Use a different email address'), 220,
      scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Use a different email address'));
    expect(changeEmailCount, 1);
  });
}

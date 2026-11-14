import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onespace/features/auth/auth_gate.dart';

void main(){
 testWidgets('OneSpace has one sign-in surface with password and device icon',
  (tester)async{
   await tester.pumpWidget(const MaterialApp(home:SignInScreen()));
   await tester.pump();
   expect(find.byKey(const Key('loginEmail')),findsOneWidget);
   expect(find.byKey(const Key('loginPassword')),findsOneWidget);
   expect(find.byKey(const Key('loginFingerprint')),findsOneWidget);
   await tester.ensureVisible(find.byKey(const Key('loginFingerprint')));
   await tester.tap(find.byKey(const Key('loginFingerprint')));
   await tester.pump();
   expect(find.textContaining('Sign in with your password first'),findsOneWidget);
   expect(tester.takeException(),isNull);
 });
 testWidgets('A saved session uses the same page with fixed email',
  (tester)async{
   await tester.pumpWidget(MaterialApp(home:SignInScreen(
    activeSessionEmail:'saved@example.com',onSessionUnlocked:(){})));
   await tester.pump();
   final field=find.descendant(of:find.byKey(const Key('loginEmail')),
    matching:find.byType(TextField));
   expect(tester.widget<TextField>(field).readOnly,isTrue);
   expect(find.byKey(const Key('loginFingerprint')),findsOneWidget);
   expect(find.textContaining('Session locked.'),findsOneWidget);
   expect(tester.takeException(),isNull);
 });
}

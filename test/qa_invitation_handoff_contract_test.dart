import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onespace/core/app_env.dart';
import 'package:onespace/features/auth/auth_gate.dart';
import 'package:onespace/features/spaces/invitation_code.dart';
import 'package:onespace/features/spaces/invitation_link_inbox.dart';

void main() {
  const token = 'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789';

  test('An invitation opened from the QA email survives the browser-to-app handoff', () {
    final website = invitationWebLink(token, qa: true);
    final native = invitationAppLink(token, qa: true);
    expect(website.path, '/qa-invite/');
    expect(native.scheme, 'onespace-preview');
    expect(invitationCodeFromUri(website, qa: true), token);
    expect(invitationCodeFromUri(native, qa: true), token);
    expect(invitationCodeFromUri(website, qa: false), isNull);
    expect(invitationCodeFromUri(native, qa: false), isNull);
    expect(invitationCodeFromUri(
      Uri.parse('https://another-domain.example/qa-invite/?code=$token'),
      qa: true), isNull);
  });

  testWidgets('New invited user sees standalone email confirmation, not signup fields',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: ConfirmEmailStep(
      email: 'invited@example.com',
      pendingInvitation: true,
      loading: false,
      message: null,
      error: null,
      onResend: () {},
      onSignIn: () {},
      onDifferentEmail: () {},
    )));
    expect(find.text('Confirm your email address'), findsOneWidget);
    expect(find.text('invited@example.com'), findsOneWidget);
    expect(find.text('Create your account'), findsNothing);
    expect(find.textContaining('invitation is safely kept'), findsOneWidget);
    expect(find.byKey(const Key('confirmationContinueToSignIn')), findsOneWidget);
    // ListView children below the viewport are built lazily on smaller
    // test surfaces. Scroll to the resend action before asserting it.
    await tester.scrollUntilVisible(
      find.byKey(const Key('confirmationResend')),
      230,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('confirmationResend')), findsOneWidget);

  });

  test('Unpaired invited account gets one focused handoff instead of 3 setup cards', () {
    final source = File('lib/features/spaces/shared_space_screen.dart')
        .readAsStringSync();
    final invited = source.indexOf('joiningAddressedInvite)) ...[');
    final general = source.indexOf('else if (spaceId == null) ...[', invited);
    expect(invited, greaterThan(0));
    expect(general, greaterThan(invited));
    final invitedBranch = source.substring(invited, general);
    expect(invitedBranch, contains('completePendingInvitation'));
    expect(invitedBranch, contains('Signed in as:'));
    expect(invitedBranch, isNot(contains("tt('Invite my partner')")));
    expect(invitedBranch, isNot(contains("tr(context, 'createSpaceTitle')")));
    expect(invitedBranch, isNot(contains("tr(context, 'joinPartner')")));
    expect(source, contains("if (data['space_id'] == null)"));
    expect(source, contains("if (status == 'already_joined')"));
    expect(source, contains('InvitationLinkInbox.instance.clear()'));
    expect(source, contains('dismissedAddressedInvite = true'));
    expect(source, contains('joiningAddressedInvite = true'));
  });

  test('Unpaired account has one personal onboarding panel, not three setup cards', () {
    final source = File('lib/features/spaces/shared_space_screen.dart')
        .readAsStringSync();
    final start = source.indexOf('else if (spaceId == null) ...[');
    final end = source.indexOf('if (memberCount < 2) ...[', start);
    expect(start, greaterThan(0));
    expect(end, greaterThan(start));
    final branch = source.substring(start, end);
    expect('_panel('.allMatches(branch).length, 1);
    expect(branch, contains('Your personal OneSpace is ready'));
    expect(branch, contains('joinSpaceSingleAction'));
    expect(branch, contains('joinSpaceInvitationCode'));
    expect(branch, contains('Scan invitation QR code'));
    expect(branch, contains('Invite my partner'));
    expect(branch, isNot(contains("tr(context, 'createSpaceTitle')")));
    expect(branch, isNot(contains("tr(context, 'joinPartner')")));
  });

  testWidgets('Verified recipient invitation survives a lost browser deep link',
      (tester) async {
    // A widget test has no Android/iOS keystore. Without this test double,
    // FlutterSecureStorage.read/write/delete can await a platform response
    // forever; CI then times out after 10 minutes before building the APK.
    FlutterSecureStorage.setMockInitialValues({});
    final inbox = InvitationLinkInbox.instance;
    await inbox.clear();
    expect(inbox.pendingCode, isNull);
    await inbox.rememberVerifiedQaAddressedCode(token);
    expect(inbox.pendingCode, token);
    await inbox.rememberVerifiedQaAddressedCode('bad-token');
    expect(inbox.pendingCode, token);
    await inbox.clear();
    expect(inbox.pendingCode, isNull);
  });

  test('Unpaired recipient performs authenticated fallback lookup before generic setup', () {
    final source = File('lib/features/spaces/shared_space_screen.dart')
      .readAsStringSync();
    expect(source, contains("client.rpc('qa_find_my_addressed_invitation')"));
    expect(source, contains('rememberVerifiedQaAddressedCode(code)'));
    expect(source, contains('checkingAddressedInvite || inviteLookupFailed'));
    expect(source, contains('Continue without an invitation'));
    expect(source, contains("if (!OneSpaceEnv.isProduction) unawaited(_resumeOrDiscoverAddressedInvite());"));
  });

  test('Android QA and Production packages cannot share Supabase environment', () {
    expect(OneSpaceEnv.packageMatchesEnvironment('onespace.qa'), isTrue);
    expect(OneSpaceEnv.packageMatchesEnvironment('live.onespace.app'), isFalse);
    expect(OneSpaceEnv.supabaseUrl,
      'https://ugwrpeduzyzrujkizqfo.supabase.co');
  });
}

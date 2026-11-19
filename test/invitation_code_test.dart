import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/spaces/invitation_code.dart';

void main() {
  test('Accepts a 64-character hex code and normalizes formatting', () {
    const raw = 'ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789';
    expect(
      normalizedInvitationCode('  $raw  '),
      raw.toLowerCase(),
    );
  });

  test('Rejects empty, truncated and non-hex invitations', () {
    expect(normalizedInvitationCode(''), isNull);
    expect(normalizedInvitationCode('12345'), isNull);
    expect(normalizedInvitationCode(List.filled(64, 'x').join()), isNull);
  });

  test('R71: the code is found inside a whole pasted message', () {
    const code = 'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789';
    expect(normalizedInvitationCode(invitationMessage(code)), code);
    expect(normalizedInvitationCode('Code: ${code}ff'), isNull);
  });
  test('Same invitation code is embedded in a reusable HTTPS link', () {
    const code = 'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789';
    final url = invitationWebLink(code);
    expect(url.scheme, 'https');
    expect(url.host, 'onespace.live');
    expect(invitationCodeFromUri(url), code);
    expect(normalizedInvitationCode(invitationMessage(code)), code);
    expect(invitationMessage(code, email: true), contains('Google Play'));
    expect(invitationMessage(code, email: true), contains('App Store'));
    expect(invitationMessage(code, email: true), contains(url.toString()));
  });

  test('QA and Production invitation deep links stay separate', () {
    const code = 'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789';
    expect(invitationCodeFromUri(invitationAppLink(code), qa: false), code);
    expect(invitationCodeFromUri(invitationAppLink(code, qa: true), qa: true), code);
    expect(invitationWebLink(code, qa: true).path, '/qa-invite/');
    expect(invitationWebLink(code).path, '/app-invite/');
    expect(invitationCodeFromUri(invitationWebLink(code, qa: true), qa: true), code);
    expect(invitationCodeFromUri(invitationWebLink(code), qa: true), isNull);
    expect(invitationCodeFromUri(Uri.parse('https://onespace.live/qa-invite/?code=$code')), isNull);
    expect(invitationCodeFromUri(invitationWebLink(code, qa: true)), isNull);
    expect(invitationCodeFromUri(invitationAppLink(code), qa: true), isNull);
    expect(invitationCodeFromUri(Uri.parse('https://untrusted.example/app-invite/?code=$code')), isNull);
    expect(invitationCodeFromUri(Uri.parse('https://onespace.live/app-invite/?code=bad')), isNull);
  });

  test('Gmail draft uses RFC 6068 percent encoding, never plus-as-spaces', () {
    const code = 'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789';
    final uri = invitationEmailDraftUri(code, qa: true);
    final url = uri.toString();
    expect(uri.scheme, 'mailto');
    expect(url, contains('subject=A%20little%20space'));
    expect(url, contains('%0A'));
    expect(url, isNot(contains('+')));
    expect(uri.queryParameters['subject'], contains('OneSpace invitation'));
    expect(uri.queryParameters['body'], contains(invitationWebLink(code, qa: true).toString()));
    expect(uri.queryParameters['body'], contains('Two of Us. One Space.'));
  });

}

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
}

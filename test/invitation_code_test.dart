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
    expect(normalizedInvitationCode('x' * 64), isNull);
  });
}

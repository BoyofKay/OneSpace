import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/profile/password_change_rules.dart';

void main() {
  bool can(String old, String next, String confirm, {bool busy=false}) =>
    PasswordChangeRules.canSubmit(
      current:old,next:next,confirmation:confirm,busy:busy);
  test('password change starts disabled and stays disabled while incomplete', () {
    expect(can('', '', ''), false);
    expect(can('saved-password','', ''), false);
    expect(can('saved-password','different-secret',''), false);
    expect(can('saved-password','short','short'), false);
    expect(can('saved-password','different-secret','mismatch'), false);
  });
  test('same password cannot be submitted; valid distinct password can', () {
    expect(can('saved-password','saved-password','saved-password'), false);
    expect(can('saved-password','different-secret','different-secret'), true);
    expect(can('saved-password','different-secret','different-secret',busy:true), false);
  });
}

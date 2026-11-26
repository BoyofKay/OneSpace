import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Founder waitlist backend (website forms, Production only). Moved here from
/// the public website repository on 26 Nov 2026; these checks moved with it
/// from the website's tests/check_security_seo.py.
void main() {
  test('Turnstile spam check fails closed and is bound to onespace.live', () {
    final src = File('supabase/founders/functions/_lib.ts').readAsStringSync();
    expect(src, contains("return ok === true ? 'ok' : 'blocked'"),
        reason: 'Turnstile must fail closed');
    expect(src, contains("j.hostname === 'onespace.live'"),
        reason: 'Turnstile hostname binding absent');
    expect(src, isNot(contains('turnstile_unavailable === true')),
        reason: 'unverified token bypass');
    expect(src, isNot(contains('const fast =')),
        reason: 'client timing should not bypass checks');
  });
}

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/support/faq_content.dart';

/// Founding 500 (Amr, 22 Nov 2026) and the in-app FAQ, Privacy and Terms
/// rewrite: no Founder numbers anywhere, email-only sign-in, solo use, and
/// separation / account deletion as decided in ADR-2026-11-20.
void main() {
  test('Founder badge shows no number', () {
    final me = File('lib/features/profile/me_screen.dart').readAsStringSync();
    expect(me, contains("rpc('my_founder_status')"));
    expect(me, contains("tt('Founder Member')"));
    expect(me.toLowerCase(), isNot(contains('founder_number')));
    final sql = File('supabase/schema/0318_qa_founder_badge.sql').readAsStringSync();
    expect(sql, contains('founder_people_count() < 500'));
    expect(sql, contains('before insert on auth.users'));
    expect(sql, contains('update of email_confirmed_at on auth.users'));
    expect(sql, isNot(contains('founder_number')));
  });

  test('Founder eligibility is server-controlled in both database environments', () {
    final qaPatch = File('supabase/schema/0319_qa_founder_server_authority.sql').readAsStringSync();
    final prodRollout = File('supabase/production/founder_badge_rollout_20261122.sql').readAsStringSync();
    for (final sql in [qaPatch, prodRollout]) {
      expect(sql, contains("new.raw_app_meta_data || jsonb_build_object('onespace_founder_offer', true)"));
      expect(sql, contains("(new.raw_app_meta_data ->> 'onespace_founder_offer')::boolean"));
      expect(sql, contains("new.raw_user_meta_data := coalesce(new.raw_user_meta_data, '{}'::jsonb) - 'founder'"));
      expect(sql, contains('pg_advisory_xact_lock(1500500)'));
      expect(sql, contains('revoke all on function private.founder_grant_on_confirm()'));
    }
    expect(prodRollout, contains('create or replace function public.my_founder_status()'));
    expect(prodRollout, contains('create table if not exists private.app_founders'));
  });

  test('FAQ matches how the app works today', () {
    final all = faqEntries.map((e) => '${e.qEn} ${e.aEn}').join('\n');
    expect(all, contains('Can I use OneSpace without a partner?'));
    expect(all, contains('48 hours'));
    expect(all, contains('What happens if we separate?'));
    expect(all, isNot(contains('If you signed up with Google or Apple')));
    // 27 Nov 2026: Google/Apple sign-in was dropped; the FAQ must not mention it.
    expect(all, isNot(contains('Google or Apple')));
    expect(all, isNot(contains('Items you shared stay for your partner')));
    for (final e in faqEntries) {
      expect(e.qAr.trim(), isNotEmpty);
      expect(e.aAr.trim(), isNotEmpty);
    }
  });

  test('Terms and privacy describe separation and the 7-day grace', () {
    final terms = File('lib/features/auth/terms.dart').readAsStringSync();
    expect(terms, contains("termsVersion = '2026-11-22'"));
    expect(terms, contains('You can use OneSpace on your own'));
    expect(terms, contains('permanently deleted for both of you'));
    expect(terms, isNot(contains('shared items stay with the other person')));
    final privacy = File('lib/features/support/support_screens.dart').readAsStringSync();
    expect(privacy, contains('If you separate'));
    expect(privacy, isNot(contains('Shared items stay for your partner')));
  });
}

import 'package:shared_preferences/shared_preferences.dart';

/// Email addresses only. Passwords, biometric templates and auth tokens are
/// never stored here; Supabase manages the one active session separately.
class RememberedAccounts {
  const RememberedAccounts._();
  static const _key = 'onespace_recent_emails_v1';
  static final _prefs = SharedPreferencesAsync();

  static Future<List<String>> list() async {
    final emails = await _prefs.getStringList(_key) ?? <String>[];
    return emails.where((email) => email.contains('@')).take(1).toList();
  }

  static Future<String?> lastUsedEmail() async {
    final entries = await list();
    return entries.isEmpty ? null : entries.first;
  }

  static Future<void> remember(String email) async {
    final normalized = email.trim().toLowerCase();
    if (!normalized.contains('@')) return;
    // A private device remembers only its most recently authenticated email.
    await _prefs.setStringList(_key,[normalized]);
  }

  static Future<void> forgetAll() => _prefs.remove(_key);
}

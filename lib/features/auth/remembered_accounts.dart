import 'package:shared_preferences/shared_preferences.dart';

/// Convenience only: stores email addresses, NEVER credentials or sessions.
/// A person must consent to remember an address on this device.
class RememberedAccounts {
  const RememberedAccounts._();
  static const _key = 'onespace_recent_emails_v1';
  static final _prefs = SharedPreferencesAsync();

  static Future<List<String>> list() async {
    final items = await _prefs.getStringList(_key) ?? <String>[];
    return items.where((e) => e.contains('@')).take(4).toList();
  }

  static Future<void> remember(String email) async {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty || !normalized.contains('@')) return;
    final current = await list();
    final next = <String>[
      normalized,
      ...current.where((item) => item != normalized),
    ].take(4).toList();
    await _prefs.setStringList(_key, next);
  }

  static Future<void> forgetAll() => _prefs.remove(_key);
}

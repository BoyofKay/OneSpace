import 'package:supabase_flutter/supabase_flutter.dart';

import 'world_currencies.dart';

/// R69: each person's preferred currency (Settings › Language and currency).
/// It is the starting value of every money field: budgets, prices, costs.
class PreferredCurrency {
  PreferredCurrency._();

  /// Every circulating currency (26 Nov 2026: the app is global), named in the
  /// app language and sorted by that name; the code is shown after it.
  static Map<String, String> choices([String language = 'en']) {
    final list = worldCurrencies.entries.toList()
      ..sort((a, b) => (language == 'ar' ? a.value.$2 : a.value.$1)
          .compareTo(language == 'ar' ? b.value.$2 : b.value.$1));
    return {for (final e in list) e.key: '${language == 'ar' ? e.value.$2 : e.value.$1} (${e.key})'};
  }

  static String _code = 'USD';
  static bool _loaded = false;

  /// The currency to start money fields with (USD until loaded; global app since 26 Nov 2026).
  static String get code => _code;

  /// Loads the saved choice once (falls back to USD).
  static Future<String> load() async {
    if (_loaded) return _code;
    try {
      final db = Supabase.instance.client;
      final me = db.auth.currentUser?.id;
      if (me == null) return _code;
      final row = await db.from('profiles').select('preferred_currency').eq('id', me).maybeSingle();
      final saved = row?['preferred_currency']?.toString();
      if (saved != null && RegExp(r'^[A-Z]{3}$').hasMatch(saved)) _code = saved;
      _loaded = true;
    } catch (_) {}
    return _code;
  }

  static Future<void> save(String code) async {
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(code)) return;
    final db = Supabase.instance.client;
    final me = db.auth.currentUser?.id;
    if (me == null) return;
    await db.from('profiles').update({'preferred_currency': code}).eq('id', me);
    _code = code;
    _loaded = true;
  }

  /// Forget the cache (sign-out).
  static void reset() {
    _code = 'USD';
    _loaded = false;
  }
}

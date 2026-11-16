import 'package:supabase_flutter/supabase_flutter.dart';

/// R69: each person's preferred currency (Settings › Language and currency).
/// It is the starting value of every money field: budgets, prices, costs.
class PreferredCurrency {
  PreferredCurrency._();

  /// Common choices, the region's first.
  static const choices = <String, String>{
    'SAR': 'Saudi riyal (SAR)', 'USD': 'US dollar (USD)', 'EGP': 'Egyptian pound (EGP)',
    'AED': 'UAE dirham (AED)', 'KWD': 'Kuwaiti dinar (KWD)', 'QAR': 'Qatari riyal (QAR)',
    'BHD': 'Bahraini dinar (BHD)', 'OMR': 'Omani rial (OMR)', 'JOD': 'Jordanian dinar (JOD)',
    'EUR': 'Euro (EUR)', 'GBP': 'British pound (GBP)', 'CAD': 'Canadian dollar (CAD)',
    'AUD': 'Australian dollar (AUD)', 'TRY': 'Turkish lira (TRY)', 'INR': 'Indian rupee (INR)',
  };

  static String _code = 'SAR';
  static bool _loaded = false;

  /// The currency to start money fields with (SAR until loaded).
  static String get code => _code;

  /// Loads the saved choice once (falls back to SAR).
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
    _code = 'SAR';
    _loaded = false;
  }
}

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Android Keystore-backed session persistence. The previous preview used
/// Supabase's SharedPreferencesLocalStorage, so migrate the old session once
/// and delete the plaintext copy only AFTER an encrypted write succeeds.
class SecureAuthStorage extends LocalStorage {
  static const _storage = FlutterSecureStorage();
  static const _sessionKey = supabasePersistSessionKey;

  @override
  Future<void> initialize() async {
    final old = SharedPreferencesLocalStorage(
      persistSessionKey: _sessionKey,
    );
    await old.initialize();
    final saved = await _storage.read(key: _sessionKey);
    if (saved == null) {
      final legacySession = await old.accessToken();
      if (legacySession != null && legacySession.isNotEmpty) {
        await _storage.write(key: _sessionKey, value: legacySession);
        // Confirm encrypted persistence before removing the old copy.
        if (await _storage.read(key: _sessionKey) == legacySession) {
          await old.removePersistedSession();
        }
      }
    } else {
      // The secure session is authoritative; clear stale plaintext copies.
      await old.removePersistedSession();
    }
  }

  @override
  Future<String?> accessToken() => _storage.read(key: _sessionKey);

  @override
  Future<bool> hasAccessToken() => _storage.containsKey(key: _sessionKey);

  @override
  Future<void> persistSession(String session) =>
      _storage.write(key: _sessionKey, value: session);

  @override
  Future<void> removePersistedSession() => _storage.delete(key: _sessionKey);
}

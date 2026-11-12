import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Android's OS, not OneSpace, verifies fingerprint or device PIN.
/// Authentication only unlocks the one already-restored Supabase session.
class DeviceUnlock {
  const DeviceUnlock._();
  static const _prefix = 'onespace_device_unlock_v1_';
  static final _prefs = SharedPreferencesAsync();

  // Retained solely to read pre-existing preview preferences during migration.
  static Future<bool> isEnabled(String userId) async =>
      await _prefs.getBool('$_prefix$userId') ?? false;

  static Future<void> setEnabled(String userId, bool enabled) async {
    await _prefs.setBool('$_prefix$userId', enabled);
  }

  static Future<bool> isAvailable() async {
    try {
      return await LocalAuthentication().isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  static Future<bool> authenticate({
    String reason = 'Unlock your saved OneSpace session',
  }) async {
    try {
      final auth = LocalAuthentication();
      if (!await auth.isDeviceSupported()) return false;
      return await auth.authenticate(
        localizedReason: reason,
        biometricOnly: false,
        persistAcrossBackgrounding: false,
        authMessages: const [
          AndroidAuthMessages(
            signInTitle: 'Unlock OneSpace',
            signInHint: 'Use your phone PIN or fingerprint',
            cancelButton: 'Cancel',
          ),
        ],
      );
    } catch (_) {
      return false;
    }
  }

  /// Best-effort cancellation of an active Android authentication prompt.
  /// The OS Back gesture also dismisses a biometric/PIN prompt.
  static Future<void> cancel() async {
    try {
      await LocalAuthentication().stopAuthentication();
    } catch (_) {
      // The prompt may already be gone.
    }
  }
}

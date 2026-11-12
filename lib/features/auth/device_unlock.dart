import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A device-level convenience gate for the user's *already saved* Supabase
/// session. This does not authenticate a second account or store passwords.
/// Phone PIN, pattern and biometrics are handled by the operating system.
class DeviceUnlock {
  const DeviceUnlock._();
  static const _prefix = 'onespace_device_unlock_v1_';
  static final _prefs = SharedPreferencesAsync();

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

  static Future<bool> authenticate({String reason = 'Unlock OneSpace'}) async {
    try {
      final auth = LocalAuthentication();
      if (!await auth.isDeviceSupported()) return false;
      return await auth.authenticate(
        localizedReason: reason,
        biometricOnly: false,
      );
    } catch (_) {
      return false;
    }
  }
}

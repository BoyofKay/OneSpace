import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Android's OS, not OneSpace, verifies fingerprint or device PIN.
/// Authentication only unlocks the one already-restored Supabase session.
class DeviceUnlock {
  const DeviceUnlock._();
  static const _prefix = 'onespace_device_unlock_v1_';
  static final _prefs = SharedPreferencesAsync();
  static const _settings = MethodChannel('onespace/device_unlock');

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
      );
    } catch (_) {
      return false;
    }
  }

  /// Opens Android's native enrollment/settings screen. No fingerprint data
  /// ever goes through the app; enrollment may differ across manufacturers.
  static Future<bool> openSystemEnrollment() async {
    try {
      await _settings.invokeMethod<void>('openEnrollment');
      return true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

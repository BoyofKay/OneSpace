import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart';

import 'app_env.dart';

/// The Xcode bundle identity, URL callback and Dart backend must belong to
/// the same QA or production build. Verify before Supabase restores a session.
class IosBuildConfigurationException implements Exception {
  const IosBuildConfigurationException();
}

class IosBuildConfiguration {
  const IosBuildConfiguration._();

  static const MethodChannel _channel = MethodChannel('onespace/build_environment');

  static bool matches({
    required String? environment,
    required String? bundleId,
    required String? authScheme,
    required bool production,
  }) {
    return environment == (production ? 'production' : 'qa') &&
        bundleId == (production ? 'com.onespace.onespace' : 'com.onespace.onespace.qa') &&
        authScheme == (production ? 'onespace' : 'onespace-preview');
  }

  static Future<void> verify() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    final config = await _channel.invokeMapMethod<String, dynamic>('read');
    if (config == null || !matches(
      environment: config['environment'] as String?,
      bundleId: config['bundleId'] as String?,
      authScheme: config['authScheme'] as String?,
      production: OneSpaceEnv.isProduction,
    )) {
      throw const IosBuildConfigurationException();
    }
  }
}

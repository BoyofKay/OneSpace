import 'dart:async';

import 'package:flutter/services.dart';

import 'app_env.dart';

/// Checks the installed Android package BEFORE connecting to Supabase.
/// Never default to an environment or skip the check on plugin failure.
/// An unresponsive native MethodChannel must not leave the UI spinning forever.
class AndroidStartupGate {
  const AndroidStartupGate._();

  static const methodChannel = MethodChannel('onespace/environment');
  static const defaultDeadline = Duration(seconds: 6);

  static Future<String> verify({
    Future<String?> Function()? readPackageId,
    Duration timeout = defaultDeadline,
  }) async {
    final String? installed;
    try {
      installed = await (readPackageId ??
          () => methodChannel.invokeMethod<String>('packageId'))()
          .timeout(timeout);
    } on TimeoutException {
      throw StateError('Android startup verification timed out. '
          'No account data or backend was opened. Retry the app.');
    } on MissingPluginException {
      throw StateError('Android startup verification is unavailable. '
          'Please install the correct signed OneSpace app.');
    } on PlatformException {
      throw StateError('Android could not verify this app installation. '
          'Please retry without clearing app data.');
    }
    if (!OneSpaceEnv.packageMatchesEnvironment(installed)) {
      throw StateError('QA/Production configuration mismatch: '
          'this Android package cannot connect to its configured backend. '
          'Please use the correct signed OneSpace version.');
    }
    return installed!;
  }
}

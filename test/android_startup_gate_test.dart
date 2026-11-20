import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/core/android_startup_gate.dart';
import 'package:onespace/core/app_env.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('QA startup verifies the actual Android package before opening backend', () async {
    final actual = await AndroidStartupGate.verify(
      readPackageId: () async => OneSpaceEnv.expectedAndroidPackage,
    );
    expect(actual, OneSpaceEnv.expectedAndroidPackage);
  });

  test('a different package is refused rather than accessing the wrong backend', () async {
    final wrong = OneSpaceEnv.isProduction ? 'onespace.qa' : 'live.onespace.app';
    await expectLater(
      AndroidStartupGate.verify(readPackageId: () async => wrong),
      throwsA(isA<StateError>()),
    );
  });

  test('a dead or missing native package callback fails visibly and quickly', () async {
    final pending = Completer<String?>();
    await expectLater(
      AndroidStartupGate.verify(
        readPackageId: () => pending.future,
        timeout: const Duration(milliseconds: 10),
      ),
      throwsA(isA<StateError>().having(
        (e) => e.message.toString(), 'error', contains('timed out'))),
    );
    await expectLater(
      AndroidStartupGate.verify(
        readPackageId: () async => null,
      ),
      throwsA(isA<StateError>().having(
        (e) => e.message.toString(), 'error', contains('mismatch'))),
    );
  });

  test('native channel failures fail closed without exposing account data', () async {
    await expectLater(
      AndroidStartupGate.verify(
        readPackageId: () async => throw MissingPluginException(),
      ),
      throwsA(isA<StateError>().having(
        (e) => e.message.toString(), 'error', contains('unavailable'))),
    );
    await expectLater(
      AndroidStartupGate.verify(
        readPackageId: () async =>
          throw PlatformException(code: 'NATIVE_CHANNEL_FAILED'),
      ),
      throwsA(isA<StateError>().having(
        (e) => e.message.toString(), 'error', contains('could not verify'))),
    );
  });
}

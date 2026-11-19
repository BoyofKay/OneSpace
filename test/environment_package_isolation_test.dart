import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/core/app_env.dart';

void main() {
  test('installed package must match selected backend before initializing auth', () {
    expect(OneSpaceEnv.packageMatchesEnvironment(
      OneSpaceEnv.expectedAndroidPackage), isTrue);
    expect(OneSpaceEnv.packageMatchesEnvironment(
      OneSpaceEnv.isProduction ? 'onespace.qa' : 'live.onespace.app'), isFalse);
    expect(OneSpaceEnv.packageMatchesEnvironment(null), isFalse);
    expect(OneSpaceEnv.packageMatchesEnvironment('com.onespace.onespace'), isFalse);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/core/ios_build_configuration.dart';

void main() {
  test('QA iOS identity is accepted only for QA', () {
    expect(IosBuildConfiguration.matches(
      environment: 'qa', bundleId: 'com.onespace.onespace.qa',
      authScheme: 'onespace-preview', production: false), isTrue);
    expect(IosBuildConfiguration.matches(
      environment: 'qa', bundleId: 'com.onespace.onespace.qa',
      authScheme: 'onespace-preview', production: true), isFalse);
  });
  test('production iOS identity is accepted only for production', () {
    expect(IosBuildConfiguration.matches(
      environment: 'production', bundleId: 'com.onespace.onespace',
      authScheme: 'onespace', production: true), isTrue);
    expect(IosBuildConfiguration.matches(
      environment: 'production', bundleId: 'com.onespace.onespace',
      authScheme: 'onespace-preview', production: true), isFalse);
    expect(IosBuildConfiguration.matches(
      environment: 'production', bundleId: 'com.onespace.onespace.qa',
      authScheme: 'onespace', production: true), isFalse);
  });
}

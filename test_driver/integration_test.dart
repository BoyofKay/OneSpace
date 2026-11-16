// Host side of the screenshot robot. Screenshots are taken by
// tools/screenshots/watch.py with adb when the app prints a SNAP line.
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();

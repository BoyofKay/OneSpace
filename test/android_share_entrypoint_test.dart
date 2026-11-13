import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android share integration stays available without a redundant in-app action', () {
    final app = File('lib/main.dart').readAsStringSync();
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final activity = File('android/app/src/main/kotlin/com/onespace/onespace/MainActivity.kt').readAsStringSync();

    expect(app.contains("Save a link or idea"), isFalse);
    expect(app.contains("ShareIntakeScreen(shared:data)"), isTrue);
    expect(app.contains("takePendingShare"), isTrue);
    expect(manifest.contains('android.intent.action.SEND'), isTrue);
    expect(manifest.contains('android:mimeType="text/plain"'), isTrue);
    expect(activity.contains('captureShare(intent)'), isTrue);
  });
}

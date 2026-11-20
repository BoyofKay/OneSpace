import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/core/android_startup_gate.dart';
import 'package:onespace/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android bootstrap renders before package verification, then shows failure instead of black',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(AndroidStartupGate.methodChannel,
        (_) async => 'live.onespace.app');
    addTearDown(() {
      messenger.setMockMethodCallHandler(AndroidStartupGate.methodChannel, null);
      debugDefaultTargetPlatformOverride = null;
    });

    await tester.pumpWidget(OneSpaceBootstrap(
      startupClock: Stopwatch()..start(),
    ));
    // First frame must be informative even before any native channel replies.
    expect(find.text('OneSpace'), findsOneWidget);
    expect(find.text('Two of Us. One Space'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('QA/Production configuration mismatch'),
      findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    // This mismatched install was never allowed to initialize Supabase.
  });
}

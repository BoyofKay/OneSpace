// UI audit robot. Runs the real app (QA backend) as a Linux desktop program
// under a virtual screen, no Android emulator, and photographs every main
// screen at phone, landscape phone, foldable and tablet sizes, in English and
// Arabic, light and dark, normal and large text, and with the keyboard up.
// Signs in as the fictional demo couple (Omar & Lina) in QA.
//
//   xvfb-run -a flutter test integration_test/ui_audit_test.dart -d linux \
//     --dart-define=ONESPACE_ENV=qa
//   env: DEMO_PASSWORD (required for signed-in screens), AUDIT_OUT (folder),
//        AUDIT_SHAPES (comma list of shape names, default all),
//        AUDIT_VARIANTS (comma list of variant names, default all),
//        AUDIT_RESET=0 (skip resetting the demo space; the workflow resets once)
//
// Runs in .github/workflows/ui-audit.yml. Read-only apart from resetting the
// demo couple's own space to its standard demo content before it starts.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:onespace/main.dart' as app;
import 'package:onespace/l10n/onespace_locale_controller.dart';
import 'package:onespace/theme/onespace_appearance.dart';
import 'package:onespace/features/counters/counters_screen.dart';
import 'package:onespace/features/places/places_screen.dart';
import 'package:onespace/features/notes/notes_screen.dart';
import 'package:onespace/features/calendar/calendar_screen.dart';
import 'package:onespace/features/plans/plans_screen.dart';
import 'package:onespace/features/coordinate/activity_detail_screen.dart';
import 'package:onespace/features/world/trips_screen.dart';
import 'package:onespace/features/occasions/occasions_screen.dart';
import 'package:onespace/features/reminders/reminders_screen.dart';
import 'package:onespace/features/connect/couple_letters_screen.dart';
import 'package:onespace/features/connect/partner_gestures_screen.dart';
import 'package:onespace/features/notifications/notifications_screen.dart';
import 'package:onespace/theme/appearance_settings_screen.dart';

const _url = 'https://ugwrpeduzyzrujkizqfo.supabase.co';
const _key = 'sb_publishable_TtW_uUboFxD4adF5o7FSfA_cpjojMCe';
const _email = 'demo.omar@example.com';

/// Screen shapes in logical pixels (dp), like the real devices.
class _Shape {
  const _Shape(this.name, this.width, this.height);
  final String name;
  final double width, height;
}

const _shapes = [
  _Shape('phone', 393, 852),            // Pixel 8 / most phones
  _Shape('small-phone', 360, 640),      // older small phones
  _Shape('phone-landscape', 852, 393),
  _Shape('foldable-open', 690, 841),    // Pixel Fold / Galaxy Z Fold inner screen
  _Shape('tablet', 800, 1280),          // 10" tablet upright
  _Shape('tablet-landscape', 1280, 800),
];

/// Variants: language, theme, text size, keyboard.
class _Variant {
  const _Variant(this.name, {this.lang = 'en', this.dark = false, this.text = 1.0});
  final String name, lang;
  final bool dark;
  final double text;
}

const _variants = [
  _Variant('en'),
  _Variant('ar', lang: 'ar'),
  _Variant('en-dark', dark: true),
  _Variant('en-bigtext', text: 1.6),
];

List<String>? _envList(String key) {
  final v = Platform.environment[key]?.trim() ?? '';
  return v.isEmpty ? null : v.split(',').map((s) => s.trim()).toList();
}

Future<void> _resetDemoSpace(String password) async {
  final login = await http.post(Uri.parse('$_url/auth/v1/token?grant_type=password'),
      headers: {'apikey': _key, 'Content-Type': 'application/json'},
      body: jsonEncode({'email': _email, 'password': password}));
  if (login.statusCode != 200) throw StateError('Demo login failed: ${login.statusCode}');
  final token = (jsonDecode(login.body) as Map<String, dynamic>)['access_token'] as String;
  final reset = await http.post(Uri.parse('$_url/rest/v1/rpc/demo_reset_space'),
      headers: {'apikey': _key, 'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      body: jsonEncode({'p_mode': 'apart_different_tz', 'p_lang': 'en'}));
  if (reset.statusCode >= 300) throw StateError('Demo reset failed: ${reset.statusCode} ${reset.body}');
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('OneSpace UI audit', (tester) async {
    final out = Directory(Platform.environment['AUDIT_OUT'] ?? '/tmp/ui_audit')..createSync(recursive: true);
    final password = Platform.environment['DEMO_PASSWORD'] ?? '';
    final shapeFilter = _envList('AUDIT_SHAPES');
    final variantFilter = _envList('AUDIT_VARIANTS');
    final shapes = _shapes.where((s) => shapeFilter == null || shapeFilter.contains(s.name)).toList();
    final variants = _variants.where((v) => variantFilter == null || variantFilter.contains(v.name)).toList();
    final logFile = File('${out.path}/audit_log.txt')..writeAsStringSync('');
    void note(String line) {
      debugPrint('AUDIT $line');
      logFile.writeAsStringSync('$line\n', mode: FileMode.append);
    }

    if (password.isNotEmpty && Platform.environment['AUDIT_RESET'] != '0') {
      await _resetDemoSpace(password);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('appearance.palette.v1', 'cleanLight');
    await prefs.setString('appearance.mode.v1', 'light');
    await prefs.setString('appearance.background.v1', 'calm');
    await prefs.setString('appearance.season.v1', 'off');

    const dpr = 2.0;
    tester.view.devicePixelRatio = dpr;
    void resize(_Shape s) {
      tester.view.physicalSize = Size(s.width * dpr, s.height * dpr);
    }
    resize(shapes.first);

    final testOnError = FlutterError.onError;
    final testErrorWidget = ErrorWidget.builder;
    app.main();

    Future<void> wait(double seconds) async {
      for (var i = 0; i < (seconds * 10).round(); i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    var count = 0;
    var prefix = '';
    Future<void> shot(String name) async {
      await wait(1.2);
      final view = tester.binding.renderViews.first;
      final layer = view.debugLayer! as OffsetLayer;
      // The root layer is in physical pixels; save at 1.5x (sharp, not huge).
      final physical = tester.view.physicalSize;
      final bytes = await tester.runAsync(() async {
        final image = await layer.toImage(Offset.zero & physical, pixelRatio: 1.5 / dpr);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        return data!.buffer.asUint8List();
      });
      final file = File('${out.path}/$prefix$name.png');
      await file.writeAsBytes(bytes!);
      // Overflow stripes and build errors are caught by FlutterError and shown
      // in the log; the photo is the evidence.
      count++;
      note('SHOT $prefix$name');
    }

    // Collect layout errors (yellow-black overflow stripes etc.) per screen.
    // Layout errors (overflow stripes etc.) are noted against the screen
    // they happened on, and do not stop the robot.
    FlutterError.onError = (details) {
      final text = details.exceptionAsString().split('\n').first;
      final where = details.stack.toString().split('\n')
          .firstWhere((l) => l.contains('package:onespace'), orElse: () => '');
      note('ERROR $prefix: $text ${where.trim()}');
    };

    try {
      await wait(6);
      SupabaseClient? db;
      for (var i = 0; i < 60 && db == null; i++) {
        try { db = Supabase.instance.client; } catch (_) { await wait(1); }
      }

      // Signed-out screens first.
      if (db == null) throw StateError('The app did not finish starting (Supabase not ready)');
      // Behave like Android (scrolling, page transitions) from here on. Set only
      // after start-up so the Android-only install check is not attempted.
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      if (db.auth.currentUser != null) await db.auth.signOut();
      await wait(4);
      for (final s in shapes) {
        for (final v in variants) {
          resize(s);
          prefix = '${s.name}__${v.name}__';
          OneSpaceLocaleController.instance.selectLanguage(v.lang);
          tester.platformDispatcher.textScaleFactorTestValue = v.text;
          await OneSpaceAppearance.instance.setMode(v.dark ? ThemeMode.dark : ThemeMode.light);
          await wait(1.5);
          await shot('00_sign_in');
          if (v.name == 'en') {
            // Keyboard up over the sign-in form (about 45% of the screen).
            tester.view.viewInsets = FakeViewPadding(bottom: s.height * 0.45 * dpr);
            await wait(1);
            await shot('00_sign_in_keyboard');
            tester.view.resetViewInsets();
          }
        }
      }

      if (password.isEmpty) {
        note('SKIPPED signed-in screens: DEMO_PASSWORD not set');
      } else {
        await db.auth.signInWithPassword(email: _email, password: password);
        for (var i = 0; i < 60 && find.byType(NavigationBar).evaluate().isEmpty
            && find.byType(NavigationRail).evaluate().isEmpty; i++) { await wait(1); }
        await wait(5);

        NavigatorState nav() => tester.state<NavigatorState>(find.byType(Navigator).first);
        Future<void> popAll() async { while (nav().canPop()) { nav().pop(); await wait(0.6); } }
        Future<void> open(Widget screen, String name, {double settle = 4}) async {
          nav().push(MaterialPageRoute<void>(builder: (_) => screen));
          await wait(settle);
          await shot(name);
          await popAll();
        }
        Future<void> tab(IconData outlined, IconData filled, String name) async {
          final f = find.byIcon(outlined).evaluate().isNotEmpty ? find.byIcon(outlined) : find.byIcon(filled);
          if (f.evaluate().isEmpty) { note('MISSING tab $name'); return; }
          await tester.tap(f.first);
          await wait(3);
          await shot(name);
        }
        Future<String?> idOf(String table, String column, String value) async {
          final row = await db!.from(table).select('id').eq(column, value).limit(1).maybeSingle();
          return row?['id']?.toString();
        }
        final weekend = await idOf('activities', 'title', 'Weekend away');
        final trip = await idOf('shared_trips', 'title', 'Istanbul reunion');
        final occasion = await idOf('occasion_plans', 'title', "Lina's birthday");

        for (final s in shapes) {
          for (final v in variants) {
            resize(s);
            prefix = '${s.name}__${v.name}__';
            OneSpaceLocaleController.instance.selectLanguage(v.lang);
            tester.platformDispatcher.textScaleFactorTestValue = v.text;
            await OneSpaceAppearance.instance.setMode(v.dark ? ThemeMode.dark : ThemeMode.light);
            await popAll();
            await wait(2);

            await tab(Icons.today_outlined, Icons.today, '01_today');
            final fab = find.byType(FloatingActionButton);
            if (fab.evaluate().isNotEmpty) {
              await tester.tap(fab.first);
              await wait(2);
              await shot('02_quick_add');
              // Open each Quick add form (English only: the labels are English).
              if (v.lang == 'en') {
                for (final label in ['Reminder', 'To-do', 'Event', 'Note']) {
                  final target = find.text(label);
                  if (target.evaluate().isEmpty) { note('MISSING quick add $label'); continue; }
                  await tester.tap(target.last);
                  await wait(3);
                  final slug = label.toLowerCase().replaceAll(RegExp('[^a-z]'), '');
                  await shot('03_add_$slug');
                  if (v.name == 'en') {
                    tester.view.viewInsets = FakeViewPadding(bottom: s.height * 0.45 * dpr);
                    await wait(1);
                    await shot('03_add_${slug}_keyboard');
                    tester.view.resetViewInsets();
                  }
                  await popAll();
                  await wait(1);
                  final again = find.byType(FloatingActionButton);
                  if (label != 'Note' && again.evaluate().isNotEmpty) {
                    await tester.tap(again.first);
                    await wait(2);
                  }
                }
              } else {
                await popAll();
              }
            } else {
              note('MISSING quick add button');
            }
            await popAll();
            await tab(Icons.bookmark_border, Icons.bookmark, '04_remember');
            await tab(Icons.hub_outlined, Icons.hub, '05_coordinate');
            await tab(Icons.favorite_border, Icons.favorite, '06_connect');
            await tab(Icons.person_outline, Icons.person, '07_me');
            await tab(Icons.today_outlined, Icons.today, '01_today');

            await open(const NotificationsScreen(), '10_notifications');
            await open(const CalendarScreen(), '11_calendar');
            await open(const PlansScreen(), '12_todo_lists');
            await open(const RemindersScreen(), '13_reminders');
            await open(const NotesScreen(), '14_notes');
            await open(const OccasionsScreen(), '15_occasions');
            await open(const TripsScreen(), '16_trips');
            await open(const CountersScreen(), '17_counters');
            await open(const PlacesScreen(), '18_places');
            await open(const PartnerGesturesScreen(), '19_love');
            await open(const CoupleLettersScreen(), '20_letters');
            await open(const AppearanceSettingsScreen(), '21_appearance');
            if (weekend != null) await open(ActivityScreen(id: weekend), '22_activity');
            if (trip != null) await open(TripDetail(tripId: trip), '23_trip');
            if (occasion != null) await open(OccasionDetail(id: occasion), '24_occasion');
          }
        }
      }
    } finally {
      FlutterError.onError = testOnError;
      ErrorWidget.builder = testErrorWidget;
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      tester.view.reset();
      debugDefaultTargetPlatformOverride = null;
    }
    expect(count, greaterThan(0));
  }, timeout: const Timeout(Duration(minutes: 90)));
}

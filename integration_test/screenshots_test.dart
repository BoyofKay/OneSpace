// R80: the screenshot robot. Signs in as the fictional demo couple (Omar & Lina),
// resets their space to fresh demo content, then captures real app screens for
// the website and the app stores. Runs only in .github/workflows/screenshots.yml.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/screenshots_test.dart \
//     --dart-define=DEMO_PASSWORD=... --dart-define=SHOT_SET=core --dart-define=SHOT_LANG=en
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:onespace/main.dart' as app;
import 'package:onespace/theme/onespace_appearance.dart';
import 'package:onespace/features/counters/counters_screen.dart';
import 'package:onespace/features/places/places_screen.dart';
import 'package:onespace/features/notes/notes_screen.dart';
import 'package:onespace/features/calendar/calendar_screen.dart';
import 'package:onespace/features/plans/plans_screen.dart';
import 'package:onespace/features/coordinate/activity_detail_screen.dart';
import 'package:onespace/features/world/trips_screen.dart';
import 'package:onespace/features/occasions/occasions_screen.dart';
import 'package:onespace/features/connect/couple_letters_screen.dart';
import 'package:onespace/features/checkins/checkins_screen.dart';
import 'package:onespace/features/connect/partner_gestures_screen.dart';
import 'package:onespace/features/connect/shared_experiences_screen.dart';
import 'package:onespace/features/notifications/notifications_screen.dart';
import 'package:onespace/features/memories/memories_screen.dart';
import 'package:onespace/theme/appearance_settings_screen.dart';

const _url = 'https://ugwrpeduzyzrujkizqfo.supabase.co';
const _key = 'sb_publishable_TtW_uUboFxD4adF5o7FSfA_cpjojMCe';
const _email = String.fromEnvironment('DEMO_EMAIL', defaultValue: 'demo.omar@example.com');
const _password = String.fromEnvironment('DEMO_PASSWORD');
const _set = String.fromEnvironment('SHOT_SET', defaultValue: 'core'); // core | themes | together
const _lang = String.fromEnvironment('SHOT_LANG', defaultValue: 'en'); // en | ar

/// Fresh demo content before the app starts, so nothing is cached from a
/// previous run. Uses plain HTTP with the public key and the demo login.
Future<void> _resetDemoSpace() async {
  final login = await http.post(Uri.parse('$_url/auth/v1/token?grant_type=password'),
      headers: {'apikey': _key, 'Content-Type': 'application/json'},
      body: jsonEncode({'email': _email, 'password': _password}));
  if (login.statusCode != 200) throw StateError('Demo login failed: ${login.statusCode}');
  final token = (jsonDecode(login.body) as Map<String, dynamic>)['access_token'] as String;
  final mode = _set == 'together' ? 'living_together' : 'apart_different_tz';
  final reset = await http.post(Uri.parse('$_url/rest/v1/rpc/demo_reset_space'),
      headers: {'apikey': _key, 'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      body: jsonEncode({'p_mode': mode, 'p_lang': _lang}));
  if (reset.statusCode >= 300) throw StateError('Demo reset failed: ${reset.statusCode} ${reset.body}');
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('OneSpace screenshots ($_set, $_lang)', (tester) async {
    await _resetDemoSpace();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('appearance.palette.v1', 'cleanLight');
    await prefs.setString('appearance.mode.v1', 'light');
    await prefs.setString('appearance.background.v1', 'calm');
    await prefs.setString('appearance.season.v1', 'off');

    app.main();
    Future<void> wait(double seconds) async {
      for (var i = 0; i < (seconds * 10).round(); i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await wait(4);
    SupabaseClient? db;
    for (var i = 0; i < 60 && db == null; i++) {
      try { db = Supabase.instance.client; } catch (_) { await wait(1); }
    }
    if (db!.auth.currentUser == null) {
      await db.auth.signInWithPassword(email: _email, password: _password);
    }
    // Wait for the home screen (bottom navigation) to appear.
    for (var i = 0; i < 60 && find.byType(NavigationBar).evaluate().isEmpty; i++) { await wait(1); }
    await wait(5);
    if (Platform.isAndroid) await binding.convertFlutterSurfaceToImage();
    await wait(1);

    var count = 0;
    Future<void> shot(String name) async {
      await wait(1.5);
      await binding.takeScreenshot('${_set}_${_lang}_$name');
      count++;
    }
    NavigatorState nav() => tester.state<NavigatorState>(find.byType(Navigator).first);
    Future<void> open(Widget screen, String name, {double settle = 5, Future<void> Function()? then}) async {
      nav().push(MaterialPageRoute<void>(builder: (_) => screen));
      await wait(settle);
      await shot(name);
      if (then != null) await then();
      while (nav().canPop()) { nav().pop(); await wait(0.6); }
    }
    Future<void> tab(IconData outlined, IconData filled, String name, {double settle = 4}) async {
      final f = find.byIcon(outlined).evaluate().isNotEmpty ? find.byIcon(outlined) : find.byIcon(filled);
      if (f.evaluate().isEmpty) return;
      await tester.tap(f.first);
      await wait(settle);
      await shot(name);
    }
    Future<String?> idOf(String table, String column, String value) async {
      final row = await db!.from(table).select('id').eq(column, value).limit(1).maybeSingle();
      return row?['id']?.toString();
    }
    final ar = _lang == 'ar';

    Future<void> today() => tab(Icons.today_outlined, Icons.today, 'today', settle: 6);

    if (_set == 'themes') {
      for (final palette in OneSpacePalette.values) {
        await OneSpaceAppearance.instance.setPalette(palette);
        await wait(2);
        await tab(Icons.today_outlined, Icons.today, 'today_${palette.name}');
        await open(const CountersScreen(), 'counters_${palette.name}');
        await open(const PartnerGesturesScreen(), 'love_${palette.name}');
      }
    } else if (_set == 'together') {
      await today();
      await open(const PartnerGesturesScreen(), 'love');
      await open(const PlansScreen(), 'lists');
      await open(const CountersScreen(), 'counters');
    } else {
      await today();
      final fab = find.byType(FloatingActionButton);
      if (fab.evaluate().isNotEmpty) {
        await tester.tap(fab.first);
        await wait(2.5);
        await shot('quickadd');
        nav().maybePop();
        await wait(1);
      }
      await tab(Icons.bookmark_border, Icons.bookmark, 'remember');
      await tab(Icons.hub_outlined, Icons.hub, 'coordinate');
      await tab(Icons.favorite_border, Icons.favorite, 'connect');
      await tab(Icons.person_outline, Icons.person, 'me');
      await today();

      await open(const NotificationsScreen(), 'notifications');
      await open(const CountersScreen(), 'counters');
      await open(const PlacesScreen(), 'places', then: () async {
        final map = find.byIcon(Icons.map_outlined);
        if (map.evaluate().isNotEmpty) {
          await tester.tap(map.first);
          await wait(7); // map tiles
          await shot('places_map');
        }
      });
      await open(const NotesScreen(), 'notes');
      await open(const CalendarScreen(), 'calendar');
      await open(const PlansScreen(), 'lists');
      final weekend = await idOf('activities', 'title', ar ? 'عطلة نهاية الأسبوع' : 'Weekend away');
      if (weekend != null) {
        await open(ActivityScreen(id: weekend), 'activity');
        await open(ActivityScreen(id: weekend, focusConversation: true), 'activity_chat');
      }
      final sofa = await idOf('activities', 'title', ar ? 'أريكة جديدة' : 'A new sofa');
      if (sofa != null) await open(ActivityScreen(id: sofa), 'decision');
      final trip = await idOf('shared_trips', 'title', ar ? 'لقاء إسطنبول' : 'Istanbul reunion');
      if (trip != null) await open(TripDetail(tripId: trip), 'trip');
      final occasion = await idOf('occasion_plans', 'title', ar ? 'عيد ميلاد لينا' : "Lina's birthday");
      if (occasion != null) await open(OccasionDetail(id: occasion), 'occasion');
      await open(const CoupleLettersScreen(), 'letters');
      await open(const CheckinsScreen(), 'checkins');
      await open(const PartnerGesturesScreen(), 'love');
      await open(const SharedExperiencesScreen(), 'experiences');
      await open(const MemoriesScreen(), 'memories');
      await open(const AppearanceSettingsScreen(), 'appearance');
    }
    expect(count, greaterThan(0));
  }, timeout: const Timeout(Duration(minutes: 25)));
}

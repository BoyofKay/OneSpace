// R80: the screenshot robot. Signs in as the fictional demo couple (Omar & Lina),
// resets their space to fresh demo content, then captures real app screens for
// the website and the app stores. Runs only in .github/workflows/screenshots.yml.
//
//   flutter build apk --debug -t integration_test/screenshots_test.dart
//   adb shell setprop debug.onespace.shots core-en; adb shell setprop debug.onespace.pw ...
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/screenshots_test.dart --use-application-binary=<apk>
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
import 'package:onespace/features/trips/trips_screen.dart';
import 'package:onespace/features/occasions/occasions_screen.dart';
import 'package:onespace/features/connect/couple_letters_screen.dart';
import 'package:onespace/features/connect/partner_gestures_screen.dart';
import 'package:onespace/features/notifications/notifications_screen.dart';
import 'package:onespace/theme/appearance_settings_screen.dart';
import 'package:onespace/core/account_content_scope.dart';
import 'package:onespace/features/calendar/calendar_event_editor.dart';
import 'package:onespace/features/reminders/reminders_screen.dart';
import 'package:onespace/features/coordinate/new_activity_screen.dart';
import 'package:onespace/features/contacts/contact_cards_screen.dart';
import 'package:onespace/features/checkins/checkins_screen.dart';
import 'package:onespace/features/connect/shared_experiences_screen.dart';
import 'package:onespace/features/memories/scrapbook_studio_screen.dart';
import 'package:onespace/features/memories/selfie_calendar_screen.dart';
import 'package:onespace/features/share_in/share_intake_rules.dart';
import 'package:onespace/features/share_in/share_intake_screen.dart';
import 'package:onespace/features/share_in/items_to_sort_screen.dart';

const _url = 'https://ugwrpeduzyzrujkizqfo.supabase.co';
const _key = 'sb_publishable_TtW_uUboFxD4adF5o7FSfA_cpjojMCe';
const _email = 'demo.omar@example.com';
// Set by tools/screenshots/run.sh with `adb shell setprop` so one prebuilt APK
// serves every run: debug.onespace.shots = <set>-<lang>, debug.onespace.pw.
//   set: core | themes | together | video | tutorial     lang: en | ar
late String _password;
late String _set;
late String _lang;

Future<String> _prop(String key, String fallback) async {
  try {
    final r = await Process.run('getprop', [key]);
    final v = (r.stdout as String).trim();
    return v.isEmpty ? fallback : v;
  } catch (_) {
    return fallback;
  }
}

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
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('OneSpace screenshots', (tester) async {
    final spec = await _prop('debug.onespace.shots', 'core-en');
    _set = spec.split('-').first;
    _lang = spec.endsWith('-ar') ? 'ar' : 'en';
    _password = await _prop('debug.onespace.pw', '');
    debugPrint('SHOTS $_set $_lang');
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

    // The host (tools/screenshots/watch.py) sees SNAP lines and runs
    // `adb exec-out screencap`, so the real status bar is included and the app
    // doesn't have to render a copy of itself (much lighter on the emulator).
    var count = 0;
    Future<void> shot(String name) async {
      await wait(1.5);
      debugPrint('SNAP ${_set}_${_lang}_$name');
      await wait(2.5);
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
      if (f.evaluate().isNotEmpty) await tester.tap(f.first);
      await wait(settle);
      await shot(name);
    }
    Future<String?> idOf(String table, String column, String value) async {
      final row = await db!.from(table).select('id').eq(column, value).limit(1).maybeSingle();
      return row?['id']?.toString();
    }
    final ar = _lang == 'ar';

    Future<void> today() => tab(Icons.today_outlined, Icons.today, 'today', settle: 6);

    // Video set: tools/screenshots/run.sh records the screen; these markers
    // (device clock) tell tools/screenshots/cut_clips.py where each clip is.
    Future<void> clip(String name, Future<void> Function() body) async {
      debugPrint('CLIP_START $name ${DateTime.now().millisecondsSinceEpoch}');
      await wait(0.8);
      await body();
      await wait(0.8);
      debugPrint('CLIP_END $name ${DateTime.now().millisecondsSinceEpoch}');
    }
    Future<void> scroll(double dy, {double seconds = 1.6}) async {
      final s = find.byType(Scrollable);
      if (s.evaluate().isEmpty) return;
      await tester.timedDrag(s.first, Offset(0, dy), Duration(milliseconds: (seconds * 1000).round()));
      await wait(0.8);
    }
    Future<void> push(Widget screen, {double settle = 3}) async {
      nav().push(MaterialPageRoute<void>(builder: (_) => screen));
      await wait(settle);
    }
    Future<void> popAll() async { while (nav().canPop()) { nav().pop(); await wait(0.8); } }
    Future<void> tapIcon(IconData a, IconData b, {double settle = 2.5}) async {
      final f = find.byIcon(a).evaluate().isNotEmpty ? find.byIcon(a) : find.byIcon(b);
      if (f.evaluate().isNotEmpty) { await tester.tap(f.first); await wait(settle); }
    }

    // Tutorial set (D110): one short video per feature, English first. Each
    // CHAPTER line marks where a caption starts inside its clip; cut_clips.py
    // turns them into <lang>_<clip>.chapters.json for the website. Every step
    // is best-effort: a missing button skips that step, never the whole run.
    String clipName = '';
    int clipStart = 0;
    var chapterNo = 0;
    void chapter() {
      debugPrint('CHAPTER $clipName ${chapterNo++} ${DateTime.now().millisecondsSinceEpoch - clipStart}');
    }
    Future<void> scene(String name, Future<void> Function() body) async {
      await clip(name, () async {
        clipName = name; chapterNo = 0; clipStart = DateTime.now().millisecondsSinceEpoch;
        try { await body(); } catch (e) { debugPrint('SCENE_WARN $name $e'); }
        try { await popAll(); } catch (_) {}
      });
      await shot('tut_$name');
    }
    Future<bool> tapFinder(Finder f, {double settle = 2}) async {
      if (f.evaluate().isEmpty) return false;
      await tester.ensureVisible(f.first);
      await wait(0.4);
      await tester.tap(f.first);
      await wait(settle);
      return true;
    }
    Future<bool> tapText(String text, {double settle = 2}) async =>
        await tapFinder(find.text(text), settle: settle) ||
        await tapFinder(find.textContaining(text), settle: settle);
    Future<bool> tapTip(String tip, {double settle = 2}) => tapFinder(find.byTooltip(tip), settle: settle);
    Future<void> type(String text, {int field = 0}) async {
      final f = find.byType(EditableText);
      if (f.evaluate().length <= field) return;
      final target = f.at(field);
      await tester.ensureVisible(target);
      await tester.tap(target);
      await wait(0.5);
      for (var i = 1; i <= text.length; i++) {
        await tester.enterText(target, text.substring(0, i));
        await tester.pump(const Duration(milliseconds: 55));
      }
      await wait(0.6);
      FocusManager.instance.primaryFocus?.unfocus();
      await wait(0.6);
    }
    Future<void> back() async { if (nav().canPop()) { nav().pop(); await wait(1.2); } }

    Future<void> tutorials() async {
      final scope = await AccountContentScope.load(db!);
      final sp = scope.sharedSpaceId!;
      final now = DateTime.now();
      final toFriday = (DateTime.friday - now.weekday + 7) % 7;
      final friday = now.add(Duration(days: toFriday == 0 ? 7 : toFriday));

      await scene('today', () async {
        await tapIcon(Icons.today_outlined, Icons.today, settle: 3);
        chapter(); await wait(2.5);
        chapter(); await wait(2);
        chapter(); await scroll(-260); await wait(1.5);
        chapter(); await scroll(-360); await wait(2);
        await scroll(900, seconds: 1);
        chapter();
        final fab = find.byType(FloatingActionButton);
        if (fab.evaluate().isNotEmpty) { await tester.tap(fab.first); await wait(3.5); nav().maybePop(); await wait(1); }
      });

      await scene('calendar', () async {
        await push(CalendarEventEditor(spaceId: sp, initialDate: friday), settle: 2.5);
        chapter(); await type("Dinner with Lina's parents");
        chapter(); await scroll(-300); await wait(2);
        chapter(); await scroll(-400); await wait(2.5);
        await back();
        await push(const CalendarScreen(), settle: 3);
        chapter(); await tapText('Day', settle: 3); await wait(2); await scroll(-300); await wait(1.5);
      });

      await scene('todo', () async {
        await push(const PlansScreen(), settle: 3);
        chapter();
        if (await tapText('New list') || await tapFinder(find.byType(FloatingActionButton))) {
          await type('Weekend groceries');
          chapter();
          await type('Milk\nEggs\nBread\nTomatoes\nCoffee', field: 1);
          await wait(1.5);
          await back();
        }
        chapter();
        if (await tapText('Groceries', settle: 3)) {
          for (final item in find.byType(Checkbox).evaluate().take(2).toList()) {
            await tester.tap(find.byWidget(item.widget)); await wait(1.2);
          }
          chapter(); await scroll(-400); await wait(2);
        }
      });

      await scene('reminders', () async {
        await push(ReminderEditorScreen(spaceId: sp, initialShared: true), settle: 2.5);
        chapter(); await type('Renew passport');
        chapter(); await scroll(-300); await wait(2);
        chapter(); await scroll(-300); await wait(2);
        await back();
        await push(const RemindersScreen(), settle: 3);
        chapter(); await wait(2.5);
      });

      await scene('notes', () async {
        await push(NoteEditorScreen(spaceId: sp), settle: 2.5);
        chapter(); await type('Gift ideas for Mum');
        await tapTip('Bullets', settle: 1); await type('Scarf from the market', field: 1);
        chapter(); await wait(2);
        chapter(); await scroll(-300); await wait(2);
        await back();
        await push(const NotesScreen(), settle: 3);
        await tapText('Weekend away ideas', settle: 3); await wait(2);
      });

      await scene('activities', () async {
        await push(NewActivityScreen(scope: scope), settle: 2.5);
        chapter(); await wait(2); await scroll(-250); await wait(1.5);
        await back();
        final sofa = await idOf('activities', 'title', 'A new sofa');
        if (sofa != null) {
          await push(ActivityScreen(id: sofa), settle: 3.5);
          chapter(); await scroll(-350); await wait(2);
          chapter(); await back();
          await push(ActivityScreen(id: sofa, focusConversation: true), settle: 3.5); await wait(2); await back();
          await push(ActivityScreen(id: sofa), settle: 3);
          chapter(); if (await tapTip('Compare options', settle: 3)) { await wait(2.5); await back(); }
          chapter(); await scroll(-700, seconds: 2); await wait(2);
        }
      });

      await scene('trips', () async {
        await push(const TripsScreen(), settle: 3);
        chapter(); await wait(2);
        final trip = await idOf('shared_trips', 'title', 'Istanbul reunion');
        if (trip != null) {
          await push(TripDetail(tripId: trip), settle: 3.5);
          chapter(); await scroll(-350); await wait(2);
          chapter(); await scroll(-350); await wait(2);
          chapter(); await scroll(-400); await wait(2);
          chapter(); await scroll(-500); await wait(2);
        }
      });

      await scene('occasions', () async {
        await push(OccasionEditor(spaceId: sp, initialKind: 'birthday'), settle: 2.5);
        chapter(); await wait(1.5); await scroll(-300); await wait(1.5);
        await back();
        final occ = await idOf('occasion_plans', 'title', "Lina's birthday");
        if (occ != null) {
          await push(OccasionDetail(id: occ), settle: 3.5);
          chapter(); await scroll(-300); await wait(2);
          chapter(); await scroll(-350); await wait(2);
          chapter(); await scroll(-350); await wait(2);
          chapter(); await scroll(-450); await wait(2);
        }
      });

      await scene('counters', () async {
        await push(const CountersScreen(), settle: 3);
        chapter();
        if (await tapText('Add a counter', settle: 2.5)) { await type('Our wedding'); await scroll(-300); chapter(); await wait(1.5); await back(); }
        chapter(); await tapText('Wedding day', settle: 3); await wait(2.5); await back();
        chapter(); await tapTip('Timelines', settle: 3); await wait(1.5); await scroll(-300); await wait(1.5);
      });

      await scene('places', () async {
        await push(const PlacesScreen(), settle: 3);
        chapter(); await tapText('Nook Café', settle: 3); await wait(2); await back();
        chapter(); await scroll(-400); await wait(1.5); await tapText('Santorini', settle: 3); await wait(2); await back();
        chapter();
        final map = find.byIcon(Icons.map_outlined);
        if (map.evaluate().isNotEmpty) { await tester.tap(map.first); await wait(7); await back(); }
        chapter(); await tapText('Santorini', settle: 3); await scroll(-400); await tapText('Plan a trip', settle: 3); await wait(2);
      });

      await scene('contacts', () async {
        await push(const ContactCardsScreen(), settle: 3);
        chapter(); await wait(2);
        chapter(); await tapText('Dr. Sara', settle: 3); await wait(2);
        chapter(); await scroll(-300); await wait(2);
        chapter(); await wait(1.5);
      });

      await scene('letters', () async {
        await push(CoupleLetterEditor(spaceId: sp), settle: 2.5);
        chapter(); await type('For your graduation'); await type('I am so proud of you. Open this when you have your gown on.', field: 1);
        chapter(); await scroll(-300); await wait(2);
        chapter(); await wait(1); await back();
        await push(const CoupleLettersScreen(), settle: 3);
        chapter(); await tapText('Thinking of you', settle: 3); await wait(2.5);
      });

      await scene('gestures', () async {
        await push(const PartnerGesturesScreen(), settle: 3);
        chapter(); await tapText('Send a hug', settle: 3);
        chapter(); await wait(2);
        chapter(); await push(const PartnerGesturesScreen(manageOnly: true), settle: 3); await scroll(-300); await wait(1.5); await back();
        chapter(); if (await tapText('Create my own gesture', settle: 2.5)) { await type('Coffee is on me'); await wait(1.5); }
      });

      await scene('checkins', () async {
        await push(const CheckinsScreen(), settle: 3);
        chapter(); await wait(2);
        chapter(); await scroll(-300); await wait(2);
        chapter(); await scroll(-300); await wait(2);
        chapter(); await scroll(600, seconds: 1); await wait(1.5);
      });

      await scene('experiences', () async {
        await push(ExperienceEditor(spaceId: sp, initialKind: 'show'), settle: 2.5);
        chapter(); await type('Slow Horses'); await scroll(-250); await wait(1.5);
        await back();
        await push(const SharedExperiencesScreen(), settle: 3);
        chapter(); await wait(2);
        chapter(); await tapText('The Great British Bake Off', settle: 3); await wait(2); await back();
        chapter(); await tapText('Before Sunrise', settle: 3); await scroll(-300); await wait(2);
      });

      await scene('memories', () async {
        await push(ScrapbookStudioScreen(spaceId: sp), settle: 3.5);
        chapter(); await wait(2.5);
        chapter(); await scroll(-300); await wait(2);
        await back();
        final book = await idOf('memories', 'title', 'Our year in pages');
        if (book != null) { await push(ScrapbookStudioScreen(spaceId: sp, memoryId: book), settle: 3.5); }
        chapter(); await wait(2);
        chapter(); await scroll(-300); await wait(1.5); await back();
        await push(SelfieCalendarScreen(spaceId: sp), settle: 3.5);
        chapter(); await wait(2.5);
      });

      await scene('share_in', () async {
        await push(const ShareIntakeScreen(shared: IncomingShare(
          title: 'Linen picnic blanket', link: 'https://shop.example.com/linen-picnic-blanket', note: '')), settle: 3.5);
        chapter(); await wait(2);
        chapter(); await scroll(-250); await wait(2);
        chapter(); await scroll(-300); await wait(1.5); await back();
        await push(const ItemsToSortScreen(), settle: 3);
        chapter(); await wait(2.5);
      });
    }

    if (_set == 'tutorial') {
      await tutorials();
    } else if (_set == 'video') {
      await clip('tour', () async {
        await wait(1.5);
        await scroll(-420); await scroll(-420); await scroll(840, seconds: 1.2);
        await tapIcon(Icons.bookmark_border, Icons.bookmark);
        await tapIcon(Icons.hub_outlined, Icons.hub);
        await tapIcon(Icons.favorite_border, Icons.favorite);
        await tapIcon(Icons.today_outlined, Icons.today);
      });
      await clip('quickadd', () async {
        final fab = find.byType(FloatingActionButton);
        if (fab.evaluate().isNotEmpty) { await tester.tap(fab.first); await wait(3); nav().maybePop(); await wait(1); }
      });
      await clip('counters', () async {
        await push(const CountersScreen(), settle: 3.5);
        await scroll(-500, seconds: 2); await wait(1); await scroll(500, seconds: 1.4);
        await popAll();
      });
      final weekend = await idOf('activities', 'title', ar ? 'عطلة نهاية الأسبوع' : 'Weekend away');
      if (weekend != null) {
        await clip('plan', () async {
          await push(ActivityScreen(id: weekend), settle: 3.5);
          await scroll(-450, seconds: 1.8); await wait(1);
          await popAll();
          await push(ActivityScreen(id: weekend, focusConversation: true), settle: 4);
          await wait(1.5);
          await popAll();
        });
      }
      await clip('places', () async {
        await push(const PlacesScreen(), settle: 3);
        await scroll(-300); await scroll(300, seconds: 1);
        final map = find.byIcon(Icons.map_outlined);
        if (map.evaluate().isNotEmpty) {
          await tester.tap(map.first); await wait(6);
          final m = find.byType(Scrollable).evaluate().isEmpty ? find.byType(Listener) : find.byType(Scrollable);
          if (m.evaluate().isNotEmpty) { await tester.timedDrag(m.first, const Offset(-160, 60), const Duration(milliseconds: 1500)); await wait(2); }
        }
        await popAll();
      });
      final trip = await idOf('shared_trips', 'title', ar ? 'لقاء إسطنبول' : 'Istanbul reunion');
      if (trip != null) {
        await clip('trip', () async {
          await push(TripDetail(tripId: trip), settle: 3.5);
          await scroll(-500, seconds: 2); await scroll(-500, seconds: 2); await wait(1);
          await popAll();
        });
      }
      await clip('love', () async {
        await push(const PartnerGesturesScreen(), settle: 3.5);
        await scroll(-400, seconds: 1.8); await wait(1); await scroll(400, seconds: 1.2);
        await popAll();
      });
      await clip('letters', () async {
        await push(const CoupleLettersScreen(), settle: 3.5);
        await wait(2);
        await popAll();
      });
      await clip('themes', () async {
        await push(const AppearanceSettingsScreen(), settle: 3);
        for (final p in [OneSpacePalette.softRose, OneSpacePalette.oceanTeal, OneSpacePalette.lavenderDusk, OneSpacePalette.midnightBlue, OneSpacePalette.desertSand, OneSpacePalette.cleanLight]) {
          await OneSpaceAppearance.instance.setPalette(p);
          await wait(1.6);
        }
        await popAll();
        await OneSpaceAppearance.instance.setPalette(OneSpacePalette.midnightBlue);
        await wait(2.5);
        await OneSpaceAppearance.instance.setPalette(OneSpacePalette.cleanLight);
        await wait(1.5);
      });
      await shot('video_done');
    } else if (_set == 'themes') {
      for (final palette in OneSpacePalette.values) {
        await OneSpaceAppearance.instance.setPalette(palette);
        await wait(2);
        await tab(Icons.today_outlined, Icons.today, 'today_${palette.name}');
        await open(const CountersScreen(), 'counters_${palette.name}');
        await open(const PartnerGesturesScreen(), 'love_${palette.name}');
      }
    } else if (_set == 'together') {
      await wait(4);
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
      await open(const PartnerGesturesScreen(), 'love');
      await open(const AppearanceSettingsScreen(), 'appearance');

    }
    expect(count, greaterThan(0));
  }, timeout: const Timeout(Duration(minutes: 40)));
}

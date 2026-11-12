import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'features/auth/auth_gate.dart';
import 'core/secure_auth_storage.dart';
import 'core/performance_timings.dart';
import 'features/lists/lists_screen.dart';
import 'features/notes/notes_screen.dart';
import 'features/plans/plans_screen.dart';
import 'features/profile/profile_settings_screen.dart';
import 'features/spaces/shared_space_screen.dart';
import 'l10n/onespace_locale_controller.dart';
import 'l10n/onespace_strings.dart';

Future<void> main() async {
  final startupClock = Stopwatch()..start();
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://ugwrpeduzyzrujkizqfo.supabase.co',
    publishableKey: 'sb_publishable_TtW_uUboFxD4adF5o7FSfA_cpjojMCe',
    authOptions: FlutterAuthClientOptions(
      localStorage: SecureAuthStorage(),
    ),
  );
  PerformanceTimings.instance.record(
    'Supabase initialization', startupClock.elapsed);
  WidgetsBinding.instance.addPostFrameCallback((_) {
    PerformanceTimings.instance.record('First app frame', startupClock.elapsed);
  });
  runApp(const OneSpaceApp());
}

class OneSpaceApp extends StatelessWidget {
  const OneSpaceApp({super.key});

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF20334A);
    const teal = Color(0xFF167E81);
    return ValueListenableBuilder<Locale?>(
      valueListenable: OneSpaceLocaleController.instance,
      builder: (context, currentLocale, child) => MaterialApp(
        title: 'OneSpace',
        locale: currentLocale,
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFFF7F8FA),
          colorScheme: ColorScheme.fromSeed(seedColor: teal),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFFF7F8FA),
            foregroundColor: ink,
            centerTitle: false,
          ),
        ),
        home: const AuthGate(signedIn: OneSpaceHome()),
      ),
    );
  }
}

class OneSpaceHome extends StatefulWidget {
  const OneSpaceHome({super.key});

  @override
  State<OneSpaceHome> createState() => _OneSpaceHomeState();
}

class _OneSpaceHomeState extends State<OneSpaceHome> {
  int selectedIndex = 0;
  int _dashboardRefreshToken = 0;
  bool _showProfile = false;
  bool _profileVisited = false;
  final Set<int> _visited = {0};

  void _navigate(int index) {
    if (!mounted || (selectedIndex == index && !_showProfile)) return;
    setState(() {
      if (index == 0 && selectedIndex != 0) _dashboardRefreshToken++;
      selectedIndex = index;
      _showProfile = false;
      _visited.add(index);
    });
  }

  void _openProfile() {
    setState(() {
      _showProfile = true;
      _profileVisited = true;
    });
  }

  void _closeProfile() {
    setState(() => _showProfile = false);
  }

  @override
  Widget build(BuildContext context) {
    // Lazy IndexedStack keeps previously visited tabs alive while not
    // starting the network streams of tabs the user has never opened.
    final visiblePage = _showProfile ? 4 : selectedIndex;
    return Scaffold(
      appBar: AppBar(
        leading: _showProfile
            ? IconButton(
                tooltip: tr(context, 'backHome'),
                icon: const Icon(Icons.arrow_back),
                onPressed: _closeProfile,
              )
            : null,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('OneSpace',
                style: TextStyle(fontWeight: FontWeight.w800)),
            Text(tr(context, 'tagline'),
                style: const TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          if (!_showProfile)
            IconButton(
              key: const Key('profileTopBarButton'),
              tooltip: tr(context, 'profile'),
              onPressed: _openProfile,
              icon: const Icon(Icons.account_circle_outlined, size: 28),
            ),
        ],
      ),
      body: SafeArea(
        child: IndexedStack(
          index: visiblePage,
          children: [
            SharedSpaceScreen(
              refreshToken: _dashboardRefreshToken,
              onOpenPlans: () => _navigate(1),
              onOpenLists: () => _navigate(2),
              onOpenNotes: () => _navigate(3),
            ),
            if (_visited.contains(1))
              PlansScreen(onOpenSpace: () => _navigate(0))
            else
              const SizedBox.shrink(),
            if (_visited.contains(2))
              const ListsScreen()
            else
              const SizedBox.shrink(),
            if (_visited.contains(3))
              const NotesScreen()
            else
              const SizedBox.shrink(),
            if (_profileVisited)
              const ProfileSettingsScreen()
            else
              const SizedBox.shrink(),
          ],
        ),
      ),
      bottomNavigationBar: _showProfile ? null : NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: _navigate,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: tr(context, 'home'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.checklist_rounded),
            label: tr(context, 'plans'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.shopping_cart_outlined),
            label: tr(context, 'lists'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.sticky_note_2_outlined),
            label: tr(context, 'notes'),
          ),
        ],
      ),
    );
  }
}

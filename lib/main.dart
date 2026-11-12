import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'features/auth/auth_gate.dart';
import 'core/secure_auth_storage.dart';
import 'core/performance_timings.dart';
import 'features/lists/lists_screen.dart';
import 'features/calendar/calendar_screen.dart';
import 'features/notes/notes_screen.dart';
import 'features/memories/memories_screen.dart';
import 'features/goals/goals_screen.dart';
import 'features/checkins/checkins_screen.dart';
import 'features/plans/plans_screen.dart';
import 'features/profile/profile_settings_screen.dart';
import 'features/spaces/shared_space_screen.dart';
import 'l10n/onespace_locale_controller.dart';
import 'l10n/onespace_strings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final timer = Stopwatch()..start();
  // Render a real frame before initializing secure storage and the network
  // session. Previously OneSpace displayed a blank startup while awaiting
  // Supabase.initialize(), which can be slow on a remote region.
  runApp(OneSpaceBootstrap(startupClock: timer));
}

/// Runs immediately; it does not require an initialized Supabase singleton.
/// Client-backed screens are never mounted until startup is complete.
class OneSpaceBootstrap extends StatefulWidget {
  const OneSpaceBootstrap({super.key, required this.startupClock});
  final Stopwatch startupClock;

  @override
  State<OneSpaceBootstrap> createState() => _OneSpaceBootstrapState();
}

class _OneSpaceBootstrapState extends State<OneSpaceBootstrap> {
  bool _ready = false;
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PerformanceTimings.instance.record(
        'First app frame', widget.startupClock.elapsed);
    });
    _initialize();
  }

  Future<void> _initialize() async {
    setState(() { _busy = true; _error = null; });
    final clock = Stopwatch()..start();
    try {
      await Supabase.initialize(
        url: 'https://ugwrpeduzyzrujkizqfo.supabase.co',
        publishableKey: 'sb_publishable_TtW_uUboFxD4adF5o7FSfA_cpjojMCe',
        authOptions: FlutterAuthClientOptions(
          localStorage: SecureAuthStorage(),
        ),
      );
      PerformanceTimings.instance.record(
        'Supabase session initialization', clock.elapsed);
      if (mounted) setState(() { _ready = true; _busy = false; });
    } catch (_) {
      PerformanceTimings.instance.record(
        'Session initialization failed',clock.elapsed);
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'OneSpace could not open its saved session. '
            'Check the device and network, then retry.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return const OneSpaceApp();
    return MaterialApp(
      debugShowCheckedModeBanner:false,
      home:Scaffold(
        body:SafeArea(
          child:Center(child:ConstrainedBox(
            constraints:const BoxConstraints(maxWidth:360),
            child:Padding(
              padding:const EdgeInsets.all(28),
              child:Column(mainAxisSize:MainAxisSize.min,children:[
                const Icon(Icons.favorite_rounded,
                  color:Color(0xFF167E81),size:60),
                const SizedBox(height:12),
                const Text('OneSpace',style:TextStyle(
                  fontSize:30,fontWeight:FontWeight.w800)),
                const SizedBox(height:6),
                const Text('Two lives. One space.'),
                const SizedBox(height:25),
                if (_busy) ...[
                  const CircularProgressIndicator(),
                  const SizedBox(height:16),
                  const Text('Opening your secure space…'),
                ],
                if (_error != null) ...[
                  Text(_error!,textAlign:TextAlign.center),
                  const SizedBox(height:14),
                  FilledButton.icon(
                    onPressed:_initialize,
                    icon:const Icon(Icons.refresh),
                    label:const Text('Retry')),
                ],
              ]),
            ),
          )),
        ),
      ),
    );
  }
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
      // Reuse the already-loaded Home snapshot on quick tab switches.
      // Pull down in Home for an explicit refresh.
      selectedIndex = index;
      _showProfile = false;
      _visited.add(index);
    });
  }

  Future<void> _openMemories() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const MemoriesScreen()),
    );
    // A return from this dedicated journal screen refreshes Home once.
    if (mounted) setState(() => _dashboardRefreshToken++);
  }

  Future<void> _openGoals() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const GoalsScreen()),
    );
    if (mounted) setState(() => _dashboardRefreshToken++);
  }

  Future<void> _openCheckins() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const CheckinsScreen()),
    );
    if (mounted) setState(() => _dashboardRefreshToken++);
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
    final visiblePage = _showProfile ? 5 : selectedIndex;
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
              onOpenCalendar: () => _navigate(2),
              onOpenMemories: _openMemories,
              onOpenGoals: _openGoals,
              onOpenCheckins: _openCheckins,
              onOpenLists: () => _navigate(3),
              onOpenNotes: () => _navigate(4),
            ),
            if (_visited.contains(1))
              PlansScreen(onOpenSpace: () => _navigate(0))
            else
              const SizedBox.shrink(),
            if (_visited.contains(2))
              CalendarScreen(
                active: visiblePage == 2,
                onOpenPlans: () => _navigate(1),
              )
            else
              const SizedBox.shrink(),
            if (_visited.contains(3))
              const ListsScreen()
            else
              const SizedBox.shrink(),
            if (_visited.contains(4))
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
            icon: const Icon(Icons.calendar_today_outlined),
            label: tr(context, 'calendar'),
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

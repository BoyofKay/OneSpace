import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'features/auth/auth_gate.dart';
import 'features/search/global_search_screen.dart';
import 'features/connect/couple_letters_screen.dart';
import 'features/notifications/notifications_screen.dart';
import 'features/coordinate/coordinate_screen.dart';
import 'features/hubs/section_hubs.dart';
import 'features/remember/remember_screen.dart';
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
                const Text('One Life. Two Places. One Space.'),
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
  int refreshToken = 0;
  bool showProfile = false;
  final Set<int> visited = {0};

  void navigate(int index) {
    setState(() {
      if ((index == 0 || index == 1) && selectedIndex != index) refreshToken++;
      selectedIndex = index;
      showProfile = false;
      visited.add(index);
    });
  }

  void open(Widget screen) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => screen),
    ).then((_) {
      if (mounted) setState(() => refreshToken++);
    });
  }

  @override
  Widget build(BuildContext context) {
    final visible = showProfile ? 5 : selectedIndex;
    return Scaffold(
      appBar: AppBar(
        leading: showProfile ? IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => setState(() {
            showProfile = false;
            refreshToken++;
          }),
          tooltip: tr(context, 'backHome'),
        ) : null,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start,children: [
          const Text('OneSpace',style:TextStyle(fontWeight:FontWeight.w800)),
          Text(tr(context,'tagline'),style:const TextStyle(fontSize:12)),
        ]),
        actions: [
          if (!showProfile) IconButton(
            icon:const Icon(Icons.search_outlined),
            tooltip:'Search our space',
            onPressed:()=>open(const GlobalSearchScreen()),
          ),
          if (!showProfile) const NotificationBell(),
          if (!showProfile) IconButton(
            key: const Key('profileTopBarButton'),
            icon: const Icon(Icons.account_circle_outlined,size:28),
            tooltip: tr(context,'profile'),
            onPressed: () => setState(() => showProfile = true),
          ),
        ],
      ),
      body:SafeArea(child:IndexedStack(index:visible,children:[
        SharedSpaceScreen(
          refreshToken:refreshToken,
          onOpenPlans:()=>open(const PlansScreen()),
          onOpenLists:()=>open(const ListsScreen()),
          onOpenNotes:()=>open(const NotesScreen()),
          onOpenCalendar:()=>open(const CalendarScreen()),
          onOpenMemories:()=>open(const MemoriesScreen()),
          onOpenGoals:()=>open(const GoalsScreen()),
          onOpenCheckins:()=>open(const CheckinsScreen()),
          onOpenLetters:()=>open(const CoupleLettersScreen()),
          onOpenCoordinate:()=>navigate(2),
          onOpenWorld:()=>navigate(4),
          onOpenProfile:()=>setState(() => showProfile = true),
        ),
        if(visited.contains(1)) RememberScreen(refreshToken:refreshToken)
          else const SizedBox.shrink(),
        if(visited.contains(2))const CoordinateScreen()
          else const SizedBox.shrink(),
        if(visited.contains(3))const SectionHub(section:'connect')
          else const SizedBox.shrink(),
        if(visited.contains(4))const SectionHub(section:'world')
          else const SizedBox.shrink(),
        if(showProfile)const ProfileSettingsScreen()
          else const SizedBox.shrink(),
      ])),
      bottomNavigationBar:showProfile?null:NavigationBar(
        selectedIndex:selectedIndex,
        onDestinationSelected:navigate,
        destinations:[
          NavigationDestination(icon:const Icon(Icons.today_outlined),
            selectedIcon:const Icon(Icons.today),label:tr(context,'todayTab')),
          NavigationDestination(icon:const Icon(Icons.bookmark_border),
            selectedIcon:const Icon(Icons.bookmark),label:tr(context,'rememberTab')),
          NavigationDestination(icon:const Icon(Icons.hub_outlined),
            selectedIcon:const Icon(Icons.hub),label:tr(context,'coordinateTab')),
          NavigationDestination(icon:const Icon(Icons.favorite_border),
            selectedIcon:const Icon(Icons.favorite),label:tr(context,'connectTab')),
          NavigationDestination(icon:const Icon(Icons.public_outlined),
            selectedIcon:const Icon(Icons.public),label:tr(context,'worldTab')),
        ],
      ),
    );
  }
}

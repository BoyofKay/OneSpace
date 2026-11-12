import 'package:material_ui/material_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart' show GlobalWidgetsLocalizations;

import 'l10n/onespace_locale_controller.dart';
import 'l10n/onespace_strings.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'features/auth/auth_gate.dart';
import 'features/plans/plans_screen.dart';
import 'features/profile/profile_settings_screen.dart';
import 'features/spaces/shared_space_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://ugwrpeduzyzrujkizqfo.supabase.co',
    publishableKey: 'sb_publishable_TtW_uUboFxD4adF5o7FSfA_cpjojMCe',
  );
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

  @override
  Widget build(BuildContext context) {
    const sections = ['Home', 'Plans', 'Memories'];
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('OneSpace', style: TextStyle(fontWeight: FontWeight.w800)),
            Text(tr(context, 'tagline'), style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
      // Remount the active tab on navigation so newly created/joined spaces
      // and account profiles load fresh from Supabase, rather than keeping
      // stale membership information from an inactive IndexedStack child.
      body: SafeArea(
        child: selectedIndex == 0
            ? const SharedSpaceScreen()
            : selectedIndex == 1
                ? PlansScreen(
                    onOpenSpace: () => setState(() => selectedIndex = 0),
                  )
                : selectedIndex == 2
                    ? _section(sections[2])
                    : const ProfileSettingsScreen(),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (value) => setState(() => selectedIndex = value),
        destinations: [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: tr(context, 'home'),
          ),
          NavigationDestination(
            icon: Icon(Icons.checklist_rounded),
            label: tr(context, 'plans'),
          ),
          NavigationDestination(
            icon: Icon(Icons.photo_library_outlined),
            label: tr(context, 'memories'),
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_rounded),
            label: tr(context, 'more'),
          ),
        ],
      ),
    );
  }

  Widget _section(String title) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.auto_awesome_outlined,
                size: 56, color: Color(0xFF167E81)),
            const SizedBox(height: 18),
            Text(title,
                style: const TextStyle(
                    fontSize: 26, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              tr(context, 'comingSoon'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: () => setState(() => selectedIndex = 0),
              child: Text(tr(context, 'backHome')),
            ),
          ],
        ),
      ),
    );
  }
}

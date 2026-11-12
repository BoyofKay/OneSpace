import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'features/auth/auth_gate.dart';
import 'features/lists/lists_screen.dart';
import 'features/notes/notes_screen.dart';
import 'features/plans/plans_screen.dart';
import 'features/profile/profile_settings_screen.dart';
import 'features/spaces/shared_space_screen.dart';
import 'l10n/onespace_locale_controller.dart';
import 'l10n/onespace_strings.dart';

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

  void _navigate(int index) {
    if (mounted && selectedIndex != index) {
      setState(() => selectedIndex = index);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Only mount the active screen. This reloads space membership when the
    // user switches between accounts or returns to a previous screen.
    final Widget content;
    switch (selectedIndex) {
      case 0:
        content = SharedSpaceScreen(
          onOpenPlans: () => _navigate(1),
          onOpenLists: () => _navigate(2),
          onOpenNotes: () => _navigate(3),
        );
      case 1:
        content = PlansScreen(onOpenSpace: () => _navigate(0));
      case 2:
        content = const ListsScreen();
      case 3:
        content = const NotesScreen();
      default:
        content = const ProfileSettingsScreen();
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('OneSpace',
                style: TextStyle(fontWeight: FontWeight.w800)),
            Text(tr(context, 'tagline'),
                style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
      body: SafeArea(child: content),
      bottomNavigationBar: NavigationBar(
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
          NavigationDestination(
            icon: const Icon(Icons.grid_view_rounded),
            label: tr(context, 'more'),
          ),
        ],
      ),
    );
  }
}

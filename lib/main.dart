import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'features/auth/auth_gate.dart';
import 'features/plans/plans_screen.dart';
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
    return MaterialApp(
      title: 'OneSpace',
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
    const sections = ['Home', 'Plans', 'Memories', 'More'];
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('OneSpace', style: TextStyle(fontWeight: FontWeight.w800)),
            Text('Two lives. One space.', style: TextStyle(fontSize: 12)),
          ],
        ),
      ),
      body: SafeArea(
        child: IndexedStack(
          index: selectedIndex,
          children: [
            const SharedSpaceScreen(),
            const PlansScreen(),
            _section(sections[2]),
            _section(sections[3]),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (value) => setState(() => selectedIndex = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.checklist_rounded),
            label: 'Plans',
          ),
          NavigationDestination(
            icon: Icon(Icons.photo_library_outlined),
            label: 'Memories',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_rounded),
            label: 'More',
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
            const Text(
              'Coming in a future release.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: () => setState(() => selectedIndex = 0),
              child: const Text('Back to home'),
            ),
          ],
        ),
      ),
    );
  }
}

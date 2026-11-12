import 'package:flutter/material.dart';
import 'features/plans/plans_screen.dart';

void main() => runApp(const OneSpaceApp());

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
      home: const OneSpaceHome(),
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
  final List<String> sections = const ['Home', 'Plans', 'Memories', 'More'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('OneSpace', style: TextStyle(fontWeight: FontWeight.w800)),
            Text('Two lives. One space.', style: TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            onPressed: () => _message('Notifications are coming soon'),
            icon: const Icon(Icons.notifications_none_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: IndexedStack(
          index: selectedIndex,
          children: [
            _home(),
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
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.checklist_rounded), label: 'Plans'),
          NavigationDestination(icon: Icon(Icons.photo_library_outlined), label: 'Memories'),
          NavigationDestination(icon: Icon(Icons.grid_view_rounded), label: 'More'),
        ],
      ),
    );
  }

  Widget _home() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 12),
        const Text('Your shared life, together.',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, height: 1.2)),
        const SizedBox(height: 8),
        Text('A home for everything that matters to both of you.',
            style: TextStyle(color: Colors.blueGrey.shade700)),
        const SizedBox(height: 24),
        Card(
          color: const Color(0xFFE4F2F0),
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.favorite_rounded, color: Color(0xFF167E81), size: 32),
                const SizedBox(height: 12),
                const Text('Our Space', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                const Text('Your shared space is ready to begin. Partner invitations will arrive in a future update.'),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => _message('Partner pairing is not available yet'),
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Invite your partner'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 22),
        const Text('Explore OneSpace', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        _tile(Icons.check_circle_outline, 'Plans & tasks', 'Keep your days organized together', 1),
        _tile(Icons.photo_library_outlined, 'Memories', 'Save moments worth keeping', 2),
        _tile(Icons.favorite_border, 'Connection', 'Make room for little moments', 3),
      ],
    );
  }

  Widget _tile(IconData icon, String title, String subtitle, int index) {
    return Card(
      elevation: 0,
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF167E81)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => setState(() => selectedIndex = index),
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
            const Icon(Icons.auto_awesome_outlined, size: 56, color: Color(0xFF167E81)),
            const SizedBox(height: 18),
            Text(title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('This space is taking shape. Features will arrive in upcoming releases.',
                textAlign: TextAlign.center),
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

  void _message(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/onespace_strings.dart';
import '../search/global_search_screen.dart';
import '../settings/account_data_screen.dart';
import '../settings/onespace_settings_screen.dart';
import '../share_in/items_to_sort_screen.dart';
import 'profile_settings_screen.dart';
import 'package:onespace/l10n/phrases.dart';

/// R61: the "Me" tab (bottom right): my profile, settings, language and
/// my data — everything that is about me rather than about us.
class MeScreen extends StatefulWidget {
  const MeScreen({super.key});
  @override
  State<MeScreen> createState() => _MeScreenState();
}

class _MeScreenState extends State<MeScreen> {
  String name = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final db = Supabase.instance.client;
      final me = db.auth.currentUser;
      if (me == null) return;
      final p = await db.from('profiles').select('display_name').eq('id', me.id).maybeSingle();
      if (mounted) setState(() => name = p?['display_name']?.toString() ?? me.email ?? '');
    } catch (_) {}
  }

  void _open(Widget page) => Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (_) => page));

  Widget _page(String title, Widget body) => Scaffold(appBar: AppBar(title: Text(tt(title))), body: SafeArea(child: body));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final email = Supabase.instance.client.auth.currentUser?.email ?? '';
    Widget tile(IconData icon, String title, String subtitle, VoidCallback onTap) => ListTile(
      leading: Icon(icon), title: Text(tt(title)), subtitle: Text(tt(subtitle)),
      trailing: const Icon(Icons.chevron_right), onTap: onTap);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
      Row(children: [
        CircleAvatar(radius: 30, backgroundColor: theme.colorScheme.primaryContainer,
          child: Text(tt(name.isEmpty ? '?' : name.characters.first.toUpperCase()),
            style: theme.textTheme.headlineSmall?.copyWith(color: theme.colorScheme.onPrimaryContainer))),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tt(name.isEmpty ? tr(context, 'profile') : name), style: theme.textTheme.titleLarge),
          if (email.isNotEmpty) Text(tt(email), style: theme.textTheme.bodySmall),
        ])),
      ]),
      const SizedBox(height: 16),
      Card(elevation: 0, child: Column(children: [
        tile(Icons.person_outline, tr(context, 'profile'), 'Name, partner, security and sign out',
          () => _open(_page(tr(context, 'profile'), const ProfileSettingsScreen()))),
        const Divider(height: 1),
        tile(Icons.settings_outlined, 'Settings', 'Relationship, theme, schedule, holidays, weather',
          () => _open(const OneSpaceSettingsScreen())),
        const Divider(height: 1),
        tile(Icons.translate, 'Language', 'English · العربية',
          () => _open(_page('Language', const ProfileSettingsScreen(settingsOnly: true, section: 'language')))),
      ])),
      const SizedBox(height: 12),
      Card(elevation: 0, child: Column(children: [
        tile(Icons.search, 'Search our space', 'Everything we saved, in one search',
          () => _open(const GlobalSearchScreen())),
        const Divider(height: 1),
        tile(Icons.inbox_outlined, 'Items to sort', 'Things shared into OneSpace to decide on later',
          () => _open(const ItemsToSortScreen())),
      ])),
      const SizedBox(height: 12),
      Card(elevation: 0, child: tile(Icons.shield_outlined, 'Your data and account',
        'Download my data · Delete my account', () => _open(const AccountDataScreen()))),
    ]);
  }
}

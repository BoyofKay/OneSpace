import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/onespace_strings.dart';
import '../notifications/push_registration_gate.dart';
import '../../core/usage_events.dart';
import '../settings/account_data_screen.dart';
import '../settings/onespace_settings_screen.dart';
import '../support/support_screens.dart';
import '../support/whats_new.dart';
import 'profile_settings_screen.dart';
import 'package:onespace/l10n/phrases.dart';

/// R61/R64: the "Me" tab (bottom right): profile, settings, language, help &
/// support and my data; troubleshooting and sign out at the very bottom.
class MeScreen extends StatefulWidget {
  const MeScreen({super.key});
  @override
  State<MeScreen> createState() => _MeScreenState();
}

class _MeScreenState extends State<MeScreen> {
  String name = '';
  /// Founding 500 (Amr, 22 Nov 2026): a badge without any number.
  bool founder = false;

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
    try {
      final isFounder = await Supabase.instance.client.rpc('my_founder_status');
      if (mounted && isFounder == true) setState(() => founder = true);
    } catch (_) {}  // the badge is optional; never block the Me screen
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
    return ListView(padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 32), children: [
      Row(children: [
        CircleAvatar(radius: 30, backgroundColor: theme.colorScheme.primaryContainer,
          child: Text(tt(name.isEmpty ? '?' : name.characters.first.toUpperCase()),
            style: theme.textTheme.headlineSmall?.copyWith(color: theme.colorScheme.onPrimaryContainer))),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tt(name.isEmpty ? tr(context, 'profile') : name), style: theme.textTheme.titleLarge),
          if (email.isNotEmpty) Text(tt(email), style: theme.textTheme.bodySmall),
          if (founder) Padding(padding: const EdgeInsets.only(top: 6), child: Container(
            key: const Key('founderBadge'),
            padding: const EdgeInsetsDirectional.fromSTEB(8, 3, 10, 3),
            decoration: BoxDecoration(color: theme.colorScheme.secondaryContainer, borderRadius: BorderRadius.circular(999)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.workspace_premium_outlined, size: 16, color: theme.colorScheme.onSecondaryContainer),
              const SizedBox(width: 4),
              Text(tt('Founder Member'), style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSecondaryContainer)),
            ]))),
        ])),
      ]),
      const SizedBox(height: 16),
      Card(elevation: 0, child: Column(children: [
        tile(Icons.person_outline, tr(context, 'profile'), 'Name, partner and password',
          () => _open(_page(tr(context, 'profile'), const ProfileSettingsScreen()))),
        const Divider(height: 1),
        tile(Icons.settings_outlined, 'Settings', 'Relationship, theme, schedule, holidays, weather',
          () => _open(const OneSpaceSettingsScreen())),
        const Divider(height: 1),
        tile(Icons.translate, 'Language and currency', 'English · العربية · SAR, USD…',
          () => _open(_page('Language and currency', const ProfileSettingsScreen(settingsOnly: true, section: 'language')))),
      ])),
      const SizedBox(height: 12),
      const SizedBox(height: 12),
      Padding(padding: const EdgeInsetsDirectional.only(start: 4, bottom: 6),
        child: Text(tt('Help and support'), style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary))),
      Card(elevation: 0, child: Column(children: [
        tile(Icons.help_outline, 'Questions and answers', 'How OneSpace works, privacy, notifications',
          () => _open(const FaqScreen())),
        const Divider(height: 1),
        tile(Icons.mail_outline, 'Contact us', 'Questions, feedback or ideas',
          () => _open(const SupportFormScreen(kind: 'contact'))),
        const Divider(height: 1),
        tile(Icons.bug_report_outlined, 'Report a technical issue', 'Something is broken or looks wrong',
          () => _open(const SupportFormScreen(kind: 'issue'))),
        const Divider(height: 1),
        tile(Icons.forum_outlined, 'Your messages', 'What you sent us and its status',
          () => _open(const MySupportRequestsScreen())),
        const Divider(height: 1),
        tile(Icons.new_releases_outlined, "What's new", 'The latest changes in OneSpace',
          () => WhatsNew.show(context)),
        const Divider(height: 1),
        tile(Icons.privacy_tip_outlined, 'About and privacy', 'What we keep, what we never do',
          () => _open(const AboutPrivacyScreen())),
      ])),
      const SizedBox(height: 12),
      Card(elevation: 0, child: tile(Icons.shield_outlined, 'Your data and account',
        'Download my data · Delete my account', () => _open(const AccountDataScreen()))),
      const SizedBox(height: 28),
      const Divider(),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: () async {
          await UsageEvents.instance.flushBeforeSignOut();
          await disableCurrentPushDevice();
          await Supabase.instance.client.auth.signOut();
        },
        icon: const Icon(Icons.logout),
        label: Text(tr(context, 'signOut'))),
      const SizedBox(height: 4),
      Center(child: TextButton.icon(
        onPressed: () => showTroubleshooting(context),
        icon: const Icon(Icons.speed_outlined, size: 18),
        label: Text(tt('Troubleshooting')))),
      Center(child: Text(tt('OneSpace ${AppInfo.version}'), style: theme.textTheme.bodySmall)),
    ]);
  }
}

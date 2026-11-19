import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:onespace/l10n/phrases.dart';

/// Read-only space identity preview until private records and media can be
/// preserved before leaving, removing a partner or deleting a space.
class MySpaceScreen extends StatefulWidget {
  const MySpaceScreen({super.key});
  @override
  State<MySpaceScreen> createState() => _MySpaceScreenState();
}

class _MySpaceScreenState extends State<MySpaceScreen> {
  final _db = Supabase.instance.client;
  bool _loading = true;
  String? _error;
  bool _owner = false;
  int _members = 0;
  String? _spaceName;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final me = _db.auth.currentUser?.id;
      if (me == null) throw StateError('Sign in required');
      final myMembership = await _db.from('space_members')
        .select('space_id').eq('user_id', me).limit(1).maybeSingle();
      if (myMembership != null) {
        final id = myMembership['space_id'].toString();
        final space = await _db.from('spaces')
          .select('name,created_by').eq('id', id).maybeSingle();
        final memberships = await _db.from('space_members')
          .select('user_id').eq('space_id',id);
        if (!mounted) return;
        setState(() {
          _spaceName = space?['name']?.toString() ?? 'Our Space';
          _owner = space?['created_by']?.toString() == me;
          _members = memberships.length;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = tt('Unable to load your space.'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(tt('My Space'))),
      body: SafeArea(child: _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(padding: const EdgeInsets.all(20), children: [
          if (_spaceName == null && _error == null)
            Card(child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tt('You are not connected to a shared space.'),
                    style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(tt('Use Today to invite a partner or join a space.')),
                ],
              ),
            )),
          if (_spaceName != null) ...[
            Text(_spaceName!, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.shield_outlined),
              title: Text(tt(_owner ? 'Space owner' : 'Partner')),
              subtitle: Text(tt(_owner
                ? 'You can invite or remove a partner once secure archiving is ready.'
                : 'You can leave your shared space once secure archiving is ready.')),
            ),
            ListTile(
              leading: const Icon(Icons.people_outline),
              title: Text(tt('Members')),
              trailing: Text('$_members / 2'),
            ),
            const Divider(),
            Text(tt('Space separation'), style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(tt('The leave, remove and delete actions are not enabled in this '
              'QA build. Private data preservation, verified exports and '
              'media cleanup must pass QA before these actions are safe.')),
          ],
          if (_error != null) Text(_error!,
            style: TextStyle(color: theme.colorScheme.error)),
        ])),
    );
  }
}

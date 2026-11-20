import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/app_env.dart';
import 'package:onespace/l10n/phrases.dart';

/// Account-owned private storage and relationship-owned shared storage.
/// The destructive server-side transition stays disabled until all existing
/// content modules and RLS policies use the new separation-safe model.
/// Previous non-destructive archive preparations are never auto-executed.
class MySpaceScreen extends StatefulWidget {
  const MySpaceScreen({super.key});

  @override
  State<MySpaceScreen> createState() => _MySpaceScreenState();
}

class _MySpaceScreenState extends State<MySpaceScreen> {
  final _db = Supabase.instance.client;
  bool _loading = true;
  bool _busy = false;
  bool _owner = false;
  int _members = 0;
  String? _spaceName;
  String? _error;
  String? _message;
  Map<String, dynamic>? _legacyPending;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final me = _db.auth.currentUser?.id;
      if (me == null) throw StateError('Sign in required');
      final membership = await _db.from('space_members')
          .select('space_id').eq('user_id', me).limit(1).maybeSingle();
      String? name;
      var owner = false;
      var members = 0;
      if (membership != null) {
        final id = membership['space_id'].toString();
        final space = await _db.from('spaces')
            .select('name,created_by').eq('id', id).maybeSingle();
        final list = await _db.from('space_members')
            .select('user_id').eq('space_id', id);
        name = space?['name']?.toString() ?? 'Our Space';
        owner = space?['created_by']?.toString() == me;
        members = list.length;
      }
      Map<String,dynamic>? pending;
      if (!OneSpaceEnv.isProduction) {
        final result = await _db.rpc('my_space_lifecycle_status');
        if (result is Map && result['active_job'] is Map) {
          pending = Map<String,dynamic>.from(result['active_job'] as Map);
        }
      }
      if (!mounted) return;
      setState(() {
        _spaceName = name;
        _owner = owner;
        _members = members;
        _legacyPending = pending;
      });
    } catch (_) {
      if (mounted) setState(() => _error =
          tt('Unable to load your space. No changes were made.'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _cancelOldRequest() async {
    final job = _legacyPending;
    if (OneSpaceEnv.isProduction || _busy || job == null ||
        job['requested_by_me'] != true) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tt('Cancel previous preparation request?')),
        content: Text(tt('This request was created under the old '
          'non-destructive archive policy. No partner has been removed '
          'and no shared content has been deleted.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: Text(tt('Keep request'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
            child: Text(tt('Cancel old request'))),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() { _busy = true; _message = null; _error = null; });
    try {
      final result = await _db.rpc('cancel_space_lifecycle_action',
        params: {'p_job_id': job['id'].toString()});
      if (mounted) setState(() => _message = result == true
        ? tt('Old preparation request cancelled. Your space is unchanged.')
        : tt('This request cannot be cancelled at its current stage.'));
      await _load();
    } on PostgrestException catch (_) {
      if (mounted) setState(() => _error =
        tt('Could not cancel the old request. No shared content was deleted.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _disabledAction(IconData icon, String title) =>
    OutlinedButton.icon(
      onPressed: null,
      icon: Icon(icon),
      label: Text(tt(title)),
    );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(tt('My Space')), actions: [
        IconButton(
          onPressed: _loading || _busy ? null : _load,
          tooltip: tt('Refresh status'),
          icon: const Icon(Icons.refresh),
        ),
      ]),
      body: SafeArea(child: _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(padding: const EdgeInsets.all(20), children: [
          if (_spaceName == null) ...[
            Text(tt('Your private space belongs to your account.'),
              style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(tt('You are currently unpaired. Your private records '
              'will remain yours when you connect with a partner.')),
          ] else ...[
            Text(_spaceName!, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.people_outline),
              title: Text(tt(_members == 2
                ? (_owner ? 'Space owner and partner' : 'Shared with your partner')
                : 'Not currently paired')),
              subtitle: Text(tt('Current members: $_members / 2')),
            ),
          ],
          const SizedBox(height: 12),
          Card(child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.lock_outline),
                const SizedBox(width: 8),
                Expanded(child: Text(tt('Your private content stays yours'),
                  style: theme.textTheme.titleMedium)),
              ]),
              const SizedBox(height: 8),
              Text(tt('OneSpace is moving to separate account-owned private '
                'storage and relationship-owned shared storage. The app will '
                'continue to show both together in one interface.')),
            ]),
          )),
          if (_legacyPending != null) ...[
            const SizedBox(height: 12),
            Card(child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tt('Earlier preparation request — not executed'),
                  style: theme.textTheme.titleSmall),
                const SizedBox(height: 7),
                Text(tt('This request was made under the previous archive '
                  'workflow. Nobody has been removed and no shared content '
                  'has been deleted. Any future permanent deletion requires '
                  'a new, explicit confirmation.')),
                if (_legacyPending!['requested_by_me'] == true)
                  TextButton.icon(
                    onPressed: _busy ? null : _cancelOldRequest,
                    icon: const Icon(Icons.close),
                    label: Text(tt('Cancel old request')),
                  ),
              ]),
            )),
          ],
          if (_spaceName != null) ...[
            const SizedBox(height: 16),
            Text(tt('Relationship actions'),
              style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(tt('Leaving, removing a partner or deleting a space will '
              'permanently erase the shared content and its attachments. '
              'Neither person will be able to restore it. Each person will '
              'keep their own private content, even when unpaired or '
              'connected to a different partner.')),
            const SizedBox(height: 10),
            if (_members == 2 && _owner)
              _disabledAction(Icons.person_remove_outlined, 'Remove partner'),
            if (_members == 2 && !_owner)
              _disabledAction(Icons.logout, 'Leave this space'),
            if (_owner)
              _disabledAction(Icons.delete_outline, 'Delete this space'),
            const SizedBox(height: 8),
            Text(tt('These actions are temporarily unavailable while '
              'private data ownership, shared deletion and security checks '
              'are migrated. No archival or restoration is required.'),
              style: theme.textTheme.bodySmall),
          ],
          if (_message != null) Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_message!),
          ),
          if (_error != null) Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ),
        ])),
    );
  }
}

import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:onespace/l10n/phrases.dart';
import 'my_archives_screen.dart';

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
  bool _checking = false;
  Map<String,dynamic>? _readiness;
  Map<String,dynamic>? _personalVault;
  Map<String,dynamic>? _lifecycle;
  bool _submitting = false;
  String? _actionMessage;

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
      final lifecycleData = await _db.rpc('my_space_lifecycle_status');
      if (!mounted) return;
      setState(() => _lifecycle = lifecycleData is Map
        ? Map<String,dynamic>.from(lifecycleData) : null);
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

  Future<void> _checkReadiness() async {
    if (_checking) return;
    setState(() { _checking = true; _error = null; });
    try {
      final result = await _db.rpc('space_separation_preflight');
      final vault = await _db.rpc('my_personal_vault_status');
      if (mounted) setState(() {
        _readiness = result is Map
          ? Map<String,dynamic>.from(result) : null;
        _personalVault = vault is Map
          ? Map<String,dynamic>.from(vault) : null;
      });
    } catch (_) {
      if (mounted) setState(() => _error =
        tt('Unable to complete the read-only data safety check.'));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }


  Future<bool> _confirmAction(String title, String body, String confirm) async {
    return await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tt(title)),
        content: Text(tt(body)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(tt('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(tt(confirm)),
          ),
        ],
      ),
    ) == true;
  }

  Future<void> _stageAction(String action, String title, String warning) async {
    if (_submitting || !await _confirmAction(title, warning, 'Prepare securely')) return;
    if (!mounted) return;
    setState(() { _submitting = true; _actionMessage = null; _error = null; });
    try {
      final response = await _db.rpc('request_space_lifecycle_action',
        params: {'p_action': action});
      if (!mounted) return;
      setState(() => _actionMessage = response is Map
        ? (response['message']?.toString() ?? 'Preparation request recorded.')
        : 'Preparation request recorded.');
      await _load();
      await _checkReadiness();
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error =
        tt('Preparation failed. No membership was changed.'));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _cancelStagedAction(String jobId) async {
    if (_submitting || !await _confirmAction('Cancel separation preparation?',
      'Requests can only be cancelled before archive export starts.',
      'Cancel request')) return;
    if (!mounted) return;
    setState(() { _submitting = true; _actionMessage = null; _error = null; });
    try {
      final cancelled = await _db.rpc('cancel_space_lifecycle_action',
        params: {'p_job_id': jobId});
      if (mounted) setState(() => _actionMessage = cancelled == true
        ? 'Preparation cancelled. The space is unchanged.'
        : 'Request cannot be cancelled at this stage.');
      await _load();
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = tt('Unable to cancel request.'));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pending = _lifecycle?['active_job'] is Map
      ? Map<String,dynamic>.from(_lifecycle!['active_job'] as Map)
      : null;
    final mayAct = !_submitting && pending == null;
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
            ListTile(
              leading: const Icon(Icons.folder_zip_outlined),
              title: Text(tt('My Archives')),
              subtitle: Text(tt('Your encrypted backups and download status')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(builder: (_) => const MyArchivesScreen())),
            ),
            const Divider(),
            Text(tt('Space separation'), style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(tt('You may request secure preparation for leaving, removing a partner, '
              'or closing the space. Actual separation remains blocked until '
              'encrypted exports, file integrity and privacy checks pass.')),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _checking ? null : _checkReadiness,
              icon: const Icon(Icons.fact_check_outlined),
              label: Text(tt('Check separation readiness')),
            ),

            if (_submitting) const LinearProgressIndicator(),
            if (pending != null)
              Card(child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tt('Separation preparation requested'),
                    style: theme.textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(tt('Request status: ') + (pending['status'] ?? '').toString()),
                  const SizedBox(height: 6),
                  Text(tt('No memberships or space content have been removed.')),
                  if (pending['requested_by_me'] == true)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.close),
                      onPressed: _submitting ? null
                        : () => _cancelStagedAction(pending['id'].toString()),
                      label: Text(tt('Cancel preparation')),
                    ),
                ]),
              )),
            const SizedBox(height: 10),
            if (_owner && _members == 2)
              OutlinedButton.icon(
                icon: const Icon(Icons.person_remove_outlined),
                onPressed: mayAct ? () => _stageAction('owner_removes_partner',
                  'Remove partner?',
                  'First prepare verified private and shared archives for both people. This request does not remove the partner now.') : null,
                label: Text(tt('Prepare partner removal')),
              ),
            if (!_owner && _members == 2)
              OutlinedButton.icon(
                icon: const Icon(Icons.logout),
                onPressed: mayAct ? () => _stageAction('partner_leaves',
                  'Leave this space?',
                  'Your private records and shared history must be archived first. This request does not leave the space now.') : null,
                label: Text(tt('Prepare to leave space')),
              ),
            if (_owner)
              OutlinedButton.icon(
                icon: const Icon(Icons.delete_outline),
                onPressed: mayAct ? () => _stageAction('owner_deletes_space',
                  'Delete this space?',
                  'Both users must receive verified archives first. This request does not delete the space now.') : null,
                label: Text(tt('Prepare space deletion')),
              ),
            const SizedBox(height: 10),
            if (_checking) const LinearProgressIndicator(),
            if (_readiness != null) Card(child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                Text(tt('Safety check: not yet ready'),
                  style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                Text('${tt('Space-linked records')}: ${_readiness!['space_linked_records'] ?? '—'}'),
                Text('${tt('My private records detected')}: ${_readiness!['private_root_records'] ?? '—'}'),
                Text('${tt('Shared records detected')}: ${_readiness!['shared_root_records'] ?? '—'}'),
                const SizedBox(height: 8),
                if (_personalVault != null) ...[
                  Text(tt('My protected private records') +
                    ': ${_personalVault!['primary_private_records'] ?? '—'}'),
                  Text(tt('My protected related records') +
                    ': ${_personalVault!['owned_related_records'] ?? '—'}'),
                ],
                const SizedBox(height: 8),
                Text(tt('Nothing was deleted or moved by this check.')),
              ]),
            )),
          ],
          if (_actionMessage != null) Text(tt(_actionMessage!)),
          if (_error != null) Text(_error!,
            style: TextStyle(color: theme.colorScheme.error)),
        ])),
    );
  }
}

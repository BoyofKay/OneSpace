import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:onespace/l10n/phrases.dart';
import 'my_archives_screen.dart';
import 'space_lifecycle_progress_card.dart';
import '../../core/app_env.dart';

/// Safe lifecycle preparation only; destructive actions remain server-gated until
/// structured private/shared records can be
/// preserved (excluding media and uploaded documents) before leaving, removing a partner or deleting a space.
class MySpaceScreen extends StatefulWidget {
  const MySpaceScreen({super.key});
  @override
  State<MySpaceScreen> createState() => _MySpaceScreenState();
}

class _MySpaceScreenState extends State<MySpaceScreen>
    with WidgetsBindingObserver {
  final _db = Supabase.instance.client;
  bool _loading = true;
  String? _error;
  bool _owner = false;
  int _members = 0;
  String? _spaceName;
  bool _checking = false;
  Map<String,dynamic>? _readiness;
  Map<String,dynamic>? _personalVault;
  Map<String,dynamic>? _dependentAudit;
  Map<String,dynamic>? _archiveCatalog;
  Map<String,dynamic>? _lifecycle;
  bool _submitting = false;
  bool _refreshingLifecycle = false;
  Timer? _statusTimer;
  String? _actionMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _statusTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!OneSpaceEnv.isProduction &&
          _lifecycle?['active_job'] is Map &&
          !_refreshingLifecycle && !_submitting) {
        unawaited(_refreshLifecycle());
      }
    });
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !OneSpaceEnv.isProduction &&
        !_refreshingLifecycle && !_submitting) {
      unawaited(_refreshLifecycle());
    }
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Read-only refresh; does not trigger separation or write to the backend.
  Future<void> _refreshLifecycle() async {
    if (_refreshingLifecycle || OneSpaceEnv.isProduction) return;
    if (!mounted) return;
    setState(() => _refreshingLifecycle = true);
    try {
      final result = await _db.rpc('my_space_lifecycle_status');
      if (result is! Map) throw StateError('No lifecycle status returned');
      if (mounted) setState(() {
        _lifecycle = Map<String, dynamic>.from(result);
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error =
        tt('Unable to refresh relationship request status. '
          'The original request has not been cancelled.'));
    } finally {
      if (mounted) setState(() => _refreshingLifecycle = false);
    }
  }

  Future<void> _load() async {
    try {
      final me = _db.auth.currentUser?.id;
      if (me == null) throw StateError('Sign in required');
      final myMembership = await _db.from('space_members')
        .select('space_id').eq('user_id', me).limit(1).maybeSingle();
      // Lifecycle staging exists in QA only. Production must still load
      // Profile without calling functions not deployed to its backend.
      final lifecycleData = OneSpaceEnv.isProduction
        ? null : await _db.rpc('my_space_lifecycle_status');
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
    if (_checking || OneSpaceEnv.isProduction) return;
    setState(() { _checking = true; _error = null; });
    try {
      final result = await _db.rpc('space_separation_preflight');
      final vault = await _db.rpc('my_personal_vault_status');
      final dependencies = await _db.rpc('space_archive_dependency_inventory');
      final catalog = await _db.rpc('qa_archive_catalog_coverage');
      if (mounted) setState(() {
        _readiness = result is Map
          ? Map<String,dynamic>.from(result) : null;
        _personalVault = vault is Map
          ? Map<String,dynamic>.from(vault) : null;
        _dependentAudit = dependencies is Map
          ? Map<String,dynamic>.from(dependencies) : null;
        _archiveCatalog = catalog is Map
          ? Map<String,dynamic>.from(catalog) : null;
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
    if (OneSpaceEnv.isProduction || _submitting ||
        !await _confirmAction(title, warning, 'Prepare securely')) return;
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
      await _refreshLifecycle();
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
    if (OneSpaceEnv.isProduction || _submitting ||
        !await _confirmAction('Cancel separation preparation?',
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
      await _refreshLifecycle();
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
    final mayAct = !OneSpaceEnv.isProduction && _lifecycle != null &&
      !_submitting && pending == null;
    return Scaffold(
      appBar: AppBar(title: Text(tt('My Space'))),
      body: SafeArea(child: _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(padding: const EdgeInsets.all(20), children: [
          // Both original partners see the same genuine server-side lifecycle
          // request state. This block is not a progress simulation.
          if (!OneSpaceEnv.isProduction && _lifecycle != null &&
              _lifecycle!['active_job'] is Map) ...[
            SpaceLifecycleProgressCard(
              lifecycle: _lifecycle!,
              refreshing: _refreshingLifecycle,
              submitting: _submitting,
              onRefresh: _refreshLifecycle,
              onCancel: _cancelStagedAction,
            ),
            const SizedBox(height: 12),
          ],
          // Keep archive access after leaving or deleting a space. An unpaired
          // member must still be able to save their own verified archives.
          if (!OneSpaceEnv.isProduction) ...[
            ListTile(
              leading: const Icon(Icons.folder_zip_outlined),
              title: Text(tt('My Archives')),
              subtitle: Text(tt('Verified copies, when available, belong to your account')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(builder: (_) => const MyArchivesScreen())),
            ),
            const Divider(),
          ],
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
            Text(tt(OneSpaceEnv.isProduction
              ? 'Space separation is not available in Production until the QA archive and privacy checks are completed.'
              : 'You may request secure preparation for leaving, removing a partner, '
                'or closing the space. Actual separation remains blocked until '
                'structured-data archives, privacy checks and restoration tests pass. Photos, uploaded documents and other media are excluded from archive and restore.')),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _checking || OneSpaceEnv.isProduction ? null : _checkReadiness,
              icon: const Icon(Icons.fact_check_outlined),
              label: Text(tt('Check separation readiness')),
            ),

            if (_submitting) const LinearProgressIndicator(),
            const SizedBox(height: 10),
            if (!OneSpaceEnv.isProduction && _owner && _members == 2)
              OutlinedButton.icon(
                icon: const Icon(Icons.person_remove_outlined),
                onPressed: mayAct ? () => _stageAction('owner_removes_partner',
                  'Remove partner?',
                  'First prepare verified structured private and shared archives for both people. Photos, documents and other media are excluded. This does not remove the partner now.') : null,
                label: Text(tt('Prepare partner removal')),
              ),
            if (!OneSpaceEnv.isProduction && !_owner && _members == 2)
              OutlinedButton.icon(
                icon: const Icon(Icons.logout),
                onPressed: mayAct ? () => _stageAction('partner_leaves',
                  'Leave this space?',
                  'Your structured private records and shared history must be archived first; media and uploaded documents are excluded. This does not leave the space now.') : null,
                label: Text(tt('Prepare to leave space')),
              ),
            if (!OneSpaceEnv.isProduction && _owner)
              OutlinedButton.icon(
                icon: const Icon(Icons.delete_outline),
                onPressed: mayAct ? () => _stageAction('owner_deletes_space',
                  'Delete this space?',
                  'Both users must receive verified structured-data archives first. Media and uploaded documents are excluded. This does not delete the space now.') : null,
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
                Text(tt('Record-by-record totals are restricted to preserve each partner’s private data.')),
                Text('Verified archives: ${_readiness!['archives_verified'] ?? 0} / ${_readiness!['archives_expected'] ?? '—'}'),
                if (_dependentAudit != null) ...[
                  const SizedBox(height: 6),
                  Text('Dependent tables checked: ${_dependentAudit!['dependent_tables_inspected'] ?? 0}'),
                  Text('Tables with multiple ownership routes: ${_dependentAudit!['multi_root_tables'] ?? 0}'),
                ],
                if (_archiveCatalog != null) ...[
                  const SizedBox(height: 8),
                  Text('Structured table types reviewed: ${_archiveCatalog!['approved_table_policies'] ?? 0} / ${_archiveCatalog!['total_tables'] ?? '—'}'),
                  Text('Pending root and related types: ${(_archiveCatalog!['root_types_pending'] as num? ?? 0) + (_archiveCatalog!['dependent_types_pending'] as num? ?? 0)}'),
                  Text(tt('Uploaded photos, videos, voice notes and documents will not be in the archive.')),
                ],
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

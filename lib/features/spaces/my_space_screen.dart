import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:onespace/l10n/phrases.dart';

/// QA lifecycle preparation: requests never imply completed separation.
class MySpaceScreen extends StatefulWidget {
  const MySpaceScreen({super.key});
  @override
  State<MySpaceScreen> createState() => _MySpaceScreenState();
}

class _MySpaceScreenState extends State<MySpaceScreen> {
  final _db = Supabase.instance.client;
  Map<String, dynamic>? _status;
  Map<String, dynamic>? _readiness;
  bool _loading = true, _busy = false;
  String? _error, _message;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final data = await _db.rpc('my_space_lifecycle_status');
      final audit = await _db.rpc('space_lifecycle_readiness');
      if (mounted) setState(() {
        _status = Map<String, dynamic>.from(data as Map);
        _readiness = Map<String, dynamic>.from(audit as Map);
        _error = null;
      });
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Unable to load your space.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _confirm(String title, String explanation, String action) async {
    return await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tt(title)),
        content: Text(tt(explanation)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: Text(tt('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
            child: Text(tt(action))),
        ],
      ),
    ) == true;
  }

  Future<void> _request(String action, String title, String explanation) async {
    if (_busy || !await _confirm(title, explanation, 'Prepare securely') || !mounted) return;
    setState(() { _busy = true; _error = null; _message = null; });
    try {
      final raw = await _db.rpc('request_space_lifecycle_action',
        params: {'p_action': action});
      if (!mounted) return;
      final response = Map<String, dynamic>.from(raw as Map);
      setState(() => _message = response['message']?.toString() ??
        'Preparation requested. Membership remains unchanged.');
      await _load();
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Unable to request this action.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel(String id) async {
    if (_busy || !await _confirm('Cancel preparation?',
      'A request can be cancelled before archive export starts.',
      'Cancel request') || !mounted) return;
    setState(() { _busy = true; _error = null; _message = null; });
    try {
      final cancelled = await _db.rpc('cancel_space_lifecycle_action',
        params: {'p_job_id': id});
      if (mounted) setState(() => _message = cancelled == true
        ? 'Preparation cancelled. Your space is unchanged.'
        : 'This request can no longer be cancelled.');
      await _load();
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Unable to cancel this request.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _status;
    final readiness = _readiness;
    final job = s?['active_job'] is Map
      ? Map<String, dynamic>.from(s!['active_job'] as Map) : null;
    final hasSpace = s?['has_space'] == true;
    final owner = s?['role'] == 'owner';
    final members = (s?['member_count'] as num?)?.toInt() ?? 0;
    final enabled = !_busy && job == null;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(tt('My Space')),
        actions: [IconButton(
          tooltip: tt('Refresh status'),
          onPressed: _busy ? null : () {
            setState(() => _loading = true);
            _load();
          },
          icon: const Icon(Icons.refresh),
        )],
      ),
      body: _loading ? const Center(child: CircularProgressIndicator())
        : ListView(padding: const EdgeInsets.all(18), children: [
          if (_error != null) Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(tt(_error!), style: TextStyle(color: theme.colorScheme.error))),
          if (_message != null) Text(tt(_message!)),
          if (!hasSpace) ...[
            Text(tt('You are not in a space.'),
              style: theme.textTheme.titleMedium),
            Text(tt('You may create a space or accept an invitation from the pairing screen.')),
          ] else ...[
            Text(tt('Your relationship space'), style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(tt(owner ? 'You are the original owner.'
              : 'You joined as an invited partner.')),
            Text(tt(members == 2 ? 'Two people are connected.'
              : 'You are currently the only member.')),
            const SizedBox(height: 16),
            Card(elevation: 0, child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tt('Your data protection'),
                  style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(tt('OneSpace must verify encrypted private and shared archives and media integrity before any separation or deletion.')),
                const SizedBox(height: 8),
                if (readiness != null) ...[
                  Text(tt('Safety assessment: ') + (readiness['reason'] ?? 'Pending').toString()),
                  const SizedBox(height: 6),
                  Text(tt('Space records assessed: ') + (readiness['space_linked_records'] ?? 0).toString()),
                  if (readiness['storage_reconciliation_pending'] == true)
                    Text(tt('Older storage files still need reconciliation before a space can be closed.')),
                  if ((readiness['unclassified_root_records'] as num? ?? 0) > 0)
                    Text(tt('Some records need an explicit private/shared classification before archiving.')),
                  const SizedBox(height: 8),
                ],
                Text(tt('Verified archives: ') +
                  (s?['archives_verified'] ?? 0).toString() +
                  ' / ' + (s?['archives_expected'] ?? 0).toString()),
                if (job != null) ...[
                  const SizedBox(height: 12),
                  Text(tt('Request status: ') + (job['status'] ?? '').toString()),
                  const SizedBox(height: 6),
                  Text(tt('Your space and memberships have NOT changed. The secure archive and transition process must finish first.')),
                  if (job['requested_by_me'] == true) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => _cancel(job['id'].toString()),
                      icon: const Icon(Icons.close),
                      label: Text(tt('Cancel preparation')),
                    ),
                  ],
                ],
              ]),
            )),
            const SizedBox(height: 18),
            if (owner && members == 2) ...[
              OutlinedButton.icon(
                onPressed: enabled ? () => _request('owner_removes_partner',
                  'Remove partner?', 'This starts secure preparation only. Your partner remains connected until all safety checks pass.') : null,
                icon: const Icon(Icons.person_remove_outlined),
                label: Text(tt('Remove partner')),
              ),
              const SizedBox(height: 8),
            ],
            if (!owner) ...[
              OutlinedButton.icon(
                onPressed: enabled ? () => _request('partner_leaves',
                  'Leave this space?', 'This starts secure preparation only. You remain connected until your private data and the shared archive are protected.') : null,
                icon: const Icon(Icons.logout),
                label: Text(tt('Leave space')),
              ),
              const SizedBox(height: 8),
            ],
            if (owner) OutlinedButton.icon(
              onPressed: enabled ? () => _request('owner_deletes_space',
                'Delete space?', 'Both users keep private data. This begins archive preparation and does NOT delete the space immediately.') : null,
              style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error),
              icon: const Icon(Icons.delete_outline),
              label: Text(tt('Delete space')),
            ),
            const SizedBox(height: 12),
            Text(tt('Requesting an action does not yet remove members or delete data.'),
              style: theme.textTheme.bodySmall),
          ],
        ]),
    );
  }
}

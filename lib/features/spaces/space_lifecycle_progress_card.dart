import 'package:material_ui/material_ui.dart';
import 'package:onespace/l10n/phrases.dart';

/// QA lifecycle request display. This is NOT a progress worker or a
/// replacement for server-side authorization. Never infer completion from
/// elapsed time or from the fraction of archive records inspected.
class SpaceLifecycleProgressCard extends StatelessWidget {
  const SpaceLifecycleProgressCard({
    super.key,
    required this.lifecycle,
    required this.refreshing,
    required this.onRefresh,
    required this.onCancel,
    this.submitting = false,
  });

  final Map<String, dynamic> lifecycle;
  final bool refreshing;
  final bool submitting;
  final VoidCallback onRefresh;
  final void Function(String id) onCancel;

  static String actionLabel(String? action, bool mine) => switch (action) {
    'owner_removes_partner' => mine
        ? 'You requested to remove your partner'
        : 'Your partner requested to remove you',
    'partner_leaves' => mine
        ? 'You requested to leave this space'
        : 'Your partner requested to leave this space',
    'owner_deletes_space' => mine
        ? 'You requested to close this space'
        : 'Your partner requested to close this space',
    _ => 'A relationship change was requested',
  };

  static String statusTitle(String? status) => switch (status) {
    'awaiting_verified_export' => 'Request recorded — blocked before separation',
    'cancelled' => 'Preparation cancelled',
    'completed' => 'Relationship change completed',
    'failed' => 'Preparation could not proceed',
    _ => 'Request status needs review',
  };

  Widget _step(BuildContext context, IconData icon, String title, String detail) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 11),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 21, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tt(title), style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(tt(detail), style: theme.textTheme.bodySmall),
        ])),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = lifecycle['active_job'];
    if (active is! Map) return const SizedBox.shrink();
    final job = Map<String, dynamic>.from(active);
    final status = job['status']?.toString();
    final mine = job['requested_by_me'] == true;
    final date = DateTime.tryParse(job['requested_at']?.toString() ?? '')?.toLocal();
    final expected = (lifecycle['archives_expected'] is num)
        ? (lifecycle['archives_expected'] as num).toInt() : 0;
    final rawVerified = (lifecycle['archives_verified'] is num)
        ? (lifecycle['archives_verified'] as num).toInt() : 0;
    final verified = rawVerified.clamp(0, expected < 0 ? 0 : expected);
    final isWaiting = status == 'awaiting_verified_export';
    final theme = Theme.of(context);
    return Card(
      key: const Key('lifecycleRequestProgressCard'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.pending_actions_outlined),
            const SizedBox(width: 8),
            Expanded(child: Text(tt('Relationship request status'),
              style: theme.textTheme.titleMedium)),
          ]),
          const SizedBox(height: 10),
          Text(tt(actionLabel(job['action']?.toString(), mine)),
            style: theme.textTheme.titleSmall),
          if (date != null) ...[
            const SizedBox(height: 5),
            Text(tt('Requested on ') +
              MaterialLocalizations.of(context).formatMediumDate(date),
              style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 9),
          Text(tt(statusTitle(status)),
            key: const Key('lifecycleHumanStatus'),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700)),
          if (isWaiting) ...[
            const SizedBox(height: 8),
            Text(tt('This is a preparation request, not an automated separation. '
              'No partner has left or been removed. All current space memberships '
              'and records remain unchanged.')),
            const SizedBox(height: 10),
            Text(tt('Archive safety requirements'),
              style: theme.textTheme.titleSmall),
            _step(context, Icons.check_circle_outline,
              '1. Request received',
              'Both members can see that a request has been recorded.'),
            _step(context, Icons.lock_clock_outlined,
              '2. Encrypted archive verification — blocked',
              'Verified private and original-couple shared structured archives: '
                '$verified / $expected. No trusted complete archive exists yet.'),
            _step(context, Icons.hourglass_empty,
              '3. Safe private restoration — not started',
              'Restore must be proven without exposing either partner’s '
                'private records or importing old shared history into a new couple.'),
            _step(context, Icons.pause_circle_outline,
              '4. Relationship change — not started',
              'Separation is disabled until the archive and restoration '
                'safety gates are actually satisfied.'),
            const SizedBox(height: 12),
            Text(tt('There is no running background separation job or '
              'completion estimate. Photos, audio, videos, uploaded documents '
              'and their file pointers are excluded from the approved archive.'),
              style: theme.textTheme.bodySmall),
          ] else ...[
            const SizedBox(height: 6),
            Text(tt('Refresh to check the latest server status. '
              'Do not assume the relationship has changed until OneSpace '
              'explicitly confirms completion.')),
          ],
          const SizedBox(height: 12),
          Row(children: [
            OutlinedButton.icon(
              key: const Key('lifecycleRefreshStatus'),
              onPressed: refreshing || submitting ? null : onRefresh,
              icon: refreshing
                ? const SizedBox(width: 17, height: 17,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
              label: Text(tt('Refresh status')),
            ),
            if (mine && isWaiting && job['id'] != null) ...[
              const SizedBox(width: 8),
              Expanded(child: TextButton.icon(
                key: const Key('lifecycleCancelRequest'),
                onPressed: refreshing || submitting ? null
                  : () => onCancel(job['id'].toString()),
                icon: const Icon(Icons.close),
                label: Text(tt('Cancel request')),
              )),
            ],
          ]),
        ]),
      ),
    );
  }
}

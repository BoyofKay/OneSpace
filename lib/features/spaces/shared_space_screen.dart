import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'invitation_code.dart';
import 'space_task_summary.dart';
import '../../core/performance_timings.dart';
import '../../core/current_space_cache.dart';
import '../../l10n/onespace_strings.dart';

class SharedSpaceScreen extends StatefulWidget {
  const SharedSpaceScreen({
    super.key,
    this.onOpenPlans,
    this.onOpenLists,
    this.onOpenNotes,
    this.onOpenCalendar,
    this.onOpenMemories,
    this.onOpenGoals,
    this.onOpenCheckins,
    this.refreshToken = 0,
  });

  final VoidCallback? onOpenPlans;
  final VoidCallback? onOpenLists;
  final VoidCallback? onOpenNotes;
  final VoidCallback? onOpenCalendar;
  final VoidCallback? onOpenMemories;
  final VoidCallback? onOpenGoals;
  final VoidCallback? onOpenCheckins;
  final int refreshToken;

  @override
  State<SharedSpaceScreen> createState() => _SharedSpaceScreenState();
}

class _SharedSpaceScreenState extends State<SharedSpaceScreen> {
  final client = Supabase.instance.client;
  final invitationController = TextEditingController();
  String? spaceId;
  String? spaceName;
  int memberCount = 0;
  List<String> memberDisplayNames = const [];
  SpaceTaskSummary? taskSummary;
  int activeShoppingLists = 0;
  int activeOtherLists = 0;
  int activeNotes = 0;
  int activeCalendarEvents = 0;
  int activeMemories = 0;
  int activeGoals = 0;
  int achievedGoals = 0;
  int recentCheckins = 0;
  DateTime? pendingInviteExpiry;
  bool loading = true;
  bool membershipResolved = false;
  bool summaryLoading = false;
  String? summaryIssue;
  int _requestVersion = 0;
  bool working = false;
  String? issue;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant SharedSpaceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _load();
  }

  @override
  void dispose() {
    _requestVersion++;
    invitationController.dispose();
    super.dispose();
  }

  /// First load membership; render the space as soon as we have its ID.
  /// Remaining independent groups load concurrently, so one failing optional
  /// query cannot hide the entire dashboard.
  /// One authenticated RPC replaces eight HTTP round trips to Supabase.
  /// Every scalar count inside the RPC obeys the caller's existing RLS.
  Future<void> _load() async {
    final request = ++_requestVersion;
    final watch = Stopwatch()..start();
    if (!mounted) return;
    setState(() {
      loading = spaceId == null;
      summaryLoading = spaceId != null;
      issue = null;
      summaryIssue = null;
    });
    try {
      final result = await client.rpc('get_home_snapshot')
          .timeout(const Duration(seconds: 14));
      if (!mounted || request != _requestVersion) return;

      if (result == null) {
        CurrentSpaceCache.instance.seed(client.auth.currentUser!.id, null);
        setState(() {
          spaceId = null;
          spaceName = null;
          memberCount = 0;
          memberDisplayNames = const [];
          taskSummary = null;
          activeShoppingLists = 0;
          activeOtherLists = 0;
          activeNotes = 0;
          pendingInviteExpiry = null;
          membershipResolved = true;
          summaryLoading = false;
          loading = false;
        });
      } else {
        final data = Map<String, dynamic>.from(result as Map);
        final memberLabel = tr(context, 'member');
        final meLabel = tr(context, 'me');
        final members = (data['members'] as List<dynamic>? ?? const []);
        final names = <String>[
          for (final raw in members)
            if (raw is Map)
              '${raw['name'] ?? memberLabel}'
              '${raw['is_me'] == true ? ' ($meLabel)' : ''}',
        ];
        int metric(String key) => (data[key] as num?)?.toInt() ?? 0;
        setState(() {
          spaceId = data['space_id']?.toString();
          spaceName = data['space_name']?.toString();
          memberCount = metric('member_count');
          memberDisplayNames = names;
          final rawExpiry = data['pending_invitation_expires_at'];
          pendingInviteExpiry = rawExpiry == null
              ? null : DateTime.tryParse(rawExpiry.toString());
          taskSummary = SpaceTaskSummary(
            openShared: metric('open_shared_tasks'),
            assignedToMe: metric('assigned_to_me'),
            myPrivate: metric('my_private_tasks'),
            completedShared: metric('completed_shared_tasks'),
          );
          activeShoppingLists = metric('shopping_lists');
          activeOtherLists = metric('other_lists');
          activeNotes = metric('notes');
          activeCalendarEvents = metric('calendar_entries');
          activeMemories = metric('memories_count');
          activeGoals = metric('active_goals');
          achievedGoals = metric('completed_goals');
          recentCheckins = metric('recent_checkins');
          membershipResolved = true;
          summaryLoading = false;
          loading = false;
        });
      }
      if (spaceId != null) {
        CurrentSpaceCache.instance.seed(client.auth.currentUser!.id, spaceId);
      }
      PerformanceTimings.instance.record('Home overview network', watch.elapsed);
    } on PostgrestException catch (error) {
      PerformanceTimings.instance.record('Home overview failed', watch.elapsed);
      if (mounted && request == _requestVersion) {
        setState(() {
          issue = error.message;
          loading = false;
          summaryLoading = false;
        });
      }
    } catch (_) {
      PerformanceTimings.instance.record('Home overview failed', watch.elapsed);
      if (mounted && request == _requestVersion) {
        setState(() {
          issue = tr(context, 'loadedError');
          loading = false;
          summaryLoading = false;
        });
      }
    }
  }

  Future<void> _perform(Future<void> Function() action) async {
    setState(() {
      working = true;
      issue = null;
    });
    try {
      await action();
      if (mounted) await _load();
    } on PostgrestException catch (e) {
      if (mounted) setState(() => issue = e.message);
    } catch (_) {
      if (mounted) setState(() => issue = tr(context, 'actionError'));
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> _create() => _perform(() async {
        await client.rpc('create_space');
      });

  Future<void> _accept() async {
    final code = normalizedInvitationCode(invitationController.text);
    if (code == null) {
      setState(() => issue = tr(context, 'invalidInvite'));
      return;
    }
    await _perform(() async {
      await client.rpc('accept_invitation', params: {'p_token': code});
      invitationController.clear();
    });
  }

  Future<void> _invite() async {
    final id = spaceId;
    if (id == null) return;
    setState(() {
      working = true;
      issue = null;
    });
    try {
      final token = await client.rpc(
        'create_invitation',
        params: {'p_space_id': id},
      ) as String;
      await Clipboard.setData(ClipboardData(text: token));
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(tr(context, 'inviteTitle')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(context, 'inviteCopied')),
                const SizedBox(height: 16),
                SelectableText(
                  token,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () => Clipboard.setData(ClipboardData(text: token)),
              icon: const Icon(Icons.copy),
              label: Text(tr(context, 'copyAgain')),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(tr(context, 'done')),
            ),
          ],
        ),
      );
      if (mounted) await _load();
    } on PostgrestException catch (e) {
      if (mounted) setState(() => issue = e.message);
    } catch (_) {
      if (mounted) setState(() => issue = tr(context, 'requestInviteError'));
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> _revokeInvite() async {
    final id = spaceId;
    if (id == null || pendingInviteExpiry == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr(context, 'revokeTitle')),
        content: Text(tr(context, 'revokeMessage')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(tr(context, 'keepInvitation')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(tr(context, 'revoke')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _perform(() async {
      await client.rpc('revoke_pending_invitation', params: {'p_space_id': id});
    });
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(tr(context, 'ourSpace'),
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(tr(context, 'spaceSubtitle')),
          const SizedBox(height: 16),
          if (issue != null) ...[
            Text(issue!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
          ],
          if (loading)
            Padding(
              padding: const EdgeInsets.all(36),
              child: Center(
                child: Column(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 14),
                    Text(tr(context, 'openingSpace')),
                  ],
                ),
              ),
            )
          else if (!membershipResolved && spaceId == null) ...[
            Text(tr(context, 'loadedError')),
            TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: Text(tr(context, 'retry')),
            ),
          ]
          else if (spaceId == null) ...[
            _panel(
              tr(context, 'createSpaceTitle'),
              tr(context, 'createSpaceDescription'),
              Icons.favorite_border,
              FilledButton(
                onPressed: working ? null : _create,
                child: Text(tr(context, 'createSpaceButton')),
              ),
            ),
            const SizedBox(height: 14),
            _panel(
              tr(context, 'joinPartner'),
              tr(context, 'joinDescription'),
              Icons.people_outline,
              Column(
                children: [
                  TextField(
                    controller: invitationController,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: tr(context, 'invitationCode'),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: tr(context, 'pasteCode'),
                        icon: const Icon(Icons.content_paste),
                        onPressed: () async {
                          final clip = await Clipboard.getData('text/plain');
                          if (!mounted) return;
                          final text = clip?.text;
                          if (text != null) {
                            invitationController.text = text.trim();
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.tonal(
                    onPressed: working ? null : _accept,
                    child: Text(tr(context, 'joinSpace')),
                  ),
                ],
              ),
            ),
          ] else ...[
            _panel(
              spaceName ?? 'Our Space',
              memberCount == 2
                  ? tr(context, 'connected')
                  : tr(context, 'invitePartnerDescription'),
              Icons.favorite_rounded,
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${tr(context, 'members')}: $memberCount / 2'),
                  const SizedBox(height: 8),
                  for (final memberName in memberDisplayNames)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          const Icon(Icons.person_outline, size: 18),
                          const SizedBox(width: 8),
                          Expanded(child: Text(memberName)),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  if (memberCount < 2) ...[
                    FilledButton.icon(
                      onPressed: working ? null : _invite,
                      icon: const Icon(Icons.person_add_alt_1),
                      label: Text(pendingInviteExpiry == null
                          ? tr(context, 'createInvitation')
                          : tr(context, 'replaceInvitation')),
                    ),
                    if (pendingInviteExpiry != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        '${tr(context, 'invitationExpires')}: '
                        '${pendingInviteExpiry!.toLocal().toString().split('.').first}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      TextButton.icon(
                        onPressed: working ? null : _revokeInvite,
                        icon: const Icon(Icons.link_off),
                        label: Text(tr(context, 'revokeInvitation')),
                      ),
                    ],
                  ],
                  TextButton.icon(
                    onPressed: working ? null : _load,
                    icon: const Icon(Icons.refresh),
                    label: Text(tr(context, 'refreshStatus')),
                  ),
                ],
              ),
            ),
          ],
          if (spaceId != null) ...[
            const SizedBox(height: 24),
            Text(
              tr(context, 'plansAtGlance'),
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    if (summaryLoading && taskSummary == null)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    if (summaryIssue != null) ...[
                      Text(tr(context, 'dashboardStatsUnavailable')),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh),
                        label: Text(tr(context, 'retry')),
                      ),
                    ],
                    if (taskSummary != null) ...[
                      _metric(tr(context, 'openSharedTasks'), taskSummary!.openShared),
                      _metric(tr(context, 'assignedToMe'), taskSummary!.assignedToMe),
                      _metric(tr(context, 'myPrivateTasks'), taskSummary!.myPrivate),
                      _metric(tr(context, 'completedSharedTasks'),
                          taskSummary!.completedShared),
                      const Divider(),
                      _metric(tr(context, 'shoppingListsCount'), activeShoppingLists),
                      _metric(tr(context, 'otherListsCount'), activeOtherLists),
                      _metric(tr(context, 'notesCount'), activeNotes),
                      _metric(tr(context, 'calendarEntries'), activeCalendarEvents),
                      _metric(tr(context, 'memoriesCount'), activeMemories),
                      _metric(tr(context, 'activeGoalsCount'), activeGoals),
                      _metric(tr(context, 'achievedGoalsCount'), achievedGoals),
                      _metric(tr(context, 'recentCheckinsCount'), recentCheckins),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(tr(context, 'quickAccess'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: widget.onOpenPlans,
                  icon: const Icon(Icons.checklist_rounded),
                  label: Text(tr(context, 'plans')),
                ),
                OutlinedButton.icon(
                  onPressed: widget.onOpenLists,
                  icon: const Icon(Icons.shopping_cart_outlined),
                  label: Text(tr(context, 'openLists')),
                ),
                OutlinedButton.icon(
                  onPressed: widget.onOpenNotes,
                  icon: const Icon(Icons.sticky_note_2_outlined),
                  label: Text(tr(context, 'openNotes')),
                ),
                OutlinedButton.icon(
                  onPressed: widget.onOpenCalendar,
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text(tr(context, 'calendar')),
                ),
                OutlinedButton.icon(
                  onPressed: widget.onOpenMemories,
                  icon: const Icon(Icons.auto_stories_outlined),
                  label: Text(tr(context, 'openMemories')),
                ),
                OutlinedButton.icon(
                  onPressed: widget.onOpenGoals,
                  icon: const Icon(Icons.flag_outlined),
                  label: Text(tr(context, 'openGoals')),
                ),
                OutlinedButton.icon(
                  onPressed: widget.onOpenCheckins,
                  icon: const Icon(Icons.favorite_outline),
                  label: Text(tr(context, 'openCheckins')),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              tr(context, 'summaryHelp'),
              style: TextStyle(fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _metric(String title, int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(title)),
          Text('$count', style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _panel(String title, String description, IconData icon, Widget action) {
    return Card(
      elevation: 0,
      color: const Color(0xFFE4F2F0),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 30, color: const Color(0xFF167E81)),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(description),
            const SizedBox(height: 14),
            action,
          ],
        ),
      ),
    );
  }
}

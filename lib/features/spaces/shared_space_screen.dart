import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'invitation_code.dart';
import 'space_task_summary.dart';
import '../../l10n/onespace_strings.dart';

class SharedSpaceScreen extends StatefulWidget {
  const SharedSpaceScreen({super.key});

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
  DateTime? pendingInviteExpiry;
  bool loading = true;
  bool working = false;
  String? issue;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    invitationController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // Capture labels before awaiting; never use BuildContext across async gaps.
    final memberLabel = tr(context, 'member');
    final meLabel = tr(context, 'me');
    setState(() {
      loading = true;
      issue = null;
    });
    try {
      final userId = client.auth.currentUser!.id;
      final memberships = await client
          .from('space_members')
          .select('space_id')
          .eq('user_id', userId)
          .limit(1);
      if (!mounted) return;
      if (memberships.isEmpty) {
        setState(() {
          spaceId = null;
          spaceName = null;
          memberCount = 0;
          memberDisplayNames = const [];
          taskSummary = null;
          pendingInviteExpiry = null;
        });
      } else {
        final id = memberships.first['space_id'] as String;
        final space = await client.from('spaces').select('name').eq('id', id).single();
        final members = await client
            .from('space_members')
            .select('user_id')
            .eq('space_id', id);
        final memberIds =
            members.map((member) => member['user_id'] as String).toList();
        final profiles = await client
            .from('profiles')
            .select('id,display_name')
            .inFilter('id', memberIds);
        final names = <String>[];
        for (final memberId in memberIds) {
          final matches = profiles.where((profile) => profile['id'] == memberId);
          final foundName = matches.isEmpty
              ? memberLabel
              : (matches.first['display_name'] as String? ?? memberLabel);
          names.add(memberId == userId ? '$foundName ($meLabel)' : foundName);
        }
        final invitations = await client
            .from('space_invitations')
            .select('expires_at, revoked_at, accepted_at')
            .eq('space_id', id)
            .eq('invited_by', userId)
            .order('created_at', ascending: false)
            .limit(1);
        DateTime? pending;
        if (invitations.isNotEmpty) {
          final invite = invitations.first;
          final expiry = DateTime.tryParse(invite['expires_at'] as String);
          if (invite['revoked_at'] == null &&
              invite['accepted_at'] == null &&
              expiry != null &&
              expiry.isAfter(DateTime.now())) {
            pending = expiry;
          }
        }
        final tasks = await client
            .from('tasks')
            .select('status,visibility,assigned_to')
            .eq('space_id', id);
        final summary = SpaceTaskSummary.fromRows(tasks, userId);
        if (!mounted) return;
        setState(() {
          spaceId = id;
          spaceName = space['name'] as String?;
          memberCount = members.length;
          memberDisplayNames = names;
          taskSummary = summary;
          pendingInviteExpiry = pending;
        });
      }
    } catch (_) {
      if (mounted) setState(() => issue = tr(context, 'loadedError'));
    } finally {
      if (mounted) setState(() => loading = false);
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
            const Center(child: CircularProgressIndicator())
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
          if (spaceId != null && taskSummary != null) ...[
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
                    _metric(tr(context, 'openSharedTasks'), taskSummary!.openShared),
                    _metric(tr(context, 'assignedToMe'), taskSummary!.assignedToMe),
                    _metric(tr(context, 'myPrivateTasks'), taskSummary!.myPrivate),
                    _metric(tr(context, 'completedSharedTasks'),
                        taskSummary!.completedShared),
                  ],
                ),
              ),
            ),
            Text(
              tr(context, 'summaryHelp'),
              style: TextStyle(fontSize: 12),
            ),
          ],
          const SizedBox(height: 24),
          Text(
            tr(context, 'yourAccount'),
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
          ),
          const SizedBox(height: 8),
          Text(client.auth.currentUser?.email ?? 'Signed in'),
          TextButton.icon(
            onPressed: working ? null : () => client.auth.signOut(),
            icon: const Icon(Icons.logout),
            label: Text(tr(context, 'signOut')),
          ),
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

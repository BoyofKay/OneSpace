import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'invitation_code.dart';

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
          pendingInviteExpiry = null;
        });
      } else {
        final id = memberships.first['space_id'] as String;
        final space = await client.from('spaces').select('name').eq('id', id).single();
        final members = await client
            .from('space_members')
            .select('user_id')
            .eq('space_id', id);
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
        if (!mounted) return;
        setState(() {
          spaceId = id;
          spaceName = space['name'] as String?;
          memberCount = members.length;
          pendingInviteExpiry = pending;
        });
      }
    } catch (_) {
      if (mounted) setState(() => issue = 'Could not load your space. Check your connection.');
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
      if (mounted) setState(() => issue = 'Could not complete the request. Try again.');
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
      setState(() => issue = 'Enter a valid 64-character invitation code.');
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
          title: const Text('Invite your partner'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'This invitation code has been copied. Share it privately '
                  'or switch accounts on this phone and paste it under Join a space. '
                  'It expires after 48 hours.',
                ),
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
              label: const Text('Copy again'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      );
      if (mounted) await _load();
    } on PostgrestException catch (e) {
      if (mounted) setState(() => issue = e.message);
    } catch (_) {
      if (mounted) setState(() => issue = 'Could not generate invitation.');
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
        title: const Text('Revoke invitation?'),
        content: const Text(
          'The invitation code will stop working immediately. '
          'You can generate a new code later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep invitation'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Revoke'),
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
          const Text('Our Space',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text('A private home for the two of you.'),
          const SizedBox(height: 16),
          if (issue != null) ...[
            Text(issue!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
          ],
          if (loading)
            const Center(child: CircularProgressIndicator())
          else if (spaceId == null) ...[
            _panel(
              'Create your shared space',
              'Start a private space, then invite your partner to join.',
              Icons.favorite_border,
              FilledButton(
                onPressed: working ? null : _create,
                child: const Text('Create Our Space'),
              ),
            ),
            const SizedBox(height: 14),
            _panel(
              'Join your partner',
              'Already have an invitation? Paste the code below.',
              Icons.people_outline,
              Column(
                children: [
                  TextField(
                    controller: invitationController,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: 'Invitation code',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: 'Paste invitation code',
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
                    child: const Text('Join space'),
                  ),
                ],
              ),
            ),
          ] else ...[
            _panel(
              spaceName ?? 'Our Space',
              memberCount == 2
                  ? 'You and your partner are connected.'
                  : 'Your space is created. Invite your partner.',
              Icons.favorite_rounded,
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Members: $memberCount of 2'),
                  const SizedBox(height: 12),
                  if (memberCount < 2) ...[
                    FilledButton.icon(
                      onPressed: working ? null : _invite,
                      icon: const Icon(Icons.person_add_alt_1),
                      label: Text(pendingInviteExpiry == null
                          ? 'Create invitation code'
                          : 'Generate a replacement code'),
                    ),
                    if (pendingInviteExpiry != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Pending invitation expires: '
                        '${pendingInviteExpiry!.toLocal().toString().split('.').first}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      TextButton.icon(
                        onPressed: working ? null : _revokeInvite,
                        icon: const Icon(Icons.link_off),
                        label: const Text('Revoke pending invitation'),
                      ),
                    ],
                  ],
                  TextButton.icon(
                    onPressed: working ? null : _load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh status'),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          const Text(
            'Your account',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
          ),
          const SizedBox(height: 8),
          Text(client.auth.currentUser?.email ?? 'Signed in'),
          TextButton.icon(
            onPressed: working ? null : () => client.auth.signOut(),
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
          ),
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

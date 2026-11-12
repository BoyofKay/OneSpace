import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
        });
      } else {
        final id = memberships.first['space_id'] as String;
        final space = await client.from('spaces').select('name').eq('id', id).single();
        final members = await client
            .from('space_members')
            .select('user_id')
            .eq('space_id', id);
        if (!mounted) return;
        setState(() {
          spaceId = id;
          spaceName = space['name'] as String?;
          memberCount = members.length;
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

  Future<void> _accept() => _perform(() async {
        final token = invitationController.text.trim().toLowerCase();
        if (token.isEmpty) throw const FormatException('Enter an invitation code');
        await client.rpc('accept_invitation', params: {'p_token': token});
        invitationController.clear();
      });

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
          title: const Text('Invitation copied'),
          content: const Text(
            'Your secure invitation code is copied to the clipboard. '
            'Send it privately to your partner. They can create their own '
            'OneSpace account and paste it under Join a space. '
            'The invitation expires after 48 hours. Generating another code '
            'revokes the previous one.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Got it'),
            ),
          ],
        ),
      );
    } on PostgrestException catch (e) {
      if (mounted) setState(() => issue = e.message);
    } catch (_) {
      if (mounted) setState(() => issue = 'Could not generate invitation.');
    } finally {
      if (mounted) setState(() => working = false);
    }
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
                    decoration: const InputDecoration(
                      labelText: 'Invitation code',
                      border: OutlineInputBorder(),
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
                  if (memberCount < 2)
                    FilledButton.icon(
                      onPressed: working ? null : _invite,
                      icon: const Icon(Icons.person_add_alt_1),
                      label: const Text('Copy partner invitation'),
                    ),
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

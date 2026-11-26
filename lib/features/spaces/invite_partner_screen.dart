import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/app_env.dart';
import 'invitation_code.dart';
import 'invitation_qr.dart';
import 'package:onespace/l10n/phrases.dart';

/// Invitation management is a full page, never a form popup.
/// The recipient is bound to the code in QA before email is sent.
class InvitePartnerScreen extends StatefulWidget {
  const InvitePartnerScreen({super.key, this.spaceId});
  final String? spaceId;
  @override
  State<InvitePartnerScreen> createState() => _InvitePartnerScreenState();
}

class _InvitePartnerScreenState extends State<InvitePartnerScreen> {
  final _db = Supabase.instance.client;
  final _email = TextEditingController();
  String? _space;
  String? _token;
  String? _recipient;
  String? _error;
  String _delivery = 'pending';
  DateTime? _expiry;
  bool _loading = true;
  bool _busy = false;
  bool _editingRecipient = false;

  @override
  void initState() {
    super.initState();
    _space = widget.spaceId;
    _load();
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  bool get _validEmail {
    final e = _email.text.trim().toLowerCase();
    return e.length <= 254 &&
      RegExp(r'^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$').hasMatch(e) &&
      e != _db.auth.currentUser?.email?.toLowerCase();
  }

  /// Explains why Invite is unavailable, instead of a silently disabled button.
  String? get _emailHint {
    final e = _email.text.trim().toLowerCase();
    if (e.isEmpty) return null;
    if (e == _db.auth.currentUser?.email?.toLowerCase()) {
      return tt('This is your own email. You can’t invite yourself. '
        'Enter your partner’s email address.');
    }
    if (!_validEmail) return tt('Enter a valid email address, like name@example.com.');
    return null;
  }

  bool get _hasActive => _token != null &&
    _expiry != null && _expiry!.isAfter(DateTime.now());

  Future<void> _load() async {
    try {
      final id = _space;
      if (id != null) {
        final row = await _db.from('space_invitations')
          .select('token,invited_email,expires_at,delivery_status')
          .eq('space_id', id)
          .isFilter('accepted_at', null)
          .isFilter('revoked_at', null)
          .gt('expires_at', DateTime.now().toUtc().toIso8601String())
          .order('expires_at', ascending: false)
          .limit(1)
          .maybeSingle();
        if (!mounted) return;
        setState(() {
          _token = row?['token']?.toString();
          _recipient = row?['invited_email']?.toString();
          _expiry = DateTime.tryParse(row?['expires_at']?.toString() ?? '');
          _delivery = row?['delivery_status']?.toString() ?? 'pending';
          if (_recipient != null) _email.text = _recipient!;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error =
        tt('Unable to load the invitation. Try again.'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendEmail() async {
    if (_space == null || _recipient == null) return;
    final FunctionResponse result;
    try {
      result = await _db.functions.invoke('onespace-send-invitation',
        body: {'space_id': _space, 'recipient_email': _recipient});
    } on FunctionException catch (e) {
      // Show the server's reason (e.g. "wait a minute") instead of a guess.
      final reason = e.details is Map ? (e.details as Map)['error']?.toString() : null;
      throw StateError(reason ?? 'Email not accepted by provider');
    }
    if (result.status != 200 || result.data is! Map ||
        (result.data as Map)['ok'] != true) {
      throw StateError('Email not accepted by provider');
    }
    if (mounted) setState(() => _delivery = 'sent');
  }

  Future<void> _invite({bool replace = false}) async {
    if (_busy || !_validEmail) return;
    if (replace && _hasActive) {
      final approved = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(scrollable:true,
          title: Text(tt('Replace the current invitation?')),
          content: Text(tt('The previous invitation code will stop working immediately, '
            'even if the email has already been sent.')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: Text(tt('Keep invitation'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true),
              child: Text(tt('Generate new code'))),
          ],
        ));
      if (approved != true || !mounted) return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final id = _space ?? await _db.rpc('create_space') as String;
      _space = id;
      final address = _email.text.trim().toLowerCase();
      final token = await _db.rpc('create_addressed_invitation', params: {
        'p_space_id': id, 'p_email': address, 'p_replace': replace,
      }) as String;
      if (!mounted) return;
      setState(() { _recipient = address; _token = token; });
      await _load();
      try {
        await _sendEmail();
      } catch (e) {
        if (mounted) setState(() => _error =
          tt('The invitation is saved, but the email could not be sent. ') +
          (e is StateError && !e.message.startsWith('Email not accepted') ? tt(e.message)
            : tt('Use Resend email without generating a new code.')));
      }
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = tt('Could not create the invitation.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    if (_busy || !_hasActive || _recipient == null) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(scrollable:true,
        title: Text(tt('Resend the invitation?')),
        content: Text(tt('Send another OneSpace invitation to') +
          ' ' + _recipient! + '? ' +
          tt('The code and expiry date will stay the same.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tt('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tt('Resend email')),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    setState(() { _busy = true; _error = null; });
    try {
      await _sendEmail();
    } catch (e) {
      if (mounted) setState(() => _error =
        e is StateError && !e.message.startsWith('Email not accepted') ? tt(e.message)
          : tt('Unable to resend now. The same code is still valid.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revoke() async {
    if (_busy || !_hasActive || _space == null) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(scrollable:true,
        title: Text(tt('Revoke invitation?')),
        content: Text(tt('Your partner will no longer be able to use this code.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: Text(tt('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
            child: Text(tt('Revoke'))),
        ],
      ));
    if (approved != true || !mounted) return;
    setState(() { _busy = true; _error = null; });
    try {
      await _db.rpc('revoke_pending_invitation',
        params: {'p_space_id': _space});
      if (mounted) setState(() {
        _token = null;
        _expiry = null;
        _recipient = null;
        _delivery = 'pending';
        _email.clear();
        _editingRecipient = false;
      });
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share(String via) async {
    final code = _token;
    if (code == null) return;
    final message = invitationMessage(code, qa: !OneSpaceEnv.usesLegacyBackend);
    final uri = via == 'sms'
      ? Uri.parse('sms:?body=${Uri.encodeComponent(message)}')
      : Uri.parse('https://wa.me/?text=${Uri.encodeComponent(message)}');
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
          mounted) {
        setState(() => _error = tt('Could not open the sharing app.'));
      }
    } catch (_) {
      if (mounted) setState(() => _error = tt('Could not open the sharing app.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(tt('Invite my partner'))),
      body: SafeArea(child: _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(padding: const EdgeInsets.all(20), children: [
          Text(tt(_hasActive ? 'Your invitation is ready'
            : 'Start your shared space'),
            style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(tt(_hasActive
            ? 'Your invitation is tied to the email address below. '
              'Only that verified account can join.'
            : 'Enter your partner’s email to send a private OneSpace invitation.')),
          const SizedBox(height: 18),
          TextField(
            controller: _email,
            enabled: !_busy && (!_hasActive || _editingRecipient),
            onChanged: (_) => setState(() {}),
            textInputAction: TextInputAction.done,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            autofillHints: const [AutofillHints.email],
            decoration: InputDecoration(
              labelText: tt('Partner email'),
              border: const OutlineInputBorder(),
              errorText: _emailHint,
              errorMaxLines: 3,
            ),
          ),
          const SizedBox(height: 14),
          if (!_hasActive)
            FilledButton.icon(
              onPressed: _busy || !_validEmail ? null : () => _invite(),
              icon: const Icon(Icons.mail_outlined),
              label: Text(tt('Invite')),
            )
          else ...[
            Card(child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tt('Invitation status'),
                    style: theme.textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(tt(_delivery == 'sent'
                    ? 'Email submitted to delivery provider'
                    : _delivery == 'send_failed'
                      ? 'Email not sent'
                      : 'Invitation saved')),
                  if (_expiry != null) Text(
                    '${tt('Expires')}: ${_expiry!.toLocal().toString().split('.').first}'),
                  const SizedBox(height: 14),
                  InvitationQr(code: _token!),
                  const SizedBox(height: 12),
                  Text(tt('Invitation code')),
                  const SizedBox(height: 7),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [
                      Expanded(child: SelectableText(_token!,
                        style: const TextStyle(fontFamily:'monospace',
                          fontSize: 13))),
                      IconButton(
                        tooltip: tt('Copy code'),
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: _token!));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(tt('Invitation code copied'))));
                          }
                        },
                        icon: const Icon(Icons.copy),
                      ),
                    ]),
                  ),
                ],
              ),
            )),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: _busy || _recipient == null ? null : _resend,
              icon: const Icon(Icons.send_outlined),
              label: Text(tt('Resend email — same code')),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: OutlinedButton.icon(
                onPressed: _busy ? null : () => _share('whatsapp'),
                icon: const Icon(Icons.chat_bubble_outline, size: 19),
                label: const Text('WhatsApp', maxLines: 1),
              )),
              const SizedBox(width: 12),
              Expanded(child: OutlinedButton.icon(
                onPressed: _busy ? null : () => _share('sms'),
                icon: const Icon(Icons.sms_outlined, size: 19),
                label: Text(tt('Text message'), maxLines: 1),
              )),
            ]),
            const SizedBox(height: 22),
            const Divider(height: 1),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: _busy ? null : () async {
                if (!_editingRecipient) {
                  setState(() => _editingRecipient = true);
                  return;
                }
                if (!_validEmail) {
                  setState(() => _error = _emailHint ?? tt('Enter a valid partner email.'));
                  return;
                }
                await _invite(replace: true);
                if (mounted) setState(() => _editingRecipient = false);
              },
              icon: const Icon(Icons.autorenew),
              label: Text(tt(_editingRecipient
                ? 'Confirm replacement' : 'Generate a replacement code')),
            ),
            const SizedBox(height: 10),
            Center(child: TextButton.icon(
              onPressed: _busy ? null : _revoke,
              icon: const Icon(Icons.link_off),
              label: Text(tt('Revoke invitation')),
            )),
          ],
          if (_error != null) Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ),
          if (_busy) const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: LinearProgressIndicator()),
          const SizedBox(height: 16),
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: Text(tt('Close')),
          ),
        ])),
    );
  }
}

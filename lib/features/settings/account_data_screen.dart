import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:onespace/l10n/phrases.dart';
import '../../core/app_env.dart';

/// R59 (D47): Download my data · Delete my account.
///
/// After a seven-day grace period the approved future deletion workflow
/// deletes the requester's account/private records AND the current couple's
/// shared records; the surviving partner keeps only their own private data.
/// The backend currently fails closed; never enable deletion until verified.
class AccountDataRules {
  const AccountDataRules._();
  // QA only. The server gate (private.qa_account_v2_gate) is the real
  // control; Production keeps the request button disabled.
  static bool get qaDeletionControlsApproved => !OneSpaceEnv.usesLegacyBackend;
  static const confirmWord = 'DELETE';
  static bool confirmed(String typed) => typed.trim().toUpperCase() == confirmWord;
  static String fileName(DateTime now) =>
      'OneSpace-my-data-${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.json';
  static bool pending(Map<String, dynamic>? request) =>
      request != null && request['cancelled_at'] == null && request['completed_at'] == null;
}

class AccountDataScreen extends StatefulWidget {
  const AccountDataScreen({super.key});
  @override
  State<AccountDataScreen> createState() => _AccountDataScreenState();
}

class _AccountDataScreenState extends State<AccountDataScreen> {
  static const _channel = MethodChannel('onespace/data_export');
  final db = Supabase.instance.client;
  Map<String, dynamic>? request;
  bool loading = true, exporting = false, busy = false;
  String? message, error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final me = db.auth.currentUser?.id;
      if (me == null) return;
      final row = await db.from('account_deletion_requests').select('user_id,requested_at,purge_after,cancelled_at,completed_at,processing_at').eq('user_id', me).maybeSingle();
      if (mounted) setState(() { request = row; loading = false; });
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _export() async {
    setState(() { exporting = true; error = null; message = null; });
    try {
      final data = await db.rpc('export_my_data');
      final text = const JsonEncoder.withIndent('  ').convert(data);
      final saved = await _channel.invokeMethod<String>('saveToDownloads', {
        'name': AccountDataRules.fileName(DateTime.now()),
        'bytes': Uint8List.fromList(utf8.encode(text)),
      });
      if (mounted) setState(() => message = 'Saved to ${saved ?? 'Downloads'}.');
    } on PlatformException catch (e) {
      if (mounted) setState(() => error = e.message ?? 'Could not save the file.');
    } on MissingPluginException {
      if (mounted) setState(() => error = 'Saving files is not available on this phone yet.');
    } catch (_) {
      if (mounted) setState(() => error = 'Could not prepare your data. Please try again.');
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  Future<void> _cancelDeletion() async {
    setState(() { busy = true; error = null; });
    try {
      await db.rpc('cancel_account_deletion');
      await _load();
      if (mounted) setState(() => message = 'Deletion cancelled. Your account stays as it is.');
    } catch (_) {
      if (mounted) setState(() => error = 'Could not cancel. Please try again.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _requestDeletion() async {
    if (AccountDataRules.qaDeletionControlsApproved == false || busy) return;
    final phrase = TextEditingController();
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, refresh) => AlertDialog(scrollable:true,
            title: Text(tt('Delete your account?')),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tt('You have 7 days to cancel this request. '
                      'After the deadline, your account and ALL your private '
                      'data and files will be permanently deleted. '
                      'Your current couple’s shared space and all shared '
                      'data and files will also be deleted. Your partner '
                      'will become unpaired and keep only their own private '
                      'content. Nothing is transferred to a new partner.')),
                  const SizedBox(height: 12),
                  Text(tt('No automatic archive or recovery is created.')),
                  const SizedBox(height: 14),
                  Text(tt('Type DELETE to confirm:')),
                  TextField(
                    key: const Key('qaAccountDeletionTypedConfirmation'),
                    controller: phrase,
                    autocorrect: false,
                    enableSuggestions: false,
                    onChanged: (_) => refresh(() {}),
                    decoration: InputDecoration(labelText: tt('Confirmation')),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(tt('Cancel'))),
              FilledButton(
                key: const Key('qaConfirmAccountDeletionRequest'),
                onPressed: AccountDataRules.confirmed(phrase.text)
                  ? () => Navigator.pop(dialogContext, true) : null,
                child: Text(tt('Schedule deletion in 7 days')),
              ),
            ],
          ),
        ),
      );
      if (confirmed != true || !mounted) return;
      setState(() { busy = true; error = null; message = null; });
      try {
        await db.rpc('qa_request_account_deletion');
        await _load();
        if (mounted) setState(() =>
          message = tt('Deletion requested. You can cancel within 7 days.'));
      } catch (_) {
        if (mounted) setState(() =>
          error = 'Account deletion could not be scheduled. No data was deleted.');
      } finally {
        if (mounted) setState(() => busy = false);
      }
    } finally {
      phrase.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pending = AccountDataRules.pending(request);
    final due = DateTime.tryParse(request?['purge_after']?.toString() ?? '')?.toLocal();
    return Scaffold(
      appBar: AppBar(title: Text(tt('Your data and account'))),
      body: loading ? const Center(child: CircularProgressIndicator()) : ListView(
        padding: const EdgeInsets.all(18), children: [
          if (pending) Card(elevation: 0, color: theme.colorScheme.errorContainer,
            child: Padding(padding: const EdgeInsets.all(14), child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tt('Your account is scheduled for deletion'),
                  style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(tt(due == null ? 'It will be deleted soon.'
                  : 'It will be deleted on ${MaterialLocalizations.of(context).formatFullDate(due)}.'),
                  style: TextStyle(color: theme.colorScheme.onErrorContainer)),
                const SizedBox(height: 10),
                FilledButton.icon(onPressed: busy ? null : _cancelDeletion,
                  icon: const Icon(Icons.undo), label: Text(tt('Keep my account'))),
              ]))),
          const SizedBox(height: 8),
          Card(elevation: 0, child: Padding(padding: const EdgeInsets.all(14), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.download_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(child: Text(tt('Download my data'), style: theme.textTheme.titleMedium)),
              ]),
              const SizedBox(height: 6),
              Text(tt('This exports available account information as an unencrypted '
                'JSON file in your phone Downloads. Photos, documents and other '
                'attachments are NOT included. This is an optional manual export unrelated to account or relationship '
                'deletion. Store this JSON file privately.')),
              const SizedBox(height: 10),
              FilledButton.tonalIcon(onPressed: exporting ? null : _export,
                icon: exporting ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.download_outlined),
                label: Text(tt(exporting ? tt('Preparing…') : tt('Download')))),
            ]))),
          const SizedBox(height: 8),
          if (!pending) Card(elevation: 0,
            child: Padding(padding: const EdgeInsets.all(14), child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.person_remove_outlined, color: theme.colorScheme.error),
                  const SizedBox(width: 10),
                  Expanded(child: Text(tt('Delete my account'),
                    style: theme.textTheme.titleMedium)),
                ]),
                const SizedBox(height: 8),
                Text(tt('After you request deletion, you will have 7 days '
                  'to cancel. During that period, nothing is deleted. '
                  'At the deadline, your account and all your private '
                  'records will be permanently deleted. Your current '
                  'relationship’s shared records and attachments will '
                  'also be permanently deleted. Your partner will keep '
                  'only their own private content and become unpaired. '
                  'Deleted content cannot be restored.')),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: AccountDataRules.qaDeletionControlsApproved && !busy
                    ? _requestDeletion : null,
                  icon: const Icon(Icons.person_remove_outlined),
                  label: Text(tt(AccountDataRules.qaDeletionControlsApproved
                    ? 'Delete my account' : 'Account deletion temporarily unavailable')),
                ),
              ]))),
          if (message != null) Padding(padding: const EdgeInsets.only(top: 12),
            child: Text(tt(message!), style: theme.textTheme.bodyMedium)),
          if (error != null) Padding(padding: const EdgeInsets.only(top: 12),
            child: Text(tt(error!), style: TextStyle(color: theme.colorScheme.error))),
        ]),
    );
  }
}


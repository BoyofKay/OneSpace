import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:onespace/l10n/phrases.dart';

/// R59 (D47): Download my data · Delete my account.
///
/// Deleting keeps shared items for the partner and removes private items,
/// photos, devices and personal settings after a 7-day grace period, during
/// which the person can cancel by signing in again.
class AccountDataRules {
  const AccountDataRules._();
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
      final row = await db.from('account_deletion_requests').select().eq('user_id', me).maybeSingle();
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
                'attachments are NOT included. This is not the encrypted '
                'private/shared separation archive. Store this file privately.')),
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
                Text(tt('Temporarily unavailable in QA while OneSpace '
                  'implements verified private/shared exports and automatic '
                  'space separation. Your account and records remain unchanged.')),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.shield_outlined),
                  label: Text(tt('Secure deletion under preparation')),
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


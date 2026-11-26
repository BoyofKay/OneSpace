import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_env.dart';
import 'invitation_code.dart';
import 'package:onespace/l10n/phrases.dart';

/// A real branded email (images, linked button and signature) must be sent
/// as HTML by our authenticated mail service. mailto is plain text only.
Future<void> showInvitationEmailDialog(BuildContext context, {
  required String token, required String spaceId,
}) async {
  String recipient = '';
  String? issue;
  bool working = false;
  bool sent = false;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, update) => AlertDialog(scrollable:true,
        title: Text(tt('Send an invitation by email')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tt('Send a professionally formatted email with the OneSpace logo, a clickable invitation, and app store availability.')),
              const SizedBox(height: 14),
              TextField(
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.email],
                enabled: !working && !sent,
                decoration: InputDecoration(
                  labelText: tt('Your partner’s email'),
                  hintText: 'partner@example.com',
                  border: const OutlineInputBorder(),
                ),
                onChanged: (v) => recipient = v.trim(),
              ),
              if (issue != null) ...[
                const SizedBox(height: 10),
                Text(tt(issue!), style: TextStyle(
                  color: Theme.of(ctx).colorScheme.error)),
              ],
              if (sent) ...[
                const SizedBox(height: 10),
                Text(tt('Invitation sent. The code and expiry have not changed.')),
              ],
              const SizedBox(height: 14),
              Text(tt('Or open a plain-text draft in Gmail or your email app. The draft cannot include images or store badges.'),
                style: Theme.of(ctx).textTheme.bodySmall),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: working ? null : () => Navigator.pop(ctx),
            child: Text(tt('Done')),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.open_in_new),
            label: Text(tt('Open email draft')),
            onPressed: working ? null : () async {
              try {
                final uri = invitationEmailDraftUri(token,
                  qa: !OneSpaceEnv.usesLegacyBackend);
                final opened = await launchUrl(uri,
                  mode: LaunchMode.externalApplication);
                if (!opened && ctx.mounted) {
                  update(() => issue = tt('No email app is available.'));
                }
              } catch (_) {
                if (ctx.mounted) update(() => issue = tt('No email app is available.'));
              }
            },
          ),
          FilledButton.icon(
            icon: const Icon(Icons.email_outlined),
            label: Text(tt(working ? 'Sending...' : sent ? 'Sent' : 'Send branded email')),
            onPressed: working || sent ? null : () async {
              if (!RegExp(r'^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$')
                  .hasMatch(recipient) || recipient.length > 254) {
                update(() => issue = tt('Enter a valid email address.'));
                return;
              }
              update(() { working = true; issue = null; });
              try {
                final response = await Supabase.instance.client.functions.invoke(
                  'onespace-send-invitation',
                  body: {'space_id': spaceId, 'recipient_email': recipient},
                );
                if (response.status != 200 ||
                    response.data is! Map || (response.data as Map)['ok'] != true) {
                  throw StateError('Email send not confirmed');
                }
                if (ctx.mounted) update(() => sent = true);
              } catch (_) {
                if (ctx.mounted) update(() => issue =
                  tt('Unable to send the email. Use the draft or copy the invitation instead.'));
              } finally {
                if (ctx.mounted) update(() => working = false);
              }
            },
          ),
        ],
      ),
    ),
  );
}

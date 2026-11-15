import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/editor_scaffold.dart';
import '../../core/form_kit.dart';
import '../../core/performance_timings.dart';
import '../../l10n/onespace_strings.dart';
import 'package:onespace/l10n/phrases.dart';
import 'faq_content.dart';

/// R64: Help & support — FAQs, Contact us, Report a technical issue.
/// Messages go to public.support_requests (each person sees only their own;
/// the OneSpace team reads them in the Supabase dashboard).
class AppInfo {
  const AppInfo._();
  /// Set by the build (--dart-define=ONESPACE_VERSION=0.1.N).
  static const version = String.fromEnvironment('ONESPACE_VERSION', defaultValue: 'dev');
  static String get platform => Platform.isIOS ? 'ios' : Platform.isAndroid ? 'android' : 'other';
}

/// Anonymous technical details: app version, phone type, language, screen
/// timings and one API round trip. No content, names or IDs.
Future<String> collectDiagnostics(BuildContext context) async {
  final db = Supabase.instance.client;
  final id = db.auth.currentUser?.id;
  if (id != null) {
    final sample = Stopwatch()..start();
    try {
      await db.from('space_members').select('space_id').eq('user_id', id).limit(1)
          .timeout(const Duration(seconds: 12));
      PerformanceTimings.instance.record('Seoul API round trip', sample.elapsed);
    } catch (_) {
      PerformanceTimings.instance.record('API failed or timed out', sample.elapsed);
    }
  }
  final media = context.mounted ? MediaQuery.maybeOf(context) : null;
  return [
    'App: OneSpace ${AppInfo.version}',
    'Phone: ${AppInfo.platform} ${Platform.operatingSystemVersion}',
    'Language: ${OneSpacePhrases.lang}',
    if (media != null) 'Screen: ${media.size.width.round()}×${media.size.height.round()} · text ${media.textScaler.scale(10) / 10}x',
    'Time zone: ${DateTime.now().timeZoneName} (UTC${DateTime.now().timeZoneOffset.isNegative ? '' : '+'}${DateTime.now().timeZoneOffset.inMinutes / 60})',
    '',
    PerformanceTimings.instance.report,
  ].join('\n');
}

/// The old "Troubleshooting" timings dialog, now reachable from the Me tab.
Future<void> showTroubleshooting(BuildContext context) async {
  final report = await collectDiagnostics(context);
  if (!context.mounted) return;
  await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
    title: Text(tt('Troubleshooting')),
    content: SingleChildScrollView(child: SelectableText(report)),
    actions: [
      TextButton.icon(
        onPressed: () { Clipboard.setData(ClipboardData(text: report)); Navigator.of(ctx).pop(); },
        icon: const Icon(Icons.copy_outlined), label: Text(tr(context, 'copyDiagnostics'))),
      TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(tr(context, 'done'))),
    ]));
}

// ---------------------------------------------------------------- FAQs

class FaqScreen extends StatefulWidget {
  const FaqScreen({super.key});
  @override
  State<FaqScreen> createState() => _FaqScreenState();
}

class _FaqScreenState extends State<FaqScreen> {
  final search = TextEditingController();

  @override
  void dispose() { search.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final ar = OneSpacePhrases.arabic;
    final q = search.text.trim().toLowerCase();
    final theme = Theme.of(context);
    final groups = <String, List<FaqEntry>>{};
    for (final f in faqEntries) {
      final text = '${f.q(ar)} ${f.a(ar)}'.toLowerCase();
      if (q.isNotEmpty && !text.contains(q)) continue;
      groups.putIfAbsent(f.topic(ar), () => []).add(f);
    }
    return Scaffold(
      appBar: AppBar(title: Text(tt('Questions and answers'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        TextField(controller: search, onChanged: (_) => setState(() {}),
          decoration: InputDecoration(prefixIcon: const Icon(Icons.search),
            labelText: tt('Search questions'), border: const OutlineInputBorder())),
        const SizedBox(height: 12),
        if (groups.isEmpty) Padding(padding: const EdgeInsets.all(24),
          child: Text(tt('No answer matches. Ask us with Contact us.'), textAlign: TextAlign.center)),
        for (final g in groups.entries) ...[
          Padding(padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Text(g.key, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary))),
          Card(elevation: 0, child: Column(children: [
            for (final f in g.value) ExpansionTile(
              title: Text(f.q(ar)),
              childrenPadding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 14),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [Text(f.a(ar), style: theme.textTheme.bodyMedium)]),
          ])),
        ],
        const SizedBox(height: 16),
        OutlinedButton.icon(icon: const Icon(Icons.mail_outline), label: Text(tt('Still need help? Contact us')),
          onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute<void>(
            builder: (_) => const SupportFormScreen(kind: 'contact')))),
      ]),
    );
  }
}

// ---------------------------------------------------------- Contact / issue

class SupportFormScreen extends StatefulWidget {
  const SupportFormScreen({super.key, required this.kind});
  /// 'contact' (question, feedback, idea) or 'issue' (something is broken).
  final String kind;
  @override
  State<SupportFormScreen> createState() => _SupportFormScreenState();
}

class _SupportFormScreenState extends State<SupportFormScreen> {
  final subject = TextEditingController();
  final message = TextEditingController();
  final email = TextEditingController();
  late String kind = widget.kind;
  String topic = '';
  bool attachDetails = true;
  bool saving = false;
  String? error;

  bool get issue => kind == 'issue';

  @override
  void initState() {
    super.initState();
    email.text = Supabase.instance.client.auth.currentUser?.email ?? '';
  }

  @override
  void dispose() { subject.dispose(); message.dispose(); email.dispose(); super.dispose(); }

  Future<void> _send() async {
    final mail = email.text.trim();
    if (mail.isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(mail)) {
      setState(() => error = tt('Enter a valid email address.'));
      return;
    }
    setState(() { saving = true; error = null; });
    try {
      final details = issue && attachDetails ? await collectDiagnostics(context) : null;
      final title = [if (topic.isNotEmpty) topic, subject.text.trim()].join(' · ');
      await Supabase.instance.client.from('support_requests').insert({
        'kind': issue ? 'issue' : (topic == 'Idea' ? 'idea' : 'contact'),
        'subject': title.length > 160 ? title.substring(0, 160) : title,
        'message': message.text.trim(),
        'reply_email': mail.isEmpty ? null : mail,
        'app_version': AppInfo.version,
        'platform': AppInfo.platform,
        'locale': OneSpacePhrases.lang,
        'diagnostics': details == null ? null
          : (details.length > 8000 ? details.substring(0, 8000) : details),
      });
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.favorite_outline),
        title: Text(tt('Thank you — we got it')),
        content: Text(tt(issue
          ? 'We will look into it and reply by email. You can see what you sent under Your messages.'
          : 'We read every message and will reply by email. You can see what you sent under Your messages.')),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(tt('Done')))]));
      if (mounted) Navigator.of(context).pop(true);
    } on PostgrestException catch (e) {
      if (mounted) setState(() => error = e.message.contains('several messages')
        ? tt('You have sent several messages today. Please try again tomorrow.')
        : tt('Could not send. Check your connection and try again.'));
    } catch (_) {
      if (mounted) setState(() => error = tt('Could not send. Check your connection and try again.'));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final topics = issue
      ? const {'Crash or freeze': 'Crash or freeze', 'Something looks wrong': 'Something looks wrong',
          'Notifications': 'Notifications', 'Sign-in or partner': 'Sign-in or partner',
          'Photos or files': 'Photos or files', 'Other': 'Other'}
      : const {'Question': 'Question', 'Feedback': 'Feedback', 'Idea': 'Idea',
          'Account or privacy': 'Account or privacy', 'Other': 'Other'};
    return EditorScaffold(
      title: issue ? 'Report a technical issue' : 'Contact us',
      isNew: true,
      saving: saving,
      saveLabel: 'Send',
      listenTo: [subject, message, email],
      isChanged: () => subject.text.trim().isNotEmpty || message.text.trim().isNotEmpty,
      isComplete: () => subject.text.trim().isNotEmpty && message.text.trim().isNotEmpty,
      missingHint: 'Fill in the fields marked *',
      onSave: _send,
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
        Text(tt(issue
          ? 'Tell us what happened and we will fix it. Your notes, photos and messages are never included.'
          : 'Questions, feedback or ideas — we read everything and reply by email.'),
          style: theme.textTheme.bodyMedium),
        const SizedBox(height: 16),
        ChoiceRow<String>(label: issue ? 'What kind of problem?' : 'What is it about?',
          options: topics, selected: topic.isEmpty ? null : topic, allowNone: true,
          onSelected: (v) => setState(() => topic = v ?? '')),
        TextField(controller: subject, maxLength: 120, textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: tt(issue ? 'Short summary *' : 'Subject *'),
            hintText: tt(issue ? 'The calendar does not open' : 'How do I invite my partner?'),
            border: const OutlineInputBorder())),
        const SizedBox(height: 8),
        TextField(controller: message, maxLength: 4000, minLines: 5, maxLines: 12,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: tt(issue ? 'What happened? *' : 'Your message *'),
            hintText: tt(issue ? 'What you tapped, what you expected and what you saw instead.' : 'Write as much as you like.'),
            alignLabelWithHint: true, border: const OutlineInputBorder())),
        const SizedBox(height: 8),
        TextField(controller: email, keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(labelText: tt('Reply to (email)'),
            helperText: tt('We only use it to answer you.'), border: const OutlineInputBorder())),
        if (issue) ...[
          const SizedBox(height: 12),
          OptionChip(label: 'Include technical details', value: attachDetails, icon: Icons.memory,
            help: 'App version, phone type, language and loading times. No content or names.',
            onChanged: (v) => setState(() => attachDetails = v)),
          const SizedBox(height: 6),
          Text(tt('Tip: a screenshot helps. Send it with Contact us after this report, or reply to our email with it.'),
            style: theme.textTheme.bodySmall),
        ],
        if (error != null) Padding(padding: const EdgeInsets.only(top: 12),
          child: Text(error!, style: TextStyle(color: theme.colorScheme.error))),
      ]),
    );
  }
}

// ------------------------------------------------------------ Your messages

class MySupportRequestsScreen extends StatefulWidget {
  const MySupportRequestsScreen({super.key});
  @override
  State<MySupportRequestsScreen> createState() => _MySupportRequestsScreenState();
}

class _MySupportRequestsScreenState extends State<MySupportRequestsScreen> {
  List<Map<String, dynamic>>? rows;
  bool failed = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final r = await Supabase.instance.client.from('support_requests')
        .select('kind,subject,message,status,created_at').order('created_at', ascending: false).limit(50);
      if (mounted) setState(() { rows = List<Map<String, dynamic>>.from(r); failed = false; });
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = MaterialLocalizations.of(context);
    String status(String s) => switch (s) {
      'in_progress' => 'We are working on it', 'answered' => 'Answered by email', 'closed' => 'Closed', _ => 'Received',
    };
    return Scaffold(
      appBar: AppBar(title: Text(tt('Your messages'))),
      body: RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: [
        if (failed) Text(tt('Could not load your messages. Pull down to retry.'))
        else if (rows == null) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
        else if (rows!.isEmpty) Text(tt('You have not sent anything yet.'))
        else for (final r in rows!) Card(elevation: 0, child: ListTile(
          leading: Icon(r['kind'] == 'issue' ? Icons.bug_report_outlined : Icons.mail_outline),
          title: Text(r['subject'].toString()),
          subtitle: Text('${tt(status(r['status'].toString()))} · ${loc.formatMediumDate(DateTime.parse(r['created_at'].toString()).toLocal())}\n${r['message']}',
            maxLines: 3, overflow: TextOverflow.ellipsis),
          isThreeLine: true)),
      ])),
    );
  }
}

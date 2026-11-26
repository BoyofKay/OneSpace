import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';

import '../../core/editor_scaffold.dart';
import '../../core/app_env.dart';
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
      PerformanceTimings.instance.record(OneSpaceEnv.diagnosticRoundTripLabel, sample.elapsed);
    } catch (_) {
      PerformanceTimings.instance.record('API failed or timed out', sample.elapsed);
    }
  }
  final media = context.mounted ? MediaQuery.maybeOf(context) : null;
  return [
    '${tt('App')}: ${OneSpaceEnv.label} ${AppInfo.version}',
    '${tt('Environment')}: ${tt(OneSpaceEnv.isProduction ? 'Production' : 'QA')} · ${OneSpaceEnv.backendRegion}',
    '${tt('Phone')}: ${AppInfo.platform} ${Platform.operatingSystemVersion}',
    '${tt('Language')}: ${OneSpacePhrases.lang}',
    if (media != null) '${tt('Screen')}: ${media.size.width.round()}×${media.size.height.round()} · ${tt('Text size')} ${media.textScaler.scale(10) / 10}x',
    '${tt('Time zone')}: ${DateTime.now().timeZoneName} (UTC${DateTime.now().timeZoneOffset.isNegative ? '' : '+'}${DateTime.now().timeZoneOffset.inMinutes / 60})',
    '',
    if (PerformanceTimings.instance.measurements.value.isEmpty)
      tt('No timings collected yet.')
    else
      ...PerformanceTimings.instance.measurements.value.entries.map(
        (entry) => '${tt(entry.key)}: ${entry.value} ${tt('ms')}'),
  ].join('\n');
}

/// The old "Troubleshooting" timings dialog, now reachable from the Me tab.
Future<void> showTroubleshooting(BuildContext context) async {
  final report = await collectDiagnostics(context);
  if (!context.mounted) return;
  await showDialog<void>(context: context, builder: (ctx) => AlertDialog(scrollable:true,
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
  /// R73: an optional screenshot (private; only you and support can see it).
  XFile? screenshot;
  Uint8List? screenshotBytes;
  String? error;

  bool get issue => kind == 'issue';
  /// R74: the form also works from the sign-in screen (no account needed).
  bool get signedOut => Supabase.instance.client.auth.currentUser == null;

  @override
  void initState() {
    super.initState();
    email.text = Supabase.instance.client.auth.currentUser?.email ?? '';
  }

  @override
  void dispose() { subject.dispose(); message.dispose(); email.dispose(); super.dispose(); }

  Future<void> _send() async {
    final mail = email.text.trim();
    if (signedOut && mail.isEmpty) {
      setState(() => error = tt('Enter your email so we can reply.'));
      return;
    }
    if (mail.isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(mail)) {
      setState(() => error = tt('Enter a valid email address.'));
      return;
    }
    setState(() { saving = true; error = null; });
    try {
      final details = issue && attachDetails ? await collectDiagnostics(context) : null;
      String? shotPath;
      final shot = screenshot, bytes = screenshotBytes;
      if (issue && shot != null && bytes != null) {
        final db = Supabase.instance.client;
        final ext = shot.name.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
        shotPath = '${db.auth.currentUser!.id}/${DateTime.now().millisecondsSinceEpoch}.$ext';
        await db.storage.from('onespace-support').uploadBinary(shotPath, bytes,
          fileOptions: FileOptions(contentType: ext == 'png' ? 'image/png' : 'image/jpeg'));
      }
      final title = [if (topic.isNotEmpty) topic, subject.text.trim()].join(' · ');
      if (signedOut) {
        await Supabase.instance.client.rpc('submit_public_support', params: {
          'p_kind': topic == 'I cannot sign in' ? 'account' : issue ? 'issue' : topic == 'Complaint' ? 'complaint' : 'contact',
          'p_subject': title.length > 160 ? title.substring(0, 160) : title,
          'p_message': message.text.trim(),
          'p_reply_email': mail,
          'p_app_version': AppInfo.version,
          'p_platform': AppInfo.platform,
          'p_locale': OneSpacePhrases.lang,
          'p_diagnostics': details == null ? null : (details.length > 4000 ? details.substring(0, 4000) : details),
        });
        if (!mounted) return;
        await showDialog<void>(context: context, builder: (ctx) => AlertDialog(scrollable:true,
          icon: const Icon(Icons.favorite_outline),
          title: Text(tt('Thank you — we got it')),
          content: Text(tt('We will reply to {} as soon as we can.').replaceFirst('{}', mail)),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(tt('Done')))]));
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
      await Supabase.instance.client.from('support_requests').insert({
        'kind': issue ? 'issue' : (topic == 'Idea' ? 'idea' : topic == 'Complaint' ? 'complaint' : 'contact'),
        'subject': title.length > 160 ? title.substring(0, 160) : title,
        'message': message.text.trim(),
        'reply_email': mail.isEmpty ? null : mail,
        'app_version': AppInfo.version,
        'platform': AppInfo.platform,
        'locale': OneSpacePhrases.lang,
        'diagnostics': details == null ? null
          : (details.length > 8000 ? details.substring(0, 8000) : details),
        if (shotPath != null) 'screenshot_path': shotPath,
      });
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (ctx) => AlertDialog(scrollable:true,
        icon: const Icon(Icons.favorite_outline),
        title: Text(tt('Thank you — we got it')),
        content: Text(tt(issue
          ? 'We will look into it and reply by email. You can see what you sent under Your messages.'
          : 'We read every message and will reply by email. You can see what you sent under Your messages.')),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(tt('Done')))]));
      if (mounted) Navigator.of(context).pop(true);
    } on PostgrestException catch (e) {
      if (mounted) setState(() => error = e.message.contains('Too many')
        ? tt('Too many messages. Please try again later.')
        : e.message.contains('several messages')
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
          'Complaint': 'Complaint', 'Account or privacy': 'Account or privacy', 'Other': 'Other'};
    final shown = signedOut ? {'I cannot sign in': 'I cannot sign in', ...topics} : topics;
    return EditorScaffold(
      title: issue ? 'Report a technical issue' : 'Contact us',
      isNew: true,
      saving: saving,
      saveLabel: 'Send',
      listenTo: [subject, message, email],
      isChanged: () => subject.text.trim().isNotEmpty || message.text.trim().isNotEmpty,
      isComplete: () => subject.text.trim().isNotEmpty && message.text.trim().isNotEmpty
        && (!signedOut || email.text.trim().isNotEmpty),
      missingHint: 'Fill in the fields marked *',
      onSave: _send,
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
        Text(tt(issue
          ? 'Tell us what happened and we will fix it. Your notes, photos and messages are never included.'
          : 'Questions, feedback or ideas — we read everything and reply by email.'),
          style: theme.textTheme.bodyMedium),
        const SizedBox(height: 16),
        ChoiceRow<String>(label: issue ? 'What kind of problem?' : 'What is it about?',
          options: shown, selected: topic.isEmpty ? null : topic, allowNone: true,
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
          decoration: InputDecoration(labelText: tt(signedOut ? 'Your email *' : 'Reply to (email)'),
            helperText: tt('We only use it to answer you.'), border: const OutlineInputBorder())),
        if (issue) ...[
          const SizedBox(height: 12),
          OptionChip(label: 'Include technical details', value: attachDetails, icon: Icons.memory,
            help: 'App version, phone type, language and loading times. No content or names.',
            onChanged: (v) => setState(() => attachDetails = v)),
          const SizedBox(height: 10),
          if (signedOut)
            const SizedBox.shrink()
          else if (screenshotBytes == null)
            OutlinedButton.icon(
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(tt('Add a screenshot')),
              onPressed: saving ? null : () async {
                final picked = await ImagePicker().pickImage(source: ImageSource.gallery,
                  imageQuality: 85, maxWidth: 2000, maxHeight: 2000);
                if (picked == null) return;
                final bytes = await picked.readAsBytes();
                if (bytes.length > 6 * 1024 * 1024) {
                  if (mounted) setState(() => error = tt('That picture is too large (6 MB at most).'));
                  return;
                }
                if (mounted) setState(() { screenshot = picked; screenshotBytes = bytes; });
              })
          else Card(elevation: 0, child: ListTile(
            leading: ClipRRect(borderRadius: BorderRadius.circular(6),
              child: Image.memory(screenshotBytes!, width: 48, height: 48, fit: BoxFit.cover)),
            title: Text(tt('Screenshot attached')),
            subtitle: Text(tt('Only you and the support team can see it.')),
            trailing: IconButton(tooltip: tt('Remove'), icon: const Icon(Icons.close),
              onPressed: () => setState(() { screenshot = null; screenshotBytes = null; })))),
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
    final db = Supabase.instance.client;
    try {
      List<dynamic> r;
      try {
        r = await db.from('support_requests')
          .select('kind,subject,message,status,outcome,support_reply,support_reply_at,created_at')
          .order('created_at', ascending: false).limit(50);
      } on PostgrestException {
        // A backend without replies yet (before 0323): show what it has.
        r = await db.from('support_requests')
          .select('kind,subject,message,status,created_at')
          .order('created_at', ascending: false).limit(50);
      }
      if (mounted) setState(() { rows = List<Map<String, dynamic>>.from(r); failed = false; });
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(tt('Your messages'))),
      body: RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: [
        if (failed) Text(tt('Could not load your messages. Pull down to retry.'))
        else if (rows == null) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
        else if (rows!.isEmpty) Text(tt('You have not sent anything yet.'))
        else ...[
          Text(tt('Replies from OneSpace support appear here. Pull down to refresh.'),
            style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          for (final r in rows!) SupportRequestCard(row: r),
        ],
      ])),
    );
  }
}

/// UAT 26 Nov 2026 (D105): one sent message with its status, outcome and the
/// reply support wrote for this person. Never shows support's internal note.
class SupportRequestCard extends StatelessWidget {
  const SupportRequestCard({super.key, required this.row});
  final Map<String, dynamic> row;

  static String kindLabel(String? kind) => switch (kind) {
    'issue' => 'Technical issue', 'idea' => 'Idea', 'complaint' => 'Complaint',
    'account' => 'Sign-in help', _ => 'Message',
  };
  static String statusLabel(String? status) => switch (status) {
    'in_progress' => 'We are working on it', 'answered' => 'Answered', 'closed' => 'Closed', _ => 'Received',
  };
  static String? outcomeLabel(String? outcome) => switch (outcome) {
    'solved' => 'Solved', 'not_a_bug' => 'Working as intended',
    'feature_request' => 'Added to our list of ideas', 'duplicate' => 'Already reported',
    'no_reply' => 'Closed without a reply from you', 'other' => 'Closed', _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = MaterialLocalizations.of(context);
    String date(Object? v) {
      final d = DateTime.tryParse(v?.toString() ?? '');
      return d == null ? '' : loc.formatMediumDate(d.toLocal());
    }
    final reply = row['support_reply']?.toString().trim() ?? '';
    final outcome = outcomeLabel(row['outcome']?.toString());
    final closed = row['status'] == 'closed';
    return Card(elevation: 0, child: Padding(padding: const EdgeInsets.all(14), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(row['kind'] == 'issue' ? Icons.bug_report_outlined : Icons.mail_outline, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text('${tt(kindLabel(row['kind']?.toString()))} · ${date(row['created_at'])}',
            style: theme.textTheme.bodySmall)),
          Chip(visualDensity: VisualDensity.compact,
            label: Text(tt(statusLabel(row['status']?.toString()))),
            backgroundColor: closed ? theme.colorScheme.surfaceContainerHighest : theme.colorScheme.secondaryContainer),
        ]),
        const SizedBox(height: 6),
        Text(tt(row['subject']?.toString() ?? ''), style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(row['message']?.toString() ?? '', maxLines: 4, overflow: TextOverflow.ellipsis),
        if (outcome != null) ...[
          const SizedBox(height: 10),
          Row(children: [
            Icon(Icons.check_circle_outline, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Expanded(child: Text('${tt('Outcome')}: ${tt(outcome)}', style: theme.textTheme.bodyMedium)),
          ]),
        ],
        if (reply.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${tt('Reply from OneSpace support')}${row['support_reply_at'] == null ? '' : ' · ${date(row['support_reply_at'])}'}',
                style: theme.textTheme.labelMedium),
              const SizedBox(height: 4),
              SelectableText(reply),
            ])),
        ],
      ])));
  }
}

// ------------------------------------------------------------ About & privacy

/// R64: plain-language privacy summary (also needed for the app stores).
class AboutPrivacyScreen extends StatelessWidget {
  const AboutPrivacyScreen({super.key});

  static const _en = <(String, String)>[
    ('What OneSpace is', 'Your own private space for everyday life, on your own or as a couple. It gathers what you save in different apps in one place. If you invite a partner, what you mark "Shared" is visible to both of you.'),
    ('What we store', 'Your account (name, email, language, time zone), and what you create: notes, lists, reminders, events, trips, occasions, memories, photos, letters, check-ins and gestures. Items marked "Only me" are visible only to you.'),
    ('What we never do', 'We do not sell data, show ads, track your location or phone activity, or read your content to profile you. Voice commands are handled by your phone\'s speech service and are not stored.'),
    ('Where it is kept', 'In our database and file storage (Supabase), protected by access rules checked for every item, so only you, and the partner you invite, can reach your items. The live app is hosted in the European Union (Frankfurt); test versions may use servers in South Korea. Push notifications go through Firebase Cloud Messaging.'),
    ('If you separate', 'If either of you leaves the shared space, removes the other or deletes it, everything shared in it is permanently deleted for both of you and cannot be restored. Each person keeps their own "Only me" items.'),
    ('Your choices', 'Download a copy of your account information at any time, and delete your account from Me → Your data and account. Nothing is deleted for 7 days and you can cancel in that time. After that your account and your "Only me" items are deleted, together with what you share with your current partner; your partner keeps their own "Only me" items.'),
    ('Help and support', 'Messages you send from Contact us or Report a technical issue are kept so we can answer you. Technical details are only attached when you allow it. If the app hits an error, the error message (never your content) is sent to us automatically so we can fix it.'),
  ];
  static const _ar = <(String, String)>[
    ('ما هو OneSpace', 'مساحتك الخاصة لحياتك اليومية، بمفردك أو مع شريكك. يجمع ما تحفظه في تطبيقات مختلفة في مكان واحد. وإذا دعوت شريكًا، فما تجعله «مشتركًا» يراه كلاكما.'),
    ('ما الذي نحفظه', 'حسابك (الاسم والبريد واللغة والمنطقة الزمنية)، وما تنشئه: الملاحظات والقوائم والتذكيرات والمواعيد والرحلات والمناسبات والذكريات والصور والرسائل والتواصل اليومي واللفتات. العناصر المعلّمة «أنا فقط» تظهر لك وحدك.'),
    ('ما لا نفعله أبدًا', 'لا نبيع البيانات ولا نعرض إعلانات ولا نتتبع موقعك أو نشاط هاتفك ولا نقرأ محتواك لبناء ملف عنك. الأوامر الصوتية تعالجها خدمة الكلام في هاتفك ولا تُحفظ.'),
    ('أين تُحفظ', 'في قاعدة بياناتنا وتخزين الملفات (Supabase)، بحماية قواعد وصول تُفحص لكل عنصر، فلا يصل إلى عناصرك سواك وسوى الشريك الذي تدعوه. النسخة الرسمية مستضافة في الاتحاد الأوروبي (فرانكفورت)، وقد تستخدم النسخ التجريبية خوادم في كوريا الجنوبية. تمر الإشعارات عبر Firebase Cloud Messaging.'),
    ('إذا انفصلتما', 'إذا غادر أحدكما المساحة المشتركة أو أزال الآخر أو حذفها، يُحذف كل ما شاركتماه فيها نهائيًا لكليكما ولا يمكن استعادته. ويحتفظ كل منكما بعناصره «أنا فقط».'),
    ('خياراتك', 'نزّل نسخة من معلومات حسابك في أي وقت، واحذف حسابك من «أنا» ← «بياناتك وحسابك». لا يُحذف شيء لمدة 7 أيام ويمكنك الإلغاء خلالها. بعد ذلك يُحذف حسابك وعناصرك «أنا فقط»، ومعها ما تشاركه مع شريكك الحالي؛ ويحتفظ شريكك بعناصره «أنا فقط».'),
    ('المساعدة والدعم', 'نحتفظ بالرسائل التي ترسلها عبر «تواصل معنا» أو «الإبلاغ عن مشكلة تقنية» لنرد عليك. لا تُرفق التفاصيل التقنية إلا بإذنك. وإذا واجه التطبيق خطأً تصلنا رسالة الخطأ تلقائيًا (دون أي من محتواك) لنصلحه.'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = OneSpacePhrases.arabic ? _ar : _en;
    return Scaffold(
      appBar: AppBar(title: Text(tt('About and privacy'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
        Center(child: Image.asset('assets/branding/mark.png', width: 84, height: 84)),
        const SizedBox(height: 8),
        Center(child: Text('OneSpace', style: theme.textTheme.titleLarge)),
        Center(child: Text('${tr(context, 'tagline')} · ${AppInfo.version}', style: theme.textTheme.bodySmall)),
        const SizedBox(height: 16),
        for (final (title, body) in items) Card(elevation: 0, child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
            const SizedBox(height: 6),
            Text(body, style: theme.textTheme.bodyMedium),
          ]))),
      ]),
    );
  }
}

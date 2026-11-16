import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:onespace/l10n/phrases.dart';
import '../support/support_screens.dart';

/// R74 (Ahmed): people agree to the terms when they sign up (email or
/// Google / Apple). Bump [termsVersion] when the text changes in substance;
/// everyone is then asked once more.
const termsVersion = '2026-11-16';

const _termsEn = <(String, String)>[
  ('The short version', 'OneSpace is a private space for you and your partner. Use it kindly and lawfully, keep your password safe, and remember that what you mark "Shared" is seen by your partner.'),
  ('Your account', 'You need to be at least 18. Give a real email address and keep your sign-in private. You are responsible for what happens under your account. One shared space connects exactly two people.'),
  ('Your content', 'What you write and upload stays yours. You give OneSpace only the permission needed to store it, show it to you and your partner, and send you notifications about it. We do not sell it, show ads or use it to profile you.'),
  ('Sharing with your partner', 'Items marked "Shared" are visible to your partner and may notify them. "Only me" items are visible only to you. If one of you leaves or deletes the account, shared items stay with the other person.'),
  ('Acceptable use', 'Do not use OneSpace to harass, threaten or spy on anyone, to store illegal material, or to break into other accounts or the service. We may suspend accounts that do.'),
  ('Test version', 'This is an early version shared with a small group of testers. Features may change, and something may break. Please keep your own copy of anything important and tell us about problems.'),
  ('Ending', 'You can download your data and delete your account at any time (Me → Your data and account). We may end the test or the service with notice by email.'),
  ('Liability', 'OneSpace is provided "as is". To the extent the law allows, we are not liable for indirect losses or for missed reminders or notifications.'),
  ('Privacy', 'How we handle data is explained in About and privacy. Contact us from the app or the sign-in screen with any question.'),
];

const _termsAr = <(String, String)>[
  ('باختصار', 'OneSpace مساحة خاصة لك ولشريكك. استخدمه بلطف وبما يوافق القانون، واحفظ كلمة مرورك، وتذكّر أن ما تجعله «مشتركًا» يراه شريكك.'),
  ('حسابك', 'يجب أن يكون عمرك 18 عامًا على الأقل. استخدم بريدًا حقيقيًا وحافظ على سرية تسجيل دخولك. أنت مسؤول عمّا يحدث في حسابك. المساحة المشتركة تجمع شخصين فقط.'),
  ('محتواك', 'ما تكتبه وترفعه يبقى ملكك. تمنح OneSpace فقط الإذن اللازم لحفظه وعرضه لك ولشريكك وإرسال إشعارات عنه. لا نبيعه ولا نعرض إعلانات ولا نستخدمه لبناء ملف عنك.'),
  ('المشاركة مع شريكك', 'العناصر «المشتركة» يراها شريكك وقد تصله إشعارات عنها. عناصر «أنا فقط» تراها وحدك. إذا غادر أحدكما أو حذف حسابه، تبقى العناصر المشتركة مع الآخر.'),
  ('الاستخدام المقبول', 'لا تستخدم OneSpace للمضايقة أو التهديد أو التجسس على أحد، أو لحفظ مواد غير قانونية، أو لاختراق حسابات أخرى أو الخدمة. قد نوقف الحسابات المخالفة.'),
  ('نسخة تجريبية', 'هذه نسخة مبكرة لمجموعة صغيرة من المختبرين. قد تتغير الميزات وقد يتعطل شيء. احتفظ بنسخة من كل ما هو مهم، وأخبرنا بأي مشكلة.'),
  ('الإنهاء', 'يمكنك تنزيل بياناتك وحذف حسابك في أي وقت (أنا ← بياناتك وحسابك). قد ننهي التجربة أو الخدمة بإشعار عبر البريد.'),
  ('المسؤولية', 'يُقدَّم OneSpace «كما هو». وبالقدر الذي يسمح به القانون، لسنا مسؤولين عن الخسائر غير المباشرة أو عن تذكيرات أو إشعارات لم تصل.'),
  ('الخصوصية', 'طريقة تعاملنا مع البيانات موضحة في «عن التطبيق والخصوصية». تواصل معنا من التطبيق أو من شاشة الدخول لأي سؤال.'),
];

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = OneSpacePhrases.arabic ? _termsAr : _termsEn;
    return Scaffold(
      appBar: AppBar(title: Text(tt('Terms of use'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
        Text(tt('Version {}').replaceFirst('{}', termsVersion), style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        for (final (title, body) in items) Card(elevation: 0, child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
            const SizedBox(height: 6),
            Text(body, style: theme.textTheme.bodyMedium),
          ]))),
        const SizedBox(height: 8),
        OutlinedButton.icon(icon: const Icon(Icons.privacy_tip_outlined), label: Text(tt('About and privacy')),
          onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute<void>(
            builder: (_) => const AboutPrivacyScreen()))),
      ]),
    );
  }
}

/// "I agree to the Terms of use and the Privacy summary" with links.
class TermsAgreement extends StatelessWidget {
  const TermsAgreement({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;
  @override
  Widget build(BuildContext context) {
    final link = TextStyle(color: Theme.of(context).colorScheme.primary, decoration: TextDecoration.underline);
    void open(Widget page) => Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (_) => page));
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Checkbox(value: value, onChanged: onChanged == null ? null : (v) => onChanged!(v ?? false)),
      Expanded(child: Padding(padding: const EdgeInsets.only(top: 12), child: Wrap(children: [
        Text(tt('I agree to the ')),
        InkWell(onTap: () => open(const TermsScreen()), child: Text(tt('Terms of use'), style: link)),
        Text(tt(' and the ')),
        InkWell(onTap: () => open(const AboutPrivacyScreen()), child: Text(tt('Privacy summary'), style: link)),
        Text(tt(', and I am 18 or older.')),
      ]))),
    ]);
  }
}

/// Shown once after signing in when this account has not accepted the
/// current terms (Google / Apple sign-ups, or older accounts).
class TermsGate extends StatefulWidget {
  const TermsGate({super.key, required this.child});
  final Widget child;
  @override
  State<TermsGate> createState() => _TermsGateState();
}

class _TermsGateState extends State<TermsGate> {
  static String? _acceptedFor;
  bool? accepted;
  bool agree = false;
  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final db = Supabase.instance.client;
    final user = db.auth.currentUser;
    if (user == null) return;
    if (_acceptedFor == user.id) { setState(() => accepted = true); return; }
    try {
      final row = await db.from('profiles').select('terms_version').eq('id', user.id).maybeSingle();
      var ok = row?['terms_version'] == termsVersion;
      // Agreed on the sign-up form before the email was confirmed.
      if (!ok && user.userMetadata?['terms_version'] == termsVersion) {
        await db.rpc('accept_terms', params: {'p_version': termsVersion});
        ok = true;
      }
      if (ok) _acceptedFor = user.id;
      if (mounted) setState(() => accepted = ok);
    } catch (_) {
      // Never lock someone out of their space over a network hiccup.
      if (mounted) setState(() => accepted = true);
    }
  }

  Future<void> _accept() async {
    setState(() { saving = true; error = null; });
    try {
      await Supabase.instance.client.rpc('accept_terms', params: {'p_version': termsVersion});
      _acceptedFor = Supabase.instance.client.auth.currentUser?.id;
      if (mounted) setState(() => accepted = true);
    } catch (_) {
      if (mounted) setState(() => error = tt('Could not save. Check your connection and try again.'));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (accepted == true) return widget.child;
    if (accepted == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final theme = Theme.of(context);
    return Scaffold(body: SafeArea(child: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: ListView(padding: const EdgeInsets.all(24), shrinkWrap: true, children: [
        Icon(Icons.handshake_outlined, size: 48, color: theme.colorScheme.primary),
        const SizedBox(height: 12),
        Text(tt('Before you start'), textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(tt('Please read and accept the terms of use. They are short and written in plain language.'),
          textAlign: TextAlign.center),
        const SizedBox(height: 16),
        TermsAgreement(value: agree, onChanged: saving ? null : (v) => setState(() => agree = v)),
        if (error != null) Text(error!, style: TextStyle(color: theme.colorScheme.error)),
        const SizedBox(height: 16),
        FilledButton(onPressed: agree && !saving ? _accept : null, child: Text(tt('Accept and continue'))),
        TextButton(onPressed: saving ? null : () => Supabase.instance.client.auth.signOut(),
          child: Text(tt('Sign out'))),
      ]),
    ))));
  }
}

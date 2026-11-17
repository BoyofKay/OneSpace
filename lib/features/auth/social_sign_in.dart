import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:onespace/l10n/phrases.dart';
import '../../core/app_env.dart';
import '../../core/auth_redirect.dart';

/// R74 (Ahmed): sign up / sign in with Google or Apple. The buttons appear by
/// themselves once a provider is switched on in Supabase Auth, so the app never
/// shows a button that cannot work.
class SocialProviders {
  const SocialProviders._();
  static const _url = '${OneSpaceEnv.supabaseUrl}/auth/v1/settings';
  static const _key = OneSpaceEnv.publishableKey;
  static Future<Set<String>>? _cached;

  static Future<Set<String>> enabled() => _cached ??= () async {
    try {
      final r = await http.get(Uri.parse(_url), headers: {'apikey': _key}).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) { _cached = null; return <String>{}; }
      final external = (jsonDecode(r.body) as Map)['external'] as Map? ?? const {};
      return {for (final p in const ['google', 'apple']) if (external[p] == true) p};
    } catch (_) {
      _cached = null;
      return <String>{};
    }
  }();
}

class SocialSignInButtons extends StatefulWidget {
  const SocialSignInButtons({super.key, required this.registering, required this.termsAccepted,
    required this.onNeedTerms, this.disabled = false});
  final bool registering, termsAccepted, disabled;
  /// Called when someone signing up has not ticked the terms box yet.
  final VoidCallback onNeedTerms;
  @override
  State<SocialSignInButtons> createState() => _SocialSignInButtonsState();
}

class _SocialSignInButtonsState extends State<SocialSignInButtons> {
  Set<String> providers = const {};
  String? busy;
  String? error;

  @override
  void initState() {
    super.initState();
    SocialProviders.enabled().then((p) { if (mounted) setState(() => providers = p); });
  }

  Future<void> _go(String provider) async {
    if (widget.registering && !widget.termsAccepted) { widget.onNeedTerms(); return; }
    setState(() { busy = provider; error = null; });
    try {
      await Supabase.instance.client.auth.signInWithOAuth(
        provider == 'apple' ? OAuthProvider.apple : OAuthProvider.google,
        redirectTo: oneSpaceAuthRedirectTo,
        authScreenLaunchMode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) setState(() => error = tt('Could not open the sign-in page. Try again.'));
    } finally {
      if (mounted) setState(() => busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (providers.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    Widget button(String p, IconData icon, String label) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        icon: busy == p ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(icon),
        label: Text(tt(label)),
        onPressed: widget.disabled || busy != null ? null : () => _go(p)));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 14),
      Row(children: [
        const Expanded(child: Divider()),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(tt('or'), style: theme.textTheme.bodySmall)),
        const Expanded(child: Divider()),
      ]),
      const SizedBox(height: 10),
      if (providers.contains('google')) button('google', Icons.g_mobiledata_rounded,
        widget.registering ? 'Sign up with Google' : 'Continue with Google'),
      if (providers.contains('apple')) button('apple', Icons.apple,
        widget.registering ? 'Sign up with Apple' : 'Continue with Apple'),
      if (error != null) Text(error!, style: TextStyle(color: theme.colorScheme.error)),
    ]);
  }
}

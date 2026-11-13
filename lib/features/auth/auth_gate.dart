import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth_redirect.dart';
import '../../core/current_space_cache.dart';
import '../../l10n/onespace_locale_controller.dart';
import '../../l10n/onespace_strings.dart';
import 'auth_language_switcher.dart';
import 'password_recovery_screen.dart';
import 'remembered_accounts.dart';
import 'saved_session_login.dart';
import 'session_lock_rules.dart';

/// Exactly one Supabase session is persisted. A restored session gets an
/// OS-level unlock gate, while other remembered accounts require their own
/// credentials. We never store multiple tokens or user passwords.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.signedIn});
  final Widget signedIn;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  StreamSubscription<AuthState>? _subscription;
  bool _recovery = false;
  bool _locked = false;
  bool _coveredForBackground = false;
  DateTime _lastInteraction = DateTime.now();
  DateTime? _backgroundedAt;
  Timer? _idleTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final auth = Supabase.instance.client.auth;
    _locked = auth.currentSession != null;
    if (!_locked) _startIdleTimer();
    if (_locked) _loadAccountLocale();
    _subscription = auth.onAuthStateChange.listen(
      (state) {
        if (!mounted) return;
        if (state.event == AuthChangeEvent.passwordRecovery) {
          setState(() {
            _recovery = true;
            _locked = false;
          });
        } else if (state.event == AuthChangeEvent.signedOut) {
          // Never reuse an earlier account's partner identity or space ID.
          CurrentSpaceCache.instance.clear();
          _idleTimer?.cancel();
          OneSpaceLocaleController.instance.selectLanguage(null);
          setState(() {
            _recovery = false;
            _locked = false;
            _coveredForBackground = false;
          });
        } else if (state.event == AuthChangeEvent.signedIn) {
          // A refresh/restore must never bypass the locked saved-session UI.
          // Only the actual OS/password verification callback unlocks it.
          _loadAccountLocale();
          if (!_locked) _startIdleTimer();
          if (!_locked) setState(() {});
        }
      },
      onError: (Object error, StackTrace trace) {
        debugPrint('Temporary OneSpace auth event error.');
      },
    );
  }

  Future<void> _loadAccountLocale() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final profile = await Supabase.instance.client.from('profiles')
          .select('locale').eq('id', userId).single();
      if (mounted && Supabase.instance.client.auth.currentUser?.id == userId) {
        OneSpaceLocaleController.instance.selectLanguage(
          profile['locale'] as String?,
        );
      }
    } catch (_) {
      // Device locale remains available when offline.
    }
  }

  void _unlockCurrentAccount() {
    if (mounted && Supabase.instance.client.auth.currentSession != null) {
      setState(() {
        _locked = false;
        // Keep the privacy shield until Android signals resumed.
      });
      if (!_coveredForBackground) _startIdleTimer();
    }
  }

  void _startIdleTimer() {
    _idleTimer?.cancel();
    _lastInteraction = DateTime.now();
    _idleTimer = Timer(SessionLockRules.idleTimeout, () {
      if (!mounted || Supabase.instance.client.auth.currentSession == null) return;
      // Never let an active session's UI remain exposed after inactivity.
      setState(() => _locked = true);
    });
  }

  void _registerInteraction() {
    if (_locked || _coveredForBackground) return;
    _startIdleTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null || !mounted) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _backgroundedAt ??= DateTime.now();
      _idleTimer?.cancel();
      if (!_coveredForBackground) {
        setState(() => _coveredForBackground = true);
      }
    } else if (state == AppLifecycleState.resumed) {
      final now = DateTime.now();
      final since = _backgroundedAt;
      final lockOnReturn = since != null &&
          (SessionLockRules.backgroundExpired(since, now) ||
              SessionLockRules.idleExpired(_lastInteraction, now));
      _backgroundedAt = null;
      setState(() {
        _coveredForBackground = false;
        if (lockOnReturn) _locked = true;
      });
      if (!_locked) _startIdleTimer();
    }
  }

  Future<void> _switchAccount() async {
    // Signing out removes the *active* stored Supabase session. Recently used
    // email addresses stay locally, and the next account must sign in itself.
    await Supabase.instance.client.auth.signOut();
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;
    final session = auth.currentSession;
    if (_recovery && session != null) return const ResetPasswordScreen();
    if (session == null) return const SignInScreen();
    // Android's credential prompt may temporarily send the Activity to
    // inactive. Keep the underlying screen mounted while hiding its content:
    // replacing it would dispose the widget awaiting the OS auth result.
    final Widget content;
    if (_locked) {
      content = SavedSessionLogin(
        email: auth.currentUser?.email ?? '',
        onUnlocked: _unlockCurrentAccount,
        onSwitchAccount: _switchAccount,
      );
    } else {
      content = Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _registerInteraction(),
        onPointerSignal: (_) => _registerInteraction(),
        child: widget.signedIn,
      );
    }
    return Stack(
      children: [
        content,
        if (_coveredForBackground)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0xFFF7F8FA),
              child: Center(
                child: Icon(Icons.lock_outline, size: 48),
              ),
            ),
          ),
      ],
    );
  }
}

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final formKey = GlobalKey<FormState>();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final nameController = TextEditingController();
  bool registering = false;
  bool loading = false;
  bool hidePassword = true;
  bool awaitingConfirmation = false;
  bool showingRecovery = false;
  bool rememberAtSignup = true;
  String? error;
  String? info;

  @override
  void initState() {
    super.initState();
    _prefillLastEmail();
  }

  Future<void> _prefillLastEmail() async {
    try{
      final email=await RememberedAccounts.lastUsedEmail();
      if(mounted&&email!=null&&emailController.text.isEmpty){
        emailController.text=email;
      }
    }catch(_){}
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (loading || !(formKey.currentState?.validate() ?? false)) return;
    setState(() { loading = true; error = null; info = null; });
    final email = emailController.text.trim().toLowerCase();
    try {
      final auth = Supabase.instance.client.auth;
      if (registering) {
        final result = await auth.signUp(
          email: email,
          password: passwordController.text,
          data: {
            'display_name': nameController.text.trim(),
            'locale': Localizations.localeOf(context).languageCode == 'ar'
                ? 'ar' : 'en',
          },
          emailRedirectTo: oneSpaceAuthRedirectTo,
        );
        if (rememberAtSignup) await RememberedAccounts.remember(email);
        if (mounted && result.session == null) {
          setState(() {
            awaitingConfirmation = true;
            info = tr(context, 'signupCheckEmail');
          });
        }
      } else {
        await auth.signInWithPassword(
          email: email, password: passwordController.text,
        );
        TextInput.finishAutofillContext(shouldSave: true);
        // Last successful account is always shown first on the next sign-in.
        await RememberedAccounts.remember(email);
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = tr(context, 'loginFailed'));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _resendConfirmation() async {
    final email = emailController.text.trim().toLowerCase();
    if (!email.contains('@')) {
      setState(() => error = tr(context, 'emailRequired'));
      return;
    }
    setState(() { loading = true; error = null; info = null; });
    try {
      await Supabase.instance.client.auth.resend(
        type: OtpType.signup, email: email,
        emailRedirectTo: oneSpaceAuthRedirectTo,
      );
      if (mounted) setState(() => info = tr(context, 'confirmationResent'));
    } on AuthException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = tr(context, 'loginFailed'));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (showingRecovery) {
      return ForgotPasswordScreen(
        initialEmail: emailController.text.trim(),
        onBack: () => setState(() => showingRecovery = false),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: ListView(
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: [
                AuthLanguageSwitcher(disabled: loading),
                const SizedBox(height: 12),
                const Icon(Icons.favorite_rounded,
                    size: 54, color: Color(0xFF167E81)),
                const SizedBox(height: 8),
                const Text('OneSpace',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                const SizedBox(height: 5),
                Text(tr(context, 'tagline'), textAlign: TextAlign.center),
                const SizedBox(height: 23),
                Text(registering ? tr(context, 'createAccount')
                    : tr(context, 'welcome'),
                    style: const TextStyle(
                        fontSize: 23, fontWeight: FontWeight.w700)),
                const SizedBox(height: 18),
                AutofillGroup(
                  child: Form(
                    key: formKey,
                    child: Column(
                      children: [
                        if (registering) ...[
                          TextFormField(
                            controller: nameController,
                            maxLength: 80,
                            decoration: InputDecoration(
                              labelText: tr(context, 'yourName'),
                              border: const OutlineInputBorder(),
                            ),
                            validator: (value) => value == null ||
                                value.trim().isEmpty
                                ? tr(context, 'nameRequired') : null,
                          ),
                          const SizedBox(height: 12),
                        ],
                        TextFormField(
                          key: const Key('loginEmail'),
                          controller: emailController,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [
                            AutofillHints.username, AutofillHints.email,
                          ],
                          decoration: InputDecoration(
                            labelText: tr(context, 'email'),
                            border: const OutlineInputBorder(),
                          ),
                          validator: (value) => value == null ||
                                  !value.trim().contains('@')
                              ? tr(context, 'emailRequired') : null,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                key: const Key('loginPassword'),
                                controller: passwordController,
                                obscureText: hidePassword,
                                autofillHints: [
                                  registering
                                      ? AutofillHints.newPassword
                                      : AutofillHints.password,
                                ],
                                decoration: InputDecoration(
                                  labelText: tr(context, 'password'),
                                  border: const OutlineInputBorder(),
                                  suffixIcon: IconButton(
                                    tooltip: hidePassword
                                        ? 'Show password' : 'Hide password',
                                    icon: Icon(hidePassword
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined),
                                    onPressed: () => setState(
                                        () => hidePassword = !hidePassword),
                                  ),
                                ),
                                validator: (value) => value == null ||
                                    value.isEmpty
                                    ? tr(context, 'passwordRequired')
                                    : registering && value.length < 8
                                        ? tr(context, 'passwordTooShort') : null,
                              ),
                            ),
                          ],
                        ),
                        if (registering)
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            value: rememberAtSignup,
                            title: Text(tr(context, 'rememberEmail')),
                            onChanged: loading ? null : (value) =>
                                setState(() => rememberAtSignup = value ?? false),
                          ),
                      ],
                    ),
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(error!, style: const TextStyle(color: Colors.red)),
                ],
                if (info != null) ...[
                  const SizedBox(height: 10),
                  Text(info!, style: const TextStyle(
                      color: Color(0xFF167E81))),
                ],
                if (awaitingConfirmation) TextButton(
                  onPressed: loading ? null : _resendConfirmation,
                  child: Text(tr(context, 'resendConfirmation')),
                ),
                const SizedBox(height: 18),
                FilledButton(
                  key: const Key('loginSubmit'),
                  onPressed: loading ? null : _submit,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text(loading ? tr(context, 'pleaseWait')
                        : tr(context, registering ? 'register' : 'signIn')),
                  ),
                ),
                if (!registering) ...[
                  TextButton(
                    onPressed: loading ? null : () =>
                        setState(() => showingRecovery = true),
                    child: Text(tr(context, 'forgotPassword')),
                  ),
                ],
                TextButton(
                  onPressed: loading ? null : () => setState(() {
                    registering = !registering;
                    awaitingConfirmation = false;
                    error = null;
                    info = null;
                  }),
                  child: Text(tr(context, registering
                      ? 'alreadyRegistered' : 'needAccount')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

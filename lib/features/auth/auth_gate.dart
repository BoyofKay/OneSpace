import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_env.dart';
import '../../core/auth_redirect.dart';
import '../../core/current_space_cache.dart';
import '../../theme/onespace_appearance.dart';
import '../../theme/occasion_theme_resolver.dart';
import '../../l10n/onespace_locale_controller.dart';
import '../../l10n/onespace_strings.dart';
import 'auth_language_switcher.dart';
import 'password_recovery_screen.dart';
import 'remembered_accounts.dart';
import 'device_unlock.dart';
import '../../core/first_name.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'session_lock_rules.dart';
import '../notifications/push_registration_gate.dart';
import 'package:onespace/l10n/phrases.dart';
import '../../core/phone_calendar_sync.dart';
import '../support/support_screens.dart';
import 'social_sign_in.dart';
import 'terms.dart';
import '../spaces/invitation_link_inbox.dart';

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
    if (_locked) unawaited(_loadAccountLocale());
    _subscription = auth.onAuthStateChange.listen(
      (state) {
        if (!mounted) return;
        if (state.event == AuthChangeEvent.passwordRecovery) {
          setState(() {
            _recovery = true;
            _locked = false;
          });
          // Verified Supabase recovery callback: remove Profile and other
          // routes so that ResetPasswordScreen is immediately visible.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !_recovery ||
                Supabase.instance.client.auth.currentSession == null) return;
            Navigator.of(context, rootNavigator: true)
                .popUntil((route) => route.isFirst);
          });
        } else if (state.event == AuthChangeEvent.signedOut) {
          // Never reuse an earlier account's partner identity or space ID.
          CurrentSpaceCache.instance.clear();
          OneSpaceAppearance.instance.setPersonalSeason(null);
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
          unawaited(_loadAccountLocale());
          if (!_locked){
            _startIdleTimer();
            unawaited(_refreshPersonalMoment());
            setState(() {});
          }
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
          .select('locale,display_name').eq('id', userId).single();
      if (mounted && Supabase.instance.client.auth.currentUser?.id == userId) {
        OneSpaceLocaleController.instance.selectLanguage(
          profile['locale'] as String?,
        );
        final name=FirstName.of(profile['display_name'],fallback:'');
        final email=Supabase.instance.client.auth.currentUser?.email?.toLowerCase();
        if(name.isNotEmpty&&email!=null){
          final prefs=SharedPreferencesAsync();
          await prefs.setString('onespace_greeting_first_name_v1',name);
          await prefs.setString('onespace_greeting_email_v1',email);
        }
      }
    } catch (_) {
      // Device locale remains available when offline.
    }
  }

  /// A private/specific annual celebration changes only THIS phone's theme.
  /// Supabase RLS filters the user's allowed occasions before resolution.
  Future<void> _refreshPersonalMoment()async{
    if(_locked)return;
    final client=Supabase.instance.client;
    final user=client.auth.currentUser?.id;
    if(user==null)return;
    try{
     final space=await CurrentSpaceCache.instance.get();
     if(space==null||client.auth.currentUser?.id!=user)return;
     final rows=await client.from('occasion_plans')
      .select('kind,occasion_on,annual,status,archived_at')
      .eq('space_id',space).isFilter('archived_at',null).limit(300);
     if(!mounted||_locked||client.auth.currentUser?.id!=user)return;
     OneSpaceAppearance.instance.setPersonalSeason(
      OccasionThemeResolver.forDate(
       List<Map<String,dynamic>>.from(rows),DateTime.now()));
    }catch(_){
     // Theme/biometric unlock must never depend on the network.
    }
  }

  void _unlockCurrentAccount() {
    if (mounted && Supabase.instance.client.auth.currentSession != null) {
      setState(() {
        _locked = false;
        // Keep the privacy shield until Android signals resumed.
      });
      if (!_coveredForBackground) _startIdleTimer();
      unawaited(_refreshPersonalMoment());
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
      if (!_locked){
        _startIdleTimer();
        unawaited(_refreshPersonalMoment());
        unawaited(PhoneCalendarSync.syncNow());
      }
    }
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
      content = SignInScreen(
        activeSessionEmail:auth.currentUser?.email ?? '',
        onSessionUnlocked:_unlockCurrentAccount,
      );
    } else {
      content = Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _registerInteraction(),
        onPointerSignal: (_) => _registerInteraction(),
        child: PushRegistrationGate(child:TermsGate(child:widget.signedIn)),
      );
    }
    return Stack(
      children: [
        content,
        if (_coveredForBackground)
          Positioned.fill(
            child: ColoredBox(
              color:Theme.of(context).colorScheme.surface,
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
  const SignInScreen({super.key,this.activeSessionEmail,this.onSessionUnlocked});

  /// The same sign-in page also unlocks an existing saved session.
  /// A signed-out device cannot use biometrics as substitute server credentials.
  final String? activeSessionEmail;
  final VoidCallback? onSessionUnlocked;

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
  bool agreedTerms = false;
  String? _rememberedFirstName;
  String? _rememberedEmail;
  String? error;
  String? info;

  @override
  void initState() {
    super.initState();
    if(widget.activeSessionEmail!=null){
      emailController.text=widget.activeSessionEmail!;
    }
    _prefillLastEmail();
    InvitationLinkInbox.instance.addListener(_invitationChanged);
  }

  void _invitationChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _prefillLastEmail() async {
    try{
      final email=widget.activeSessionEmail?.trim().toLowerCase()??
        await RememberedAccounts.lastUsedEmail();
      if(mounted&&email!=null&&emailController.text.isEmpty){
        emailController.text=email;
        final prefs=SharedPreferencesAsync();
        final matching=await prefs.getString('onespace_greeting_email_v1');
        final name=await prefs.getString('onespace_greeting_first_name_v1');
        if(mounted&&matching==email&&name!=null&&name.trim().isNotEmpty){
         setState((){
          _rememberedEmail=email;
          _rememberedFirstName=FirstName.of(name,fallback:'');
         });
        }
      }
    }catch(_){}
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    nameController.dispose();
    InvitationLinkInbox.instance.removeListener(_invitationChanged);
    super.dispose();
  }

  Future<void> _submit() async {
    if (loading || !(formKey.currentState?.validate() ?? false)) return;
    if (registering && !agreedTerms) {
      setState(() => error = 'Please accept the terms of use to create an account.');
      return;
    }
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
            // R74: agreed on this form; recorded on the profile at first sign-in.
            'terms_version': termsVersion,
          },
          emailRedirectTo: oneSpaceAuthRedirectTo,
        );
        if (rememberAtSignup) await RememberedAccounts.remember(email);
        if (mounted && result.session == null) {
          passwordController.clear();
          setState(() {
            awaitingConfirmation = true;
            info = null;
          });
        }
      } else {
        await auth.signInWithPassword(
          email: email, password: passwordController.text,
        );
        TextInput.finishAutofillContext(shouldSave: true);
        // Last successful account is always shown first on the next sign-in.
        await RememberedAccounts.remember(email);
        if(mounted&&widget.onSessionUnlocked!=null&&
          auth.currentSession!=null){widget.onSessionUnlocked!();}
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = tr(context, 'loginFailed'));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _deviceUnlock()async{
    if(loading)return;
    if(widget.onSessionUnlocked==null ||
       Supabase.instance.client.auth.currentSession==null){
      setState(()=>info=tt('Sign in with your password first. After sign-in, '
       'you can unlock a saved session with your fingerprint or phone PIN.'));
      return;
    }
    setState((){loading=true;info=null;error=null;});
    try{
      if(!await DeviceUnlock.isAvailable()){
        if(mounted)setState(()=>error=tr(context,'phoneUnlockUnavailable'));
        return;
      }
      final granted=await DeviceUnlock.authenticate();
      if(!mounted)return;
      if(granted){
        widget.onSessionUnlocked!();
      }else{
        setState(()=>info=tt('Device verification was cancelled or did not succeed. '
         'You can use the password instead.'));
      }
    }catch(_){
      if(mounted)setState(()=>error='Device unlock unavailable. Use your password.');
    }finally{if(mounted)setState(()=>loading=false);}
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
    if (awaitingConfirmation) {
      return ConfirmEmailStep(
        email: emailController.text.trim().toLowerCase(),
        pendingInvitation: InvitationLinkInbox.instance.pendingCode != null,
        loading: loading,
        message: info,
        error: error,
        onResend: _resendConfirmation,
        onSignIn: () => setState(() {
          awaitingConfirmation = false;
          registering = false;
          passwordController.clear();
          info = null;
          error = null;
        }),
        onDifferentEmail: () => setState(() {
          awaitingConfirmation = false;
          registering = false;
          emailController.clear();
          passwordController.clear();
          info = null;
          error = null;
        }),
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
                Icon(Icons.favorite_rounded,
                    size:54,color:Theme.of(context).colorScheme.primary),
                const SizedBox(height: 8),
                Text(tt('OneSpace'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                const SizedBox(height: 5),
                Text(tr(context, 'tagline'), textAlign: TextAlign.center),
                if (InvitationLinkInbox.instance.pendingCode != null) ...[
                  const SizedBox(height: 16),
                  Card(child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(children: [
                      const Icon(Icons.mark_email_read_outlined),
                      const SizedBox(width: 10),
                      Expanded(child: Text(tt(registering
                        ? (OneSpaceEnv.usesLegacyBackend ? 'Your partner’s invitation is saved. Create your account, confirm your email, then sign in to join automatically.'
                          : 'Your partner’s invitation is saved. Create your account, confirm your email, then sign in to accept or decline it.')
                        : (OneSpaceEnv.usesLegacyBackend ? 'Your partner’s invitation is saved. Sign in with the invited email to join automatically.'
                          : 'Your partner’s invitation is saved for your next sign-in. Sign in with the invited email to accept or decline it.')))),
                    ]),
                  )),
                ],
                const SizedBox(height: 23),
                Text(tt(registering ? tr(context, 'createAccount')
                    : (_rememberedFirstName!=null&&
                       emailController.text.trim().toLowerCase()==_rememberedEmail
                       ?'Welcome back, $_rememberedFirstName':tr(context,'welcome'))),
                    style: const TextStyle(
                        fontSize: 23, fontWeight: FontWeight.w700)),
                if(widget.onSessionUnlocked!=null)Padding(
                 padding:EdgeInsets.only(top:5,bottom:12),
                 child:Text(tt('Session locked. Use your phone PIN, fingerprint or password.'))),
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
                  onChanged:(_)=>setState((){}),
                          controller: emailController,
                          readOnly:widget.activeSessionEmail!=null,
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
                            if(!registering)...[
                              const SizedBox(width:10),
                              SizedBox(width:56,height:56,child:OutlinedButton(
                                key:const Key('loginFingerprint'),
                                style:OutlinedButton.styleFrom(
                                 padding:EdgeInsets.zero,
                                 shape:RoundedRectangleBorder(
                                  borderRadius:BorderRadius.circular(12))),
                                onPressed:loading?null:_deviceUnlock,
                                child:const Icon(Icons.fingerprint,size:30),
                              )),
                            ],
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
                        if (registering)
                          TermsAgreement(value: agreedTerms, onChanged: loading ? null
                            : (v) => setState(() { agreedTerms = v; error = null; })),
                      ],
                    ),
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(tt(error!),style:TextStyle(color:Theme.of(context).colorScheme.error)),
                ],
                if (info != null) ...[
                  const SizedBox(height: 10),
                  Text(tt(info!),style:TextStyle(color:Theme.of(context).colorScheme.primary)),
                ],
                const SizedBox(height: 18),
                FilledButton(
                  key: const Key('loginSubmit'),
                  onPressed: loading ? null : _submit,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text(tt(loading ? tr(context, 'pleaseWait')
                        : tr(context, registering ? 'register' : 'signIn'))),
                  ),
                ),
                if (widget.onSessionUnlocked == null)
                  SocialSignInButtons(registering: registering, termsAccepted: agreedTerms, disabled: loading,
                    onNeedTerms: () => setState(() => error = 'Please accept the terms of use to create an account.')),
                if (!registering) ...[
                  TextButton(
                    onPressed: loading ? null : () =>
                        setState(() => showingRecovery = true),
                    child: Text(tr(context, 'forgotPassword')),
                  ),
                ],
                if(widget.onSessionUnlocked==null)TextButton(
                  onPressed: loading ? null : () => setState(() {
                    registering = !registering;
                    awaitingConfirmation = false;
                    error = null;
                    info = null;
                  }),
                  child: Text(tr(context, registering
                      ? 'alreadyRegistered' : 'needAccount')),
                ),
                // R74: help even when you cannot sign in.
                const SizedBox(height: 12),
                const Divider(),
                Wrap(alignment: WrapAlignment.center, children: [
                  TextButton.icon(icon: const Icon(Icons.help_outline, size: 18), label: Text(tt('Help')),
                    onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute<void>(
                      builder: (_) => const FaqScreen()))),
                  TextButton.icon(icon: const Icon(Icons.mail_outline, size: 18), label: Text(tt('Contact us')),
                    onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute<void>(
                      builder: (_) => const SupportFormScreen(kind: 'contact')))),
                  TextButton.icon(icon: const Icon(Icons.bug_report_outlined, size: 18), label: Text(tt('Report a problem')),
                    onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute<void>(
                      builder: (_) => const SupportFormScreen(kind: 'issue')))),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Step 2 of signup. This is deliberately a full screen, not a message
/// underneath the still-active Create Account form.
class ConfirmEmailStep extends StatelessWidget {
  const ConfirmEmailStep({
    required this.email,
    required this.pendingInvitation,
    required this.loading,
    required this.message,
    required this.error,
    required this.onResend,
    required this.onSignIn,
    required this.onDifferentEmail,
  });

  final String email;
  final bool pendingInvitation;
  final bool loading;
  final String? message;
  final String? error;
  final VoidCallback onResend;
  final VoidCallback onSignIn;
  final VoidCallback onDifferentEmail;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: ListView(shrinkWrap: true,
        padding: const EdgeInsets.all(24),
        children: [
          const Icon(Icons.mark_email_read_outlined, size: 62),
          const SizedBox(height: 20),
          Text(tt('Confirm your email address'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 14),
          Text(tt('We sent a confirmation link to:'),
            textAlign: TextAlign.center),
          const SizedBox(height: 6),
          SelectableText(email,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          Text(tt('Open that email and confirm your account. Then return here and sign in.'),
            textAlign: TextAlign.center),
          if (pendingInvitation) ...[
            const SizedBox(height: 16),
            Card(child: Padding(padding: const EdgeInsets.all(14),
              child: Text(tt('Your partner’s invitation is safely kept on this phone. After email confirmation and sign-in, OneSpace will finish joining the invited space. Do not create a separate space.')))),
          ],
          if (message != null) ...[
            const SizedBox(height: 12),
            Text(tt(message!), textAlign: TextAlign.center),
          ],
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(tt(error!), textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            key: const Key('confirmationContinueToSignIn'),
            onPressed: loading ? null : onSignIn,
            icon: const Icon(Icons.login),
            label: Text(tt('I confirmed my email — Sign in')),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            key: const Key('confirmationResend'),
            onPressed: loading ? null : onResend,
            icon: const Icon(Icons.refresh),
            label: Text(tt('Resend confirmation email')),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: loading ? null : onDifferentEmail,
            child: Text(tt('Use a different email address')),
          ),
          if (loading) const LinearProgressIndicator(),
        ]),
    ))),
  );
}

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth_redirect.dart';
import '../../l10n/onespace_locale_controller.dart';
import '../../l10n/onespace_strings.dart';
import 'device_unlock.dart';
import 'password_recovery_screen.dart';
import 'remembered_accounts.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.signedIn});
  final Widget signedIn;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<AuthState>? _subscription;
  bool _recoveryInProgress = false;
  bool _checkingSavedSession = true;
  bool _sessionLocked = false;
  bool _authenticating = false;
  String? _unlockError;

  @override
  void initState() {
    super.initState();
    final auth = Supabase.instance.client.auth;
    if (auth.currentSession != null) {
      _checkSavedSession();
      _loadAccountLocale();
    } else {
      _checkingSavedSession = false;
    }
    _subscription = auth.onAuthStateChange.listen(
      (state) {
        if (!mounted) return;
        if (state.event == AuthChangeEvent.passwordRecovery) {
          setState(() {
            _recoveryInProgress = true;
            _sessionLocked = false;
            _checkingSavedSession = false;
          });
          return;
        }
        if (state.event == AuthChangeEvent.signedOut) {
          OneSpaceLocaleController.instance.selectLanguage(null);
          setState(() {
            _recoveryInProgress = false;
            _sessionLocked = false;
            _checkingSavedSession = false;
            _unlockError = null;
          });
          return;
        }
        if (state.event == AuthChangeEvent.signedIn) {
          setState(() {
            _checkingSavedSession = false;
            _sessionLocked = false;
            _unlockError = null;
          });
          _loadAccountLocale();
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('OneSpace auth state temporarily unavailable.');
      },
    );
  }

  Future<void> _checkSavedSession() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) setState(() => _checkingSavedSession = false);
      return;
    }
    final enabled = await DeviceUnlock.isEnabled(userId);
    if (!mounted) return;
    if (Supabase.instance.client.auth.currentUser?.id != userId) return;
    setState(() {
      _checkingSavedSession = false;
      _sessionLocked = enabled;
    });
  }

  Future<void> _loadAccountLocale() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('locale')
          .eq('id', userId)
          .single();
      if (Supabase.instance.client.auth.currentUser?.id == userId) {
        OneSpaceLocaleController.instance.selectLanguage(
          profile['locale'] as String?,
        );
      }
    } catch (_) {
      // Offline users can continue with the device's language.
    }
  }

  Future<void> _unlock() async {
    if (_authenticating) return;
    setState(() {
      _authenticating = true;
      _unlockError = null;
    });
    final granted = await DeviceUnlock.authenticate(
      reason: 'Unlock your saved OneSpace session',
    );
    if (!mounted) return;
    setState(() {
      _authenticating = false;
      _sessionLocked = !granted;
      _unlockError = granted ? null : 'Device unlock failed or was cancelled.';
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = Supabase.instance.client.auth.currentSession != null;
    if (_recoveryInProgress && signedIn) {
      return const ResetPasswordScreen();
    }
    if (!signedIn) return const SignInScreen();
    if (_checkingSavedSession) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_sessionLocked) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.fingerprint, size: 66, color: Color(0xFF167E81)),
                    const SizedBox(height: 16),
                    Text(tr(context, 'unlockOneSpace'),
                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(Supabase.instance.client.auth.currentUser?.email ?? ''),
                    const SizedBox(height: 20),
                    if (_unlockError != null)
                      Text(_unlockError!, style: const TextStyle(color: Colors.red)),
                    FilledButton.icon(
                      onPressed: _authenticating ? null : _unlock,
                      icon: const Icon(Icons.lock_open),
                      label: Text(tr(context, 'unlockButton')),
                    ),
                    TextButton(
                      onPressed: _authenticating
                          ? null
                          : () => Supabase.instance.client.auth.signOut(),
                      child: Text(tr(context, 'differentAccount')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    return widget.signedIn;
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
  final displayNameController = TextEditingController();
  bool registering = false;
  bool loading = false;
  bool hidePassword = true;
  bool awaitingConfirmation = false;
  bool showingRecoveryRequest = false;
  String? error;
  String? info;
  bool rememberEmail = false;
  List<String> rememberedEmails = const [];

  @override
  void initState() {
    super.initState();
    _restoreRemembered();
  }

  Future<void> _restoreRemembered() async {
    try {
      final emails = await RememberedAccounts.list();
      if (!mounted) return;
      setState(() {
        rememberedEmails = emails;
        if (emails.isNotEmpty && emailController.text.isEmpty) {
          emailController.text = emails.first;
          rememberEmail = true;
        }
      });
    } catch (_) {
      // Remembered emails are only a convenience; login works without them.
    }
  }

  Future<void> _forgetRemembered() async {
    await RememberedAccounts.forgetAll();
    if (!mounted) return;
    setState(() {
      rememberedEmails = const [];
      rememberEmail = false;
      emailController.clear();
    });
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    displayNameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!formKey.currentState!.validate()) return;
    setState(() {
      loading = true;
      error = null;
      info = null;
    });
    try {
      final auth = Supabase.instance.client.auth;
      final email = emailController.text.trim().toLowerCase();
      final password = passwordController.text;
      if (registering) {
        final result = await auth.signUp(
          email: email,
          password: password,
          data: {'display_name': displayNameController.text.trim()},
          emailRedirectTo: oneSpaceAuthRedirectTo,
        );
        if (mounted && result.session == null) {
          setState(() {
            awaitingConfirmation = true;
            info = 'Check your email to confirm your account, then sign in.';
          });
        }
      } else {
        await auth.signInWithPassword(email: email, password: password);
        if (rememberEmail) {
          await RememberedAccounts.remember(email);
        }
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _resendConfirmation() async {
    final email = emailController.text.trim().toLowerCase();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => error = 'Enter your email address first.');
      return;
    }
    setState(() {
      loading = true;
      error = null;
      info = null;
    });
    try {
      await Supabase.instance.client.auth.resend(
        type: OtpType.signup,
        email: email,
        emailRedirectTo: oneSpaceAuthRedirectTo,
      );
      if (mounted) {
        setState(() => info =
            'If your account is waiting for confirmation, another email was requested.');
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not request confirmation email.');
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (showingRecoveryRequest) {
      return ForgotPasswordScreen(
        initialEmail: emailController.text.trim(),
        onBack: () => setState(() => showingRecoveryRequest = false),
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
                const SizedBox(height: 20),
                const Icon(Icons.favorite_rounded, size: 64, color: Color(0xFF167E81)),
                const SizedBox(height: 12),
                const Text('OneSpace',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 34, fontWeight: FontWeight.bold)),
                Text(tr(context, 'tagline'),
                    textAlign: TextAlign.center),
                const SizedBox(height: 32),
                Text(registering ? tr(context, 'createAccount') : tr(context, 'welcome'),
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                const SizedBox(height: 18),
                if (!registering && rememberedEmails.isNotEmpty) ...[
                  Text(tr(context, 'recentAccounts')),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: rememberedEmails
                        .map((email) => ActionChip(
                              label: Text(email),
                              onPressed: loading
                                  ? null
                                  : () => setState(() {
                                        emailController.text = email;
                                        passwordController.clear();
                                        error = null;
                                      }),
                            ))
                        .toList(),
                  ),
                  TextButton(
                    onPressed: loading ? null : _forgetRemembered,
                    child: Text(tr(context, 'forgetEmails')),
                  ),
                  const SizedBox(height: 12),
                ],
                Form(
                  key: formKey,
                  child: Column(
                    children: [
                      if (registering) ...[
                        TextFormField(
                          controller: displayNameController,
                          maxLength: 80,
                          decoration: InputDecoration(
                            labelText: tr(context, 'yourName'),
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                                  ? 'Enter a display name'
                                  : null,
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextFormField(
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        decoration: InputDecoration(
                          labelText: tr(context, 'email'),
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) =>
                            value == null || !value.contains('@')
                                ? 'Enter a valid email'
                                : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: passwordController,
                        obscureText: hidePassword,
                        autofillHints: [registering
                            ? AutofillHints.newPassword
                            : AutofillHints.password],
                        decoration: InputDecoration(
                          labelText: tr(context, 'password'),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: hidePassword ? 'Show password' : 'Hide password',
                            icon: Icon(hidePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined),
                            onPressed: () =>
                                setState(() => hidePassword = !hidePassword),
                          ),
                        ),
                        validator: (value) => value == null || value.isEmpty
                            ? 'Enter your password'
                            : registering && value.length < 8
                                ? 'Use at least 8 characters'
                                : null,
                      ),
                    ],
                  ),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr(context, 'rememberEmail')),
                  subtitle: const Text('Passwords are never saved.'),
                  value: rememberEmail,
                  onChanged: loading
                      ? null
                      : (enabled) =>
                          setState(() => rememberEmail = enabled ?? false),
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(error!, style: const TextStyle(color: Colors.red)),
                ],
                if (info != null) ...[
                  const SizedBox(height: 12),
                  Text(info!, style: const TextStyle(color: Color(0xFF167E81))),
                ],
                if (awaitingConfirmation) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: loading ? null : _resendConfirmation,
                    child: const Text('Resend confirmation email'),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: loading ? null : _submit,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text(loading
                        ? tr(context, 'pleaseWait')
                        : registering ? tr(context, 'register') : tr(context, 'signIn')),
                  ),
                ),
                if (!registering)
                  TextButton(
                    onPressed: loading
                        ? null
                        : () => setState(() => showingRecoveryRequest = true),
                    child: Text(tr(context, 'forgotPassword')),
                  ),
                TextButton(
                  onPressed: loading
                      ? null
                      : () => setState(() {
                          registering = !registering;
                          awaitingConfirmation = false;
                          error = null;
                          info = null;
                        }),
                  child: Text(registering
                      ? tr(context, 'alreadyRegistered')
                      : tr(context, 'needAccount')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

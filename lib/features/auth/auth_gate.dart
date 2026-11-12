import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth_redirect.dart';
import 'password_recovery_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.signedIn});
  final Widget signedIn;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<AuthState>? _subscription;
  bool _recoveryInProgress = false;

  @override
  void initState() {
    super.initState();
    _subscription = Supabase.instance.client.auth.onAuthStateChange.listen(
      (state) {
        if (!mounted) return;
        setState(() {
          if (state.event == AuthChangeEvent.passwordRecovery) {
            _recoveryInProgress = true;
          } else if (state.event == AuthChangeEvent.signedOut) {
            _recoveryInProgress = false;
          }
        });
      },
      onError: (Object error, StackTrace stackTrace) {
        // Auth can emit transient network errors while offline. Ignore these
        // here and let the account screens show actionable request failures.
        debugPrint('OneSpace auth state temporarily unavailable.');
      },
    );
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
    return signedIn ? widget.signedIn : const SignInScreen();
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
                const Text('Two lives. One space.',
                    textAlign: TextAlign.center),
                const SizedBox(height: 32),
                Text(registering ? 'Create your account' : 'Welcome back',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                const SizedBox(height: 18),
                Form(
                  key: formKey,
                  child: Column(
                    children: [
                      if (registering) ...[
                        TextFormField(
                          controller: displayNameController,
                          maxLength: 80,
                          decoration: const InputDecoration(
                            labelText: 'Your display name',
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
                        decoration: const InputDecoration(
                          labelText: 'Email',
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
                          labelText: 'Password',
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
                        ? 'Please wait...'
                        : registering ? 'Create account' : 'Sign in'),
                  ),
                ),
                if (!registering)
                  TextButton(
                    onPressed: loading
                        ? null
                        : () => setState(() => showingRecoveryRequest = true),
                    child: const Text('Forgot password?'),
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
                      ? 'Already have an account? Sign in'
                      : 'New to OneSpace? Create an account'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

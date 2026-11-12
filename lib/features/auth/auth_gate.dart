import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.signedIn});
  final Widget signedIn;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<AuthState>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = Supabase.instance.client.auth.onAuthStateChange.listen(
      (_) {
        if (mounted) setState(() {});
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
        );
        if (mounted && result.session == null) {
          setState(() {
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

  @override
  Widget build(BuildContext context) {
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
                        validator: (value) =>
                            value == null || value.length < 6
                                ? 'Use at least 6 characters'
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
                TextButton(
                  onPressed: loading
                      ? null
                      : () => setState(() {
                          registering = !registering;
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

import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth_redirect.dart';
import 'package:onespace/l10n/phrases.dart';

/// Signed-out password recovery. Email delivery depends on Supabase Auth settings.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail = '', this.onBack});

  final String initialEmail;
  final VoidCallback? onBack;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final TextEditingController _email;
  bool _sending = false;
  bool _sent = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _email = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _requestReset() async {
    final email = _email.text.trim().toLowerCase();
    if (email.isEmpty || !email.contains('@') || email.endsWith('@')) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        email,
        redirectTo: oneSpaceAuthRedirectTo,
      );
      if (mounted) setState(() => _sent = true);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not request a reset email. Try again.');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tt('Password recovery'))),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: ListView(
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: [
                const Icon(
                  Icons.mark_email_read_outlined,
                  size: 54,
                  color: Color(0xFF167E81),
                ),
                const SizedBox(height: 18),
                Text(
                  tt(_sent ? 'Check your email' : 'Forgot your password?'),
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Text(tt(_sent
                    ? 'If that email address has an account, follow the '
                        'recovery link. Open the link on this Android device '
                        'to return to OneSpace.'
                    : 'We will send a recovery link to your account email.')),
                const SizedBox(height: 22),
                if (!_sent)
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: tt('Email address'),
                    ),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    tt(_error!),
                    style: const TextStyle(color: Colors.red),
                  ),
                ],
                const SizedBox(height: 18),
                if (!_sent)
                  FilledButton(
                    onPressed: _sending ? null : _requestReset,
                    child: Text(tt(_sending ? tt('Sending...') : tt('Send recovery link'))),
                  ),
                OutlinedButton(
                  onPressed: widget.onBack ?? () => Navigator.of(context).pop(),
                  child: Text(tt('Back to sign in')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Reached only after Supabase has authenticated a password-recovery link.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});
  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _updatePassword() async {
    final password = _password.text;
    if (password.length < 8) {
      setState(() => _error = 'Use at least 8 characters.');
      return;
    }
    if (password != _confirmation.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    var updated = false;
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: password),
      );
      updated = true;
      await Supabase.instance.client.auth.signOut();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tt('Password updated. Please sign in.'))),
      );
    } on AuthException catch (e) {
      if (mounted) {
        setState(() => _error = updated
            ? 'Password changed, but sign out failed. Please sign out manually.'
            : e.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = updated
            ? 'Password changed, but sign out failed. Please sign out manually.'
            : 'Unable to update password. Please retry.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    await Supabase.instance.client.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tt('Set a new password'))),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: ListView(
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: [
                Text(
                  tt('Secure your OneSpace account'),
                  style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Text(tt('Choose a new password to finish account recovery.')),
                const SizedBox(height: 24),
                TextField(
                  controller: _password,
                  obscureText: true,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: InputDecoration(
                    labelText: tt('New password (8+ characters)'),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _confirmation,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: tt('Confirm new password'),
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(tt(_error!), style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _updatePassword,
                  child: Text(tt(_busy ? tt('Updating...') : tt('Update password'))),
                ),
                TextButton(
                  onPressed: _busy ? null : _cancel,
                  child: Text(tt('Cancel recovery and sign out')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

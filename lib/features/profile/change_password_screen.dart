import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth_redirect.dart';
import 'package:onespace/l10n/phrases.dart';

/// A dedicated subpage. The system password manager may fill the current
/// password; OneSpace never reads credentials from the password manager.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});
  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _resetSent = false;
  bool _showPasswords = false;

  // Initial state and incomplete/repeated passwords must never submit.
  bool get _canUpdate {
    final oldValue = _current.text;
    final nextValue = _next.text;
    final confirmation = _confirm.text;
    return !_busy && oldValue.isNotEmpty && nextValue.length >= 8 &&
      nextValue != oldValue && confirmation == nextValue;
  }
  String? _error;
  final _auth = Supabase.instance.client.auth;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _update() async {
    if (_busy) return;
    if (!_canUpdate) {
      setState(() => _error = tt(
        'Enter your current password and a different new password '
        'of at least 8 characters, then confirm it.'));
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await _auth.updateUser(UserAttributes(
        currentPassword: _current.text,
        password: _next.text,
      ));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tt('Password updated.'))));
      Navigator.of(context).pop();
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = tt('Unable to change password. Try again.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    if (_busy || _resetSent) return;
    final email = _auth.currentUser?.email;
    if (email == null || email.isEmpty) {
      setState(() => _error = tt('Sign in to request a password reset.'));
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await _auth.resetPasswordForEmail(email, redirectTo: oneSpaceAuthRedirectTo);
      if (mounted) setState(() => _resetSent = true);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = tt('Unable to send the reset email.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    InputDecoration inputDecoration(String label) => InputDecoration(
      labelText: tt(label),
      border: const OutlineInputBorder(),
      suffixIcon: IconButton(
        tooltip: tt(_showPasswords ? 'Hide passwords' : 'Show passwords'),
        onPressed: () => setState(() => _showPasswords = !_showPasswords),
        icon: Icon(_showPasswords ? Icons.visibility_off_outlined
            : Icons.visibility_outlined),
      ),
    );
    return Scaffold(
      appBar: AppBar(title: Text(tt('Change password'))),
      body: SafeArea(child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          AutofillGroup(child: Column(children: [
            TextField(
              controller: _current,
              onChanged: (_) => setState(() => _error = null),
              obscureText: !_showPasswords,
              autofillHints: const [AutofillHints.password],
              textInputAction: TextInputAction.next,
              autocorrect: false,
              enableSuggestions: false,
              decoration: inputDecoration('Current password'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _next,
              onChanged: (_) => setState(() => _error = null),
              obscureText: !_showPasswords,
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.next,
              autocorrect: false,
              enableSuggestions: false,
              decoration: inputDecoration('New password (8+ characters)'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _confirm,
              onChanged: (_) => setState(() => _error = null),
              obscureText: !_showPasswords,
              textInputAction: TextInputAction.done,
              autocorrect: false,
              enableSuggestions: false,
              decoration: inputDecoration('Confirm new password'),
            ),
          ])),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: _busy || _resetSent ? null : _reset,
              child: Text(tt('Send a reset email')),
            ),
          ),
          if (_resetSent) Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(tt('Check your email for a password reset link.')),
          ),
          if (_error != null) Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: OutlinedButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(tt('Cancel')),
              ),
            )),
            const SizedBox(width: 12),
            Expanded(flex: 2, child: FilledButton(
              onPressed: _canUpdate ? _update : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(tt(_busy ? 'Updating...' : 'Update password'),
                  textAlign: TextAlign.center),
              ),
            )),
          ]),
        ],
      )),
    );
  }
}

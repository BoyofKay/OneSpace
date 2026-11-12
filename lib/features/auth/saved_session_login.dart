import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/onespace_strings.dart';
import 'auth_language_switcher.dart';
import 'device_unlock.dart';

/// One restored Supabase session: the user's password OR OS verification can
/// reopen it. No password, refresh token, or biometric template is saved here.
class SavedSessionLogin extends StatefulWidget {
  const SavedSessionLogin({
    super.key,
    required this.email,
    required this.onUnlocked,
    required this.onSwitchAccount,
  });
  final String email;
  final VoidCallback onUnlocked;
  final Future<void> Function() onSwitchAccount;

  @override
  State<SavedSessionLogin> createState() => _SavedSessionLoginState();
}

class _SavedSessionLoginState extends State<SavedSessionLogin> {
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _unlockWithDevice() async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    final available = await DeviceUnlock.isAvailable();
    if (!mounted) return;
    if (!available) {
      setState(() {
        _busy = false;
        _error = tr(context, 'phoneUnlockUnavailable');
      });
      return;
    }
    final granted = await DeviceUnlock.authenticate();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = granted ? null : tr(context, 'deviceUnlockFailed');
    });
    if (granted) widget.onUnlocked();
  }

  Future<void> _unlockWithPassword() async {
    if (_busy) return;
    if (_password.text.isEmpty) {
      setState(() => _error = tr(context, 'passwordRequired'));
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final result = await Supabase.instance.client.auth.signInWithPassword(
        email: widget.email,
        password: _password.text,
      );
      if (mounted && result.session != null) {
        TextInput.finishAutofillContext(shouldSave: true);
        widget.onUnlocked();
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = tr(context, 'loginFailed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              const AuthLanguageSwitcher(),
              const SizedBox(height: 18),
              const Icon(Icons.favorite_rounded,
                  color: Color(0xFF167E81), size: 54),
              const SizedBox(height: 10),
              const Text('OneSpace', textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text(tr(context, 'welcome'), style: const TextStyle(
                  fontSize: 23, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(tr(context, 'savedSessionHelp'),
                style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 12),
              AutofillGroup(
                child: Column(
                  children: [
                    TextFormField(
                initialValue: widget.email,
                readOnly: true,
                autofillHints: const [AutofillHints.username, AutofillHints.email],
                decoration: InputDecoration(
                  labelText: tr(context, 'email'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _password,
                      obscureText: _obscure,
                      autofillHints: const [AutofillHints.password],
                      decoration: InputDecoration(
                        labelText: tr(context, 'password'),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _obscure = !_obscure),
                          icon: Icon(_obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                        ),
                      ),
                      onSubmitted: (_) => _unlockWithPassword(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 56, height: 56,
                    child: OutlinedButton(
                      key: const Key('savedSessionFingerprint'),
                      onPressed: _busy ? null : _unlockWithDevice,
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Icon(Icons.fingerprint, size: 30),
                    ),
                  ),
                ],
              ),
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 8),
              Text(tr(context, 'pinOrBiometric'),
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 14),
              FilledButton(
                key: const Key('savedSessionSignIn'),
                onPressed: _busy ? null : _unlockWithPassword,
                child: Text(tr(context, 'savedSessionPasswordAction')),
              ),
              TextButton(
                onPressed: _busy ? null : widget.onSwitchAccount,
                child: Text(tr(context, 'switchAccount')),
              ),
              Text(tr(context, 'phoneUnlockNotSetupHint'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    ),
  );
}

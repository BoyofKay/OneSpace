import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/onespace_locale_controller.dart';
import '../../l10n/onespace_strings.dart';
import '../auth/device_unlock.dart';

/// Personal settings belong to an individual account, not to the shared space.
class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  final _client = Supabase.instance.client;
  final _name = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _deviceUnlockEnabled = false;
  bool _changingUnlock = false;
  String _language = 'en';
  String? _error;
  String? _status;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final id = _client.auth.currentUser!.id;
      final profile =
          await _client.from('profiles').select('display_name,locale').eq('id', id).single();
      final unlockEnabled = await DeviceUnlock.isEnabled(id);
      if (!mounted) return;
      setState(() {
        _name.text = (profile['display_name'] as String?) ?? '';
        _language = (profile['locale'] as String?) ?? 'en';
        _deviceUnlockEnabled = unlockEnabled;
      });
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Unable to load your settings.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty || name.length > 80) {
      setState(() => _error = 'Your display name must be 1–80 characters.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _status = null;
    });
    try {
      await _client.from('profiles').update({
        'display_name': name,
        'locale': _language,
      }).eq('id', _client.auth.currentUser!.id);
      OneSpaceLocaleController.instance.selectLanguage(_language);
      if (mounted) setState(() => _status = tr(context, 'profileSaved'));
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Unable to save your profile.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changePassword() async {
    final current = TextEditingController();
    final next = TextEditingController();
    final confirmation = TextEditingController();
    String? dialogError;
    bool busy = false;
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (dialogContext, updateDialog) => AlertDialog(
              title: Text(tr(context, 'changePassword')),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: current,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Current password'),
                    ),
                    TextField(
                      controller: next,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'New password (8+ characters)'),
                    ),
                    TextField(
                      controller: confirmation,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Confirm new password'),
                    ),
                    if (dialogError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(dialogError!,
                            style: const TextStyle(color: Colors.red)),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: busy ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: busy
                      ? null
                      : () async {
                          if (current.text.isEmpty ||
                              next.text.length < 8 ||
                              next.text != confirmation.text) {
                            updateDialog(() => dialogError =
                                'Check your current password, new password length and confirmation.');
                            return;
                          }
                          updateDialog(() {
                            busy = true;
                            dialogError = null;
                          });
                          try {
                            await _client.auth.updateUser(
                              UserAttributes(
                                currentPassword: current.text,
                                password: next.text,
                              ),
                            );
                            if (!dialogContext.mounted) return;
                            Navigator.pop(dialogContext);
                            if (mounted) {
                              setState(() => _status = 'Password updated.');
                            }
                          } on AuthException catch (e) {
                            if (dialogContext.mounted) {
                              updateDialog(() => dialogError = e.message);
                            }
                          } catch (_) {
                            if (dialogContext.mounted) {
                              updateDialog(() =>
                                  dialogError = 'Unable to change password.');
                            }
                          } finally {
                            if (dialogContext.mounted) {
                              updateDialog(() => busy = false);
                            }
                          }
                        },
                  child: const Text('Update'),
                ),
              ],
            ),
          );
        },
      );
    } finally {
      // The inputs are short-lived and are never stored in app state.
      current.dispose();
      next.dispose();
      confirmation.dispose();
    }
  }

  Future<void> _configureDeviceUnlock(bool enable) async {
    if (_changingUnlock) return;
    setState(() {
      _changingUnlock = true;
      _error = null;
      _status = null;
    });
    try {
      if (enable) {
        final available = await DeviceUnlock.isAvailable();
        if (!available) {
          throw StateError('Set a screen lock on your phone first.');
        }
        final permitted = await DeviceUnlock.authenticate(
          reason: 'Enable device unlock for this OneSpace account',
        );
        if (!permitted) {
          throw StateError('Device verification was cancelled or failed.');
        }
      }
      await DeviceUnlock.setEnabled(_client.auth.currentUser!.id, enable);
      if (mounted) {
        setState(() {
          _deviceUnlockEnabled = enable;
          _status = enable
              ? 'Device unlock enabled for this account.'
              : 'Device unlock disabled for this account.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is StateError
            ? e.message.toString()
            : 'Could not update your device unlock preference.');
      }
    } finally {
      if (mounted) setState(() => _changingUnlock = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(tr(context, 'yourAccount'),
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('Your profile belongs to you, independently of your partner.'),
        const SizedBox(height: 22),
        Text(_client.auth.currentUser?.email ?? 'Signed in'),
        const SizedBox(height: 18),
        TextField(
          controller: _name,
          maxLength: 80,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: tr(context, 'yourName'),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: _language,
          decoration: InputDecoration(
            labelText: tr(context, 'language'),
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'en', child: Text('English')),
            DropdownMenuItem(value: 'ar', child: Text('العربية (Arabic)')),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _language = value);
          },
        ),
        const SizedBox(height: 8),
        Text(
          'Language is saved per account. Arabic and RTL are enabled for '
          'the main interface; remaining screens are being translated.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          Text(_error!, style: const TextStyle(color: Colors.red)),
        ],
        if (_status != null) ...[
          const SizedBox(height: 14),
          Text(_status!, style: const TextStyle(color: Color(0xFF167E81))),
        ],
        const SizedBox(height: 22),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(tr(context, 'saveProfile')),
        ),
        const SizedBox(height: 22),
        const Divider(),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.fingerprint),
          title: Text(tr(context, 'enablePhoneUnlock')),
          subtitle: Text(tr(context, 'phoneUnlockHint')),
          value: _deviceUnlockEnabled,
          onChanged: _changingUnlock ? null : _configureDeviceUnlock,
        ),
        const SizedBox(height: 12),
        const Divider(),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.lock_outline),
          title: const Text('Change password'),
          subtitle: const Text('Update your own sign-in password'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _changePassword,
        ),
        const SizedBox(height: 18),
        const Divider(),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.photo_library_outlined),
          title: Text(tr(context, 'memoriesComingSoon')),
          subtitle: Text(tr(context, 'comingSoon')),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: () => _client.auth.signOut(),
          icon: const Icon(Icons.logout),
          label: Text(tr(context, 'signOut')),
        ),
      ],
    );
  }
}

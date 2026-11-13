import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/onespace_locale_controller.dart';
import '../../l10n/onespace_strings.dart';
import '../../core/performance_timings.dart';
import '../../core/device_time_zone.dart';
import '../../core/device_weather_service.dart';
import '../../core/shared_weather.dart';

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
  String _language = 'en';
  String? _timeZone;
  bool _shareCityWeather = false;
  bool _weatherBusy = false;
  String? _city;
  num? _temperature;
  int? _weatherCode;
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
          await _client.from('profiles').select('display_name,locale,time_zone,city_weather_shared,city_name,temperature_c,weather_code').eq('id', id).single();
      if (!mounted) return;
      setState(() {
        _name.text = (profile['display_name'] as String?) ?? '';
        _language = (profile['locale'] as String?) ?? 'en';
        _timeZone = profile['time_zone']?.toString();
        _shareCityWeather = profile['city_weather_shared'] == true;
        _city = profile['city_name']?.toString();
        _temperature = profile['temperature_c'] as num?;
        _weatherCode = (profile['weather_code'] as num?)?.toInt();
      });
      final zone = await DeviceTimeZone.sync(_client,storedZone:_timeZone);
      if (mounted && zone != null) setState(() => _timeZone = zone);
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Unable to load your settings.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleCityWeather(bool enabled) async {
    if (_weatherBusy) return;
    if (enabled) {
      final consent = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Share your city and weather?'),
          content: const Text(
            'When you open OneSpace, your phone can use approximate '
            'location to identify your city and fetch its weather. '
            'Only your city name, temperature, conditions and update time '
            'are shared with your partner. No GPS coordinates or street '
            'address are saved. Open-Meteo receives a rounded location '
            'for the weather request. You can turn this off any time.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx,false),
              child: const Text('Not now')),
            FilledButton(onPressed: () => Navigator.pop(ctx,true),
              child: const Text('Allow city and weather')),
          ],
        ),
      );
      if (consent != true || !mounted) return;
    }
    setState(() {
      _weatherBusy = true;
      _error = null;
      _status = null;
    });
    try {
      if (enabled) {
        final weather = await DeviceWeatherService.enable(_client);
        if (!mounted) return;
        setState(() {
          _shareCityWeather = true;
          _city = weather.city;
          _temperature = weather.temperatureC;
          _weatherCode = weather.code;
          _status = 'Your city and weather are shared with your partner.';
        });
      } else {
        await DeviceWeatherService.disable(_client);
        if (!mounted) return;
        setState(() {
          _shareCityWeather = false;
          _city = null;
          _temperature = null;
          _weatherCode = null;
          _status = 'City and weather sharing turned off and cleared.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = enabled
          ? 'Could not enable city/weather. Check location access '
            'and your network, then try again. $e'
          : 'Unable to stop sharing on the server. Check your connection '
            'and try again. $e');
      }
    } finally {
      if (mounted) setState(() => _weatherBusy = false);
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

  Future<void> _showPerformanceDiagnostics() async {
    // Measure an authenticated API request separately from Flutter rendering.
    // This query returns only the signed-in user's own membership ID, not
    // private user content; no identifiers are retained in the report.
    final id = _client.auth.currentUser?.id;
    if (id != null) {
      final sample = Stopwatch()..start();
      try {
        await _client.from('space_members').select('space_id')
            .eq('user_id',id).limit(1)
            .timeout(const Duration(seconds:12));
        PerformanceTimings.instance.record(
          'Seoul API round trip', sample.elapsed);
      } catch (_) {
        PerformanceTimings.instance.record(
          'API failed or timed out', sample.elapsed);
      }
    }
    if (!mounted) return;
    final report = PerformanceTimings.instance.report;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr(context, 'performanceDiagnostics')),
        content: SingleChildScrollView(
          child: SelectableText(report),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: report));
              Navigator.of(dialogContext).pop();
            },
            icon: const Icon(Icons.copy_outlined),
            label: Text(tr(context, 'copyDiagnostics')),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(tr(context, 'done')),
          ),
        ],
      ),
    );
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
        const SizedBox(height: 18),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.schedule_outlined),
          title: const Text('Time zone — automatic from this phone'),
          subtitle: Text(_timeZone ?? 'Using phone time; zone not synced yet'),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.cloud_outlined),
          title: const Text('Share my city and weather'),
          subtitle: const Text(
            'Optional. Approximate city only, when the app is open. '
            'No exact location or background tracking.'),
          value: _shareCityWeather,
          onChanged: _weatherBusy ? null : _toggleCityWeather,
        ),
        if (_weatherBusy) const LinearProgressIndicator(),
        if (_shareCityWeather)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 12),
            child: Text(
              '${_city ?? 'City unavailable'} · '
              '${_temperature?.toStringAsFixed(0) ?? '—'}°C · '
              '${_weatherCode == null ? 'Weather pending' :
                  SharedWeather.condition(_weatherCode!)}',
            ),
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
          leading: const Icon(Icons.speed_outlined),
          title: Text(tr(context, 'performanceDiagnostics')),
          subtitle: Text(tr(context, 'performanceDiagnosticsHint')),
          trailing: const Icon(Icons.chevron_right),
          onTap: _showPerformanceDiagnostics,
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

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/onespace_locale_controller.dart';
import '../../l10n/onespace_strings.dart';
import '../../core/performance_timings.dart';
import '../../core/device_time_zone.dart';
import '../../core/device_weather_service.dart';
import '../../core/shared_weather.dart';
import '../../core/weather_city_picker.dart';

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
  num? _high,_low,_rain;
  String? _error;
  String? _status;
  final _partnerLabel=TextEditingController();
  TimeOfDay? _workStart,_workEnd,_bedTime,_wakeTime;
  Set<int> _workDays={7,1,2,3,4};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _partnerLabel.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final id = _client.auth.currentUser!.id;
      final profile =
          await _client.from('profiles').select('display_name,locale,time_zone,city_weather_shared,city_name,temperature_c,weather_code,weather_high_c,weather_low_c,weather_rain_pct,partner_label,work_start_local,work_end_local,sleep_start_local,sleep_end_local,work_days').eq('id', id).single();
      if (!mounted) return;
      setState(() {
        _name.text = (profile['display_name'] as String?) ?? '';
        _partnerLabel.text=profile['partner_label']?.toString()??'';
        _workStart=_parseTime(profile['work_start_local']);
        _workEnd=_parseTime(profile['work_end_local']);
        _bedTime=_parseTime(profile['sleep_start_local']);
        _wakeTime=_parseTime(profile['sleep_end_local']);
        _workDays={for(final day in (profile['work_days'] as List<dynamic>? ?? const []) if(day is num) day.toInt()};
        _language = (profile['locale'] as String?) ?? 'en';
        _timeZone = profile['time_zone']?.toString();
        _shareCityWeather = profile['city_weather_shared'] == true;
        _city = profile['city_name']?.toString();
        _temperature = profile['temperature_c'] as num?;
        _weatherCode = (profile['weather_code'] as num?)?.toInt();
        _high=profile['weather_high_c'] as num?;
        _low=profile['weather_low_c'] as num?;
        _rain=profile['weather_rain_pct'] as num?;
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

  TimeOfDay? _parseTime(Object? value) {
    final parts=value?.toString().split(':');
    if(parts==null||parts.length<2)return null;
    final h=int.tryParse(parts[0]);
    final m=int.tryParse(parts[1]);
    if(h==null||m==null)return null;
    return TimeOfDay(hour:h,minute:m);
  }
  String? _formatTime(TimeOfDay? t) {
    if(t==null)return null;
    final h=t.hour.toString().padLeft(2,'0');
    final m=t.minute.toString().padLeft(2,'0');
    return '$h:$m:00';
  }
  Future<void> _chooseTime(String kind) async {
    final chosen=await showTimePicker(context:context,
      initialTime:const TimeOfDay(hour:9,minute:0));
    if(chosen==null||!mounted)return;
    setState((){
      if(kind=='start'){_workStart=chosen;}
      else if(kind=='end'){_workEnd=chosen;}
      else if(kind=='bed'){_bedTime=chosen;}
      else {_wakeTime=chosen;}
    });
  }
  Widget _timeRow(String label,String kind,TimeOfDay? value)=>
    ListTile(
      contentPadding:EdgeInsets.zero,
      title:Text(label),
      trailing:Text(value?.format(context)??'Not set'),
      onTap:()=>_chooseTime(kind),
    );

  Future<void> _chooseWeatherCity() async {
    final selected=await showModalBottomSheet<WeatherCity>(
      context:context,isScrollControlled:true,showDragHandle:true,
      builder:(_)=>const WeatherCityPicker(),
    );
    if(selected==null||!mounted)return;
    setState((){_weatherBusy=true;_error=null;_status=null;});
    try{
      final weather=await DeviceWeatherService.selectCity(_client,selected);
      if(!mounted)return;
      setState((){
        _city=selected.label;
        _shareCityWeather=true;
        _temperature=weather.current.temperatureC;
        _weatherCode=weather.current.code;
        _high=weather.high;_low=weather.low;_rain=weather.rainPct;
        _status='Monitoring ${selected.label}. Shared with your partner.';
      });
    }catch(_){
      if(mounted){setState(()=>_error='Unable to save this city or load its '
        'weather. Please retry.');}
    }finally{
      if(mounted)setState(()=>_weatherBusy=false);
    }
  }

  Future<void> _stopWeatherSharing() async {
    if(_weatherBusy)return;
    setState((){_weatherBusy=true;_error=null;_status=null;});
    try{
      await DeviceWeatherService.disable(_client);
      if(mounted){setState((){
        _shareCityWeather=false;
        _city=null;
        _temperature=null;_weatherCode=null;_high=null;_low=null;_rain=null;
        _status='Weather sharing stopped and saved city cleared.';
      });}
    }catch(_){
      if(mounted)setState(()=>_error='Could not stop sharing. Try again.');
    }finally{
      if(mounted)setState(()=>_weatherBusy=false);
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
        'partner_label':_partnerLabel.text.trim().isEmpty?null:_partnerLabel.text.trim(),
        'work_start_local':_formatTime(_workStart),
        'work_end_local':_formatTime(_workEnd),
        'sleep_start_local':_formatTime(_bedTime),
        'sleep_end_local':_formatTime(_wakeTime),
        'work_days':_workDays.toList()..sort(),
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
        const SizedBox(height:12),
        TextField(
          controller:_partnerLabel,maxLength:60,
          decoration:const InputDecoration(
            labelText:'Preferred name for partner',
            border:OutlineInputBorder(),
          ),
        ),
        Text('Your daily schedule',
          style:Theme.of(context).textTheme.titleMedium),
        Text('Working days',style:Theme.of(context).textTheme.labelLarge),
        Wrap(spacing:7,runSpacing:4,children:[
          for(var i=0;i<7;i++)
            ChoiceChip(
              label:Text(const ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'][i]),
              selected:_workDays.contains(i==0?7:i),
              onSelected:(value)=>setState((){
                final day=i==0?7:i;
                if(value){_workDays.add(day);}
                else {_workDays.remove(day);}
              }),
            ),
        ]),
        const SizedBox(height:9),
        _timeRow('Work starts','start',_workStart),
        _timeRow('Work ends','end',_workEnd),
        _timeRow('Bedtime','bed',_bedTime),
        _timeRow('Wake-up','wake',_wakeTime),
        const Text('Quiet hours and scheduled messages will use these preferences in a later release.'),
        const SizedBox(height: 18),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.schedule_outlined),
          title: const Text('Time zone — automatic from this phone'),
          subtitle: Text(_timeZone ?? 'Using phone time; zone not synced yet'),
        ),
        const SizedBox(height: 8),
        Card(elevation:0,child:Padding(
          padding:const EdgeInsets.all(12),
          child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text('Weather city',style:Theme.of(context).textTheme.titleMedium),
            const SizedBox(height:5),
            Text(_city==null?'No city selected yet':_city!),
            const SizedBox(height:8),
            if(_shareCityWeather)
              Text('${_temperature?.toStringAsFixed(0)??'—'}°C · '
                '${_weatherCode==null?'Weather unavailable':
                  SharedWeather.condition(_weatherCode!)}'
                '\nHigh ${_high?.toStringAsFixed(0)??'—'}° · '
                'Low ${_low?.toStringAsFixed(0)??'—'}° · '
                'Rain ${_rain?.toStringAsFixed(0)??'—'}%',
              ),
            const SizedBox(height:8),
            Wrap(spacing:8,runSpacing:6,children:[
              FilledButton.icon(
                onPressed:_weatherBusy?null:_chooseWeatherCity,
                icon:const Icon(Icons.search),
                label:Text(_city==null?'Choose a city':'Change city'),
              ),
              if(_shareCityWeather)
                OutlinedButton.icon(
                  onPressed:_weatherBusy?null:_stopWeatherSharing,
                  icon:const Icon(Icons.visibility_off_outlined),
                  label:const Text('Stop monitoring'),
                ),
            ]),
            if(_weatherBusy)const LinearProgressIndicator(),
            const SizedBox(height:8),
            Text('Your phone\'s GPS is not used. You choose the city '
              'to monitor and share with your partner.',
              style:Theme.of(context).textTheme.bodySmall),
          ]),
        )),
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

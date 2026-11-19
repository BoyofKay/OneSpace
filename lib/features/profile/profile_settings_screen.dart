import 'package:material_ui/material_ui.dart';
import '../../core/auth_redirect.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/onespace_locale_controller.dart';
import '../../core/preferred_currency.dart';
import '../../l10n/onespace_strings.dart';
import '../../core/device_time_zone.dart';
import '../../core/device_weather_service.dart';
import '../../core/shared_weather.dart';
import '../../core/weather_city_picker.dart';
import 'package:onespace/l10n/phrases.dart';

/// Personal settings belong to an individual account, not to the shared space.
class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({super.key,this.settingsOnly=false,
    this.section='labels'});
  final bool settingsOnly;
  final String section;

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  final _client = Supabase.instance.client;
  final _name = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String _language = 'en';
  String _currency = 'SAR';
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
  final _labelEntry=TextEditingController();
  List<String> _partnerLabels=[];
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
    _labelEntry.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final id = _client.auth.currentUser!.id;
      final profile =
          await _client.from('profiles').select('display_name,locale,preferred_currency,time_zone,city_weather_shared,city_name,temperature_c,weather_code,weather_high_c,weather_low_c,weather_rain_pct,partner_label,partner_labels,work_start_local,work_end_local,sleep_start_local,sleep_end_local,work_days').eq('id', id).single();
      if (!mounted) return;
      setState(() {
        _name.text = (profile['display_name'] as String?) ?? '';
        _partnerLabel.text=profile['partner_label']?.toString()??'';
        _partnerLabels=[for(final item in (profile['partner_labels'] as List<dynamic>? ??const [])) item.toString()];
        _workStart=_parseTime(profile['work_start_local']);
        _workEnd=_parseTime(profile['work_end_local']);
        _bedTime=_parseTime(profile['sleep_start_local']);
        _wakeTime=_parseTime(profile['sleep_end_local']);
        _workDays={for(final day in (profile['work_days'] as List<dynamic>? ?? const [])) if(day is num) day.toInt()};
        _language = (profile['locale'] as String?) ?? 'en';
        _currency = (profile['preferred_currency'] as String?) ?? PreferredCurrency.code;
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
      title:Text(tt(label)),
      trailing:Text(tt(value?.format(context)??'Not set')),
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
      if(mounted){setState(()=>_error=tt('Unable to save this city or load its '
        'weather. Please retry.'));}
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
    if (!widget.settingsOnly && (name.isEmpty || name.length > 80)) {
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
        if(!widget.settingsOnly)'display_name': name,
        'locale': _language,
        if(widget.section=='language')'preferred_currency': _currency,
        'partner_label':_partnerLabel.text.trim().isEmpty?null:_partnerLabel.text.trim(),
        'partner_labels':_partnerLabels,
        'work_start_local':_formatTime(_workStart),
        'work_end_local':_formatTime(_workEnd),
        'sleep_start_local':_formatTime(_bedTime),
        'sleep_end_local':_formatTime(_wakeTime),
        'work_days':_workDays.toList()..sort(),
      }).eq('id', _client.auth.currentUser!.id);
      OneSpaceLocaleController.instance.selectLanguage(_language);
      if(widget.section=='language')await PreferredCurrency.save(_currency);
      if (mounted) setState(() => _status = tr(context, 'profileSaved'));
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Unable to save your profile.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Never retrieve or persist the current password in OneSpace storage.
  /// The OS password manager owns autofill; Supabase owns verification/reset.
  Future<void> _changePassword() async {
    final email = _client.auth.currentUser?.email;
    final account = TextEditingController(text: email ?? '');
    final current = TextEditingController();
    final next = TextEditingController();
    final confirmation = TextEditingController();
    String? dialogError;
    bool busy = false;
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, updateDialog) => AlertDialog(
            title: Text(tr(context, 'changePassword')),
            content: SingleChildScrollView(
              child: AutofillGroup(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tt('Google Password Manager or your phone password manager can fill the current password when you tap the field. OneSpace cannot view your saved passwords.'),
                      style: Theme.of(dialogContext).textTheme.bodySmall),
                    const SizedBox(height: 12),
                    // A username in the same autofill group helps the system
                    // match a credential to this account, without reading it.
                    TextField(
                      controller: account,
                      readOnly: true,
                      autofillHints: const [AutofillHints.username, AutofillHints.email],
                      decoration: InputDecoration(
                        labelText: tt('Account email'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: current,
                      obscureText: true,
                      enableSuggestions: false,
                      autocorrect: false,
                      autofillHints: const [AutofillHints.password],
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: tt('Current password'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        icon: const Icon(Icons.mark_email_unread_outlined, size: 18),
                        label: Text(tt('Forgot current password? Send a reset email')),
                        onPressed: busy || email == null
                          ? null
                          : () async {
                              updateDialog(() { busy = true; dialogError = null; });
                              // The verified link opens a separate reset flow.
                              // Close this dialog now so it cannot cover the
                              // reset screen when the user returns from email.
                              var requestAccepted = false;
                              try {
                                await _client.auth.resetPasswordForEmail(
                                  email, redirectTo: oneSpaceAuthRedirectTo);
                                requestAccepted = true;
                                if (dialogContext.mounted) {
                                  Navigator.of(dialogContext).pop();
                                }
                                if (mounted) {
                                  const message =
                                    'Check your email for the OneSpace reset link. Your current password will keep working until you successfully set a new one.';
                                  setState(() => _status = message);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(tt(message))));
                                }
                              } on AuthException catch (error) {
                                if (dialogContext.mounted) {
                                  updateDialog(() => dialogError = error.message);
                                }
                              } catch (_) {
                                if (dialogContext.mounted) {
                                  updateDialog(() => dialogError =
                                    'Could not send a reset email. Please retry.');
                                }
                              } finally {
                                if (!requestAccepted && dialogContext.mounted) {
                                  updateDialog(() => busy = false);
                                }
                              }
                            },
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: next,
                      obscureText: true,
                      enableSuggestions: false,
                      autocorrect: false,
                      autofillHints: const [AutofillHints.newPassword],
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: tt('New password (8+ characters)'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: confirmation,
                      obscureText: true,
                      enableSuggestions: false,
                      autocorrect: false,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        labelText: tt('Confirm new password'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    if (dialogError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(tt(dialogError!),
                          style: TextStyle(color: Theme.of(dialogContext).colorScheme.error)),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(dialogContext),
                child: Text(tt('Cancel')),
              ),
              FilledButton(
                onPressed: busy ? null : () async {
                  if (current.text.isEmpty ||
                      next.text.length < 8 ||
                      next.text != confirmation.text) {
                    updateDialog(() => dialogError =
                      'Check your current password, new password length and confirmation.');
                    return;
                  }
                  updateDialog(() { busy = true; dialogError = null; });
                  try {
                    await _client.auth.updateUser(UserAttributes(
                      currentPassword: current.text,
                      password: next.text,
                    ));
                    if (!dialogContext.mounted) return;
                    Navigator.pop(dialogContext);
                    if (mounted) setState(() => _status = 'Password updated.');
                  } on AuthException catch (error) {
                    if (dialogContext.mounted) {
                      updateDialog(() => dialogError = error.message);
                    }
                  } catch (_) {
                    if (dialogContext.mounted) {
                      updateDialog(() => dialogError =
                        'Unable to change password.');
                    }
                  } finally {
                    if (dialogContext.mounted) updateDialog(() => busy = false);
                  }
                },
                child: Text(tt(busy ? 'Updating...' : 'Update password')),
              ),
            ],
          ),
        ),
      );
    } finally {
      // Short-lived controllers; no credentials written to app preferences.
      account.dispose();
      current.dispose();
      next.dispose();
      confirmation.dispose();
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
        if(!widget.settingsOnly)...[
          Text(tt('My profile'),style:Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height:8),
          Text(tt(_client.auth.currentUser?.email??'Signed in')),
          const SizedBox(height:16),
          TextField(controller:_name,maxLength:80,
            textCapitalization:TextCapitalization.words,
            decoration:InputDecoration(labelText:tr(context,'yourName'),
              border:const OutlineInputBorder())),
          const SizedBox(height:10),
        ],
        if(widget.settingsOnly)...[
          Text(tt(widget.section=='labels'?'Preferred names':
            widget.section=='schedule'?'Schedule & days off':
            widget.section=='language'?'Language and currency':'Weather city'),
            style:Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height:6),
          Text(tt('These settings belong to your account. '
            'Your partner can choose different preferences.')),
          const SizedBox(height:16),
        if(widget.section=='language')...[
        DropdownButtonFormField<String>(
          initialValue: _language,
          decoration: InputDecoration(
            labelText: tr(context, 'language'),
            border: OutlineInputBorder(),
          ),
          items: [
            DropdownMenuItem(value: 'en', child: Text(tt('English'))),
            DropdownMenuItem(value: 'ar', child: Text(tt('العربية (Arabic)'))),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _language = value);
          },
        ),
        const SizedBox(height:16),
        // R69: the currency every money field starts with.
        DropdownButtonFormField<String>(
          key: ValueKey('currency-$_currency'),
          initialValue: PreferredCurrency.choices.containsKey(_currency) ? _currency : null,
          isExpanded: true,
          decoration: InputDecoration(labelText: tt('Preferred currency'),
            prefixIcon: const Icon(Icons.payments_outlined),
            helperText: tt('Budgets, prices and costs start with this currency.'),
            border: const OutlineInputBorder()),
          items: [for (final e in PreferredCurrency.choices.entries)
            DropdownMenuItem(value: e.key, child: Text(tt(e.value)))],
          onChanged: (value) { if (value != null) setState(() => _currency = value); },
        ),
        const SizedBox(height:12),
        ],
        if(widget.section=='labels')...[
        TextField(
          controller:_partnerLabel,maxLength:60,
          decoration:InputDecoration(
            labelText:tt('Preferred name for partner'),
            border:OutlineInputBorder(),
          ),
        ),
        Text(tt('Personal names for your partner'),
          style:Theme.of(context).textTheme.titleSmall),
        Text(tt('OneSpace can vary these affectionate names when greeting you.'),
          style:Theme.of(context).textTheme.bodySmall),
        Wrap(spacing:6,runSpacing:4,children:[
          for(final label in _partnerLabels)
            InputChip(label:Text(tt(label)),onDeleted:()=>setState(()=>
              _partnerLabels.remove(label))),
        ]),
        Row(children:[
          Expanded(child:TextField(
            controller:_labelEntry,maxLength:60,
            decoration:InputDecoration(
              hintText:tt('e.g. My sunshine'),counterText:''))),
          IconButton(
            icon:const Icon(Icons.add_circle_outline),
            tooltip:tt('Add a preferred name'),
            onPressed:(){
              final value=_labelEntry.text.trim();
              if(value.isEmpty||_partnerLabels.length>=15)return;
              if(!_partnerLabels.any((v)=>v.toLowerCase()==value.toLowerCase())){
                setState(()=>_partnerLabels.add(value));
              }
              _labelEntry.clear();
            },
          ),
        ]),
        const SizedBox(height:12),
        ],
        if(widget.section=='schedule')...[
        Text(tt('Your daily schedule'),
          style:Theme.of(context).textTheme.titleMedium),
        Text(tt('Working days'),style:Theme.of(context).textTheme.labelLarge),
        Wrap(spacing:7,runSpacing:4,children:[
          for(var i=0;i<7;i++)
            ChoiceChip(
              label:Text(tt(const ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'][i])),
              selected:_workDays.contains(i==0?7:i),
              onSelected:(value)=>setState((){
                final day=i==0?7:i;
                if(value){_workDays.add(day);}
                else {_workDays.remove(day);}
              }),
            ),
        ]),
        const SizedBox(height:9),
        _timeRow(tt('Work starts'),'start',_workStart),
        _timeRow(tt('Work ends'),'end',_workEnd),
        _timeRow(tt('Bedtime'),'bed',_bedTime),
        _timeRow(tt('Wake-up'),'wake',_wakeTime),
        const SizedBox(height: 18),
        ],
        if(widget.section=='weather')...[
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.schedule_outlined),
          title: Text(tt('Time zone — automatic from this phone')),
          subtitle: Text(tt(_timeZone ?? 'Using phone time; zone not synced yet')),
        ),
        const SizedBox(height: 8),
        Card(elevation:0,child:Padding(
          padding:const EdgeInsets.all(12),
          child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(tt('Weather city'),style:Theme.of(context).textTheme.titleMedium),
            const SizedBox(height:5),
            Text(tt(_city==null?'No city selected yet':_city!)),
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
                label:Text(tt(_city==null?tt('Choose a city'):tt('Change city'))),
              ),
              if(_shareCityWeather)
                OutlinedButton.icon(
                  onPressed:_weatherBusy?null:_stopWeatherSharing,
                  icon:const Icon(Icons.visibility_off_outlined),
                  label:Text(tt('Stop monitoring')),
                ),
            ]),
            if(_weatherBusy)const LinearProgressIndicator(),
            const SizedBox(height:8),
            Text(tt('Your phone\'s GPS is not used. You choose the city '
              'to monitor and share with your partner.'),
              style:Theme.of(context).textTheme.bodySmall),
          ]),
        )),
        ], // end weather fields
        ], // end preferences-only fields
        if (_error != null) ...[
          const SizedBox(height: 14),
          Text(tt(_error!), style: const TextStyle(color: Colors.red)),
        ],
        if (_status != null) ...[
          const SizedBox(height: 14),
          Text(tt(_status!), style: const TextStyle(color: Color(0xFF167E81))),
        ],
        const SizedBox(height: 22),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(tr(context, 'saveProfile')),
        ),
        if(!widget.settingsOnly)...[
        const SizedBox(height: 22),
        const Divider(),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.lock_outline),
          title: Text(tt('Change password')),
          subtitle: Text(tt('Update your own sign-in password')),
          trailing: const Icon(Icons.chevron_right),
          onTap: _changePassword,
        ),
        ],
      ],
    );
  }
}

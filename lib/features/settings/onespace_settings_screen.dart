import 'package:material_ui/material_ui.dart';
import '../profile/profile_settings_screen.dart';
import '../connect/partner_gestures_screen.dart';
import '../../core/current_space_cache.dart';
import '../hubs/section_hubs.dart';
import 'personal_days_off_screen.dart';
import '../../l10n/onespace_strings.dart';
import '../../theme/appearance_settings_screen.dart';
import '../../core/weather_unit_preference.dart';
import '../calendar/holiday_sources_panel.dart';
import '../../core/app_env.dart';
import '../calendar/account_holiday_countries.dart';
import 'special_dates.dart';
import '../../core/phone_calendar_sync.dart';
import 'package:onespace/l10n/phrases.dart';
import '../../core/usage_events.dart';

/// Central configuration hub, distinct from personal profile details.
class OneSpaceSettingsScreen extends StatelessWidget {
 const OneSpaceSettingsScreen({super.key});

 void _open(BuildContext context,String title,Widget child){
   Navigator.of(context).push<void>(MaterialPageRoute<void>(
     builder:(_)=>Scaffold(
       appBar:AppBar(title:Text(tt(title))),
       body:SafeArea(child:child),
     ),
   ));
 }

 @override Widget build(BuildContext context)=>Scaffold(
   appBar:AppBar(title:Text(tt('Settings'))),
   body:SafeArea(child:ListView(
     padding:const EdgeInsets.all(16),
     children:[
       Text(tt('Our relationship'),
         style:Theme.of(context).textTheme.titleMedium),
       Card(elevation:0,child:ListTile(
         leading:const Icon(Icons.favorite_border),
         title:Text(tt('Living arrangement & meeting dates')),
         subtitle:Text(tt('Together or apart, last visit, next reunion')),
         trailing:const Icon(Icons.chevron_right),
         onTap:()=>_open(context,'Our relationship',
           const SingleChildScrollView(child:RelationshipSettings())),
       )),
       const SizedBox(height:16),
       Text(tt('My preferences'),style:Theme.of(context).textTheme.titleMedium),
       Card(elevation:0,child:ListTile(
        leading:const Icon(Icons.palette_outlined),
        title:Text(tr(context,'themeSettings')),
        subtitle:Text(tt('Four colors · Light, dark or follow phone · Holidays')),
        trailing:const Icon(Icons.chevron_right),
        onTap:()=>Navigator.of(context).push<void>(MaterialPageRoute<void>(
          builder:(_)=>const AppearanceSettingsScreen())),
       )),
       Card(elevation:0,child:Column(children:[
         ListTile(
           leading:const Icon(Icons.badge_outlined),
           title:Text(tt('Preferred names & labels')),
           subtitle:Text(tt('Manage the names used for your partner')),
           trailing:const Icon(Icons.chevron_right),
           onTap:()=>_open(context,'Personalization',
             const ProfileSettingsScreen(settingsOnly:true,section:'labels')),
         ),
         const Divider(height:1),
         ListTile(
           leading:const Icon(Icons.access_time_outlined),
           title:Text(tt('Working hours & sleep')),
           subtitle:Text(tt('Set days, hours and quiet-time preferences')),
           trailing:const Icon(Icons.chevron_right),
           onTap:()=>_open(context,'Daily schedule',
             const ProfileSettingsScreen(settingsOnly:true,section:'schedule')),
         ),
         const Divider(height:1),
         ListTile(
           leading:const Icon(Icons.event_available_outlined),
           title:Text(tt('Days off & sleep exceptions')),
           subtitle:Text(tt('Share days off on our calendar; adjust bedtime and wake-up')),
           trailing:const Icon(Icons.chevron_right),
           onTap:()=>Navigator.of(context).push<void>(
             MaterialPageRoute<void>(
               builder:(_)=>const PersonalDaysOffScreen())),
         ),
         const Divider(height:1),
         ListTile(
          leading:const Icon(Icons.public_outlined),
          title:Text(tt('Regional holidays')),
          subtitle:Text(tt('Choose the countries whose holidays you see')),
          trailing:const Icon(Icons.chevron_right),
          onTap:()=>Navigator.of(context).push(MaterialPageRoute<void>(
           builder:(_)=>const _HolidayPreferencesScreen())),
         ),
         const Divider(height:1),
         ListTile(
          leading:const Icon(Icons.celebration_outlined),
          title:Text(tt('Birthdays, anniversary & special dates')),
          subtitle:Text(tt('Your birthday, your partner\'s, your anniversary and your own dates')),
          trailing:const Icon(Icons.chevron_right),
          onTap:()=>Navigator.of(context).push(MaterialPageRoute<void>(
           builder:(_)=>const SpecialDatesScreen())),
         ),
         const Divider(height:1),
         // R74: one-way export to the phone's calendar app.
         ListTile(
          leading:const Icon(Icons.event_available_outlined),
          title:Text(tt('Show in my phone calendar')),
          subtitle:Text(tt('Events, trips and special dates in Google, Samsung or iPhone calendar')),
          trailing:const Icon(Icons.chevron_right),
          onTap:()=>Navigator.of(context).push(MaterialPageRoute<void>(
           builder:(_)=>const PhoneCalendarSettingsScreen())),
         ),
         const Divider(height:1),
         _WeatherUnitsTile(),
         const Divider(height:1),
         ListTile(
           leading:const Icon(Icons.cloud_outlined),
           title:Text(tt('Weather city')),
           subtitle:Text(tt('Choose your city; use the phone time zone automatically')),
           trailing:const Icon(Icons.chevron_right),
           onTap:()=>_open(context,'Weather city',
             const ProfileSettingsScreen(settingsOnly:true,section:'weather')),
         ),
       ])),
       const SizedBox(height:16),
       Text(tt('Affection & notifications'),
         style:Theme.of(context).textTheme.titleMedium),
       Card(elevation:0,child:Column(children:[
         ListTile(
           leading:const Icon(Icons.volunteer_activism_outlined),
           title:Text(tt('My love gestures')),
           subtitle:Text(tt('Manage my gesture types and messages')),
           trailing:const Icon(Icons.chevron_right),
           onTap:()=>Navigator.of(context).push<void>(
             MaterialPageRoute<void>(
               builder:(_)=>const PartnerGesturesScreen(manageOnly:true))),
         ),
       ])),
       const SizedBox(height:16),
       Text(tt('Privacy'),style:Theme.of(context).textTheme.titleMedium),
       // D78: usage statistics — event names and times only, never content.
       Card(elevation:0,child:ValueListenableBuilder<bool>(
         valueListenable:UsageEvents.instance.enabled,
         builder:(context,on,_)=>SwitchListTile(
           secondary:const Icon(Icons.insights_outlined),
           title:Text(tt('Share usage statistics')),
           subtitle:Text(tt('Which tabs you open, how long the app is open and notification taps. Never your content.')),
           value:on,
           onChanged:(v)=>UsageEvents.instance.setEnabled(v),
         ),
       )),
     ],
   )),
 );
}


class _WeatherUnitsTile extends StatelessWidget{
 @override Widget build(BuildContext context)=>AnimatedBuilder(
  animation:WeatherUnitPreference.instance,builder:(context,_){
   final prefs=WeatherUnitPreference.instance;
   return ListTile(
    leading:const Icon(Icons.thermostat_outlined),
    title:Text(tt('Weather temperature')),
    subtitle:Text(tt(prefs.fahrenheit?tt('US · Fahrenheit (°F)'):tt('Metric · Celsius (°C)'))),
    trailing:PopupMenuButton<bool>(
     tooltip:tt('Change temperature unit'),
     onSelected:(v)=>prefs.setFahrenheit(v),
     itemBuilder:(_)=>[
      PopupMenuItem(value:false,child:Text(tt('Metric · °C'))),
      PopupMenuItem(value:true,child:Text(tt('US · °F'))),
     ]),
   );
  });
}
class _HolidayPreferencesScreen extends StatefulWidget{
 const _HolidayPreferencesScreen();
 @override State<_HolidayPreferencesScreen> createState()=>_HolidayPreferencesScreenState();
}
class _HolidayPreferencesScreenState extends State<_HolidayPreferencesScreen>{
 String? space;
 bool loading=true;
 @override void initState(){super.initState();_load();}
 Future<void> _load()async{
  final id=await CurrentSpaceCache.instance.get();
  if(mounted)setState((){space=id;loading=false;});
 }
 @override Widget build(BuildContext context)=>Scaffold(
  appBar:AppBar(title:Text(tt('Regional holidays'))),
  body:SafeArea(child:ListView(padding:const EdgeInsets.all(18),children:[
   if(!OneSpaceEnv.usesLegacyBackend)const AccountHolidayCountriesPanel()
   else ...[
   Text(tt('Choose the countries in our shared calendar.')),
   const SizedBox(height:12),
   if(loading)const LinearProgressIndicator()
   else if(space==null)Text(tt('Connect your shared space first.'))
   else HolidaySourcesPanel(spaceId:space!,onChanged:(){}),
   ],
  ])));
}

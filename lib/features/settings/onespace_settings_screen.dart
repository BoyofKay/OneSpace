import 'package:material_ui/material_ui.dart';
import '../profile/profile_settings_screen.dart';
import '../connect/partner_gestures_screen.dart';
import '../connect/scheduled_gestures_panel.dart';
import '../../core/current_space_cache.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../hubs/section_hubs.dart';
import 'personal_days_off_screen.dart';
import '../../l10n/onespace_strings.dart';
import '../../theme/appearance_settings_screen.dart';
import '../../core/weather_unit_preference.dart';
import '../calendar/holiday_sources_panel.dart';
import '../occasions/occasions_screen.dart';

/// Central configuration hub, distinct from personal profile details.
class OneSpaceSettingsScreen extends StatelessWidget {
 const OneSpaceSettingsScreen({super.key});

 void _open(BuildContext context,String title,Widget child){
   Navigator.of(context).push<void>(MaterialPageRoute<void>(
     builder:(_)=>Scaffold(
       appBar:AppBar(title:Text(title)),
       body:SafeArea(child:child),
     ),
   ));
 }

 @override Widget build(BuildContext context)=>Scaffold(
   appBar:AppBar(title:const Text('Settings')),
   body:SafeArea(child:ListView(
     padding:const EdgeInsets.all(16),
     children:[
       Text('Our relationship',
         style:Theme.of(context).textTheme.titleMedium),
       Card(elevation:0,child:ListTile(
         leading:const Icon(Icons.favorite_border),
         title:const Text('Living arrangement & meeting dates'),
         subtitle:const Text('Together or apart, last visit, next reunion'),
         trailing:const Icon(Icons.chevron_right),
         onTap:()=>_open(context,'Our relationship',
           const SingleChildScrollView(child:RelationshipSettings())),
       )),
       const SizedBox(height:16),
       Text('My preferences',style:Theme.of(context).textTheme.titleMedium),
       Card(elevation:0,child:ListTile(
        leading:const Icon(Icons.palette_outlined),
        title:Text(tr(context,'themeSettings')),
        subtitle:const Text('Four colors · Light, dark or follow phone · Holidays'),
        trailing:const Icon(Icons.chevron_right),
        onTap:()=>Navigator.of(context).push<void>(MaterialPageRoute<void>(
          builder:(_)=>const AppearanceSettingsScreen())),
       )),
       Card(elevation:0,child:Column(children:[
         ListTile(
           leading:const Icon(Icons.badge_outlined),
           title:const Text('Preferred names & labels'),
           subtitle:const Text('Manage the names used for your partner'),
           trailing:const Icon(Icons.chevron_right),
           onTap:()=>_open(context,'Personalization',
             const ProfileSettingsScreen(settingsOnly:true,section:'labels')),
         ),
         const Divider(height:1),
         ListTile(
           leading:const Icon(Icons.access_time_outlined),
           title:const Text('Working hours & sleep'),
           subtitle:const Text('Set days, hours and quiet-time preferences'),
           trailing:const Icon(Icons.chevron_right),
           onTap:()=>_open(context,'Daily schedule',
             const ProfileSettingsScreen(settingsOnly:true,section:'schedule')),
         ),
         const Divider(height:1),
         ListTile(
           leading:const Icon(Icons.event_available_outlined),
           title:const Text('Days off & sleep exceptions'),
           subtitle:const Text('Share days off on our calendar; adjust bedtime and wake-up'),
           trailing:const Icon(Icons.chevron_right),
           onTap:()=>Navigator.of(context).push<void>(
             MaterialPageRoute<void>(
               builder:(_)=>const PersonalDaysOffScreen())),
         ),
         const Divider(height:1),
         ListTile(
          leading:const Icon(Icons.public_outlined),
          title:const Text('Regional holidays'),
          subtitle:const Text('Choose which national calendars we see'),
          trailing:const Icon(Icons.chevron_right),
          onTap:()=>Navigator.of(context).push(MaterialPageRoute<void>(
           builder:(_)=>const _HolidayPreferencesScreen())),
         ),
         const Divider(height:1),
         ListTile(
          leading:const Icon(Icons.celebration_outlined),
          title:const Text('Birthdays, anniversaries & special dates'),
          subtitle:const Text('Manage milestones and important occasions'),
          trailing:const Icon(Icons.chevron_right),
          onTap:()=>Navigator.of(context).push(MaterialPageRoute<void>(
           builder:(_)=>const OccasionsScreen())),
         ),
         const Divider(height:1),
         _WeatherUnitsTile(),
         const Divider(height:1),
         ListTile(
           leading:const Icon(Icons.cloud_outlined),
           title:const Text('Weather city'),
           subtitle:const Text('Choose your city; use the phone time zone automatically'),
           trailing:const Icon(Icons.chevron_right),
           onTap:()=>_open(context,'Weather city',
             const ProfileSettingsScreen(settingsOnly:true,section:'weather')),
         ),
       ])),
       const SizedBox(height:16),
       Text('Affection & notifications',
         style:Theme.of(context).textTheme.titleMedium),
       Card(elevation:0,child:Column(children:[
         ListTile(
           leading:const Icon(Icons.volunteer_activism_outlined),
           title:const Text('My love gestures'),
           subtitle:const Text('Manage my gesture list and thoughtful rituals'),
           trailing:const Icon(Icons.chevron_right),
           onTap:()=>Navigator.of(context).push<void>(
             MaterialPageRoute<void>(
               builder:(_)=>const PartnerGesturesScreen(manageOnly:true))),
         ),
         const Divider(height:1),
         ListTile(
           leading:const Icon(Icons.auto_awesome_outlined),
           title:const Text('Thoughtful little rituals'),
           subtitle:const Text('Morning, after-work, and goodnight settings'),
           trailing:const Icon(Icons.chevron_right),
           onTap:()=>Navigator.of(context).push<void>(
             MaterialPageRoute<void>(
               builder:(_)=>const ThoughtfulRitualsScreen())),
         ),
       ])),
     ],
   )),
 );
}


/// Ritual configuration is separate from the love-gesture message library.
class ThoughtfulRitualsScreen extends StatefulWidget{
 const ThoughtfulRitualsScreen({super.key});
 @override State<ThoughtfulRitualsScreen> createState()=>
   _ThoughtfulRitualsScreenState();
}
class _ThoughtfulRitualsScreenState extends State<ThoughtfulRitualsScreen>{
 String? space,partner;
 bool loading=true;
 @override void initState(){super.initState();_load();}
 Future<void> _load()async{
   try{
     final id=await CurrentSpaceCache.instance.get();
     final me=Supabase.instance.client.auth.currentUser?.id;
     if(id==null||me==null){if(mounted)setState(()=>loading=false);return;}
     final people=await Supabase.instance.client.from('space_members')
       .select('user_id').eq('space_id',id);
     final other=people.where((p)=>p['user_id']!=me).firstOrNull;
     if(mounted)setState((){
       space=id;partner=other?['user_id']?.toString();loading=false;
     });
   }catch(_){if(mounted)setState(()=>loading=false);}
 }
 @override Widget build(BuildContext context)=>Scaffold(
   appBar:AppBar(title:const Text('Thoughtful little rituals')),
   body:SafeArea(child:ListView(padding:const EdgeInsets.all(18),children:[
     const Text('A little love, at the right time',
       style:TextStyle(fontSize:18,fontWeight:FontWeight.w700)),
     const SizedBox(height:6),
     const Text('Manage the three optional rituals separately from '
       'the gesture message library. Their delivery still depends on '
       'each partner’s consent, schedule and quiet hours.'),
     const SizedBox(height:14),
     if(loading)const Center(child:CircularProgressIndicator())
     else if(space==null||partner==null)
       const Text('Connect your partner before configuring rituals.')
     else ScheduledGesturesPanel(
       spaceId:space!,recipientId:partner!,recipientName:'your partner'),
   ])),
 );
}

class _WeatherUnitsTile extends StatelessWidget{
 @override Widget build(BuildContext context)=>AnimatedBuilder(
  animation:WeatherUnitPreference.instance,builder:(context,_){
   final prefs=WeatherUnitPreference.instance;
   return ListTile(
    leading:const Icon(Icons.thermostat_outlined),
    title:const Text('Weather temperature'),
    subtitle:Text(prefs.fahrenheit?'US · Fahrenheit (°F)':'Metric · Celsius (°C)'),
    trailing:PopupMenuButton<bool>(
     tooltip:'Change temperature unit',
     onSelected:(v)=>prefs.setFahrenheit(v),
     itemBuilder:(_)=>const [
      PopupMenuItem(value:false,child:Text('Metric · °C')),
      PopupMenuItem(value:true,child:Text('US · °F')),
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
  appBar:AppBar(title:const Text('Regional holidays')),
  body:SafeArea(child:ListView(padding:const EdgeInsets.all(18),children:[
   const Text('Choose the countries in our shared calendar.'),
   const SizedBox(height:12),
   if(loading)const LinearProgressIndicator()
   else if(space==null)const Text('Connect your shared space first.')
   else HolidaySourcesPanel(spaceId:space!,onChanged:(){}),
  ])));
}

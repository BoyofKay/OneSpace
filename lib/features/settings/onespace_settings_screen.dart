import 'package:material_ui/material_ui.dart';
import '../profile/profile_settings_screen.dart';
import '../connect/partner_gestures_screen.dart';
import '../hubs/section_hubs.dart';
import 'personal_days_off_screen.dart';

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
       ])),
     ],
   )),
 );
}

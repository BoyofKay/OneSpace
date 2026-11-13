import 'package:material_ui/material_ui.dart';
import '../profile/profile_settings_screen.dart';
import '../connect/partner_gestures_screen.dart';
import '../hubs/section_hubs.dart';

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
             const ProfileSettingsScreen(settingsOnly:true)),
         ),
         const Divider(height:1),
         ListTile(
           leading:const Icon(Icons.calendar_clock),
           title:const Text('Working hours & sleep'),
           subtitle:const Text('Set days, hours and quiet-time preferences'),
           trailing:const Icon(Icons.chevron_right),
           onTap:()=>_open(context,'Daily schedule',
             const ProfileSettingsScreen(settingsOnly:true)),
         ),
         const Divider(height:1),
         ListTile(
           leading:const Icon(Icons.cloud_outlined),
           title:const Text('Weather city & language'),
           subtitle:const Text('Choose your city; use the phone time zone automatically'),
           trailing:const Icon(Icons.chevron_right),
           onTap:()=>_open(context,'Weather & language',
             const ProfileSettingsScreen(settingsOnly:true)),
         ),
       ])),
       const SizedBox(height:16),
       Text('Affection & notifications',
         style:Theme.of(context).textTheme.titleMedium),
       Card(elevation:0,child:Column(children:[
         ListTile(
           leading:const Icon(Icons.volunteer_activism_outlined),
           title:const Text('My love gestures'),
           subtitle:const Text('Create, send or remove gestures and manage triggers'),
           trailing:const Icon(Icons.chevron_right),
           onTap:()=>Navigator.of(context).push<void>(
             MaterialPageRoute<void>(
               builder:(_)=>const PartnerGesturesScreen())),
         ),
         const Divider(height:1),
         ListTile(
           leading:const Icon(Icons.nights_stay_outlined),
           title:const Text('Automatic gestures & consent'),
           subtitle:const Text('Allow or disable automatic gestures and adjust quiet hours'),
           trailing:const Icon(Icons.chevron_right),
           onTap:()=>_open(context,'Gesture preferences',
             const ProfileSettingsScreen(settingsOnly:true)),
         ),
       ])),
     ],
   )),
 );
}

import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'gesture_schedule_rules.dart';

/// Automatic gestures require consent from BOTH partners, and use recipient-local
/// wake, work-end and bedtime settings. The database cron job is the sender.
class ScheduledGesturesPanel extends StatefulWidget {
 const ScheduledGesturesPanel({
   super.key,required this.spaceId,required this.recipientId,
   required this.recipientName,
 });
 final String spaceId,recipientId,recipientName;
 @override State<ScheduledGesturesPanel> createState()=>_ScheduledGesturesPanelState();
}
class _ScheduledGesturesPanelState extends State<ScheduledGesturesPanel> {
 final db=Supabase.instance.client;
 bool loading=true,saving=false;
 String? error;
 Map<String,dynamic>? partner;
 Map<String,Map<String,dynamic>> configs={};

 @override void initState(){super.initState();_load();}
 Future<void> _load() async {
   try{
     final rows=await db.from('gesture_schedules')
       .select('id,moment,enabled')
       .eq('space_id',widget.spaceId)
       .eq('recipient_id',widget.recipientId);
     final profile=await db.from('profiles')
       .select('receive_automatic_gestures,time_zone,'
         'sleep_start_local,sleep_end_local,work_end_local,work_days')
       .eq('id',widget.recipientId).maybeSingle();
     if(mounted){setState((){
       configs={
         for(final row in rows)row['moment'].toString():row,
       };
       partner=profile;
       loading=false;
     });}
   }catch(_){
     if(mounted){setState((){
       loading=false;error='Could not load scheduled gestures.';
     });}
   }
 }
 Future<void> _toggle(String moment,bool enabled) async {
   if(saving)return;
   setState((){saving=true;error=null;});
   try{
     final existing=configs[moment];
     final Map<String,dynamic> result;
     if(existing==null){
       result=await db.from('gesture_schedules').insert({
         'space_id':widget.spaceId,
         'recipient_id':widget.recipientId,
         'moment':moment,'enabled':enabled,
       }).select('id,moment,enabled').single();
     }else{
       result=await db.from('gesture_schedules')
         .update({'enabled':enabled})
         .eq('id',existing['id'].toString())
         .select('id,moment,enabled').single();
     }
     if(mounted){setState(()=>configs[moment]=result);}
   }on PostgrestException catch(e){
     if(mounted){setState(()=>error=e.code=='23505'
       ?'This schedule has already been configured. Refresh and try again.'
       :'Unable to save this schedule.');}
   }catch(_){
     if(mounted){setState(()=>error='Unable to save this schedule.');}
   }finally{
     if(mounted){setState(()=>saving=false);}
   }
 }
 Widget _ritual(String moment,String title,IconData icon,String rule){
   final enabled=configs[moment]?['enabled']==true;
   final ready=GestureScheduleRules.isReady(moment,partner);
   final reason=GestureScheduleRules.prerequisite(moment,partner);
   return Card(elevation:0,child:SwitchListTile(
     secondary:Icon(icon),
     title:Text(title),
     subtitle:Text(rule+'\n'+(enabled
       ?ready?'Ready to send automatically.':reason
       :'Off — no automatic messages')),
     isThreeLine:true,
     value:enabled,
     onChanged:saving?null:(v)=>_toggle(moment,v),
   ));
 }
 @override Widget build(BuildContext context){
   return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
     const Divider(height:36),
     Text('Thoughtful little rituals',
       style:Theme.of(context).textTheme.titleMedium),
     const SizedBox(height:6),
     Text('Optional scheduled messages for '+widget.recipientName+'. '
       'You choose what to send. Your partner must separately allow '
       'automatic gestures in their own Profile.'),
     const SizedBox(height:10),
     if(loading)const LinearProgressIndicator(),
     if(error!=null)Text(error!,
       style:TextStyle(color:Theme.of(context).colorScheme.error)),
     if(!loading)...[
       _ritual('morning','Morning encouragement',
         Icons.wb_sunny_outlined,'15 minutes after your partner wakes up'),
       _ritual('after_work','After-work support',
         Icons.weekend_outlined,
         '15 minutes after work, only on their working days'),
       _ritual('goodnight','Bedtime wishes',
         Icons.nightlight_outlined,'20 minutes before their bedtime'),
       const SizedBox(height:6),
       Text('Messages rotate among 10 variations per ritual, '
         'send at most once each local day, and pause during sleeping hours. '
         'Delivery follows your partner’s phone time zone and adjusts for '
         'daylight saving. All scheduled gestures are labeled automated.',
         style:Theme.of(context).textTheme.bodySmall),
       TextButton.icon(
         onPressed:saving?_load: _load,
         icon:const Icon(Icons.refresh),label:const Text('Refresh readiness')),
     ],
   ]);
 }
}

import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/current_space_cache.dart';
import '../../core/record_list_top_actions.dart';
import '../../core/record_action_history_view.dart';
import '../calendar/calendar_rules.dart';
import '../calendar/calendar_screen.dart';
import '../plans/plans_screen.dart';
import '../occasions/occasions_screen.dart';
import '../connect/partner_gestures_screen.dart';
import '../mentions/partner_mention_button.dart';
import '../../core/device_time_zone.dart';
import '../../core/partner_time_zones.dart';
import 'reminder_repeat_rules.dart';

/// R22: first-class shared and personal reminders. The database owns
/// per-recipient state, privacy checks, delivery and immutable history.
class RemindersScreen extends StatefulWidget {
 const RemindersScreen({super.key,this.initialReminderId});
 final String? initialReminderId;
 @override State<RemindersScreen> createState()=>_RemindersScreenState();
}
class _RemindersScreenState extends State<RemindersScreen> {
 final db=Supabase.instance.client;
 String? space,error,_watchedSpace,_reminderFingerprint,_recipientFingerprint;
 StreamSubscription<List<Map<String,dynamic>>>? _reminderSubscription,_recipientSubscription;
 Timer? _changeDebounce;
 bool loading=true,busy=false,showCompleted=false,showArchived=false;
 String searchText='';
 List<Map<String,dynamic>> reminders=[];
 String get me=>db.auth.currentUser?.id??'';

 @override void initState(){super.initState();load();}
 @override void dispose(){
  _changeDebounce?.cancel();
  _reminderSubscription?.cancel();
  _recipientSubscription?.cancel();
  super.dispose();
 }
 void _queueRefresh(){
  _changeDebounce?.cancel();
  _changeDebounce=Timer(const Duration(milliseconds:350),(){
   if(mounted)load(quiet:true);
  });
 }
 void _watchChanges(String id){
  if(_watchedSpace==id)return;
  _watchedSpace=id;
  _reminderSubscription?.cancel();_recipientSubscription?.cancel();
  _reminderFingerprint=null;_recipientFingerprint=null;
  _reminderSubscription=db.from('reminders').stream(primaryKey:['id'])
   .eq('space_id',id).limit(250).listen((rows){
    final stamp=rows.map((r)=>r.toString()).join('|');
    if(_reminderFingerprint!=null&&_reminderFingerprint!=stamp)_queueRefresh();
    _reminderFingerprint=stamp;
   },onError:(Object error,StackTrace stack){});
  // RLS allows reading recipient state only for this user or a shared
  // reminder. This also observes the partner's completion/snooze actions.
  _recipientSubscription=db.from('reminder_recipients').stream(primaryKey:['id'])
   .limit(500).listen((rows){
    final stamp=rows.map((r)=>r.toString()).join('|');
    if(_recipientFingerprint!=null&&_recipientFingerprint!=stamp)_queueRefresh();
    _recipientFingerprint=stamp;
   },onError:(Object error,StackTrace stack){});
 }
 Future<void> load({bool quiet=false})async{
  if(!mounted)return;
  if(!quiet)setState((){loading=true;error=null;});
  try{
   final id=await CurrentSpaceCache.instance.get();
   if(id==null){
    if(mounted)setState((){space=null;reminders=[];loading=false;});
    return;
   }
   final data=await db.from('reminders').select(
    'id,title,details,due_at,created_by,visibility,audience,'
    'source_kind,source_id,reminder_intent,reminder_gesture_kind,archived_at,updated_at,'
    'repeat_rule,urgent,source_closed_at,'
    'reminder_recipients(recipient_id,state,next_alert_at,open_occurrence_at,'
    'snoozed_until,acknowledged_at,outcome_note,updated_at),'
    'reminder_actions(actor_id,recipient_id,action,note,next_alert_at,recorded_at)')
     .eq('space_id',id).order('due_at',ascending:true).limit(250);
   if(mounted)_watchChanges(id);
   if(mounted)setState((){
    space=id;reminders=List<Map<String,dynamic>>.from(data);
    loading=false;error=null;
   });
  }on PostgrestException catch(e){
   if(mounted)setState((){loading=false;error=e.message;});
  }catch(_){
   if(mounted)setState((){
    loading=false;error='Reminders could not load. Pull down to retry.';
   });
  }
 }
 List<Map<String,dynamic>> recipients(Map<String,dynamic> r)=>
  List<Map<String,dynamic>>.from(r['reminder_recipients'] as List? ??const []);
 Map<String,dynamic>? mine(Map<String,dynamic> r){
  for(final row in recipients(r)){if(row['recipient_id']==me)return row;}
  return null;
 }
 String person(Object? id)=>id==null?'OneSpace':id==me?'You':'Partner';
 String status(String s)=>s=='done'?'Done':s=='follow_up'?'Needs follow-up':'Pending';
 String when(Object? stamp){
  final dt=DateTime.tryParse(stamp?.toString()??'')?.toLocal();
  if(dt==null)return 'Time not available';
  final day=CalendarRules.sqlDate(dt);
  final hour=dt.hour%12==0?12:dt.hour%12;
  final minute=dt.minute.toString().padLeft(2,'0');
  return day+' · '+hour.toString()+':'+minute+(dt.hour>=12?' PM':' AM');
 }
 Future<void> editor({Map<String,dynamic>? existing})async{
  final id=space;if(id==null)return;
  final saved=await Navigator.of(context).push<bool>(
   MaterialPageRoute<bool>(builder:(_)=>ReminderEditorScreen(
    spaceId:id,existing:existing)));
  if(saved==true&&mounted)await load(quiet:true);
 }
 Future<String?> notesPrompt(String type)async{
  final input=TextEditingController();
  final answer=await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(
   title:Text(type=='done'?'Mark job done':'Needs follow-up'),
   content:TextField(controller:input,maxLength:1200,maxLines:4,minLines:2,
    autofocus:true,decoration:InputDecoration(
     labelText:type=='done'?'Outcome notes (optional)':'What still needs attention?',
     border:const OutlineInputBorder())),
   actions:[
    TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel')),
    FilledButton(onPressed:()=>Navigator.pop(ctx,input.text.trim()),
     child:const Text('Save outcome')),
   ]));
  input.dispose();
  return answer;
 }
 Future<DateTime?> chooseSnooze()async{
  final answer=await showModalBottomSheet<String>(context:context,
   showDragHandle:true,builder:(ctx)=>SafeArea(child:Column(
    mainAxisSize:MainAxisSize.min,children:[
     const ListTile(title:Text('Snooze until…'),
       subtitle:Text('Your choice will be visible in a shared reminder.')),
     ListTile(leading:const Icon(Icons.more_time),
      title:const Text('Later today · 2 hours'),
      onTap:()=>Navigator.pop(ctx,'today')),
     ListTile(leading:const Icon(Icons.wb_sunny_outlined),
      title:const Text('Tomorrow · 9:00 AM'),
      onTap:()=>Navigator.pop(ctx,'tomorrow')),
     ListTile(leading:const Icon(Icons.edit_calendar_outlined),
      title:const Text('Choose a date and time'),
      onTap:()=>Navigator.pop(ctx,'custom')),
    ])));
  if(answer==null)return null;
  final now=DateTime.now();
  if(answer=='today'){
   final later=now.add(const Duration(hours:2));
   return later.day==now.day?later:DateTime(now.year,now.month,now.day+1,9);
  }
  if(answer=='tomorrow')return DateTime(now.year,now.month,now.day+1,9);
  if(!mounted)return null;
  final day=await showDatePicker(context:context,initialDate:now.add(
   const Duration(days:1)),firstDate:now,lastDate:now.add(const Duration(days:365)));
  if(day==null||!mounted)return null;
  final picked=await showTimePicker(context:context,
   initialTime:const TimeOfDay(hour:9,minute:0));
  if(picked==null)return null;
  return DateTime(day.year,day.month,day.day,picked.hour,picked.minute);
 }
 Future<void> respond(Map<String,dynamic> r,String action)async{
  if(busy||mine(r)==null)return;
  String note='';
  DateTime? snooze;
  if(action=='done'||action=='follow_up'){
   final value=await notesPrompt(action);
   if(value==null)return;
   if(action=='follow_up'&&value.trim().isEmpty){
    if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
     content:Text('Please add an outcome note for follow-up.')));
    return;
   }
   note=value;
  }else if(action=='snooze'){
   snooze=await chooseSnooze();
   if(snooze==null)return;
   if(!snooze.isAfter(DateTime.now().add(const Duration(minutes:1)))){
    if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
     content:Text('Choose a time in the future.')));
    return;
   }
  }
  if(!mounted)return;
  setState((){busy=true;error=null;});
  try{
   await db.rpc('respond_to_reminder',params:{
    'p_reminder_id':r['id'],'p_action':action,'p_note':note,
    'p_snooze_until':snooze?.toUtc().toIso8601String(),
   });
   await load(quiet:true);
  }on PostgrestException catch(e){
   if(mounted)setState(()=>error=e.message);
  }catch(_){
   if(mounted)setState(()=>error='Could not save reminder outcome.');
  }finally{if(mounted)setState(()=>busy=false);}
 }
 Future<void> archive(Map<String,dynamic> r)async{
  if(busy||r['created_by']!=me)return;
  final isArchived=r['archived_at']!=null;
  final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
   title:Text(isArchived?'Restore reminder?':'Remove reminder?'),
   content:const Text('The reminder and its outcome history stay saved.'),
   actions:[
    TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),
    FilledButton(onPressed:()=>Navigator.pop(ctx,true),
     child:Text(isArchived?'Restore':'Remove')),
   ]));
  if(ok!=true)return;
  setState(()=>busy=true);
  try{
   await db.from('reminders').update({'archived_at':isArchived?
    null:DateTime.now().toUtc().toIso8601String()}).eq('id',r['id']);
   await load(quiet:true);
  }on PostgrestException catch(e){
   if(mounted)setState(()=>error=e.message);
  }finally{if(mounted)setState(()=>busy=false);}
 }
 Future<void> linked(Map<String,dynamic> r)async{
  if(r['reminder_intent']=='love_gesture'){
   if(mounted)await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(builder:(_)=>const PartnerGesturesScreen()));
   return;
  }
  final kind=r['source_kind']?.toString();
  final id=r['source_id']?.toString();
  if(kind==null||id==null||!mounted)return;
  final Widget screen;
  if(kind=='task')screen=PlansScreen(focusTaskId:id);
  else if(kind=='calendar')screen=CalendarScreen(initialEventId:id);
  else if(kind=='occasion')screen=OccasionDetail(id:id);
  else return;
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(builder:(_)=>screen));
 }
 Widget tile(Map<String,dynamic> r){
  final own=mine(r),shared=r['visibility']=='shared';
  final rows=recipients(r);
  final allDone=rows.isNotEmpty&&rows.every((x)=>x['state']=='done');
  final repeating=r['repeat_rule'] is Map;
  final closed=r['source_closed_at']!=null;
  final nextMine=DateTime.tryParse((own?['next_alert_at']??'').toString())?.toLocal();
  final openMine=own?['open_occurrence_at']!=null;
  final due=repeating?(nextMine??DateTime.tryParse(r['due_at']?.toString()??'')?.toLocal()):
   DateTime.tryParse(r['due_at']?.toString()??'')?.toLocal();
  final overdue=!repeating&&due!=null&&due.isBefore(DateTime.now())&&!allDone;
  final history=List<Map<String,dynamic>>.from(
   r['reminder_actions'] as List? ??const [])
   ..sort((a,b)=>(b['recorded_at']??'').toString()
    .compareTo((a['recorded_at']??'').toString()));
  return Card(elevation:0,child:ExpansionTile(
   initiallyExpanded:r['id']==widget.initialReminderId,
   title:Text(r['title']?.toString()??'Reminder',
    style:TextStyle(fontWeight:FontWeight.w600,
     decoration:allDone?TextDecoration.lineThrough:null)),
   subtitle:Text([
    if(repeating)ReminderRepeat.describe(r['repeat_rule'])
    else when(r['due_at']),
    if(repeating&&openMine)'Due now'
    else if(repeating&&nextMine!=null&&!closed)'Next '+when(own?['next_alert_at']),
    shared?'Shared':'Only me',
    if(r['urgent']==true)'Urgent',
    if(closed)'Linked item closed · no more alerts',
    if(r['reminder_intent']=='love_gesture')'Choose when to send',
    if(overdue)'Overdue',
    if(r['archived_at']!=null)'Removed',
   ].join(' · '),maxLines:2,overflow:TextOverflow.ellipsis),
   leading:Icon(allDone?Icons.task_alt_outlined:
    overdue||openMine?Icons.notification_important_outlined:
    repeating?Icons.repeat:Icons.alarm_outlined,
    color:overdue||openMine?Theme.of(context).colorScheme.error:null),
   childrenPadding:const EdgeInsets.fromLTRB(16,0,16,14),
   children:[
    if((r['details']??'').toString().isNotEmpty)
     Align(alignment:Alignment.centerLeft,
      child:Padding(padding:const EdgeInsets.symmetric(vertical:8),
       child:Text(r['details'].toString()))),
    for(final x in rows)ListTile(
     dense:true,contentPadding:EdgeInsets.zero,
     leading:Icon(x['state']=='done'?Icons.check_circle_outline:
       x['state']=='follow_up'?Icons.flag_outlined:Icons.schedule_outlined),
     title:Text(person(x['recipient_id'].toString())+
       ' · '+status(x['state']?.toString()??'pending')),
     subtitle:Text([
      if(x['snoozed_until']!=null)'Snoozed until '+when(x['snoozed_until']),
      if(x['state']=='follow_up'&&x['next_alert_at']!=null)
       'Follow-up '+when(x['next_alert_at']),
      if(repeating&&x['open_occurrence_at']!=null)
       'Waiting for an answer since '+when(x['open_occurrence_at']),
      if((x['outcome_note']??'').toString().isNotEmpty)
       x['outcome_note'].toString(),
     ].join('\n')),
    ),
    if(r['source_kind']!=null||r['reminder_intent']=='love_gesture')
     Align(alignment:Alignment.centerLeft,
      child:TextButton.icon(onPressed:()=>linked(r),
       icon:const Icon(Icons.link),
       label:Text(r['reminder_intent']=='love_gesture'
        ?'Open A little love':'Open related item'))),
    if(own!=null&&r['archived_at']==null&&!closed)Wrap(
     spacing:7,runSpacing:3,children:[
      OutlinedButton.icon(onPressed:busy?null:()=>respond(r,'done'),
       icon:const Icon(Icons.check),
       label:Text(repeating?'Done for this time':'Done')),
      OutlinedButton.icon(onPressed:busy?null:()=>respond(r,'follow_up'),
       icon:const Icon(Icons.flag_outlined),label:const Text('Follow-up')),
      OutlinedButton.icon(onPressed:busy?null:()=>respond(r,'snooze'),
       icon:const Icon(Icons.snooze),label:const Text('Snooze')),
      if(own['state']=='done'&&!repeating)TextButton(
       onPressed:busy?null:()=>respond(r,'reopen'),child:const Text('Reopen')),
     ]),
    if(r['created_by']==me)Wrap(spacing:10,children:[
     TextButton.icon(onPressed:busy?null:()=>editor(existing:r),
      icon:const Icon(Icons.edit_outlined),label:const Text('Edit reminder')),
     TextButton.icon(onPressed:busy?null:()=>archive(r),
      icon:Icon(r['archived_at']==null?Icons.archive_outlined:Icons.unarchive_outlined),
      label:Text(r['archived_at']==null?'Remove':'Restore')),
    ]),
    Align(alignment:Alignment.centerRight,
     child:TextButton.icon(
      onPressed:()=>showModalBottomSheet<void>(
       context:context,showDragHandle:true,isScrollControlled:true,
       builder:(_)=>FractionallySizedBox(heightFactor:.78,
        child:RecordActionHistoryView(
         kind:'reminder',recordId:r['id'].toString()))),
      icon:const Icon(Icons.manage_history_outlined),
      label:const Text('Record action history'))),
    if(history.isNotEmpty)ExpansionTile(
     title:Text('Outcome history · '+history.length.toString()),
     children:[for(final event in history)ListTile(
      dense:true,contentPadding:EdgeInsets.zero,
      title:Text(person(event['actor_id'])+' · '+
       ReminderRepeat.actionLabel(event['action']?.toString()??'')+
       (event['actor_id']==null&&event['recipient_id']!=null?
        ' (for '+person(event['recipient_id']).toLowerCase()+')':'')),
      subtitle:Text([
       when(event['recorded_at']),
       if((event['note']??'').toString().isNotEmpty)event['note'].toString(),
       if((event['action']=='snooze'||event['action']=='deferred')&&event['next_alert_at']!=null)
        'Until '+when(event['next_alert_at']),
       if(event['action']=='missed'&&event['next_alert_at']!=null)
        'Occurrence of '+when(event['next_alert_at']),
      ].join(' · ')),
     )],
    ),
   ],
  ));
 }
 @override Widget build(BuildContext context){
  final visible=reminders.where((r)=>
   (showArchived||r['archived_at']==null)&&
   (showCompleted||recipients(r).any((x)=>x['state']!='done'))&&
   (searchText.isEmpty||
    (r['title']??'').toString().toLowerCase().contains(searchText)||
    (r['details']??'').toString().toLowerCase().contains(searchText))
   ).toList();
  return Scaffold(
   appBar:AppBar(title:const Text('Reminders'),actions:[
    RecordListTopActions(
      historyKinds:const ['reminder'],historyTitle:'Reminders',
     showHistory:showArchived,
      onToggleHistory:()=>setState(()=>showArchived=!showArchived),
      hasActiveFilters:showCompleted,
      onClearFilters:()=>setState((){showCompleted=false;}),
      filters:(_)=>StatefulBuilder(builder:(ctx,update)=>Column(
       mainAxisSize:MainAxisSize.min,children:[
        SwitchListTile(title:const Text('Include completed'),
         value:showCompleted,onChanged:(v){
          setState(()=>showCompleted=v);update((){});
         }),
        TextButton.icon(onPressed:(){
         setState(()=>showCompleted=false);update((){});
        },icon:const Icon(Icons.restart_alt),
         label:const Text('Reset filters')),
       ])),
    ),
    IconButton(onPressed:()=>load(),tooltip:'Refresh reminders',
     icon:const Icon(Icons.refresh_outlined)),
   ]),
   floatingActionButton:space==null?null:FloatingActionButton.extended(
    onPressed:busy?null:()=>editor(),icon:const Icon(Icons.add),
    label:const Text('New reminder')),
   body:RefreshIndicator(onRefresh:load,child:ListView(
    physics:const AlwaysScrollableScrollPhysics(),
    padding:const EdgeInsets.fromLTRB(16,16,16,95),children:[
     const Text('Remember what matters',
      style:TextStyle(fontSize:24,fontWeight:FontWeight.bold)),
     const SizedBox(height:6),
     const Text('Personal and shared reminders, with separate follow-up '
      'and snooze outcomes for each of you.'),
     const SizedBox(height:10),
     TextField(
      onChanged:(v)=>setState(()=>searchText=v.trim().toLowerCase()),
      decoration:const InputDecoration(
       prefixIcon:Icon(Icons.search),
       labelText:'Search reminders',
       hintText:'Search reminder title and details',
       border:OutlineInputBorder())),
     const SizedBox(height:10),
     if(error!=null)Padding(padding:const EdgeInsets.symmetric(vertical:8),
      child:Text(error!,style:TextStyle(
       color:Theme.of(context).colorScheme.error))),
     if(loading)const Padding(padding:EdgeInsets.all(40),
      child:Center(child:CircularProgressIndicator())),
     if(!loading&&space==null)const Text('Connect a shared space first.'),
     if(!loading&&space!=null&&visible.isEmpty)
      const Padding(padding:EdgeInsets.all(40),
       child:Center(child:Text('No reminders in this view. Tap New reminder.'))),
     for(final r in visible)tile(r),
   ])),
  );
 }
}

class ReminderEditorScreen extends StatefulWidget{
 const ReminderEditorScreen({super.key,required this.spaceId,this.existing,
  this.initialTitle='',this.initialDetails=''});
 final String spaceId;
 final Map<String,dynamic>? existing;
 /// R52: pre-filled from shared content ("Items to sort").
 final String initialTitle,initialDetails;
 @override State<ReminderEditorScreen> createState()=>_ReminderEditorScreenState();
}
class _ReminderEditorScreenState extends State<ReminderEditorScreen>{
 final db=Supabase.instance.client;
 late final TextEditingController title,details;
 late DateTime due;
 late String visibility,audience;
 String? sourceKind,sourceId,error;
 bool saving=false,loadingLinks=true,urgent=false;
 List<Map<String,dynamic>> links=[];
 ReminderRepeat repeat=const ReminderRepeat();
 String myZone='UTC';
 String? partnerZone,partnerName;
 @override void initState(){
  super.initState();
  final prior=widget.existing;
  title=TextEditingController(text:prior?['title']?.toString()??widget.initialTitle);
  details=TextEditingController(text:prior?['details']?.toString()??widget.initialDetails);
  due=DateTime.tryParse(prior?['due_at']?.toString()??'')?.toLocal()
   ??DateTime.now().add(const Duration(hours:1));
  visibility=prior?['visibility']?.toString()??'private';
  audience=prior?['audience']?.toString()??'me';
  sourceKind=prior?['source_kind']?.toString();
  sourceId=prior?['source_id']?.toString();
  repeat=ReminderRepeat.fromRule(prior?['repeat_rule'],start:due);
  urgent=prior?['urgent']==true;
  loadLinks();
  loadZones();
 }
 /// Repeating schedules are stored in a fixed IANA zone (this phone's), so a
 /// daylight-saving change never moves the alarm. The partner's zone is only
 /// used to show "that's 7:00 AM for them".
 Future<void> loadZones()async{
  try{
   final zone=await DeviceTimeZone.readPhone();
   final rows=await db.from('profiles').select('id,display_name,time_zone');
   final meId=db.auth.currentUser?.id;
   String? pz,pn,mz;
   for(final row in rows){
    if(row['id']==meId){mz=row['time_zone']?.toString();}
    else{pz=row['time_zone']?.toString();pn=row['display_name']?.toString();}
   }
   if(!mounted)return;
   setState((){
    myZone=zone??(PartnerTimeZones.valid(mz)?mz!:'UTC');
    partnerZone=PartnerTimeZones.valid(pz)?pz:null;
    final first=(pn??'').trim().split(' ').first;
    partnerName=first.isEmpty?null:first;
   });
  }catch(_){/* Hint only; saving still works with the phone zone. */}
 }
 String? partnerTimeHint(){
  final zone=partnerZone;
  if(audience=='me'||zone==null||zone==myZone)return null;
  final there=PartnerTimeZones.inZone(zone,due);
  if(there==null)return null;
  final h=there.hour%12==0?12:there.hour%12;
  final m=there.minute.toString().padLeft(2,'0');
  final sameDay=there.day==due.day;
  return "That's "+h.toString()+':'+m+(there.hour>=12?' PM':' AM')+
   (sameDay?'':' ('+ReminderRepeat.dayShort[there.weekday-1]+')')+
   ' for '+(partnerName??'your partner')+'.';
 }
 Future<void> addTime()async{
  final picked=await showTimePicker(context:context,
   initialTime:const TimeOfDay(hour:20,minute:0));
  if(picked==null||!mounted)return;
  final value=ReminderRepeat.hhmm(picked.hour,picked.minute);
  final main=ReminderRepeat.hhmm(due.hour,due.minute);
  if(value==main||repeat.extraTimes.contains(value))return;
  if(repeat.extraTimes.length>=5){
   setState(()=>error='Up to 6 times a day.');return;
  }
  setState(()=>repeat=repeat.copyWith(extraTimes:[...repeat.extraTimes,value]..sort()));
 }
 Future<void> pickUntil()async{
  final picked=await showDatePicker(context:context,
   initialDate:repeat.until??due.add(const Duration(days:30)),
   firstDate:due,lastDate:DateTime(2100));
  if(picked==null||!mounted)return;
  setState(()=>repeat=repeat.copyWith(until:picked));
 }
 Widget repeatSection(){
  final interval=repeat.interval;
  final unit=repeat.preset=='daily'?'day':repeat.preset=='weekly'?'week':
   repeat.preset=='monthly'?'month':'year';
  return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
   DropdownButtonFormField<String>(
    initialValue:repeat.preset,isExpanded:true,
    decoration:const InputDecoration(labelText:'Repeat',
     prefixIcon:Icon(Icons.repeat),border:OutlineInputBorder()),
    items:[for(final p in ReminderRepeat.presets)
     DropdownMenuItem(value:p,child:Text(ReminderRepeat.presetLabels[p]!))],
    onChanged:saving?null:(v)=>setState((){
     repeat=repeat.copyWith(preset:v??'none',interval:1,
      weekdays:v=='weekly'?{due.weekday}:null);
    })),
   if(repeat.repeats&&repeat.preset!='weekdays')Row(children:[
    const Text('Every'),
    IconButton(onPressed:interval>1?()=>setState(()=>
      repeat=repeat.copyWith(interval:interval-1)):null,
     icon:const Icon(Icons.remove_circle_outline),tooltip:'Less often'),
    Text(interval.toString(),style:const TextStyle(fontWeight:FontWeight.bold)),
    IconButton(onPressed:interval<99?()=>setState(()=>
      repeat=repeat.copyWith(interval:interval+1)):null,
     icon:const Icon(Icons.add_circle_outline),tooltip:'More apart'),
    Text(interval==1?unit:unit+'s'),
   ]),
   if(repeat.preset=='weekly')Wrap(spacing:6,children:[
    for(var d=1;d<=7;d++)FilterChip(
     label:Text(ReminderRepeat.dayShort[d-1]),
     selected:repeat.weekdays.contains(d),
     onSelected:(on)=>setState((){
      final next={...repeat.weekdays};
      if(on){next.add(d);}else if(next.length>1){next.remove(d);}
      repeat=repeat.copyWith(weekdays:next);
     })),
   ]),
   if(repeat.repeats)...[
    const SizedBox(height:8),
    const Text('Times of day'),
    Wrap(spacing:6,runSpacing:4,children:[
     Chip(label:Text(ReminderRepeat.clock(ReminderRepeat.hhmm(due.hour,due.minute)))),
     for(final t in repeat.extraTimes)InputChip(
      label:Text(ReminderRepeat.clock(t)),
      onDeleted:()=>setState(()=>repeat=repeat.copyWith(
       extraTimes:repeat.extraTimes.where((x)=>x!=t).toList()))),
     ActionChip(avatar:const Icon(Icons.add,size:18),
      label:const Text('Add another time'),onPressed:saving?null:addTime),
    ]),
    const SizedBox(height:6),
    Wrap(crossAxisAlignment:WrapCrossAlignment.center,spacing:8,children:[
     const Text('Ends'),
     ChoiceChip(label:const Text('Never'),selected:repeat.until==null,
      onSelected:(_)=>setState(()=>repeat=repeat.copyWith(clearUntil:true))),
     ChoiceChip(label:Text(repeat.until==null?'On a date':
       'On '+CalendarRules.sqlDate(repeat.until!)),
      selected:repeat.until!=null,onSelected:(_)=>pickUntil()),
    ]),
    const SizedBox(height:4),
    Text('Times follow this phone’s time zone ('+myZone+'), even when the clocks change.',
     style:Theme.of(context).textTheme.bodySmall),
   ],
  ]);
 }
 @override void dispose(){title.dispose();details.dispose();super.dispose();}
 Future<void> loadLinks()async{
  try{
   final lists=await Future.wait([
    db.from('tasks').select('id,title,visibility')
     .eq('space_id',widget.spaceId).isFilter('migrated_to_list',null).limit(100),
    db.from('space_events').select('id,title,visibility')
     .eq('space_id',widget.spaceId).isFilter('archived_at',null).limit(100),
    db.from('occasion_plans').select('id,title,visibility')
     .eq('space_id',widget.spaceId).isFilter('archived_at',null).limit(100),
   ]);
   if(!mounted)return;
   setState((){
    links=[
     for(var i=0;i<lists.length;i++)
      for(final row in lists[i]){
       'id':row['id'],'title':row['title'],'visibility':row['visibility'],
       'kind':['task','calendar','occasion'][i],
      },
    ];loadingLinks=false;
   });
  }catch(_){if(mounted)setState(()=>loadingLinks=false);}
 }
 Future<void> pickDue()async{
  final today=DateTime.now();
  final selected=await showDatePicker(context:context,
   initialDate:due.isBefore(today)?today:due,
   firstDate:today,lastDate:DateTime(2100));
  if(selected==null||!mounted)return;
  final time=await showTimePicker(context:context,
   initialTime:TimeOfDay(hour:due.hour,minute:due.minute));
  if(time==null)return;
  setState(()=>due=DateTime(selected.year,selected.month,selected.day,
   time.hour,time.minute));
 }
 Future<void> save()async{
  final name=title.text.trim();
  if(saving)return;
  if(name.isEmpty||name.length>160||details.text.length>4000){
   setState(()=>error='Add a title (up to 160 characters) and optional details.');
   return;
  }
  if(due.isBefore(DateTime.now().add(const Duration(minutes:1)))&&
    widget.existing==null){
   setState(()=>error='Choose a future date and time.');return;
  }
  if(sourceKind!=null&&sourceId!=null){
   final match=links.where((x)=>x['id']==sourceId).toList();
   if(match.isEmpty||visibility=='shared'&&match.first['visibility']=='private'){
    setState(()=>error='The linked item must be visible to the reminder recipients.');
    return;
   }
  }
  setState((){saving=true;error=null;});
  try{
   final fields={
    'title':name,'details':details.text.trim(),
    'due_at':due.toUtc().toIso8601String(),
    'repeat_rule':repeat.toRule(start:due,timeZone:myZone),
    'urgent':urgent&&audience!='me',
   };
   if(widget.existing==null){
    await db.from('reminders').insert({
     ...fields,'space_id':widget.spaceId,
     'visibility':visibility,'audience':audience,
     'source_kind':sourceKind,'source_id':sourceId,
    });
   }else{
    await db.from('reminders').update(fields)
      .eq('id',widget.existing!['id'].toString());
   }
   if(mounted)Navigator.pop(context,true);
  }on PostgrestException catch(e){if(mounted)setState(()=>error=e.message);}
  catch(_){if(mounted)setState(()=>error='Could not save reminder.');}
  finally{if(mounted)setState(()=>saving=false);}
 }
 @override Widget build(BuildContext context){
  final editing=widget.existing!=null;
  final eligible=links.where((item)=>visibility=='private'||
   item['visibility']=='shared').toList();
  final options={
   for(final item in eligible)
    item['kind'].toString()+':'+item['id'].toString():
      item['kind'].toString()+' · '+item['title'].toString(),
  };
  final selected=sourceKind==null||sourceId==null?null:
   sourceKind!+':'+sourceId!;
  return Scaffold(appBar:AppBar(
   title:Text(editing?'Edit reminder':'Add new reminder')),
   body:SafeArea(child:ListView(padding:const EdgeInsets.all(18),children:[
    TextField(controller:title,maxLength:160,
     decoration:const InputDecoration(labelText:'Reminder',
      border:OutlineInputBorder())),
    const SizedBox(height:10),
    TextField(controller:details,maxLength:4000,minLines:2,maxLines:5,
     decoration:const InputDecoration(labelText:'Details / instructions',
      border:OutlineInputBorder())),
    if(visibility=='shared')Align(
     alignment:Alignment.centerLeft,
     child:PartnerMentionButton(
      spaceId:widget.spaceId,controller:details,
      enabled:!saving)),
    const SizedBox(height:14),
    OutlinedButton.icon(onPressed:saving?null:pickDue,
     icon:const Icon(Icons.event_outlined),
     label:Text((repeat.repeats?'Starts · ':'Remind at · ')+_when(due))),
    if(partnerTimeHint()!=null)Padding(
     padding:const EdgeInsets.only(top:6),
     child:Row(children:[
      const Icon(Icons.public,size:18),const SizedBox(width:6),
      Expanded(child:Text(partnerTimeHint()!)),
     ])),
    const SizedBox(height:14),
    repeatSection(),
    const SizedBox(height:16),
    if(!editing)...[
     SwitchListTile(
      title:const Text('Shared with partner'),
      subtitle:const Text('Private reminders stay visible only to you.'),
      value:visibility=='shared',onChanged:saving?null:(v)=>setState((){
       visibility=v?'shared':'private';audience=v?'both':'me';
       if(visibility=='shared'&&selected!=null&&
        !options.containsKey(selected)){sourceKind=null;sourceId=null;}
      })),
     if(visibility=='shared')...[
      const Text('Who should receive the alert?'),
      Wrap(spacing:7,children:[
       for(final v in ['both','me','partner'])ChoiceChip(
        label:Text(v=='both'?'Both of us':v=='me'?'Only me':'Partner'),
        selected:audience==v,onSelected:(_)=>setState(()=>audience=v)),
      ]),
     ],
    ]else Text('Visibility: '+visibility+' · Recipients: '+audience),
    if(visibility=='shared'&&audience!='me')SwitchListTile(
     contentPadding:EdgeInsets.zero,
     secondary:const Icon(Icons.priority_high),
     title:const Text('Urgent'),
     subtitle:const Text('Alerts even during your partner\'s sleep hours. '
      'Without it, alerts wait until they wake up.'),
     value:urgent,onChanged:saving?null:(v)=>setState(()=>urgent=v)),
    const SizedBox(height:12),
    if(loadingLinks)const LinearProgressIndicator(),
    DropdownButtonFormField<String>(
     key:ValueKey(visibility+':'+selected.toString()),
     initialValue:selected!=null&&options.containsKey(selected)?selected:null,
     isExpanded:true,
     decoration:const InputDecoration(labelText:'Related item (optional)',
      border:OutlineInputBorder()),
     items:[
      const DropdownMenuItem(value:'none',child:Text('No linked item')),
      for(final item in options.entries)
       DropdownMenuItem(value:item.key,
        child:Text(item.value,overflow:TextOverflow.ellipsis)),
     ],
     onChanged:editing||saving?null:(v)=>setState((){
      if(v==null||v=='none'){sourceKind=null;sourceId=null;}
      else{final parts=v.split(':');sourceKind=parts.first;sourceId=parts.last;}
     })),
    const SizedBox(height:6),
    const Text('Choose an existing checklist, Calendar entry or Occasion. '
     'No duplicate item is created.'),
    if(error!=null)Padding(padding:const EdgeInsets.symmetric(vertical:10),
     child:Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error))),
    const SizedBox(height:18),
    FilledButton.icon(onPressed:saving?null:save,icon:const Icon(Icons.save_outlined),
     label:Text(saving?'Saving…':editing?'Save changes':'Create reminder')),
   ])),
  );
 }
 String _when(DateTime dt){
  final d=CalendarRules.sqlDate(dt);
  final h=dt.hour%12==0?12:dt.hour%12;
  return d+' · '+h.toString()+':'+dt.minute.toString().padLeft(2,'0')+
   (dt.hour>=12?' PM':' AM');
 }
}

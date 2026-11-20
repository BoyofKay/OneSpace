import '../../core/form_kit.dart';
import '../../core/repeat_control.dart';
import '../../core/item_menu.dart';
import '../../core/status_look.dart';
import '../../core/editor_scaffold.dart';
import '../../core/linked_items.dart';
import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/current_space_cache.dart';
import '../../core/app_env.dart';
import '../../core/record_list_top_actions.dart';
import '../calendar/calendar_rules.dart';
import '../calendar/calendar_screen.dart';
import '../plans/plans_screen.dart';
import '../occasions/occasions_screen.dart';
import '../connect/partner_gestures_screen.dart';
import '../mentions/partner_mention_button.dart';
import '../../core/device_time_zone.dart';
import '../../core/partner_time_zones.dart';
import 'reminder_repeat_rules.dart';
import 'package:onespace/l10n/phrases.dart';

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
 void _watchChanges(String? id){
  final key=OneSpaceEnv.isProduction ? id : 'personal:$me|pair:$id';
  if(_watchedSpace==key)return;
  _watchedSpace=key;
  _reminderSubscription?.cancel();_recipientSubscription?.cancel();
  _reminderFingerprint=null;_recipientFingerprint=null;
  final reminderStream=OneSpaceEnv.isProduction
   ? db.from('reminders').stream(primaryKey:['id'])
      .eq('space_id',id!).limit(250)
   : db.from('reminders').stream(primaryKey:['id']).limit(250);
  _reminderSubscription=reminderStream.listen((rows){
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
   String? id=await CurrentSpaceCache.instance.get();
   if (!OneSpaceEnv.isProduction) {
     final scopes=await db.rpc('my_storage_scopes');
     if(scopes is! Map || scopes['private_space_id']?.toString()!=me) {
       throw StateError('Personal reminders scope unavailable');
     }
     id=scopes['shared_space_id']?.toString();
   }
   if(id==null && OneSpaceEnv.isProduction){
    if(mounted)setState((){space=null;reminders=[];loading=false;});
    return;
   }
   // Production has not received the QA personal-scope migration.
   final scopeColumn=OneSpaceEnv.isProduction?'':'private_space_id,';
   var query=db.from('reminders').select(
    'id,title,details,due_at,created_by,${scopeColumn}visibility,audience,'
    'source_kind,source_id,reminder_intent,reminder_gesture_kind,archived_at,updated_at,'
    'repeat_rule,urgent,source_closed_at,'
    'reminder_recipients(recipient_id,state,next_alert_at,open_occurrence_at,'
    'snoozed_until,acknowledged_at,outcome_note,updated_at),'
    'reminder_actions(actor_id,recipient_id,action,note,next_alert_at,recorded_at)');
   if (OneSpaceEnv.isProduction) query=query.eq('space_id',id!);
   final data=await query.order('due_at',ascending:true).limit(250);
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
 /// R57: a one-off reminder is completed (and leaves the Open list) once I
 /// marked it done — or, when it was not sent to me, once everyone did.
 /// Repeating reminders stay open: "done" there means "done this time".
 bool completed(Map<String,dynamic> r){
  if(ReminderRepeat.fromRule(r['repeat_rule'],
    start:DateTime.tryParse(r['due_at']?.toString()??'')?.toLocal()??DateTime.now()).repeats){
   return false;
  }
  final m=mine(r);
  if(m!=null)return m['state']=='done';
  final all=recipients(r);
  return all.isNotEmpty&&all.every((x)=>x['state']=='done');
 }
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
  final id=space;
  if(id==null && OneSpaceEnv.isProduction)return;
  final saved=await Navigator.of(context).push<bool>(
   MaterialPageRoute<bool>(builder:(_)=>ReminderEditorScreen(
    spaceId:id??'',existing:existing)));
  if(saved==true&&mounted)await load(quiet:true);
 }
 Future<String?> notesPrompt(String type)async{
  final input=TextEditingController();
  final answer=await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(
   title:Text(tt(type=='done'?tt('Mark job done'):tt('Needs follow-up'))),
   content:TextField(controller:input,maxLength:1200,maxLines:4,minLines:2,
    autofocus:true,decoration:InputDecoration(
     labelText:type=='done'?tt('Outcome notes (optional)'):tt('What still needs attention?'),
     border:const OutlineInputBorder())),
   actions:[
    TextButton(onPressed:()=>Navigator.pop(ctx),child:Text(tt('Cancel'))),
    FilledButton(onPressed:()=>Navigator.pop(ctx,input.text.trim()),
     child:Text(tt('Save outcome'))),
   ]));
  input.dispose();
  return answer;
 }
 Future<DateTime?> chooseSnooze()async{
  final answer=await showModalBottomSheet<String>(context:context,
   showDragHandle:true,builder:(ctx)=>SafeArea(child:Column(
    mainAxisSize:MainAxisSize.min,children:[
     ListTile(title:Text(tt('Snooze until…')),
       subtitle:Text(tt('Your choice will be visible in a shared reminder.'))),
     ListTile(leading:const Icon(Icons.more_time),
      title:Text(tt('Later today · 2 hours')),
      onTap:()=>Navigator.pop(ctx,'today')),
     ListTile(leading:const Icon(Icons.wb_sunny_outlined),
      title:Text(tt('Tomorrow · 9:00 AM')),
      onTap:()=>Navigator.pop(ctx,'tomorrow')),
     ListTile(leading:const Icon(Icons.edit_calendar_outlined),
      title:Text(tt('Choose a date and time')),
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
    if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(
     content:Text(tt('Please add an outcome note for follow-up.'))));
    return;
   }
   note=value;
  }else if(action=='snooze'){
   snooze=await chooseSnooze();
   if(snooze==null)return;
   if(!snooze.isAfter(DateTime.now().add(const Duration(minutes:1)))){
    if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(
     content:Text(tt('Choose a time in the future.'))));
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
   title:Text(tt(isArchived?tt('Restore reminder?'):tt('Remove reminder?'))),
   content:Text(tt('The reminder and its outcome history stay saved.')),
   actions:[
    TextButton(onPressed:()=>Navigator.pop(ctx,false),child:Text(tt('Cancel'))),
    FilledButton(onPressed:()=>Navigator.pop(ctx,true),
     child:Text(tt(isArchived?tt('Restore'):tt('Remove')))),
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

 /// The time block at the start of a reminder card.
 Widget _timeBadge(DateTime? at,bool alert,bool urgent,bool done){
  final colors=Theme.of(context).colorScheme;
  final now=DateTime.now();
  final today=DateTime(now.year,now.month,now.day);
  String day='';
  String time='—';
  if(at!=null){
   final d=DateTime(at.year,at.month,at.day);
   final gap=d.difference(today).inDays;
   final names=OneSpacePhrases.weekdaysShort;
   final months=OneSpacePhrases.monthsShort;
   day=gap==0?'Today':gap==1?'Tomorrow':gap==-1?'Yesterday':
    '${names[at.weekday-1]} ${at.day} ${months[at.month-1]}';
   final h=at.hour%12==0?12:at.hour%12;
   time='$h:${at.minute.toString().padLeft(2,'0')} ${at.hour>=12?tt('PM'):tt('AM')}';
  }
  final tone=done?colors.surfaceContainerHighest:
   alert?colors.errorContainer:urgent?colors.tertiaryContainer:colors.secondaryContainer;
  final ink=done?colors.onSurfaceVariant:
   alert?colors.onErrorContainer:urgent?colors.onTertiaryContainer:colors.onSecondaryContainer;
  return Container(
   width:68,padding:const EdgeInsets.symmetric(vertical:6,horizontal:4),
   decoration:BoxDecoration(color:tone,borderRadius:BorderRadius.circular(10)),
   child:Column(mainAxisSize:MainAxisSize.min,children:[
    Text(tt(time),maxLines:1,style:TextStyle(color:ink,fontWeight:FontWeight.w700,fontSize:12.5)),
    if(day.isNotEmpty)Text(tt(day),maxLines:1,overflow:TextOverflow.ellipsis,
     style:TextStyle(color:ink,fontSize:11)),
   ]));
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
   // R55: time first (red when overdue), title, one short line, one-tap Done.
   leading:_timeBadge(due,overdue||openMine,r['urgent']==true,allDone),
   title:Text(tt(r['title']?.toString()??'Reminder'),
    maxLines:2,overflow:TextOverflow.ellipsis,
    style:StatusLook.title(context,allDone?'completed':null,
     const TextStyle(fontWeight:FontWeight.w600))),
   subtitle:Text(tt([
    if(repeating)ReminderRepeat.describe(r['repeat_rule']),
    if(repeating&&openMine)'Due now',
    if(!shared)'Only me',
    if(r['urgent']==true)'Urgent',
    if(closed)'Linked item closed',
    if(r['reminder_intent']=='love_gesture')'Choose when to send',
    if(r['archived_at']!=null)'Removed',
   ].join(' · ')),maxLines:2,overflow:TextOverflow.ellipsis),
   trailing:ItemMenu(kind:'reminder',recordId:r['id'].toString(),title:r['title']?.toString(),
     statusActions:[
      if(own!=null&&r['archived_at']==null&&!closed)...[
       ItemMenuAction(repeating?'Done for this time':'Done',Icons.check,()=>respond(r,'done')),
       ItemMenuAction(tt('Follow-up'),Icons.flag_outlined,()=>respond(r,'follow_up')),
       ItemMenuAction(tt('Snooze'),Icons.snooze,()=>respond(r,'snooze')),
       if(own['state']=='done'&&!repeating)ItemMenuAction(tt('Reopen'),Icons.undo,()=>respond(r,'reopen')),
      ],
     ],
     onOpen:r['created_by']==me?()=>editor(existing:r):null,
     removed:r['archived_at']!=null,
     onRemove:r['created_by']==me?()=>archive(r):null),
   childrenPadding:const EdgeInsetsDirectional.fromSTEB(16,0,16,14),
   children:[
    if(OneSpaceEnv.isProduction || r['private_space_id']==null)
     LinkedItemsStrip(kind:LinkKind.reminder,id:r['id'].toString()),
    if((r['details']??'').toString().isNotEmpty)
     Align(alignment:AlignmentDirectional.centerStart,
      child:Padding(padding:const EdgeInsets.symmetric(vertical:8),
       child:Text(tt(r['details'].toString())))),
    for(final x in rows)ListTile(
     dense:true,contentPadding:EdgeInsets.zero,
     leading:Icon(x['state']=='done'?Icons.check_circle_outline:
       x['state']=='follow_up'?Icons.flag_outlined:Icons.schedule_outlined),
     title:Text(tt(person(x['recipient_id'].toString())+
       ' · '+status(x['state']?.toString()??'pending'))),
     subtitle:Text(tt([
      if(x['snoozed_until']!=null)'Snoozed until '+when(x['snoozed_until']),
      if(x['state']=='follow_up'&&x['next_alert_at']!=null)
       'Follow-up '+when(x['next_alert_at']),
      if(repeating&&x['open_occurrence_at']!=null)
       'Waiting for an answer since '+when(x['open_occurrence_at']),
      if((x['outcome_note']??'').toString().isNotEmpty)
       x['outcome_note'].toString(),
     ].join('\n'))),
    ),
    if(r['source_kind']!=null||r['reminder_intent']=='love_gesture')
     Align(alignment:AlignmentDirectional.centerStart,
      child:TextButton.icon(onPressed:()=>linked(r),
       icon:const Icon(Icons.link),
       label:Text(tt(r['reminder_intent']=='love_gesture'
        ?'Open A little love':'Open related item')))),
    if(history.isNotEmpty)ExpansionTile(
     title:Text(tt('Outcome history · ')+history.length.toString()),
     children:[for(final event in history)ListTile(
      dense:true,contentPadding:EdgeInsets.zero,
      title:Text(tt(person(event['actor_id'])+' · '+
       ReminderRepeat.actionLabel(event['action']?.toString()??'')+
       (event['actor_id']==null&&event['recipient_id']!=null?
        ' (for '+person(event['recipient_id']).toLowerCase()+')':''))),
      subtitle:Text(tt([
       when(event['recorded_at']),
       if((event['note']??'').toString().isNotEmpty)event['note'].toString(),
       if((event['action']=='snooze'||event['action']=='deferred')&&event['next_alert_at']!=null)
        tt('Until')+' '+when(event['next_alert_at']),
       if(event['action']=='missed'&&event['next_alert_at']!=null)
        'Occurrence of '+when(event['next_alert_at']),
      ].join(' · '))),
     )],
    ),
   ],
  ));
 }
 /// R55: this screen's filter groups (drawn by the shared panel).
 List<FilterGroupSpec> _filterGroups()=>[FilterGroupSpec(id:'show',label:tt('Show'),options:const {'open':'Open','done':'Completed'},selected:showCompleted?'done':'open',defaultValue:'open')];

 @override Widget build(BuildContext context){
  final visible=reminders.where((r)=>
   (showArchived?r['archived_at']!=null:r['archived_at']==null)&&
   (showArchived||completed(r)==showCompleted)&&
   (searchText.isEmpty||
    (r['title']??'').toString().toLowerCase().contains(searchText)||
    (r['details']??'').toString().toLowerCase().contains(searchText))
   ).toList();
  return Scaffold(
   appBar:AppBar(title:Text(tt('Reminders')),actions:[
    RecordListTopActions(
      historyKinds:const ['reminder'],historyTitle:tt('Reminders'),
     showHistory:showArchived,
      onToggleHistory:()=>setState(()=>showArchived=!showArchived),
      groups:_filterGroups(),
      onApply:(v)=>setState((){showCompleted=v['show']=='done';}),
     ),
   ],bottom:filterShowingBar(_filterGroups(),removed:showArchived,onClear:()=>setState((){showArchived=false;showCompleted=false;}))),
   floatingActionButton:space==null&&OneSpaceEnv.isProduction
    ?null:FloatingActionButton.extended(heroTag:'fab-reminders',
    onPressed:busy?null:()=>editor(),icon:const Icon(Icons.add),
    label:Text(tt('Add reminder'))),
   body:RefreshIndicator(onRefresh:load,child:ListView(
    physics:const AlwaysScrollableScrollPhysics(),
    padding:const EdgeInsetsDirectional.fromSTEB(16,16,16,95),children:[
     Text(tt('Remember what matters'),
      style:TextStyle(fontSize:24,fontWeight:FontWeight.bold)),
     const SizedBox(height:6),
     Text(tt('Personal and shared reminders, with separate follow-up '
      'and snooze outcomes for each of you.')),
     const SizedBox(height:10),
     TextField(
      onChanged:(v)=>setState(()=>searchText=v.trim().toLowerCase()),
      decoration:InputDecoration(
       prefixIcon:Icon(Icons.search),
       labelText:tt('Search reminders'),
       hintText:tt('Titles and details'),
       border:OutlineInputBorder())),
     const SizedBox(height:10),
     if(error!=null)Padding(padding:const EdgeInsets.symmetric(vertical:8),
      child:Text(tt(error!),style:TextStyle(
       color:Theme.of(context).colorScheme.error))),
     if(loading)const Padding(padding:EdgeInsets.all(40),
      child:Center(child:CircularProgressIndicator())),
     if(!loading&&space==null&&OneSpaceEnv.isProduction)
      Text(tt('Connect a shared space first.')),
     if(!loading&&visible.isEmpty &&
       (space!=null || !OneSpaceEnv.isProduction))
      Padding(padding:EdgeInsets.all(40),
       child:Center(child:Text(tt('No reminders in this view.')))),
     for(final r in visible)tile(r),
   ])),
  );
 }
}

class ReminderEditorScreen extends StatefulWidget{
 const ReminderEditorScreen({super.key,required this.spaceId,this.existing,
  this.initialTitle='',this.initialDetails='',this.initialDue,this.initialShared=false,
  this.onCreated,this.initialSourceKind,this.initialSourceId});
 /// R66: pre-linked source (e.g. "Remind us" in an Activity).
 final String? initialSourceKind,initialSourceId;
 final String spaceId;
 final Map<String,dynamic>? existing;
 /// R52: pre-filled from shared content ("Items to sort").
 final String initialTitle,initialDetails;
 /// R53 "Create from this": pre-filled due time, shared with both, and a
 /// callback with the new reminder's id so it can be linked to its source.
 final DateTime? initialDue;
 final bool initialShared;
 final Future<void> Function(String id)? onCreated;
 @override State<ReminderEditorScreen> createState()=>_ReminderEditorScreenState();
}
class _ReminderEditorScreenState extends State<ReminderEditorScreen> with FormChangeTracker<ReminderEditorScreen>{
 /// R55: current form values; Save turns on only when they change.
 @override String get signature=>[title.text,details.text,due.toIso8601String(),visibility,audience,urgent,sourceKind,sourceId,repeat.toRule(start:due,timeZone:myZone)].join('|');

 final db=Supabase.instance.client;
 late final TextEditingController title,details;
 late DateTime due;
 late String visibility,audience;
 String? sourceKind,sourceId,error;
 /// R66: "About an item" is picked in two steps — the kind, then the item.
 String? linkType;
 static const linkKinds=['task','calendar','note','occasion','activity','trip'];
 static const linkLabels={'task':'To-do lists','calendar':'Events','note':'Notes',
  'occasion':'Occasions','activity':'Activities','trip':'Trips'};
 static const linkIcons={'task':Icons.checklist,'calendar':Icons.event_outlined,
  'note':Icons.sticky_note_2_outlined,'occasion':Icons.celebration_outlined,
  'activity':Icons.lightbulb_outline,'trip':Icons.flight_takeoff};
 bool saving=false,loadingLinks=true,urgent=false;
 List<Map<String,dynamic>> links=[];
 ReminderRepeat repeat=const ReminderRepeat();
 String myZone='UTC';
 String? partnerZone,partnerName;
 SpacePeople? people;
 /// R57: audience ↔ "Belongs to" in the shared strip.
 MetaValues get meta=>MetaValues(shared:visibility=='shared',
  belongsTo:audience=='both'?null:audience=='me'?people?.me??'me':people?.partnerId??'partner');
 void setMeta(MetaValues v){
  setState((){
   visibility=(OneSpaceEnv.isProduction || widget.spaceId.isNotEmpty) && v.shared
     ?'shared':'private';
   audience=v.belongsTo==null?'both':v.belongsTo==(people?.me??'me')?'me':'partner';
   if(!v.shared)audience='me';
  });
 }
 @override void initState(){
  super.initState();
  final prior=widget.existing;
  title=TextEditingController(text:prior?['title']?.toString()??widget.initialTitle);
  details=TextEditingController(text:prior?['details']?.toString()??widget.initialDetails);
  due=DateTime.tryParse(prior?['due_at']?.toString()??'')?.toLocal()
   ??widget.initialDue??DateTime.now().add(const Duration(hours:1));
  visibility=prior?['visibility']?.toString()??
    ((OneSpaceEnv.isProduction || widget.spaceId.isNotEmpty) &&
      widget.initialShared ?'shared':'private');
  audience=prior?['audience']?.toString()??(widget.initialShared?'both':'me');
  sourceKind=prior?['source_kind']?.toString()??widget.initialSourceKind;
  linkType=sourceKind;
  sourceId=prior?['source_id']?.toString()??widget.initialSourceId;
  repeat=ReminderRepeat.fromRule(prior?['repeat_rule'],start:due);
  urgent=prior?['urgent']==true;
  loadLinks();
  loadZones();
  SpacePeople.load().then((p){if(mounted)setState(()=>people=p);});
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
 Widget repeatSection()=>RepeatControl(value:repeat,start:due,enabled:!saving,
  showTimes:true,onAddTime:addTime,
  footnote:tt('Times follow this phone’s time zone (')+myZone+'), even when the clocks change.',
  onChanged:(r)=>setState(()=>repeat=r));
 @override void dispose(){title.dispose();details.dispose();super.dispose();}
 Future<void> loadLinks()async{
  if (!OneSpaceEnv.isProduction && widget.spaceId.isEmpty) {
    if(mounted)setState((){links=[];loadingLinks=false;});
    return;
  }
  try{
   final lists=await Future.wait([
    db.from('tasks').select('id,title,visibility')
     .eq('space_id',widget.spaceId).isFilter('migrated_to_list',null).eq('status','open').limit(100),
    db.from('space_events').select('id,title,visibility')
     .eq('space_id',widget.spaceId).isFilter('archived_at',null).limit(100),
    db.from('notes').select('id,title,visibility')
     .eq('space_id',widget.spaceId).isFilter('archived_at',null).limit(100),
    db.from('occasion_plans').select('id,title,visibility')
     .eq('space_id',widget.spaceId).isFilter('archived_at',null).limit(100),
    db.from('activities').select('id,title,visibility')
     .eq('space_id',widget.spaceId).isFilter('archived_at',null)
     .not('stage','in','(completed,cancelled)').limit(100),
    db.from('shared_trips').select('id,title,visibility')
     .eq('space_id',widget.spaceId).isFilter('archived_at',null)
     .not('status','in','(completed,cancelled)').limit(100),
   ]);
   if(!mounted)return;
   setState((){
    links=[
     for(var i=0;i<lists.length;i++)
      for(final row in lists[i]){
       'id':row['id'],'title':row['title'],'visibility':row['visibility'],
       'kind':linkKinds[i],
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
  final personal=!OneSpaceEnv.isProduction && visibility=='private'
    && widget.existing==null;
  if(visibility=='shared' && widget.spaceId.isEmpty) {
    setState(()=>error='Connect with a partner before sharing a reminder.');
    return;
  }
  if(personal && sourceKind!=null) {
    setState(()=>error='Linking items to personal reminders is not available yet.');
    return;
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
    final created=await db.from('reminders').insert({
     ...fields,
     if(personal) 'private_space_id':db.auth.currentUser!.id
     else 'space_id':widget.spaceId,
     'visibility':visibility,'audience':audience,
     'source_kind':sourceKind,'source_id':sourceId,
    }).select('id').single();
    // Never insert an account-owned reminder into a shared object's links.
    if (!personal) await widget.onCreated?.call(created['id'].toString());
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
    if(linkType==null||item['kind']==linkType)
    item['kind'].toString()+':'+item['id'].toString():
      item['title'].toString(),
  };
  final selected=sourceKind==null||sourceId==null?null:
   sourceKind!+':'+sourceId!;
  return EditorScaffold(title:editing?tt('Edit reminder'):tt('Add reminder'),
   isNew:!editing,isChanged:()=>changed,isComplete:()=>title.text.trim().isNotEmpty,
   listenTo:[title,details],saving:saving,onSave:save,
   meta:MetaStrip(value:meta,people:people,showDate:false,enabled:!editing,
    onChanged:(v){
     setMeta(v);
     final key=sourceKind==null?null:sourceKind!+':'+sourceId!;
     if(v.shared&&key!=null&&links.any((x)=>x['id']==sourceId&&x['visibility']=='private')){
      setState((){sourceKind=null;sourceId=null;});
     }
    }),
   body:SafeArea(child:ListView(padding:const EdgeInsets.all(18),children:[
    TextField(controller:title,maxLength:160,autofocus:!editing,
     textCapitalization:TextCapitalization.sentences,
     decoration:InputDecoration(labelText:tt('What to remember *'),
      hintText:tt('Call the clinic, take the vitamins…'),border:OutlineInputBorder())),
    DateField(label:repeat.repeats?tt('Starts'):tt('Remind me at'),value:due,withTime:true,required:true,
     first:DateTime.now(),onChanged:(v){if(v!=null)setState(()=>due=v);}),
    if(partnerTimeHint()!=null)Padding(
     padding:const EdgeInsets.only(bottom:12),
     child:Row(children:[
      const Icon(Icons.public,size:18),const SizedBox(width:6),
      Expanded(child:Text(tt(partnerTimeHint()!),style:Theme.of(context).textTheme.bodySmall)),
     ])),
    repeatSection(),
    const SizedBox(height:6),
    if(visibility=='shared'&&audience!='me')Padding(
     padding:const EdgeInsets.only(bottom:14),
     child:Align(alignment:AlignmentDirectional.centerStart,child:OptionChip(
      label:tt('Urgent'),icon:Icons.priority_high,value:urgent,
      help:tt('Alerts even during your partner\'s sleep hours. Without it, alerts wait until they wake up.'),
      onChanged:saving?null:(v)=>setState(()=>urgent=v)))),
    FormSection(tt('More details')),
    TextField(controller:details,maxLength:4000,minLines:2,maxLines:5,
     decoration:InputDecoration(labelText:tt('Details / instructions'),
      border:OutlineInputBorder())),
    if(visibility=='shared' && widget.spaceId.isNotEmpty)Align(
     alignment:AlignmentDirectional.centerStart,
     child:PartnerMentionButton(
      spaceId:widget.spaceId,controller:details,
      enabled:!saving)),
    const SizedBox(height:10),
    if(loadingLinks)const LinearProgressIndicator(),
    if(!editing && (OneSpaceEnv.isProduction || visibility=='shared'))
     ChoiceRow<String>(label:tt('About an item (optional)'),
     options:{for(final k in linkKinds)k:linkLabels[k]!},icons:linkIcons,
     selected:linkType,allowNone:true,
     onSelected:(v)=>setState((){linkType=v;
      if(sourceKind!=v){sourceKind=null;sourceId=null;}})),
    if(!editing&&linkType!=null &&
      (OneSpaceEnv.isProduction || visibility=='shared'))
     ChoicePickerField<String>(label:tt(linkLabels[linkType]!),
     icon:linkIcons[linkType]!,noneLabel:tt('Choose one'),options:options,
     selected:selected!=null&&options.containsKey(selected)?selected:null,
     onSelected:(v)=>setState((){
      if(v==null){sourceKind=null;sourceId=null;}
      else{final parts=v.split(':');sourceKind=parts.first;sourceId=parts.last;}
     }))
    else if(selected!=null&&options[selected]!=null)ListTile(contentPadding:EdgeInsets.zero,
     leading:const Icon(Icons.link),title:Text(tt(options[selected]!))),
    if(error!=null)Padding(padding:const EdgeInsets.symmetric(vertical:10),
     child:Text(tt(error!),style:TextStyle(color:Theme.of(context).colorScheme.error))),
   ])),
  );
 }
}

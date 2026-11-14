import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'task_recurrence_rules.dart';
import 'checklist_schedule.dart';
import 'checklist_readout_sheet.dart';
import '../notes/related_notes_panel.dart';

/// A to-do is a list container; its subitems own the checkboxes.
class TaskChecklistPanel extends StatefulWidget{
 const TaskChecklistPanel({super.key,required this.taskId,
  required this.recurrence,required this.rule,required this.canManage,
  required this.canComplete,this.testItemsStream,this.testChecksStream,
  this.testViewerId,this.listTitle='Checklist'});
 final String taskId,recurrence,listTitle;
 final Map<String,dynamic> rule;
 final bool canManage,canComplete;
 /// In-memory feeds for widget regression tests. Production always uses
 /// the existing RLS-protected Supabase streams.
 final Stream<List<Map<String,dynamic>>>? testItemsStream,testChecksStream;
 final String? testViewerId;
 @override State<TaskChecklistPanel> createState()=>_TaskChecklistPanelState();
}
class _TaskChecklistPanelState extends State<TaskChecklistPanel>{
 SupabaseClient get db=>Supabase.instance.client;
 final input=TextEditingController();
 final inputScroll=ScrollController(keepScrollOffset:false);
 String? get viewerId=>widget.testViewerId??db.auth.currentUser?.id;
 Stream<List<Map<String,dynamic>>>? itemsStream,checksStream;
 bool busy=false,contextLoaded=false,dayOff=false;
 List<int> workDays=const [1,2,3,4,5];
 String? error;
 String? contextDay;
 Timer? _dayBoundary;
 String? get zone=>widget.rule['timezone']?.toString();
 DateTime get localNow=>ChecklistSchedule.localNow(DateTime.now(),zone);
 String get currentDay=>ChecklistSchedule.day(localNow);
 String get cycle=>widget.rule.isEmpty?
  TaskRecurrenceRules.cycle(widget.recurrence,localNow):
  ChecklistSchedule.cycle(widget.recurrence,widget.rule,localNow);
 bool get scheduled=>ChecklistSchedule.occurs(
  widget.recurrence,widget.rule,localNow,
  personalDayOff:dayOff,
  usHoliday:ChecklistSchedule.usFederalHoliday(localNow),
  workDays:workDays);
 @override void initState(){super.initState();listen();_loadContext();_scheduleNextDay();}
 @override void didUpdateWidget(covariant TaskChecklistPanel old){
  super.didUpdateWidget(old);
  if(old.taskId!=widget.taskId||old.recurrence!=widget.recurrence||
    old.rule.toString()!=widget.rule.toString()||
    old.testItemsStream!=widget.testItemsStream||
    old.testChecksStream!=widget.testChecksStream){
   listen();_loadContext();_scheduleNextDay();
  }
 }
 void listen(){
  if(widget.testItemsStream!=null&&widget.testChecksStream!=null){
   itemsStream=widget.testItemsStream;
   checksStream=widget.testChecksStream;
   return;
  }
  try{
   itemsStream=db.from('task_checklist_items').stream(primaryKey:['id'])
    .eq('task_id',widget.taskId).order('created_at').limit(200);
   // Keep the server subscription scoped to the parent checklist.
   // Apply the exact occurrence filter below when rendering. This also
   // avoids relying on multi-filter realtime behavior at widget creation.
   checksStream=db.from('task_checklist_checks').stream(primaryKey:['id'])
    .eq('task_id',widget.taskId).limit(500);
   error=null;
  }catch(_){
   // A stream construction problem must render an explanation, not crash
   // the entire To-do screen during ExpansionTile.initState.
   itemsStream=Stream.value(const <Map<String,dynamic>>[]);
   checksStream=Stream.value(const <Map<String,dynamic>>[]);
   error='Could not connect checklist details. Close and reopen to retry.';
  }
 }
 Future<void> _loadContext()async{
  if(widget.testItemsStream!=null&&widget.testChecksStream!=null){
   if(mounted)setState(()=>contextLoaded=true);
   return;
  }
  final account=db.auth.currentUser?.id;
  if(account==null)return;
  final day=currentDay;
  if(mounted)setState((){
   contextLoaded=false;contextDay=day;dayOff=false;workDays=const [1,2,3,4,5];
  });
  try{
   if(ChecklistSchedule.mode(widget.rule,widget.recurrence)=='workdays'){
    final row=await db.from('profiles').select('work_days')
     .eq('id',account).maybeSingle();
    if(row?['work_days'] is List){
     workDays=(row!['work_days'] as List).whereType<num>().map((x)=>x.toInt()).toList();
    }
   }
   if(widget.rule['skip_personal_days_off']==true){
    final rows=await db.from('personal_days_off').select('id')
      .eq('user_id',account).eq('off_date',day).limit(1);
    dayOff=rows.isNotEmpty;
   }
   if(mounted&&contextDay==day)setState(()=>contextLoaded=true);
  }catch(_){
   // A failed exception check must not silently permit an off-day routine.
   if(mounted&&contextDay==day)setState((){
    error='Cannot check days-off/work schedule right now. Retry when connected.';
    contextLoaded=false;
   });
  }
 }
 void _scheduleNextDay(){
  _dayBoundary?.cancel();
  if(widget.recurrence=='none')return;
  final now=DateTime.now();
  final next=ChecklistSchedule.nextLocalMidnight(now,zone);
  _dayBoundary=Timer(next.difference(now)+const Duration(seconds:1),(){
   if(!mounted)return;
   setState(listen);
   _loadContext();
   _scheduleNextDay();
  });
 }
 @override void dispose(){
  _dayBoundary?.cancel();
  input.dispose();
  inputScroll.dispose();
  super.dispose();
 }
 Future<void> readAloud(List<Map<String,dynamic>> items,
   Map<String,Map<String,dynamic>> myChecks)async{
  // A reading view is never allowed to alter completion status.
  await showModalBottomSheet<void>(context:context,isScrollControlled:true,
   showDragHandle:true,builder:(_)=>FractionallySizedBox(
    heightFactor:.85,
    child:ChecklistReadoutSheet(
     listTitle:widget.listTitle,items:items,ownChecks:myChecks)));
 }
 Future<void> add()async{
  final title=input.text.trim();
  if(title.isEmpty||busy||!widget.canManage)return;
  setState((){busy=true;error=null;});
  try{
   await db.from('task_checklist_items').insert({
    'task_id':widget.taskId,'title':title});
   input.clear();
  }on PostgrestException catch(e){
   if(mounted)setState(()=>error=e.message);
  }catch(_){
   if(mounted)setState(()=>error='Could not add item.');
  }finally{if(mounted)setState(()=>busy=false);}
 }
 Future<void> toggle(Map<String,dynamic> item,bool completed,
   Map<String,dynamic>? current)async{
  if(busy||!widget.canComplete||!contextLoaded||!scheduled)return;
  setState((){busy=true;error=null;});
  try{
   if(current==null){
    try{
     await db.from('task_checklist_checks').insert({
      'item_id':item['id'],'cycle_date':cycle,'completed':completed});
    }on PostgrestException catch(e){
     if(e.code!='23505')rethrow;
     final existing=await db.from('task_checklist_checks')
      .select('id').eq('item_id',item['id']).eq('cycle_date',cycle)
      .eq('user_id',db.auth.currentUser!.id).limit(1);
     if(existing.isNotEmpty)await db.from('task_checklist_checks')
      .update({'completed':completed}).eq('id',existing.first['id']);
    }
   }else{
    await db.from('task_checklist_checks')
     .update({'completed':completed}).eq('id',current['id']);
   }
  }on PostgrestException catch(e){
   if(mounted)setState(()=>error=e.message);
  }catch(_){
   if(mounted)setState(()=>error='Could not update item.');
  }finally{if(mounted)setState(()=>busy=false);}
 }
 Future<void> archive(Map<String,dynamic> item)async{
  if(busy||!widget.canManage)return;
  setState(()=>busy=true);
  try{
   await db.from('task_checklist_items').update({
    'archived_at':DateTime.now().toUtc().toIso8601String()
   }).eq('id',item['id']);
  }catch(_){
   if(mounted)setState(()=>error='Could not remove item.');
  }finally{if(mounted)setState(()=>busy=false);}
 }
 @override Widget build(BuildContext context){
  final colors=Theme.of(context).colorScheme;
  return StreamBuilder<List<Map<String,dynamic>>>(stream:itemsStream,
   builder:(ctx,itemsData){
    if(itemsData.hasError)return const Text('Checklist temporarily unavailable.');
    if(!itemsData.hasData)return const LinearProgressIndicator();
    // A single malformed legacy child should not crash every checklist.
    final items=itemsData.data!.where((i)=>
     i['archived_at']==null &&
     i['id'] is String &&
     i['title'] is String &&
     (i['title'] as String).trim().isNotEmpty).toList();
    return StreamBuilder<List<Map<String,dynamic>>>(stream:checksStream,
     builder:(ctx,checkData){
      final checkMap=<String,Map<String,dynamic>>{
       for(final c in checkData.data??const <Map<String,dynamic>>[])
        if(c['user_id']==viewerId &&
         c['cycle_date']?.toString()==cycle &&
         c['item_id'] is String &&
         c['completed'] is bool &&
         items.any((i)=>i['id']==c['item_id']))
          c['item_id'].toString():c,
      };
      final done=items.where((i)=>
       checkMap[i['id'].toString()]?['completed']==true).length;
      return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
       Row(children:[
        Icon(Icons.checklist_rounded,size:17,color:colors.primary),
        const SizedBox(width:5),
        Expanded(child:Text(done.toString()+' of '+items.length.toString()+' items')),
        IconButton(
         tooltip:'Listen to checklist',
         icon:const Icon(Icons.record_voice_over_outlined),
         onPressed:items.isEmpty?null:()=>readAloud(items,checkMap),
        ),
        if(widget.recurrence!='none')Chip(
         avatar:const Icon(Icons.repeat,size:15),
         label:Text(ChecklistSchedule.mode(widget.rule,widget.recurrence).replaceAll('_',' '))),
       ]),
       if(!contextLoaded)const LinearProgressIndicator(),
       if(contextLoaded&&!scheduled)Text('Not scheduled today ('+currentDay+'). Subtasks remain available to edit.'),
       if(contextLoaded&&scheduled&&widget.recurrence!='none')
        Text('Current occurrence: '+currentDay),
       if(items.isNotEmpty)Text('Your progress · Shared checklists keep each partner\'s ticks separate',
        style:Theme.of(context).textTheme.bodySmall),
       if(items.isNotEmpty)LinearProgressIndicator(
        value:done/items.length,minHeight:5),
       if(checkData.hasError)Text('Checkmarks could not synchronize.',
        style:TextStyle(color:colors.error)),
       for(final item in items)CheckboxListTile(
        dense:true,contentPadding:EdgeInsets.zero,
        value:checkMap[item['id'].toString()]?['completed']==true,
        onChanged:!widget.canComplete||busy||!contextLoaded||!scheduled?null:
         (v)=>toggle(item,v==true,checkMap[item['id'].toString()]),
        title:Text(item['title'].toString(),
         style:TextStyle(decoration:
          checkMap[item['id'].toString()]?['completed']==true?
           TextDecoration.lineThrough:null)),
        secondary:widget.canManage?IconButton(
         tooltip:'Remove item',icon:const Icon(Icons.close,size:18),
         onPressed:busy?null:()=>archive(item)):null),
       if(widget.canManage)Row(children:[
        Expanded(child:TextField(controller:input,
         scrollController:inputScroll,maxLength:240,
         onSubmitted:(_)=>add(),
         decoration:const InputDecoration(
          hintText:'Add subtask',counterText:'',
          prefixIcon:Icon(Icons.add_task_outlined)))),
        IconButton(tooltip:'Add subtask',
         onPressed:busy?null:add,icon:const Icon(Icons.add_circle_outline)),
       ]),
       if(items.isEmpty)const Text('No subitems yet. Enter a subtask below, then tap +.'),
       if(items.length<itemsData.data!.where((i)=>i['archived_at']==null).length)
        Text('Some older subitems could not be displayed. They are still saved.',
         style:TextStyle(color:colors.error)),
       if(error!=null)Text(error!,style:TextStyle(color:colors.error)),
       const SizedBox(height:10),
       RelatedNotesPanel(sourceKind:'task',sourceId:widget.taskId),
      ]);
     });
   });
 }
}

import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'task_recurrence_rules.dart';

/// A to-do is a list container; its subitems own the checkboxes.
class TaskChecklistPanel extends StatefulWidget{
 const TaskChecklistPanel({super.key,required this.taskId,
  required this.recurrence,required this.canEdit});
 final String taskId,recurrence;
 final bool canEdit;
 @override State<TaskChecklistPanel> createState()=>_TaskChecklistPanelState();
}
class _TaskChecklistPanelState extends State<TaskChecklistPanel>{
 final db=Supabase.instance.client;
 final input=TextEditingController();
 Stream<List<Map<String,dynamic>>>? itemsStream,checksStream;
 bool busy=false;
 String? error;
 String get cycle=>TaskRecurrenceRules.cycle(widget.recurrence,DateTime.now());
 @override void initState(){super.initState();listen();}
 @override void didUpdateWidget(covariant TaskChecklistPanel old){
  super.didUpdateWidget(old);
  if(old.taskId!=widget.taskId||old.recurrence!=widget.recurrence)listen();
 }
 void listen(){
  itemsStream=db.from('task_checklist_items').stream(primaryKey:['id'])
   .eq('task_id',widget.taskId).order('created_at').limit(200);
  checksStream=db.from('task_checklist_checks').stream(primaryKey:['id'])
   .eq('cycle_date',cycle).limit(500);
 }
 @override void dispose(){input.dispose();super.dispose();}
 Future<void> add()async{
  final title=input.text.trim();
  if(title.isEmpty||busy||!widget.canEdit)return;
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
  if(busy||!widget.canEdit)return;
  setState((){busy=true;error=null;});
  try{
   if(current==null){
    try{
     await db.from('task_checklist_checks').insert({
      'item_id':item['id'],'cycle_date':cycle,'completed':completed});
    }on PostgrestException catch(e){
     if(e.code!='23505')rethrow;
     final existing=await db.from('task_checklist_checks')
      .select('id').eq('item_id',item['id']).eq('cycle_date',cycle).limit(1);
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
  if(busy||!widget.canEdit)return;
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
    final items=itemsData.data!.where((i)=>i['archived_at']==null).toList();
    return StreamBuilder<List<Map<String,dynamic>>>(stream:checksStream,
     builder:(ctx,checkData){
      final checkMap=<String,Map<String,dynamic>>{
       for(final c in checkData.data??const <Map<String,dynamic>>[])
        if(items.any((i)=>i['id']==c['item_id']))
         c['item_id'].toString():c,
      };
      final done=items.where((i)=>
       checkMap[i['id'].toString()]?['completed']==true).length;
      return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
       Row(children:[
        Icon(Icons.checklist_rounded,size:17,color:colors.primary),
        const SizedBox(width:5),
        Expanded(child:Text(done.toString()+' of '+items.length.toString()+' items')),
        if(widget.recurrence!='none')Chip(
         avatar:const Icon(Icons.repeat,size:15),
         label:Text(widget.recurrence)),
       ]),
       if(items.isNotEmpty)LinearProgressIndicator(
        value:done/items.length,minHeight:5),
       if(checkData.hasError)Text('Checkmarks could not synchronize.',
        style:TextStyle(color:colors.error)),
       for(final item in items)CheckboxListTile(
        dense:true,contentPadding:EdgeInsets.zero,
        value:checkMap[item['id'].toString()]?['completed']==true,
        onChanged:!widget.canEdit||busy?null:
         (v)=>toggle(item,v==true,checkMap[item['id'].toString()]),
        title:Text(item['title'].toString(),
         style:TextStyle(decoration:
          checkMap[item['id'].toString()]?['completed']==true?
           TextDecoration.lineThrough:null)),
        secondary:widget.canEdit?IconButton(
         tooltip:'Remove item',icon:const Icon(Icons.close,size:18),
         onPressed:busy?null:()=>archive(item)):null),
       if(widget.canEdit)Row(children:[
        Expanded(child:TextField(controller:input,maxLength:240,
         onSubmitted:(_)=>add(),
         decoration:const InputDecoration(
          hintText:'Add item',counterText:'',
          prefixIcon:Icon(Icons.add_task_outlined)))),
        IconButton(tooltip:'Add checklist item',
         onPressed:busy?null:add,icon:const Icon(Icons.add_circle_outline)),
       ]),
       if(items.isEmpty)const Text('Add the first checklist item.'),
       if(error!=null)Text(error!,style:TextStyle(color:colors.error)),
      ]);
     });
   });
 }
}

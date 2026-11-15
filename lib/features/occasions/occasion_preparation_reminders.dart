import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../reminders/reminders_screen.dart';
import 'occasion_preparation_rules.dart';

/// Makes the next four occasion preparation milestones actionable through
/// the existing Reminder system; never creates reminders automatically.
class OccasionPreparationReminders extends StatefulWidget{
 const OccasionPreparationReminders({super.key,required this.plan});
 final Map<String,dynamic> plan;
 @override State<OccasionPreparationReminders> createState()=>
  _OccasionPreparationRemindersState();
}

class _OccasionPreparationRemindersState
 extends State<OccasionPreparationReminders>{
 final db=Supabase.instance.client;
 late Stream<List<Map<String,dynamic>>> _stream;
 bool busy=false;
 String? error;
 @override void initState(){super.initState();_connect();}
 @override void didUpdateWidget(covariant OccasionPreparationReminders old){
  super.didUpdateWidget(old);
  if(old.plan['id']!=widget.plan['id'])_connect();
 }
 void _connect(){
  _stream=db.from('reminders').stream(primaryKey:['id'])
    .eq('source_id',widget.plan['id'].toString())
    .order('due_at',ascending:true).limit(200);
 }
 String formatted(DateTime date){
  final hour=date.hour%12==0?12:date.hour%12;
  final minute=date.minute.toString().padLeft(2,'0');
  return OccasionPreparationRules.dateOnly(date)+' · '+
   hour.toString()+':'+minute+(date.hour>=12?' PM':' AM');
 }
 Future<void> _open(String id)async{
  await Navigator.of(context).push<void>(MaterialPageRoute(
   builder:(_)=>RemindersScreen(initialReminderId:id)));
 }
 Future<void> _create(OccasionPreparationStep step)async{
  if(busy)return;
  final space=widget.plan['space_id']?.toString();
  final source=widget.plan['id']?.toString();
  if(space==null||source==null)return;
  final now=DateTime.now();
  var due=OccasionPreparationRules.nextFutureTime(step.suggestedDate,now);
  bool shareWithBoth=false;
  final sharedPlan=widget.plan['visibility']=='shared';
  final approved=await showModalBottomSheet<bool>(
   context:context,showDragHandle:true,isScrollControlled:true,
   builder:(ctx)=>StatefulBuilder(builder:(ctx,update)=>SafeArea(
    child:Padding(padding:EdgeInsets.fromLTRB(
     18,8,18,MediaQuery.viewInsetsOf(ctx).bottom+22),
     child:Column(mainAxisSize:MainAxisSize.min,
      crossAxisAlignment:CrossAxisAlignment.start,children:[
       Text('Set preparation reminder',
        style:Theme.of(ctx).textTheme.titleLarge),
       const SizedBox(height:8),
       Text(step.title,style:Theme.of(ctx).textTheme.titleMedium),
       const SizedBox(height:4),
       Text(step.description),
       const SizedBox(height:8),
       Text('Suggested: '+step.dateLabel,
        style:Theme.of(ctx).textTheme.bodySmall),
       if(due.year!=step.suggestedDate.year||
          due.month!=step.suggestedDate.month||
          due.day!=step.suggestedDate.day)
        const Padding(padding:EdgeInsets.symmetric(vertical:6),
         child:Text('The suggested date has passed, so a future date was selected. You can change it.')),
       ListTile(
        contentPadding:EdgeInsets.zero,
        leading:const Icon(Icons.event_outlined),
        title:const Text('Notify me on'),
        subtitle:Text(formatted(due)),
        trailing:const Icon(Icons.edit_calendar_outlined),
        onTap:()async{
         final today=DateTime.now();
         final selected=await showDatePicker(context:ctx,
          initialDate:due.isBefore(today)?today:due,
          firstDate:DateTime(today.year,today.month,today.day),
          lastDate:DateTime(2100));
         if(selected==null||!ctx.mounted)return;
         final clock=await showTimePicker(context:ctx,
          initialTime:TimeOfDay(hour:due.hour,minute:due.minute));
         if(clock!=null)update(()=>due=DateTime(selected.year,
          selected.month,selected.day,clock.hour,clock.minute));
        },
       ),
       if(sharedPlan)SwitchListTile(
        contentPadding:EdgeInsets.zero,
        title:const Text('Remind both of us'),
        subtitle:const Text('Off by default. Keep a surprise private until you choose to share it.'),
        value:shareWithBoth,
        onChanged:(v)=>update(()=>shareWithBoth=v)),
       if(!sharedPlan)const Text('Private occasion · reminder visible only to you.'),
       const SizedBox(height:12),
       Row(mainAxisAlignment:MainAxisAlignment.end,children:[
        TextButton(onPressed:()=>Navigator.pop(ctx,false),
         child:const Text('Cancel')),
        const SizedBox(width:10),
        FilledButton.icon(onPressed:()=>Navigator.pop(ctx,true),
         icon:const Icon(Icons.alarm_add_outlined),
         label:const Text('Create reminder')),
       ]),
      ]),
    ))));
  if(approved!=true||!mounted)return;
  if(!due.isAfter(DateTime.now().add(const Duration(minutes:1)))){
   ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
    content:Text('Choose a future date and time for this reminder.')));
   return;
  }
  setState((){busy=true;error=null;});
  try{
   await db.from('reminders').insert({
    'space_id':space,'title':step.title,
    'details':step.description,'due_at':due.toUtc().toIso8601String(),
    'visibility':shareWithBoth?'shared':'private',
    'audience':shareWithBoth?'both':'me',
    'source_kind':'occasion','source_id':source,
    'planning_phase':step.phase,
    'occasion_instance_on':OccasionPreparationRules.dateOnly(step.occasionDate),
   });
   if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
    content:Text('Preparation reminder saved. You can manage it in Remember → Reminders.')));
  }on PostgrestException catch(e){
   if(mounted)setState(()=>error=e.code=='23505'
    ?'You already have an active reminder for this step. Open it to edit or remove it.'
    :e.message);
  }catch(_){
   if(mounted)setState(()=>error='Could not create the reminder. Try again.');
  }finally{if(mounted)setState(()=>busy=false);}
 }
 @override Widget build(BuildContext context){
  final plan=widget.plan;
  final steps=OccasionPreparationRules.steps(
   plan:plan,today:DateTime.now());
  if(steps.isEmpty||plan['archived_at']!=null||
   plan['status']=='cancelled'||plan['status']=='celebrated'){
   return const SizedBox.shrink();
  }
  final colors=Theme.of(context).colorScheme;
  final instance=OccasionPreparationRules.dateOnly(steps.first.occasionDate);
  return StreamBuilder<List<Map<String,dynamic>>>(stream:_stream,
   builder:(context,snapshot){
    final rows=(snapshot.data??const <Map<String,dynamic>>[]).where(
     (r)=>r['source_kind']=='occasion'&&
      r['occasion_instance_on']==instance&&r['archived_at']==null).toList();
    final me=db.auth.currentUser?.id;
    return Card(elevation:0,child:Padding(
     padding:const EdgeInsets.all(14),child:Column(
      crossAxisAlignment:CrossAxisAlignment.start,children:[
       Row(children:[
        Icon(Icons.event_repeat_outlined,color:colors.primary),
        const SizedBox(width:9),
        Expanded(child:Text('Preparation reminders',
         style:Theme.of(context).textTheme.titleLarge)),
       ]),
       const SizedBox(height:6),
       const Text('Turn your plan into reminders at the right time. Nothing is scheduled automatically.'),
       if(snapshot.connectionState==ConnectionState.waiting)
        const LinearProgressIndicator(),
       if(snapshot.hasError)Text('Reminder status is unavailable. Check again when connected.',
        style:TextStyle(color:colors.error)),
       if(error!=null)Text(error!,
        style:TextStyle(color:colors.error)),
       const SizedBox(height:8),
       for(final step in steps)Builder(builder:(ctx){
        final existingId=OccasionPreparationRules.activeForMe(
         rows,step.phase,instance,me);
        return ListTile(contentPadding:EdgeInsets.zero,
         leading:Icon(existingId==null?
          Icons.radio_button_unchecked:Icons.check_circle_outline,
          color:existingId==null?null:colors.primary),
         title:Text(step.title),
         subtitle:Text(existingId!=null?
          'Reminder already saved · Tap to manage it':
          'Suggested '+step.dateLabel+' · '+step.description,
          maxLines:2,overflow:TextOverflow.ellipsis),
         trailing:Icon(existingId==null?
          Icons.add_alarm_outlined:Icons.chevron_right),
         onTap:busy||snapshot.hasError||!snapshot.hasData?null:
          ()=>existingId==null?_create(step):_open(existingId),
        );
       }),
       const SizedBox(height:5),
       Text('Your private reminders stay private, even when the occasion is shared.',
        style:Theme.of(context).textTheme.bodySmall),
      ]),
    ));
   });
 }
}

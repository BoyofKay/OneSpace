import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/current_space_cache.dart';
import '../calendar/calendar_rules.dart';

/// Workdays off are shared calendar dates; optional local sleep overrides
/// apply only to the specified night-before and morning-of.
class PersonalDaysOffScreen extends StatefulWidget{
 const PersonalDaysOffScreen({super.key});
 @override State<PersonalDaysOffScreen> createState()=>_PersonalDaysOffScreenState();
}
class _PersonalDaysOffScreenState extends State<PersonalDaysOffScreen>{
 final db=Supabase.instance.client;
 List<Map<String,dynamic>> days=const [];
 String? space,error;
 bool busy=true;
 @override void initState(){super.initState();_load();}
 Future<void> _load() async{
   try{
     final id=await CurrentSpaceCache.instance.get();
     if(id==null)throw StateError('Please connect your shared space.');
     final rows=await db.from('personal_days_off')
       .select('id,off_date,label,night_before_sleep_at,off_day_wake_at')
       .eq('space_id',id).eq('user_id',db.auth.currentUser!.id)
       .order('off_date',ascending:false).limit(150);
     if(mounted)setState((){
       space=id;days=rows;error=null;busy=false;
     });
   }catch(_){
     if(mounted)setState((){
       error='Could not load days off. Check your connection.';
       busy=false;
     });
   }
 }
 Future<void> _edit([Map<String,dynamic>? existing])async{
   if(space==null)return;
   var date=DateTime.tryParse(existing?['off_date']?.toString()??'')??
     DateTime.now();
   final label=TextEditingController(text:existing?['label']?.toString()??'Day off');
   try{
     final result=await showDialog<bool>(context:context,
       builder:(ctx)=>StatefulBuilder(builder:(ctx,update)=>AlertDialog(
         title:Text(existing==null?'Add new day off':'Edit day off'),
         content:SingleChildScrollView(child:Column(
           mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,
           children:[
             ListTile(contentPadding:EdgeInsets.zero,
               leading:const Icon(Icons.event_outlined),
               title:Text(CalendarRules.sqlDate(date)),
               subtitle:const Text('Day off date'),
               onTap:()async{
                 final picked=await showDatePicker(context:ctx,
                   initialDate:date,
                   firstDate:DateTime(2020),lastDate:DateTime(2100));
                 if(picked!=null)update(()=>date=picked);
               }),
             TextField(controller:label,maxLength:120,
               decoration:const InputDecoration(labelText:'Name or reason (optional)')),
             const Text('This date appears on both calendars. '
               'Automatic gestures respect the normal working and sleep schedule.'),
           ])),
         actions:[
           TextButton(onPressed:()=>Navigator.pop(ctx,false),
             child:const Text('Cancel')),
           FilledButton(onPressed:()=>Navigator.pop(ctx,true),
             child:const Text('Save day off')),
         ],
       )));
     if(result!=true||!mounted)return;
     setState(()=>busy=true);
     final values=<String,dynamic>{
       'space_id':space,'user_id':db.auth.currentUser!.id,
       'off_date':CalendarRules.sqlDate(date),
       'label':label.text.trim().isEmpty?'Day off':label.text.trim(),
     };
     if(existing==null){
       await db.from('personal_days_off').insert(values);
     }else{
       await db.from('personal_days_off').update({
         'off_date':CalendarRules.sqlDate(date),
         'label':values['label'],
       }).eq('id',existing['id'].toString())
         .eq('user_id',db.auth.currentUser!.id);
     }
     await _load();
   }on PostgrestException catch(e){
     if(mounted)setState((){
       busy=false;error=e.message;
     });
   }catch(_){
     if(mounted)setState((){
       busy=false;error='Could not save this day off.';
     });
   }finally{label.dispose();}
 }
 Future<void> _remove(Map<String,dynamic> row)async{
   final yes=await showDialog<bool>(context:context,builder:(ctx)=>
     AlertDialog(title:const Text('Remove this day off?'),
       content:const Text('Your usual schedule will apply again.'),
       actions:[
         TextButton(onPressed:()=>Navigator.pop(ctx,false),
           child:const Text('Keep')),
         FilledButton(onPressed:()=>Navigator.pop(ctx,true),
           child:const Text('Remove')),
       ]));
   if(yes!=true)return;
   try{
     await db.from('personal_days_off').delete()
       .eq('id',row['id'].toString())
       .eq('user_id',db.auth.currentUser!.id);
     await _load();
   }catch(_){
     if(mounted)setState(()=>error='Could not remove day off.');
   }
 }
 @override Widget build(BuildContext context)=>Scaffold(
   appBar:AppBar(title:const Text('My days off')),
   floatingActionButton:FloatingActionButton.extended(
     onPressed:busy?null:()=>_edit(),
     icon:const Icon(Icons.add),
     label:const Text('Day off')),
   body:SafeArea(child:ListView(padding:const EdgeInsets.all(18),children:[
     const Text('Exceptions to my usual working days',
       style:TextStyle(fontSize:18,fontWeight:FontWeight.w600)),
     const SizedBox(height:6),
     const Text('Days off appear on our shared calendar and skip the after-work ritual. Your normal sleep and notification schedule remains in Settings.'),
     if(error!=null)Text(error!,
       style:TextStyle(color:Theme.of(context).colorScheme.error)),
     if(busy)const Center(child:CircularProgressIndicator()),
     if(!busy&&days.isEmpty)const Padding(padding:EdgeInsets.all(25),
       child:Text('No days off added. Tap Day off to create one.')),
     for(final day in days)Card(elevation:0,child:ListTile(
       leading:const Icon(Icons.event_available_outlined),
       title:Text(day['label']?.toString()??'Day off'),
       subtitle:Text([
         day['off_date'].toString(),
       ].join(' · ')),
       onTap:()=>_edit(day),
       trailing:IconButton(
         tooltip:'Remove day off',icon:const Icon(Icons.delete_outline),
         onPressed:()=>_remove(day)),
     )),
     const SizedBox(height:90),
   ])),
 );
}

import '../../core/editor_scaffold.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/current_space_cache.dart';
import '../calendar/calendar_rules.dart';
import 'package:onespace/l10n/phrases.dart';

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
   final result=await Navigator.of(context).push<(DateTime,String)>(MaterialPageRoute(
     builder:(_)=>DayOffEditorPage(date:date,label:existing?['label']?.toString()??'',
       isNew:existing==null)));
   try{
     if(result==null||!mounted)return;
     date=result.$1;
     final label=result.$2;
     setState(()=>busy=true);
     final values=<String,dynamic>{
       'space_id':space,'user_id':db.auth.currentUser!.id,
       'off_date':CalendarRules.sqlDate(date),
       'label':label.isEmpty?'Day off':label,
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
   }
 }
 Future<void> _remove(Map<String,dynamic> row)async{
   final yes=await showDialog<bool>(context:context,builder:(ctx)=>
     AlertDialog(title:Text(tt('Remove this day off?')),
       content:Text(tt('Your usual schedule will apply again.')),
       actions:[
         TextButton(onPressed:()=>Navigator.pop(ctx,false),
           child:Text(tt('Keep'))),
         FilledButton(onPressed:()=>Navigator.pop(ctx,true),
           child:Text(tt('Remove'))),
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
   appBar:AppBar(title:Text(tt('My days off'))),
   floatingActionButton:FloatingActionButton.extended(heroTag:'fab-personal-days-off',
     onPressed:busy?null:()=>_edit(),
     icon:const Icon(Icons.add),
     label:Text(tt('Day off'))),
   body:SafeArea(child:ListView(padding:const EdgeInsets.all(18),children:[
     Text(tt('Exceptions to my usual working days'),
       style:TextStyle(fontSize:18,fontWeight:FontWeight.w600)),
     const SizedBox(height:6),
     Text(tt('Days off appear on our shared calendar and skip the after-work ritual. Your normal sleep and notification schedule remains in Settings.')),
     if(error!=null)Text(tt(error!),
       style:TextStyle(color:Theme.of(context).colorScheme.error)),
     if(busy)const Center(child:CircularProgressIndicator()),
     if(!busy&&days.isEmpty)Padding(padding:EdgeInsets.all(25),
       child:Text(tt('No days off added. Tap Day off to create one.'))),
     for(final day in days)Card(elevation:0,child:ListTile(
       leading:const Icon(Icons.event_available_outlined),
       title:Text(tt(day['label']?.toString()??'Day off')),
       subtitle:Text(tt([
         day['off_date'].toString(),
       ].join(' · '))),
       onTap:()=>_edit(day),
       trailing:IconButton(
         tooltip:tt('Remove day off'),icon:const Icon(Icons.delete_outline),
         onPressed:()=>_remove(day)),
     )),
     const SizedBox(height:90),
   ])),
 );
}


/// R56: add/edit a day off as a page (Cancel/Save pinned at the bottom).
class DayOffEditorPage extends StatefulWidget{
 const DayOffEditorPage({super.key,required this.date,required this.label,this.isNew=false});
 final DateTime date;
 final String label;
 final bool isNew;
 @override State<DayOffEditorPage> createState()=>_DayOffEditorPageState();
}
class _DayOffEditorPageState extends State<DayOffEditorPage>{
 late DateTime date=widget.date;
 late final label=TextEditingController(text:widget.label);
 @override void dispose(){label.dispose();super.dispose();}
 @override Widget build(BuildContext context)=>EditorScaffold(
   title:widget.isNew?tt('Add day off'):tt('Edit day off'),isNew:widget.isNew,
   isChanged:()=>label.text!=widget.label||!DateUtils.isSameDay(date,widget.date),
   isComplete:()=>true,listenTo:[label],saveLabel:tt('Save day off'),
   onSave:()=>Navigator.pop(context,(date,label.text.trim())),
   body:ListView(padding:const EdgeInsets.all(18),children:[
     Card(elevation:0,child:ListTile(
       leading:const Icon(Icons.event_outlined),
       title:Text(tt(MaterialLocalizations.of(context).formatFullDate(date))),
       subtitle:Text(tt(requiredLabel(tt('Date')))),
       trailing:const Icon(Icons.edit_calendar_outlined),
       onTap:()async{
         final picked=await showDatePicker(context:context,initialDate:date,
           firstDate:DateTime(2020),lastDate:DateTime(2100));
         if(picked!=null)setState(()=>date=picked);
       })),
     const SizedBox(height:12),
     TextField(controller:label,maxLength:120,
       decoration:InputDecoration(labelText:tt('Name or reason (optional)'),
         border:OutlineInputBorder())),
     Text(tt('This date appears on both calendars.'),
       style:Theme.of(context).textTheme.bodySmall),
   ]));
}

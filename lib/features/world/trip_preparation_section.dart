import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../plans/plans_screen.dart';
import 'package:onespace/l10n/phrases.dart';

/// Use the unified Remember checklists instead of creating a second
/// trip-specific checklist system or overwriting recurring personal routines.
///
/// R67: the suggested checklists moved to the trip's ⋮ menu
/// ([TripPreparationSection.addChecklist]); this section only lists the
/// checklists already made for the trip, and hides itself when there are none.
class TripPreparationSection extends StatefulWidget {
 const TripPreparationSection({super.key,required this.tripId});
 final String tripId;

 static const templates=<String,(String,IconData)>{
  'travel_basics':('Travel essentials',Icons.luggage_outlined),
  'leaving_home':('Leaving home',Icons.home_outlined),
  'with_baby':('Traveling with baby',Icons.child_care_outlined),
  'with_pets':('Traveling with pets',Icons.pets_outlined),
 };

 /// ⋮ › Add a travel checklist: pick a ready-made list, create it in
 /// Remember (linked to the trip) and open it.
 static Future<void> addChecklist(BuildContext context,String tripId)async{
  final db=Supabase.instance.client;
  List<String> made=const [];
  try{
   final rows=await db.from('tasks').select('trip_template_key').eq('trip_id',tripId);
   made=[for(final r in rows)if(r['trip_template_key']!=null)r['trip_template_key'].toString()];
  }catch(_){}
  if(!context.mounted)return;
  final key=await showModalBottomSheet<String>(context:context,showDragHandle:true,
   builder:(ctx)=>SafeArea(child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
    Padding(padding:const EdgeInsets.fromLTRB(20,0,20,8),child:Text(tt('Add a travel checklist'),
     style:Theme.of(ctx).textTheme.titleMedium)),
    for(final t in templates.entries)ListTile(
     leading:Icon(t.value.$2),title:Text(tt(t.value.$1)),
     subtitle:made.contains(t.key)?Text(tt('Already added')):null,
     enabled:!made.contains(t.key),
     onTap:()=>Navigator.pop(ctx,t.key)),
    const SizedBox(height:8),
   ]))));
  if(key==null||!context.mounted)return;
  final messenger=ScaffoldMessenger.of(context);
  final nav=Navigator.of(context);
  try{
   final id=await db.rpc('create_trip_preparation_checklist',
    params:{'p_trip_id':tripId,'p_template':key});
   nav.push(MaterialPageRoute<void>(builder:(_)=>PlansScreen(focusTaskId:id.toString())));
  }on PostgrestException catch(e){
   messenger.showSnackBar(SnackBar(content:Text(e.message)));
  }catch(_){
   messenger.showSnackBar(SnackBar(content:Text(tt('Could not create a travel checklist.'))));
  }
 }

 @override State<TripPreparationSection> createState()=>_TripPreparationState();
}
class _TripPreparationState extends State<TripPreparationSection>{
 final db=Supabase.instance.client;
 late Stream<List<Map<String,dynamic>>> linked;
 @override void initState(){super.initState();linked=_stream();}
 Stream<List<Map<String,dynamic>>> _stream()=>db.from('tasks')
  .stream(primaryKey:['id']).eq('trip_id',widget.tripId)
  .order('created_at');
 @override void didUpdateWidget(covariant TripPreparationSection old){
  super.didUpdateWidget(old);
  if(old.tripId!=widget.tripId)linked=_stream();
 }
 void open(String taskId){
  Navigator.of(context).push(MaterialPageRoute<void>(
   builder:(_)=>PlansScreen(focusTaskId:taskId)));
 }
 @override Widget build(BuildContext context)=>
 StreamBuilder<List<Map<String,dynamic>>>(
  stream:linked,builder:(context,snapshot){
   final active=List<Map<String,dynamic>>.from(snapshot.data??const [])
    .where((e)=>e['status']!='cancelled').toList();
   if(active.isEmpty)return const SizedBox.shrink();
   return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    const Divider(height:30),
    Text(tt('Travel checklists'),style:Theme.of(context).textTheme.titleLarge),
    const SizedBox(height:6),
    for(final row in active)Card(elevation:0,child:ListTile(
     leading:Icon(row['status']=='completed'?Icons.task_alt:Icons.checklist_outlined),
     title:Text(tt(row['title'].toString())),
     subtitle:Text(tt('In To-do lists')),
     trailing:const Icon(Icons.chevron_right),
     onTap:()=>open(row['id'].toString()))),
   ]);
  });
}

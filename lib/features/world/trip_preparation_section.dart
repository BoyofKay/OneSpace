import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../plans/plans_screen.dart';

/// Use the unified Remember checklists instead of creating a second
/// trip-specific checklist system or overwriting recurring personal routines.
class TripPreparationSection extends StatefulWidget {
 const TripPreparationSection({super.key,required this.tripId});
 final String tripId;
 @override State<TripPreparationSection> createState()=>_TripPreparationState();
}
class _TripPreparationState extends State<TripPreparationSection>{
 final db=Supabase.instance.client;
 late Stream<List<Map<String,dynamic>>> linked;
 bool busy=false;
 String? error;
 static const templates=<String,(String,IconData)>{
  'travel_basics':('Travel essentials',Icons.luggage_outlined),
  'leaving_home':('Leaving home',Icons.home_outlined),
  'with_baby':('Traveling with baby',Icons.child_care_outlined),
  'with_pets':('Traveling with pets',Icons.pets_outlined),
 };
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
 Future<void> create(String key)async{
  if(busy)return;
  setState((){busy=true;error=null;});
  try{
   final id=await db.rpc('create_trip_preparation_checklist',
    params:{'p_trip_id':widget.tripId,'p_template':key});
   if(mounted)open(id.toString());
  }on PostgrestException catch(e){
   if(mounted)setState(()=>error=e.message);
  }catch(_){
   if(mounted)setState(()=>error='Could not create a travel checklist.');
  }finally{if(mounted)setState(()=>busy=false);}
 }
 @override Widget build(BuildContext context)=>
 StreamBuilder<List<Map<String,dynamic>>>(
  stream:linked,builder:(context,snapshot){
   final saved=List<Map<String,dynamic>>.from(snapshot.data??const []);
   final active=saved.where((e)=>e['status']!='cancelled').toList();
   return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Text('Travel-ready checklists',style:Theme.of(context).textTheme.titleLarge),
    const SizedBox(height:4),
    const Text('Generate checklists in Remember. Edit every item and tick your own progress independently.'),
    const SizedBox(height:10),
    for(final row in active)Card(child:ListTile(
     leading:const Icon(Icons.checklist_outlined),
     title:Text(row['title'].toString()),
     subtitle:Text('Stored in To-do and Checklists · '+row['status'].toString()),
     trailing:const Icon(Icons.open_in_new),
     onTap:()=>open(row['id'].toString()))),
    if(snapshot.hasError)const Text('Linked checklists temporarily unavailable.'),
    if(!snapshot.hasData)const LinearProgressIndicator(),
    const SizedBox(height:8),
    Wrap(spacing:8,runSpacing:7,children:[
     for(final t in templates.entries)
      OutlinedButton.icon(
       icon:Icon(t.value.$2),
       label:Text(t.value.$1),
       onPressed:busy||saved.any((e)=>e['trip_template_key']==t.key)?null:
        ()=>create(t.key)),
    ]),
    if(error!=null)Text(error!,style:TextStyle(
     color:Theme.of(context).colorScheme.error)),
    if(busy)const LinearProgressIndicator(),
   ]);
  });
}

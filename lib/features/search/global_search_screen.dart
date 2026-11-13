import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../coordinate/activity_detail_screen.dart';
import '../calendar/calendar_screen.dart';
import '../notes/notes_screen.dart';
import '../plans/plans_screen.dart';
import '../connect/couple_letters_screen.dart';
import '../connect/shared_experiences_screen.dart';
import '../world/trips_screen.dart';
import '../../core/current_space_cache.dart';

/// A single RLS-filtered search surface. No cross-space indexing or copying.
class GlobalSearchScreen extends StatefulWidget {
  const GlobalSearchScreen({super.key});
  @override State<GlobalSearchScreen> createState()=>_GlobalSearchScreenState();
}
class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
 final db=Supabase.instance.client;
 final query=TextEditingController();
 Timer? debounce;
 int version=0;
 bool busy=false;
 String? error;
 List<_Hit> hits=[];
 @override void dispose() {
   debounce?.cancel(); query.dispose(); version++; super.dispose();
 }
 Future<void> search(String value) async {
   final request=++version;
   final term=value.trim();
   if(term.length<2){
     if(mounted)setState((){hits=[];busy=false;error=null;});
     return;
   }
   setState((){busy=true;error=null;});
   try{
     final id=await CurrentSpaceCache.instance.get();
     if(id==null)throw StateError('Connect your shared space first');
     final escaped=term.replaceAll('%',r'\%').replaceAll('_',r'\_');
     final pattern='%$escaped%';
     final groups=await Future.wait([
       db.from('activities').select('id,title,updated_at').eq('space_id',id)
         .ilike('title',pattern).order('updated_at',ascending:false).limit(30),
       db.from('space_events').select('id,title,event_date').eq('space_id',id)
         .ilike('title',pattern).order('event_date').limit(30),
       db.from('tasks').select('id,title,created_at').eq('space_id',id)
         .ilike('title',pattern).limit(30),
       db.from('notes').select('id,title,updated_at').eq('space_id',id)
         .ilike('title',pattern).limit(30),
       db.from('couple_letters').select('id,title,created_at').eq('space_id',id)
         .eq('status','sent').ilike('title',pattern).limit(30),
       db.from('activity_components').select('id,activity_id,label')
         .eq('kind','tag').ilike('label',pattern).limit(30),
       db.from('shared_trips').select('id,title').eq('space_id',id)
         .ilike('title',pattern).limit(30),
       db.from('shared_experiences').select('id,title').eq('space_id',id)
         .ilike('title',pattern).limit(30),
       db.from('trip_items').select('id,trip_id,title')
         .ilike('title',pattern).limit(30),
       db.from('trip_attachments').select('id,trip_id,title')
         .ilike('title',pattern).limit(30),
     ]);
     if(!mounted||request!=version)return;
     final types=['Activity','Calendar','To-do','Note','Letter','Tag','Trip','Experience','Trip item','Travel document'];
     final output=<_Hit>[];
     for(var n=0;n<groups.length;n++){
       for(final row in groups[n]){
         output.add(_Hit(types[n],
           (n==5?'#':'')+(row[n==5?'label':'title']?.toString()??''),
           row[n==5?'activity_id':(n==8||n==9)?'trip_id':'id']?.toString()??''));
       }
     }
     setState((){hits=output;busy=false;});
   }catch(_){
     if(mounted&&request==version){setState(() {
       busy=false;error='Search could not finish. Please try again.';
     });}
   }
 }
 void openHit(_Hit hit) {
   Widget target;
   switch(hit.kind){
     case 'Activity':target=ActivityScreen(id:hit.id);break;
     case 'Tag':target=ActivityScreen(id:hit.id);break;
     case 'Calendar':target=CalendarScreen(initialEventId:hit.id);break;
     case 'To-do':target=const PlansScreen();break;
     case 'Note':target=NotesScreen(initialNoteId:hit.id);break;
     case 'Trip':
     case 'Trip item':
     case 'Travel document':target=TripsScreen(initialTripId:hit.id);break;
     case 'Experience':target=SharedExperiencesScreen(initialExperienceId:hit.id);break;
     default:target=const CoupleLettersScreen();
   }
   Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>target));
 }
 @override Widget build(BuildContext context)=>Scaffold(
   appBar:AppBar(title:const Text('Search our space')),
   body:Column(children:[
     Padding(padding:const EdgeInsets.all(15),child:TextField(
       controller:query,autofocus:true,
       textInputAction:TextInputAction.search,
       onChanged:(v){debounce?.cancel();debounce=Timer(
         const Duration(milliseconds:300),()=>search(v));},
       decoration:InputDecoration(
         prefixIcon:const Icon(Icons.search),
         hintText:'Activities, trips, experiences, notes and more',
         border:const OutlineInputBorder(),
         suffixIcon:IconButton(icon:const Icon(Icons.clear),
           onPressed:(){query.clear();debounce?.cancel();search('');}),
       ),
     )),
     if(busy)const LinearProgressIndicator(),
     if(error!=null)Padding(padding:const EdgeInsets.all(12),child:Text(error!)),
     Expanded(child:ListView.builder(itemCount:hits.length,itemBuilder:(context,index){
       final hit=hits[index];
       return ListTile(
         leading:Icon(hit.kind=='Activity'?Icons.hub_outlined:
           hit.kind=='Calendar'?Icons.event_outlined:
           hit.kind=='To-do'?Icons.checklist_outlined:
           hit.kind=='Note'?Icons.note_outlined:
           hit.kind=='Tag'?Icons.sell_outlined:
           hit.kind=='Travel document'?Icons.attach_file:
           hit.kind=='Trip'||hit.kind=='Trip item'?Icons.flight_outlined:
           hit.kind=='Experience'?Icons.movie_outlined:Icons.mail_outline),
         title:Text(hit.title),
         subtitle:Text(hit.kind),
         onTap:()=>openHit(hit),
       );
     })),
     if(!busy&&hits.isEmpty&&query.text.trim().length>=2&&error==null)
       const Padding(padding:EdgeInsets.all(10),
         child:Text('No matching items found.')),
   ]),
 );
}
class _Hit {
 const _Hit(this.kind,this.title,this.id);
 final String kind,title,id;
}

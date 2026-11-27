import '../contacts/contact_cards_screen.dart';
import '../share_in/items_to_sort_screen.dart';
import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../coordinate/activity_detail_screen.dart';
import '../calendar/calendar_screen.dart';
import '../notes/notes_screen.dart';
import '../plans/plans_screen.dart';
import '../reminders/reminders_screen.dart';
import '../connect/couple_letters_screen.dart';
import '../connect/shared_experiences_screen.dart';
import '../trips/trips_screen.dart';
import '../occasions/occasions_screen.dart';
import '../memories/memories_screen.dart';
import '../../core/current_space_cache.dart';
import '../../core/app_env.dart';
import 'global_search_rules.dart';
import 'package:onespace/l10n/phrases.dart';

/// A single RLS-filtered search surface. No cross-space indexing or copying.
class GlobalSearchScreen extends StatefulWidget {
  const GlobalSearchScreen({super.key,this.initialQuery=''});
  /// R60: "search for …" by voice.
  final String initialQuery;
  @override State<GlobalSearchScreen> createState()=>_GlobalSearchScreenState();
}
class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
 final db=Supabase.instance.client;
 late final query=TextEditingController(text:widget.initialQuery);
 @override void initState(){
   super.initState();
   if(widget.initialQuery.trim().isNotEmpty){
     WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)search(widget.initialQuery);});
   }
 }
 Timer? debounce;
 int version=0;
 bool busy=false;
 String? error;
 List<_Hit> hits=[];
 String section='All';
 @override void dispose() {
   debounce?.cancel(); query.dispose(); version++; super.dispose();
 }
 Future<void> search(String value) async {
   final request=++version;
   final term=GlobalSearchRules.normalize(value);
   if(!GlobalSearchRules.canSearch(term)){
     if(mounted)setState((){hits=[];busy=false;error=null;});
     return;
   }
   setState((){busy=true;error=null;hits=[];});
   try{
     final account=db.auth.currentUser?.id;
     if(account==null)throw StateError('Sign in first');
     final id=await CurrentSpaceCache.instance.get();
     if(id==null && OneSpaceEnv.usesLegacyBackend)
       throw StateError('Connect your shared space first');
     if(!mounted||request!=version||db.auth.currentUser?.id!=account)return;
     final pattern=GlobalSearchRules.pattern(term);
     // QA: Row Level Security returns the account's own personal records plus
     // the current couple's shared ones, so personal-capable sections are not
     // filtered by space. A solo QA account still searches its personal space.
     // Couple-only sections are skipped when there is no current relationship.
     final personal=!OneSpaceEnv.usesLegacyBackend;
     final couple=id??'';
     dynamic own(dynamic request)=>personal?request:request.eq('space_id',couple);
     const none=<Map<String,dynamic>>[];
     var failedCategories=0;
     Future<dynamic> guarded(String kind,dynamic request) async {
       // A category filter avoids starting unrelated network searches.
       if(!GlobalSearchRules.shouldSearchSection(section,kind)){
        return <Map<String,dynamic>>[];
       }
       try{
         return await Future<dynamic>.value(request)
           .timeout(const Duration(seconds:10));
       }catch(_){
         failedCategories++;
         return <Map<String,dynamic>>[];
       }
     }
     final qaNoteTitles = OneSpaceEnv.usesLegacyBackend
       ? db.from('notes').select('id,title,updated_at').eq('space_id',couple)
       : db.from('notes').select('id,title,updated_at');
     final qaNoteBodies = OneSpaceEnv.usesLegacyBackend
       ? db.from('notes').select('id,title').eq('space_id',couple)
       : db.from('notes').select('id,title');
     final groups=await Future.wait([
       guarded('Activity',own(db.from('activities').select('id,title,updated_at'))
         .isFilter('archived_at',null).ilike('title',pattern).order('updated_at',ascending:false).limit(GlobalSearchRules.maxPerSection)),
       guarded('Calendar',own(db.from('space_events').select('id,title,event_date'))
         .isFilter('archived_at',null).ilike('title',pattern).order('event_date').limit(GlobalSearchRules.maxPerSection)),
       guarded('To-do',(OneSpaceEnv.usesLegacyBackend
          ? db.from('tasks').select('id,title,created_at').eq('space_id',couple)
          : db.from('tasks').select('id,title,created_at'))
         .isFilter('migrated_to_list',null).ilike('title',pattern)
         .limit(GlobalSearchRules.maxPerSection)),
       guarded('Note',qaNoteTitles
         .isFilter('archived_at',null).ilike('title',pattern).limit(GlobalSearchRules.maxPerSection)),
       guarded('Letter',id==null?none:db.from('couple_letters').select('id,title,created_at').eq('space_id',couple)
         .eq('status','sent').ilike('title',pattern).limit(GlobalSearchRules.maxPerSection)),
       guarded('Tag',(personal
          ? db.from('activity_components').select('id,activity_id,label,activities!inner(archived_at)')
          : db.from('activity_components').select('id,activity_id,label,activities!inner(space_id,archived_at)')
             .eq('activities.space_id',couple))
         .eq('kind','tag')
         .isFilter('archived_at',null).isFilter('activities.archived_at',null)
         .ilike('label',pattern).limit(GlobalSearchRules.maxPerSection)),
       guarded('Trip',id==null?none:db.from('shared_trips').select('id,title').eq('space_id',couple)
         .isFilter('archived_at',null).ilike('title',pattern).limit(GlobalSearchRules.maxPerSection)),
       guarded('Experience',id==null?none:db.from('shared_experiences').select('id,title').eq('space_id',couple)
         .isFilter('archived_at',null).ilike('title',pattern).limit(GlobalSearchRules.maxPerSection)),
       guarded('Trip item',id==null?none:db.from('trip_items').select('id,trip_id,title')
         .isFilter('archived_at',null).ilike('title',pattern).limit(GlobalSearchRules.maxPerSection)),
       guarded('Travel document',id==null?none:db.from('trip_attachments').select('id,trip_id,title')
         .isFilter('archived_at',null).ilike('title',pattern).limit(GlobalSearchRules.maxPerSection)),
       guarded('Occasion',id==null?none:db.from('occasion_plans').select('id,title').eq('space_id',couple)
         .isFilter('archived_at',null).ilike('title',pattern).limit(GlobalSearchRules.maxPerSection)),
       guarded('Reminder',(OneSpaceEnv.usesLegacyBackend
          ? db.from('reminders').select('id,title').eq('space_id',couple)
          : db.from('reminders').select('id,title'))
         .isFilter('archived_at',null).ilike('title',pattern)
         .limit(GlobalSearchRules.maxPerSection)),
       guarded('Memory',own(db.from('memories').select('id,title'))
         .isFilter('archived_at',null).ilike('title',pattern)
         .limit(GlobalSearchRules.maxPerSection)),
       // Content search uses independent parameterized PostgREST ilike calls,
       // never a string-built .or() filter that could alter query grammar.
       guarded('Activity',own(db.from('activities').select('id,title'))
         .isFilter('archived_at',null).ilike('body',pattern)
         .limit(GlobalSearchRules.maxPerSection)),
       guarded('Calendar',own(db.from('space_events').select('id,title'))
         .isFilter('archived_at',null).ilike('details',pattern)
         .limit(GlobalSearchRules.maxPerSection)),
       guarded('Experience',id==null?none:db.from('shared_experiences').select('id,title').eq('space_id',couple)
         .isFilter('archived_at',null).ilike('description',pattern)
         .limit(GlobalSearchRules.maxPerSection)),
       guarded('Note',qaNoteBodies
         .isFilter('archived_at',null).ilike('body',pattern)
         .limit(GlobalSearchRules.maxPerSection)),
       guarded('Memory',own(db.from('memories').select('id,title'))
         .isFilter('archived_at',null).ilike('body',pattern)
         .limit(GlobalSearchRules.maxPerSection)),
       guarded('Reminder',(OneSpaceEnv.usesLegacyBackend
          ? db.from('reminders').select('id,title').eq('space_id',couple)
          : db.from('reminders').select('id,title'))
         .isFilter('archived_at',null).ilike('details',pattern)
         .limit(GlobalSearchRules.maxPerSection)),
       // R54: people and the share-in tray are searchable too.
       guarded('Contact',own(db.from('saved_contacts').select('id,title:label'))
         .isFilter('archived_at',null).ilike('label',pattern)
         .limit(GlobalSearchRules.maxPerSection)),
       guarded('Item to sort',id==null?none:db.from('items_to_sort').select('id,title').eq('space_id',couple)
         .isFilter('archived_at',null).isFilter('sorted_at',null).ilike('title',pattern)
         .limit(GlobalSearchRules.maxPerSection)),
     ]);
     if(!mounted||request!=version||db.auth.currentUser?.id!=account)return;
     final types=['Activity','Calendar','To-do','Note','Letter','Tag','Trip','Experience','Trip item','Travel document','Occasion','Reminder','Memory',
      'Activity','Calendar','Experience','Note','Memory','Reminder','Contact','Item to sort'];
     final output=<_Hit>[];
     for(var n=0;n<groups.length;n++){
       for(final row in groups[n]){
         output.add(_Hit(types[n],
           (n==5?'#':'')+(row[n==5?'label':'title']?.toString()??''),
           GlobalSearchRules.destinationId(row,
             n==5?'activity_id':(n==8||n==9)?'trip_id':'id')??''));
       }
     }
     setState((){
       final seen=<String>{};
       hits=output.where((hit)=>
        hit.id.isNotEmpty&&hit.title.isNotEmpty&&
        seen.add('${hit.kind}:${hit.id}')).toList();
       busy=false;
       error=failedCategories==0?null:
        'Some sections are temporarily unavailable. Showing the results we found.';
     });
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
     case 'To-do':target=PlansScreen(focusTaskId:hit.id);break;
     case 'Reminder':target=RemindersScreen(initialReminderId:hit.id);break;
     case 'Note':target=NotesScreen(initialNoteId:hit.id);break;
     case 'Trip':
     case 'Trip item':
     case 'Travel document':target=TripsScreen(initialTripId:hit.id);break;
     case 'Experience':target=SharedExperiencesScreen(initialExperienceId:hit.id);break;
     case 'Occasion':target=OccasionsScreen(initialPlanId:hit.id);break;
     case 'Memory':target=MemoriesScreen(initialMemoryId:hit.id);break;
     case 'Contact':target=const ContactCardsScreen();break;
     case 'Item to sort':target=const ItemsToSortScreen();break;
     default:target=const CoupleLettersScreen();
   }
   Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>target));
 }
 @override Widget build(BuildContext context)=>Scaffold(
   appBar:AppBar(title:Text(tt('Search our space')),actions:[
    PopupMenuButton<String>(
     tooltip:tt('Filter search results'),
     icon:Badge(isLabelVisible:section!='All',smallSize:8,child:const Icon(Icons.tune)),
     initialValue:section,
     onSelected:(v){
      setState(()=>section=v);
      if(GlobalSearchRules.canSearch(query.text))search(query.text);
     },
     itemBuilder:(_)=>[
      for(final category in [
       'All','Activity','Calendar','To-do','Note','Letter','Tag',
       'Trip','Experience','Trip item','Travel document','Occasion','Contact','Item to sort',
       'Reminder','Memory',
      ])PopupMenuItem(value:category,child:Text(tt(category))),
     ]),
   ]),
   body:SafeArea(child:Center(child:ConstrainedBox(
    constraints:const BoxConstraints(maxWidth:860),child:Column(children:[
     Padding(padding:const EdgeInsets.all(15),child:TextField(
       controller:query,autofocus:true,
       maxLength:GlobalSearchRules.maxQueryLength,
       textInputAction:TextInputAction.search,
       onSubmitted:(v){debounce?.cancel();search(v);},
       onChanged:(v){
         version++;
         debounce?.cancel();
         setState((){hits=[];busy=false;error=null;});
         if(GlobalSearchRules.canSearch(v)){
           debounce=Timer(const Duration(milliseconds:500),(){
             if(mounted)search(v);
           });
         }
       },
       decoration:InputDecoration(
         prefixIcon:const Icon(Icons.search),
         hintText:tt('Reminders, activities, trips, notes and more'),
         border:const OutlineInputBorder(),
         suffixIcon:IconButton(tooltip:tt('Clear search'),icon:const Icon(Icons.clear),
           onPressed:(){query.clear();debounce?.cancel();search('');}),
       ),
     )),
     if(busy)const LinearProgressIndicator(),
     if(error!=null)Padding(padding:const EdgeInsets.all(12),
       child:Row(children:[
         Expanded(child:Text(tt(error!),
          style:TextStyle(color:Theme.of(context).colorScheme.error))),
         TextButton(onPressed:busy?null:()=>search(query.text),
          child:Text(tt('Retry'))),
       ])),
     Expanded(child:ListView.builder(
       keyboardDismissBehavior:ScrollViewKeyboardDismissBehavior.onDrag,
       itemCount:hits.where((hit)=>section=='All'||hit.kind==section).length,
       itemBuilder:(context,index){
       final filtered=hits.where((hit)=>section=='All'||hit.kind==section).toList();
       final hit=filtered[index];
       return ListTile(
         leading:Icon(hit.kind=='Activity'?Icons.hub_outlined:
           hit.kind=='Calendar'?Icons.event_outlined:
           hit.kind=='To-do'?Icons.checklist_outlined:
           hit.kind=='Reminder'?Icons.alarm_outlined:
           hit.kind=='Note'?Icons.note_outlined:
           hit.kind=='Memory'?Icons.photo_library_outlined:
           hit.kind=='Tag'?Icons.sell_outlined:
           hit.kind=='Occasion'?Icons.card_giftcard_outlined:
           hit.kind=='Travel document'?Icons.attach_file:
           hit.kind=='Trip'||hit.kind=='Trip item'?Icons.flight_outlined:
           hit.kind=='Experience'?Icons.movie_outlined:Icons.mail_outline),
         title:Text(tt(hit.title),maxLines:2,overflow:TextOverflow.ellipsis),
         subtitle:Text(tt(hit.kind)),
         trailing:const Icon(Icons.chevron_right),
         onTap:()=>openHit(hit),
       );
     })),
     if(!busy&&hits.isEmpty&&error==null)
       Padding(padding:const EdgeInsets.all(14),
        child:Text(tt(GlobalSearchRules.canSearch(query.text)
         ?'No matching items found.':'Type at least two characters to search.'),
         textAlign:TextAlign.center)),
   ])))),
 );
}
class _Hit {
 const _Hit(this.kind,this.title,this.id);
 final String kind,title,id;
}

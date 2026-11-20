import '../../core/form_kit.dart';
import '../counters/counter_sources.dart';
import '../counters/counter_source_actions.dart';
import '../../core/item_menu.dart';
import '../../core/editor_scaffold.dart';
import '../../core/status_look.dart';
import '../../core/linked_items.dart';
import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/current_space_cache.dart';
import '../../core/app_env.dart';
import '../../core/record_collection_search_rules.dart';
import '../../core/record_list_top_actions.dart';
import '../calendar/calendar_rules.dart';
import 'trip_item_editor.dart';
import 'trip_rules.dart';
import 'trip_documents_section.dart';
import 'trip_flight_options_section.dart';
import 'trip_preparation_section.dart';
import 'airports.dart';
import 'trip_widgets.dart';
import 'package:onespace/l10n/phrases.dart';

/// R67: the status is automatic; these are its display words.
const tripStages=TripRules.statusLabels;

class TripsScreen extends StatefulWidget {
 const TripsScreen({super.key,this.initialTripId,this.embedded=false});
 final String? initialTripId;
 /// R61: shown as the "Trips" tab inside Coordinate (no own app bar).
 final bool embedded;
 @override State<TripsScreen> createState()=>_TripsScreenState();
}
class _TripsScreenState extends State<TripsScreen> {
 final db=Supabase.instance.client;
 String? space,error;
 bool personalReady=false;
 bool loading=true,openedDeepLink=false,showArchived=false;
 String filter='upcoming',query='';
 List<Map<String,dynamic>> trips=[];
 RealtimeChannel? _changes;
 Timer? _debounce;
 String? _watchedSpace;
 int _loadVersion=0;

 @override void initState(){super.initState();load();Airports.load().then((_){if(mounted)setState((){});});}
 @override void dispose(){
  _loadVersion++;
  _debounce?.cancel();
  final channel=_changes;
  if(channel!=null)unawaited(db.removeChannel(channel));
  super.dispose();
 }
 void _watch(String spaceId){
  if(_watchedSpace==spaceId)return;
  final prior=_changes;
  if(prior!=null)unawaited(db.removeChannel(prior));
  _watchedSpace=spaceId;
  _changes=db.channel('trips-list-'+spaceId)
   .onPostgresChanges(event:PostgresChangeEvent.all,schema:'public',
    table:'shared_trips',filter:PostgresChangeFilter(
     type:PostgresChangeFilterType.eq,column:'space_id',value:spaceId),
    callback:(_)=>_scheduleRefresh())
   .subscribe();
 }
 void _scheduleRefresh(){
  _debounce?.cancel();
  _debounce=Timer(const Duration(milliseconds:700),(){
   if(mounted)load();
  });
 }
 Future<void> load() async{
  final request=++_loadVersion;
  final user=db.auth.currentUser?.id;
  if(user==null){
   if(mounted)setState((){
    loading=false;space=null;trips=[];error=null;
   });
   return;
  }
  try{
   var id=await CurrentSpaceCache.instance.get();
   var ownScope=false;
   if(!OneSpaceEnv.isProduction){
     final scopes=await db.rpc('my_storage_scopes');
     if(scopes is! Map || scopes['private_space_id']?.toString()!=user){
       throw StateError('Account-owned Trips scope unavailable');
     }
     id=scopes['shared_space_id']?.toString();
     ownScope=true;
   }
   if(!mounted||request!=_loadVersion||db.auth.currentUser?.id!=user)return;
   if(id==null&&!ownScope){
    setState((){loading=false;space=null;personalReady=false;trips=[];error=null;});
    final prior=_changes;
    if(prior!=null)unawaited(db.removeChannel(prior));
    _changes=null;_watchedSpace=null;
    return;
   }
   final tripQuery=OneSpaceEnv.isProduction
     ? db.from('shared_trips').select().eq('space_id',id!)
     : db.from('shared_trips').select();
   final data=await tripQuery.order('updated_at',ascending:false).limit(200);
   if(!mounted||request!=_loadVersion||db.auth.currentUser?.id!=user)return;
   setState((){
    space=id;personalReady=ownScope;loading=false;error=null;
    trips=List<Map<String,dynamic>>.from(data);
   });
   if(id!=null)_watch(id);
   else {
     final prior=_changes;
     if(prior!=null)unawaited(db.removeChannel(prior));
     _changes=null;_watchedSpace=null;
   }
   if(!openedDeepLink&&widget.initialTripId!=null){
    openedDeepLink=true;
    final match=trips.where((t)=>t['id']==widget.initialTripId).firstOrNull;
    WidgetsBinding.instance.addPostFrameCallback((_){
     if(!mounted)return;
     if(match!=null){
      open(match);
     }else{
      // A valid deep link may point past the first 200 list rows.
      // The detail query remains protected by the trip's RLS policy.
      Navigator.of(context).push<void>(MaterialPageRoute(
       builder:(_)=>TripDetail(tripId:widget.initialTripId!)));
     }
    });
   }
  }catch(_){
   if(mounted&&request==_loadVersion&&db.auth.currentUser?.id==user)
    setState((){error='Unable to load journeys. Pull down to retry.';loading=false;});
  }
 }
 Future<void> edit([Map<String,dynamic>? trip])async{
  if(space==null&&!personalReady)return;
  final saved=await Navigator.of(context).push<bool>(MaterialPageRoute(
   builder:(_)=>TripEditor(spaceId:space??'',existing:trip)));
  if(saved==true&&mounted)await load();
 }
 Future<void> open(Map<String,dynamic> trip)async{
  await Navigator.of(context).push<void>(MaterialPageRoute(
   builder:(_)=>TripDetail(tripId:trip['id'].toString())));
  if(mounted)await load();
 }
 /// R55: this screen's filter groups (drawn by the shared panel).
 List<FilterGroupSpec> _filterGroups()=>[FilterGroupSpec(id:'when',label:tt('Trips'),options:const {'upcoming':'Upcoming','past':'Past','all':'All'},selected:filter,defaultValue:'upcoming')];

 @override Widget build(BuildContext context){
  final now=CalendarRules.day(DateTime.now());
  final visible=trips.where((trip){
   if(!RecordCollectionSearchRules.inHistory(trip,showArchived))return false;
   if(!RecordCollectionSearchRules.matches(trip,query,
    fields:const ['title','destination','origin','notes']))return false;
   if(showArchived||filter=='all')return true;
   final st=TripRules.status(trip,now);
   if(filter=='past')return st=='completed'||st=='cancelled';
   return st!='completed'&&st!='cancelled';
  }).toList();
  return Scaffold(
   backgroundColor:widget.embedded?Colors.transparent:null,
   appBar:widget.embedded?null:AppBar(title:Text(tt('Trips')),actions:[
    RecordListTopActions(
     historyKinds:const ['trip'],historyTitle:tt('Trips'),
     showHistory:showArchived,
     onToggleHistory:()=>setState(()=>showArchived=!showArchived),
     groups:_filterGroups(),
      onApply:(v)=>setState((){filter=v['when']!;}),
     ),
   ],bottom:filterShowingBar(_filterGroups(),removed:showArchived,onClear:()=>setState((){showArchived=false;filter='upcoming';}))),
   floatingActionButton:space==null&&!personalReady?null:FloatingActionButton.extended(heroTag:'fab-trips',
    icon:const Icon(Icons.add),label:Text(tt('Add trip')),onPressed:()=>edit()),
   body:RefreshIndicator(onRefresh:load,child:ListView(
    physics:const AlwaysScrollableScrollPhysics(),
    padding:const EdgeInsetsDirectional.fromSTEB(16,12,16,90),children:[
    if(widget.embedded)...[
     Row(children:[
      Expanded(child:Text(tt('Trips'),style:Theme.of(context).textTheme.headlineMedium)),
      RecordListTopActions(
       historyKinds:const ['trip'],historyTitle:tt('Trips'),
       showHistory:showArchived,
       onToggleHistory:()=>setState(()=>showArchived=!showArchived),
       groups:_filterGroups(),
       onApply:(v)=>setState((){filter=v['when']!;})),
     ]),
     if(FilterGroupSpec.showing(_filterGroups(),removed:showArchived).isNotEmpty)FilterShowingLine(
      labels:FilterGroupSpec.showing(_filterGroups(),removed:showArchived),
      onClear:()=>setState((){showArchived=false;filter='upcoming';})),
    ]else Text(tt('Our journeys'),style:Theme.of(context).textTheme.titleLarge),
    const SizedBox(height:6),
    Text(tt('From the next reunion to the smallest weekend getaway. Plan it together, one detail at a time.'),
      style:Theme.of(context).textTheme.bodyMedium),
    const SizedBox(height:15),
    TextField(onChanged:(v)=>setState(()=>query=v),
     decoration:InputDecoration(prefixIcon:Icon(Icons.search),
      labelText:tt('Search trips'),hintText:tt('Trips or destinations'),border:OutlineInputBorder())),
    const SizedBox(height:8),
    if(showArchived)Padding(
     padding:const EdgeInsets.only(bottom:8),
     child:Text(tt('Removed trips · Use ⋮ › Restore to bring one back.'),
      style:Theme.of(context).textTheme.bodySmall)),
    if(error!=null)Text(tt(error!),style:TextStyle(color:Theme.of(context).colorScheme.error)),
    if(loading)const Padding(padding:EdgeInsets.all(24),child:Center(child:CircularProgressIndicator()))
    else if(space==null&&!personalReady)Text(tt('Connect your shared space first.'))
    else if(visible.isEmpty)Padding(padding:EdgeInsets.all(24),
     child:Text(tt('No trips in this view yet. Your next adventure can start here.')))
    else for(final trip in visible)Card(elevation:0,clipBehavior:Clip.antiAlias,
     child:ListTile(
      contentPadding:const EdgeInsets.symmetric(horizontal:14,vertical:8),
      leading:CircleAvatar(child:StatusLook.mark(tripLook(TripRules.status(trip,now)))??Icon(trip['visibility']=='private'?
       Icons.lock_outline:tripModeIcon(trip['travel_mode']?.toString()))),
      title:Text(tt(trip['title'].toString()),
       style:StatusLook.title(context,tripLook(TripRules.status(trip,now)),Theme.of(context).textTheme.titleMedium)),
      subtitle:Text(tt([
       if((trip['destination']??'').toString().isNotEmpty)Airports.label(trip['destination'].toString()),
       tripStages[TripRules.status(trip,now)]??'Planning',
       if(trip['start_on']!=null)trip['start_on'].toString()+
         (trip['end_on']!=null?' – '+trip['end_on'].toString():''),
       if(trip['visibility']=='private')'Only me',
      ].join(' · ')),maxLines:4),
      trailing:ItemMenu(kind:'trip',recordId:trip['id'].toString(),title:trip['title']?.toString(),
       onOpen:()=>open(trip),openLabel:tt('Open'),table:'shared_trips',
       moreActions:[
        if((OneSpaceEnv.isProduction||trip['private_space_id']==null)&&
           space!=null&&trip['archived_at']==null&&CounterSource.trip(trip)!=null)
         ItemMenuAction('Add to counters',Icons.hourglass_bottom_outlined,
          ()=>CounterSourceActions.open(context,space!,CounterSource.trip(trip))),
       ],
       removed:trip['archived_at']!=null,onChanged:load),
      onTap:()=>open(trip),
     )),
   ])));
 }
}


/// A booked trip still looks "open" in lists (only past/cancelled are struck).
String tripLook(String status)=>status=='booked'||status=='traveling'?'planning':status;

IconData tripModeIcon(String? mode)=>switch(mode){
 'road'=>Icons.directions_car_outlined,
 'train'=>Icons.train_outlined,
 'other'=>Icons.luggage_outlined,
 _=>Icons.flight_takeoff_outlined,
};

const tripModes=<String,String>{'flight':'Flight','road':'Road trip','train':'Train','other':'Other'};

/// R67 (forms review): the trip's first step. Everything that shapes the
/// search sits here: how we travel, one way or round trip, airports (as
/// 3-letter codes for flights), dates, flexible dates, who is traveling and
/// how many passengers. A new trip says Next: it is saved and its page opens.
class TripEditor extends StatefulWidget {
 const TripEditor({super.key,required this.spaceId,this.existing,this.prefill,this.onCreated});
 /// R53: called with the new trip's id so "Create from this" can link it.
 final Future<void> Function(String id)? onCreated;
 final String spaceId;
 final Map<String,dynamic>? existing;
 /// R52: fields pre-filled for a new trip (from shared content); never an id.
 final Map<String,String>? prefill;
 @override State<TripEditor> createState()=>_TripEditorState();
}
class _TripEditorState extends State<TripEditor> with FormChangeTracker<TripEditor> {
 @override String get signature=>[title.text,origin,destination,originText.text,destinationText.text,
  notes.text,from,to,visibility,mode,tripType,traveler,adults,children,infants,flexible].join('|');

 final db=Supabase.instance.client;
 late final TextEditingController title,notes,originText,destinationText;
 String? origin,destination,traveler;
 late String visibility,mode,tripType;
 DateTime? from,to;
 int adults=2,children=0,infants=0;
 bool flexible=false,saving=false,adultsTouched=false;
 SpacePeople? people;
 String? error;
 @override void initState(){
  super.initState();
  final x=widget.existing??widget.prefill??{};
  title=TextEditingController(text:(x['title']??'').toString());
  notes=TextEditingController(text:(x['notes']??'').toString());
  mode=(x['travel_mode']??'flight').toString();
  tripType=(x['trip_type']??'round').toString();
  final o=(x['origin']??'').toString().trim(),d=(x['destination']??'').toString().trim();
  origin=o.isEmpty?null:o;destination=d.isEmpty?null:d;
  originText=TextEditingController(text:o);destinationText=TextEditingController(text:d);
  visibility=(x['visibility']??
    (!OneSpaceEnv.isProduction&&widget.spaceId.isEmpty?'private':'shared')).toString();
  from=DateTime.tryParse((x['start_on']??'').toString());
  to=DateTime.tryParse((x['end_on']??'').toString());
  traveler=x['traveler_id']?.toString();
  final e=widget.existing;
  if(e!=null){
   adults=(e['adults'] as num?)?.toInt()??2;children=(e['children'] as num?)?.toInt()??0;
   infants=(e['infants'] as num?)?.toInt()??0;flexible=e['flexible_dates']==true;adultsTouched=true;
  }
  SpacePeople.load().then((p){if(mounted)setState(()=>people=p);});
  Airports.load().then((_){if(mounted)setState((){});});
 }
 @override void dispose(){
  title.dispose();notes.dispose();originText.dispose();destinationText.dispose();
  super.dispose();
 }
 Future<void> save()async{
  if(saving)return;
  if(title.text.trim().isEmpty){setState(()=>error='Give the trip a name.');return;}
  if(from!=null&&to!=null&&to!.isBefore(from!)){
   setState(()=>error='The return date cannot be before departure.');return;
  }
  if(adults+children+infants==0){setState(()=>error='Add at least one passenger.');return;}
  final flight=mode=='flight';
  final o=flight?(origin??''):originText.text.trim();
  final d=flight?(destination??''):destinationText.text.trim();
  setState((){saving=true;error=null;});
  try{
   final values=<String,dynamic>{
    'title':title.text.trim(),'origin':o,'destination':d,'notes':notes.text.trim(),
    'travel_mode':mode,'trip_type':tripType,'traveler_id':traveler,
    'adults':adults,'children':children,'infants':infants,'flexible_dates':flexible,
    'start_on':from==null?null:CalendarRules.sqlDate(from!),
    'end_on':to==null||tripType=='one_way'?null:CalendarRules.sqlDate(to!),
   };
   if(widget.existing==null){
    final personal=!OneSpaceEnv.isProduction&&visibility=='private';
    if(!personal&&widget.spaceId.isEmpty){
      throw StateError('Connect with a partner before sharing Trips');
    }
    if(personal&&traveler!=null&&traveler!=db.auth.currentUser?.id){
      throw StateError('A personal trip cannot name another account as traveler');
    }
    final created=await db.from('shared_trips').insert({
     ...values,
     if(personal) 'private_space_id':db.auth.currentUser!.id
     else 'space_id':widget.spaceId,
     'created_by':db.auth.currentUser!.id,
     'visibility':visibility,'status':'planning',
    }).select('id').single();
    final id=created['id'].toString();
    await widget.onCreated?.call(id);
    if(!mounted)return;
    // Next: the trip is saved; its page is the next step.
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
     builder:(_)=>TripDetail(tripId:id)),result:true);
    return;
   }
   await db.from('shared_trips').update(values).eq('id',widget.existing!['id']);
   if(mounted)Navigator.pop(context,true);
  }on PostgrestException catch(e){
   if(mounted)setState(()=>error=e.message);
  }catch(_){
   if(mounted)setState(()=>error='Unable to save trip.');
  }finally{
   if(mounted)setState(()=>saving=false);
  }
 }
 void setTraveler(String? v){
  setState((){
   traveler=v;
   if(!adultsTouched)adults=v==null?2:1;
  });
 }
 @override Widget build(BuildContext context){
  final editing=widget.existing!=null;
  final flight=mode=='flight';
  final p=people;
  return EditorScaffold(title:editing?tt('Edit trip'):tt('New trip'),
   isNew:!editing,isChanged:()=>changed,isComplete:()=>title.text.trim().isNotEmpty,
   listenTo:[title,notes,originText,destinationText],saving:saving,onSave:save,
   saveLabel:editing?'Save':'Next',
   meta:MetaStrip(value:MetaValues(shared:visibility=='shared'),showBelongs:false,showDate:false,
    enabled:!editing,onChanged:(v)=>setState(()=>visibility=
      (!OneSpaceEnv.isProduction&&widget.spaceId.isEmpty)
        ?'private':(v.shared?'shared':'private'))),
   body:ListView(padding:const EdgeInsets.all(18),children:[
   TextField(controller:title,maxLength:160,autofocus:!editing,
    textCapitalization:TextCapitalization.sentences,
    decoration:InputDecoration(labelText:tt('Trip name *'),
     hintText:tt('Christmas in Philadelphia, weekend in AlUla…'),border:const OutlineInputBorder())),
   ChoiceRow<String>(label:tt('How are we traveling?'),options:tripModes,selected:mode,
    icons:const {'flight':Icons.flight_outlined,'road':Icons.directions_car_outlined,
     'train':Icons.train_outlined,'other':Icons.luggage_outlined},
    onSelected:(v){if(v!=null)setState(()=>mode=v);}),
   ChoiceRow<String>(label:tt('Trip type'),options:const {'round':'Round trip','one_way':'One way'},
    selected:tripType,icons:const {'round':Icons.sync_alt,'one_way':Icons.arrow_right_alt},
    onSelected:(v){if(v!=null)setState(()=>tripType=v);}),
   FormSection(tt('Where')),
   if(flight)...[
    AirportField(label:tt('From'),value:origin,onChanged:(v)=>setState(()=>origin=v)),
    AirportField(label:tt('To'),value:destination,icon:Icons.flight_land_outlined,
     onChanged:(v)=>setState(()=>destination=v)),
   ]else...[
    TextField(controller:originText,maxLength:160,
     decoration:InputDecoration(labelText:tt('From'),prefixIcon:const Icon(Icons.trip_origin),
      border:const OutlineInputBorder())),
    const SizedBox(height:6),
    TextField(controller:destinationText,maxLength:160,
     decoration:InputDecoration(labelText:tt('To'),prefixIcon:const Icon(Icons.place_outlined),
      border:const OutlineInputBorder())),
   ],
   FormSection(tt('When')),
   DateField(label:tt('Leaving'),value:from,first:DateTime(2000),last:DateTime(2100),
    onChanged:(v)=>setState(()=>from=v)),
   if(tripType=='round')DateField(label:tt('Coming back'),value:to,first:from??DateTime(2000),last:DateTime(2100),
    onChanged:(v)=>setState(()=>to=v)),
   Align(alignment:AlignmentDirectional.centerStart,child:OptionChip(label:tt('Flexible dates'),
    icon:Icons.date_range_outlined,value:flexible,onChanged:(v)=>setState(()=>flexible=v))),
   Padding(padding:const EdgeInsets.only(top:4),child:Text(
    tt('Dates can wait while you plan. Booking a flight fills them in.'),
    style:Theme.of(context).textTheme.bodySmall)),
   FormSection(tt("Who's traveling")),
   if(p!=null&&p.partnerId!=null)Wrap(spacing:8,runSpacing:6,children:[
    ChoiceChip(label:Text(tt('Both of us')),selected:traveler==null,onSelected:(_)=>setTraveler(null)),
    ChoiceChip(label:Text(tt('Me')),selected:traveler==p.me,onSelected:(_)=>setTraveler(p.me)),
    ChoiceChip(label:Text(tt(p.partnerName)),selected:traveler==p.partnerId,
     onSelected:(_)=>setTraveler(p.partnerId)),
   ]),
   const SizedBox(height:10),
   CountStepper(label:tt('Adults'),help:tt('12 and over'),value:adults,icon:Icons.person_outline,
    onChanged:(v)=>setState((){adults=v;adultsTouched=true;})),
   CountStepper(label:tt('Children'),help:tt('2 to 11'),value:children,icon:Icons.child_care_outlined,
    onChanged:(v)=>setState(()=>children=v)),
   CountStepper(label:tt('Infants'),help:tt('Under 2'),value:infants,icon:Icons.baby_changing_station_outlined,
    onChanged:(v)=>setState(()=>infants=v)),
   FormSection(tt('Notes')),
   TextField(controller:notes,maxLength:5000,minLines:3,maxLines:8,
    decoration:InputDecoration(labelText:tt('Plans, ideas and things to remember'),
     alignLabelWithHint:true,border:const OutlineInputBorder())),
   if(editing)Text(tt('Who can see it stays as it was created, to protect travel documents.'),
    style:Theme.of(context).textTheme.bodySmall),
   if(error!=null)Padding(padding:const EdgeInsets.only(top:10),
    child:Text(tt(error!),style:TextStyle(color:Theme.of(context).colorScheme.error))),
  ]));
 }
}

class TripDetail extends StatefulWidget {
 const TripDetail({super.key,required this.tripId});
 final String tripId;
 @override State<TripDetail> createState()=>_TripDetailState();
}
class _TripDetailState extends State<TripDetail>{
 final _links=GlobalKey<LinkedItemsStripState>();
 final db=Supabase.instance.client;
 final message=TextEditingController();
 Map<String,dynamic>? trip;
 List<Map<String,dynamic>> items=[],messages=[];
 bool loading=true,busy=false,showRemoved=false,flightBooked=false;
 bool? flightsOpen;
 SpacePeople? people;
 String? error;
 RealtimeChannel? _changes;
 Timer? _debounce;
 int _request=0;

 @override void initState(){
  super.initState();
  _changes=db.channel('trip-detail-'+widget.tripId)
   .onPostgresChanges(event:PostgresChangeEvent.all,schema:'public',
    table:'shared_trips',filter:PostgresChangeFilter(
     type:PostgresChangeFilterType.eq,column:'id',value:widget.tripId),
    callback:(_)=>_scheduleRefresh())
   .onPostgresChanges(event:PostgresChangeEvent.all,schema:'public',
    table:'trip_items',filter:PostgresChangeFilter(
     type:PostgresChangeFilterType.eq,column:'trip_id',value:widget.tripId),
    callback:(_)=>_scheduleRefresh())
   .onPostgresChanges(event:PostgresChangeEvent.all,schema:'public',
    table:'trip_flight_options',filter:PostgresChangeFilter(
     type:PostgresChangeFilterType.eq,column:'trip_id',value:widget.tripId),
    callback:(_)=>_scheduleRefresh())
   .onPostgresChanges(event:PostgresChangeEvent.all,schema:'public',
    table:'trip_messages',filter:PostgresChangeFilter(
     type:PostgresChangeFilterType.eq,column:'trip_id',value:widget.tripId),
    callback:(_)=>_scheduleRefresh())
   .subscribe();
  SpacePeople.load().then((p){if(mounted)setState(()=>people=p);});
  Airports.load().then((_){if(mounted)setState((){});});
  load();
 }
 void _scheduleRefresh(){
  _debounce?.cancel();
  _debounce=Timer(const Duration(milliseconds:700),(){
   if(mounted)load();
  });
 }
 @override void dispose(){
  _request++;
  _debounce?.cancel();
  final channel=_changes;
  if(channel!=null)unawaited(db.removeChannel(channel));
  message.dispose();
  super.dispose();
 }

 Future<void> load()async{
  final request=++_request;
  final user=db.auth.currentUser?.id;
  if(user==null)return;
  try{
   final t=await db.from('shared_trips').select().eq('id',widget.tripId).single();
   var failures=0;
   Future<dynamic> safe(dynamic task)async{
    try{return await task;}catch(_){failures++;return null;}
   }
   final results=await Future.wait([
    safe(db.from('trip_items').select().eq('trip_id',widget.tripId).limit(250)),
    safe(db.from('trip_messages').select().eq('trip_id',widget.tripId)
     .order('created_at',ascending:true).limit(250)),
    safe(db.from('trip_flight_options').select('id').eq('trip_id',widget.tripId)
     .eq('status','booked').isFilter('archived_at',null).limit(1)),
   ]);
   if(!mounted||request!=_request||db.auth.currentUser?.id!=user)return;
   final ordered=List<Map<String,dynamic>>.from(results[0]??items)
    ..sort((a,b){
     final da=(a['local_date']??'9999-12-31').toString();
     final db=(b['local_date']??'9999-12-31').toString();
     final d=da.compareTo(db);
     return d!=0?d:(a['local_time']??'99:99').toString()
       .compareTo((b['local_time']??'99:99').toString());
    });
   setState((){
    trip=t;items=ordered;
    if(results[1]!=null)messages=List<Map<String,dynamic>>.from(results[1]);
    if(results[2]!=null)flightBooked=(results[2] as List).isNotEmpty;
    loading=false;
    error=failures==0?null:
      'Some trip sections could not refresh. Existing information is kept; pull down to retry.';
   });
  }on PostgrestException catch(e){
   if(mounted&&request==_request&&db.auth.currentUser?.id==user)
    setState((){loading=false;error=e.message;});
  }catch(_){
   if(mounted&&request==_request&&db.auth.currentUser?.id==user)
    setState((){loading=false;error='Unable to open this trip.';});
  }
 }
 Future<void> mutate(Future<void> Function() work)async{
  if(busy)return;
  setState((){busy=true;error=null;});
  try{await work();await load();}
  on PostgrestException catch(e){
   if(mounted)setState(()=>error=e.message);
  }catch(_){
   if(mounted)setState(()=>error='Unable to save this change.');
  }finally{
   if(mounted)setState(()=>busy=false);
  }
 }
 Future<void> editTrip()async{
  if(trip==null)return;
  final saved=await Navigator.of(context).push<bool>(MaterialPageRoute(
   builder:(_)=>TripEditor(spaceId:trip!['space_id']?.toString()??'',existing:trip)));
  if(saved==true&&mounted)await load();
 }
 Future<void> editItem([Map<String,dynamic>? item])async{
  final saved=await Navigator.of(context).push<bool>(MaterialPageRoute(
   builder:(_)=>TripItemEditor(tripId:widget.tripId,existing:item,trip:trip)));
  if(saved==true&&mounted)await load();
 }
 Future<void> setTripRemoved()async{
  final t=trip;if(t==null)return;
  if(t['archived_at']==null){
   final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
    title:Text(tt('Remove this trip?')),
    content:Text(tt('It moves to Removed. You can restore it from the filter anytime.')),
    actions:[
     TextButton(onPressed:()=>Navigator.pop(ctx,false),child:Text(tt('Cancel'))),
     FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:Text(tt('Remove'))),
    ]));
   if(ok!=true)return;
  }
  await mutate(()async{
   await db.from('shared_trips').update({
    'archived_at':t['archived_at']==null?DateTime.now().toUtc().toIso8601String():null,
   }).eq('id',widget.tripId);
  });
 }
 Future<void> setCancelled(bool cancel)async{
  await mutate(()async{
   // Reopening hands the status back to the automatic rules.
   await db.from('shared_trips').update({'status':cancel?'cancelled':'planning'}).eq('id',widget.tripId);
  });
 }
 Future<void> setItemRemoved(Map<String,dynamic> item)async{
  await mutate(()async{
   await db.from('trip_items').update({
    'archived_at':item['archived_at']==null?DateTime.now().toUtc().toIso8601String():null,
   }).eq('id',item['id']).eq('trip_id',widget.tripId);
  });
 }
 Future<void> postMessage()async{
  final body=message.text.trim();
  if(body.isEmpty)return;
  await mutate(()async{
   await db.from('trip_messages').insert({'trip_id':widget.tripId,'body':body});
   message.clear();
  });
 }
 Future<void> retract(Map<String,dynamic> item)async{
  await mutate(()async{
   await db.from('trip_messages').update({
    'archived_at':DateTime.now().toUtc().toIso8601String(),
   }).eq('id',item['id']).eq('created_by',db.auth.currentUser!.id);
  });
 }
 Future<void> openLink(String text)async{
  final uri=Uri.tryParse(text);
  if(uri==null||!['http','https'].contains(uri.scheme))return;
  try{
   if(!await launchUrl(uri,mode:LaunchMode.externalApplication)&&mounted){
    ScaffoldMessenger.of(context).showSnackBar(
     SnackBar(content:Text(tt('Could not open this link.'))));
   }
  }catch(_){
   if(mounted)ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content:Text(tt('Could not open this link.'))));
  }
 }
 String label(Object? user)=>user==db.auth.currentUser?.id?'You':(people?.partnerName??'Partner');
 String _date(Object? raw){
  final d=DateTime.tryParse((raw??'').toString());
  return d==null?'':MaterialLocalizations.of(context).formatMediumDate(d);
 }
 IconData kindIcon(String kind)=>switch(kind){
  'flight'=>Icons.flight_outlined,
  'stay'=>Icons.hotel_outlined,
  'transport'=>Icons.directions_car_outlined,
  'activity'=>Icons.place_outlined,
  'booking'=>Icons.book_online_outlined,
  _=>Icons.note_alt_outlined,
 };
 String place(Object? v){
  final s=(v??'').toString();
  return Airports.isCode(s)?Airports.label(s):s;
 }
 Widget itineraryCard(Map<String,dynamic> entry){
  final deleted=entry['archived_at']!=null;
  final start=entry['local_date']==null?'Date not set':
   _date(entry['local_date'])+
   (entry['local_time']!=null?' · '+entry['local_time'].toString().substring(0,5):'');
  final amount=entry['estimated_cost']==null?'':entry['currency'].toString()+
    ' '+entry['estimated_cost'].toString();
  final from=place(entry['location']),to=place(entry['destination']);
  return Card(elevation:0,child:Padding(padding:const EdgeInsets.fromLTRB(10,8,4,10),
   child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Row(children:[
     CircleAvatar(radius:18,child:Icon(kindIcon(entry['kind'].toString()),size:20)),
     const SizedBox(width:10),
     Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(tt(entry['title'].toString()),style:Theme.of(context).textTheme.titleMedium?.copyWith(
       decoration:deleted?TextDecoration.lineThrough:null)),
      Text(tt((tripItemKinds[entry['kind']]??'Travel item'))+' · '+tt(start),
       style:Theme.of(context).textTheme.bodySmall),
     ])),
     AnchoredMenuButton<String>(tooltip:tt('More'),
      onSelected:(v){
       if(v=='edit'){editItem(entry);}
       else if(v=='link'){openLink(entry['source_url'].toString());}
       else if(v=='counter' && trip != null) {
        CounterSourceActions.open(context,trip!['space_id'].toString(),
          CounterSource.itinerary(entry,shared:trip!['visibility']!='private'));
       }
       else if(v=='remove'){setItemRemoved(entry);}
      },
      itemBuilder:(_)=>[
       if(!deleted&&CounterSource.itinerary(entry)!=null)
        iconMenuItem('counter',Icons.hourglass_bottom_outlined,'Add to counters'),
       if(!deleted)iconMenuItem('edit',MenuIcons.edit,'Edit'),
       if(entry['source_url'].toString().isNotEmpty)iconMenuItem('link',Icons.open_in_new,'Open booking link'),
       iconMenuItem('remove',deleted?MenuIcons.restore:MenuIcons.remove,deleted?'Restore':'Remove'),
      ]),
    ]),
    Padding(padding:const EdgeInsetsDirectional.only(start:46,end:8),child:Column(
     crossAxisAlignment:CrossAxisAlignment.start,children:[
     if(from.isNotEmpty||to.isNotEmpty)
      Text(tt([if(from.isNotEmpty)from,if(to.isNotEmpty)to].join(' → '))),
     if(entry['end_date']!=null)Text(tt('Ends / arrives: ')+_date(entry['end_date'])+
       (entry['end_time']!=null?' · '+entry['end_time'].toString().substring(0,5):'')),
     if(entry['provider'].toString().isNotEmpty)Text(tt(entry['provider'].toString())),
     if(entry['booking_reference'].toString().isNotEmpty)
      Row(children:[
       Expanded(child:Text(tt('Reference: ')+entry['booking_reference'].toString())),
       IconButton(tooltip:tt('Copy booking reference'),icon:const Icon(Icons.copy_outlined,size:18),
        onPressed:()=>Clipboard.setData(ClipboardData(text:entry['booking_reference'].toString()))),
      ]),
     if(amount.isNotEmpty)Text(tt('Cost: ')+amount),
     if(entry['details'].toString().isNotEmpty)
      Padding(padding:const EdgeInsets.only(top:4),
       child:SelectableText(entry['details'].toString())),
    ])),
   ])));
 }

 Widget summary(Map<String,dynamic> t){
  final theme=Theme.of(context);
  final st=TripRules.status(t,DateTime.now());
  final from=place(t['origin']),to=place(t['destination']);
  final p=people;
  final who=t['traveler_id']==null?'Both of us':
   t['traveler_id']==p?.me?'Me':(p?.partnerName??'Partner');
  final pax=TripRules.passengers(t).map(tt).join(OneSpacePhrases.arabic?'، ':', ');
  final start=t['start_on'],end=t['end_on'];
  Widget chip(IconData icon,String text)=>Chip(
   avatar:Icon(icon,size:16),label:Text(tt(text)),visualDensity:VisualDensity.compact);
  return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
   if(from.isNotEmpty||to.isNotEmpty)Padding(padding:const EdgeInsets.only(top:4,bottom:6),
    child:Row(children:[
     Icon(tripModeIcon(t['travel_mode']?.toString()),color:theme.colorScheme.primary),
     const SizedBox(width:8),
     Expanded(child:Text(tt([if(from.isNotEmpty)from,if(to.isNotEmpty)to]
      .join(t['trip_type']=='one_way'?'  →  ':'  ⇄  ')),style:theme.textTheme.titleMedium)),
    ])),
   Wrap(spacing:6,runSpacing:4,children:[
    chip(st=='cancelled'?Icons.block:st=='completed'?Icons.task_alt:st=='traveling'?Icons.luggage
     :st=='booked'?Icons.confirmation_number_outlined:Icons.edit_note,tripStages[st]??'Planning'),
    if(start!=null)chip(Icons.event_outlined,_date(start)+(end!=null&&t['trip_type']!='one_way'?' – '+_date(end):'')),
    if(t['flexible_dates']==true)chip(Icons.date_range_outlined,'Flexible dates'),
    chip(Icons.group_outlined,tt(who)+(pax.isEmpty?'':' · '+pax)),
    if(t['visibility']=='private')chip(Icons.lock_outline,'Only me'),
   ]),
   if(start!=null&&st!='completed'&&st!='cancelled')Padding(padding:const EdgeInsets.only(top:6),
    child:Text(tt(TripRules.countdownLabel(DateTime.tryParse(start.toString()),DateTime.now())),
     style:theme.textTheme.titleSmall?.copyWith(color:theme.colorScheme.primary))),
  ]);
 }

 @override Widget build(BuildContext context){
  final t=trip;
  final active=items.where((i)=>i['archived_at']==null).toList();
  final shown=items.where((i)=>showRemoved||i['archived_at']==null).toList();
  final amounts=TripRules.sumByCurrency(active);
  final isFlight=(t?['travel_mode']??'flight')=='flight';
  final st=t==null?'planning':TripRules.status(t,DateTime.now());
  return Scaffold(
   appBar:AppBar(title:Text(tt('Trip')),actions:[
    if(t!=null)ItemMenu(kind:'trip',recordId:widget.tripId,title:t['title']?.toString(),
     statusActions:[
      if(t['archived_at']==null&&st!='cancelled'&&st!='completed')
       ItemMenuAction(tt('Cancel trip'),MenuIcons.cancel,()=>setCancelled(true)),
      if(t['archived_at']==null&&st=='cancelled')
       ItemMenuAction(tt('Reopen'),MenuIcons.reopen,()=>setCancelled(false)),
     ],
     onOpen:editTrip,
     moreActions:[
      if((OneSpaceEnv.isProduction||t['private_space_id']==null)&&
        t['space_id']!=null&&t['archived_at']==null&&CounterSource.trip(t)!=null)
       ItemMenuAction('Add to counters',Icons.hourglass_bottom_outlined,
        ()=>CounterSourceActions.open(context,t['space_id'].toString(),CounterSource.trip(t))),
      if(isFlight)ItemMenuAction(tt('Search on Google Flights'),Icons.travel_explore,
       ()=>openLink(tripGoogleFlights(t).toString())),
      if(OneSpaceEnv.isProduction||t['private_space_id']==null)
        ItemMenuAction(tt('Add a travel checklist'),Icons.checklist_outlined,
         ()=>TripPreparationSection.addChecklist(context,widget.tripId)),
      if(t['space_id']!=null)ItemMenuAction(tt('Create from this'),MenuIcons.createFrom,
       ()=>createFromThis(context,kind:LinkKind.trip,id:widget.tripId,
        spaceId:t['space_id'].toString(),title:t['title'].toString(),
        date:DateTime.tryParse(t['start_on']?.toString()??''),
        shared:t['visibility']!='private',onLinked:()=>_links.currentState?.reload())),
     ],
     removed:t['archived_at']!=null,
     onRemove:busy?null:setTripRemoved),
   ]),
   body:loading?const Center(child:CircularProgressIndicator()):
   t==null?Center(child:Text(tt(error??'Trip not available'))):RefreshIndicator(
    onRefresh:load,child:ListView(
    physics:const AlwaysScrollableScrollPhysics(),
    padding:const EdgeInsetsDirectional.fromSTEB(16,10,16,32),children:[
     Text(tt(t['title'].toString()),style:Theme.of(context).textTheme.headlineSmall),
     if(OneSpaceEnv.isProduction||t['private_space_id']==null)
       LinkedItemsStrip(key:_links,kind:LinkKind.trip,id:widget.tripId),
     summary(t),
     if((t['notes']??'').toString().isNotEmpty)
      Card(elevation:0,child:Padding(padding:const EdgeInsets.all(14),
       child:SelectableText(t['notes'].toString()))),
     const SizedBox(height:12),
     TripDocumentsSection(tripId:widget.tripId,itineraryItems:items),
     if(isFlight)...[
      const SizedBox(height:12),
      Card(elevation:0,clipBehavior:Clip.antiAlias,child:ExpansionTile(
       key:PageStorageKey('flights-${widget.tripId}-$flightBooked'),
       initiallyExpanded:flightsOpen??!flightBooked,
       onExpansionChanged:(v)=>flightsOpen=v,
       leading:Icon(flightBooked?Icons.check_circle:Icons.travel_explore,
        color:flightBooked?const Color(0xFF2E7D32):null),
       title:Text(tt('Flights'),style:Theme.of(context).textTheme.titleLarge),
       subtitle:Text(tt(flightBooked?'Booked · tap to see the options':'Search, save and compare')),
       childrenPadding:const EdgeInsets.fromLTRB(12,0,12,12),
       children:[TripFlightOptionsSection(tripId:widget.tripId,trip:t)])),
     ],
     const Divider(height:30),
     Row(children:[
      Expanded(child:Text(tt('Itinerary (')+active.length.toString()+')',
       style:Theme.of(context).textTheme.titleLarge)),
      if(items.any((i)=>i['archived_at']!=null))IconButton(
       tooltip:tt(showRemoved?'Hide removed':'Show removed'),isSelected:showRemoved,
       icon:const Icon(Icons.delete_outline),selectedIcon:const Icon(Icons.delete),
       onPressed:()=>setState(()=>showRemoved=!showRemoved)),
      FilledButton.tonalIcon(onPressed:()=>editItem(),icon:const Icon(Icons.add),
       label:Text(tt('Add'))),
     ]),
     Text(tt('Local times, exactly as on the booking.'),
      style:Theme.of(context).textTheme.bodySmall),
     const SizedBox(height:6),
     if(shown.isEmpty)Card(elevation:0,child:Padding(padding:const EdgeInsets.all(18),
       child:Text(tt('Add a flight, stay, activity or reservation to build the journey.')))),
     for(final entry in shown)itineraryCard(entry),
     if(amounts.isNotEmpty)...[
      const SizedBox(height:10),
      Text(tt('Costs so far: ')+tt(TripRules.formatTotals(amounts)),
       style:Theme.of(context).textTheme.titleSmall),
     ],
     if(OneSpaceEnv.isProduction||t['private_space_id']==null)
       TripPreparationSection(tripId:widget.tripId),
     const Divider(height:30),
     Text(tt(!OneSpaceEnv.isProduction&&t['private_space_id']!=null
       ?'My trip notes':'Trip conversation'),
       style:Theme.of(context).textTheme.titleLarge),
     const SizedBox(height:8),
     if(messages.where((m)=>m['archived_at']==null).isEmpty)
      Text(tt(!OneSpaceEnv.isProduction&&t['private_space_id']!=null
         ?'Keep personal notes about this trip.'
         :'Share ideas or updates for this trip.')),
     for(final m in messages.where((m)=>m['archived_at']==null))
      Card(elevation:0,child:ListTile(
       title:Text(tt(label(m['created_by']))),
       subtitle:Text(tt(m['body'].toString())),
       trailing:m['created_by']==db.auth.currentUser?.id?
        IconButton(tooltip:tt('Retract my message'),icon:const Icon(Icons.delete_outline),
         onPressed:busy?null:()=>retract(m)):null)),
     const SizedBox(height:10),
     TextField(controller:message,maxLength:3000,minLines:2,maxLines:4,
      decoration:InputDecoration(labelText:tt(!OneSpaceEnv.isProduction&&t['private_space_id']!=null
         ?'Add my note':'Share a thought'),
       border:const OutlineInputBorder())),
     Align(alignment:AlignmentDirectional.centerEnd,child:FilledButton.icon(
      onPressed:busy?null:postMessage,
      icon:const Icon(Icons.send_outlined),label:Text(tt('Send')))),
     if(error!=null)Text(tt(error!),style:TextStyle(color:Theme.of(context).colorScheme.error)),
    ])),
   );
 }
}

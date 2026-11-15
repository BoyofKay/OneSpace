import '../../core/editor_scaffold.dart';
import '../../core/status_look.dart';
import '../../core/linked_items.dart';
import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/current_space_cache.dart';
import '../../core/record_collection_search_rules.dart';
import '../../core/record_action_history_view.dart';
import '../../core/record_list_top_actions.dart';
import '../calendar/calendar_rules.dart';
import 'trip_item_editor.dart';
import 'trip_rules.dart';
import 'trip_documents_section.dart';
import 'trip_flight_options_section.dart';
import 'trip_preparation_section.dart';

const tripStages=<String,String>{
 'planning':'Planning','booked':'Booked','traveling':'Traveling',
 'completed':'Completed','cancelled':'Cancelled'
};

class TripsScreen extends StatefulWidget {
 const TripsScreen({super.key,this.initialTripId});
 final String? initialTripId;
 @override State<TripsScreen> createState()=>_TripsScreenState();
}
class _TripsScreenState extends State<TripsScreen> {
 final db=Supabase.instance.client;
 String? space,error;
 bool loading=true,openedDeepLink=false,showArchived=false;
 String filter='upcoming',query='';
 List<Map<String,dynamic>> trips=[];
 RealtimeChannel? _changes;
 Timer? _debounce;
 String? _watchedSpace;
 int _loadVersion=0;

 @override void initState(){super.initState();load();}
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
   final id=await CurrentSpaceCache.instance.get();
   if(!mounted||request!=_loadVersion||db.auth.currentUser?.id!=user)return;
   if(id==null){
    setState((){loading=false;space=null;trips=[];error=null;});
    final prior=_changes;
    if(prior!=null)unawaited(db.removeChannel(prior));
    _changes=null;_watchedSpace=null;
    return;
   }
   final data=await db.from('shared_trips').select().eq('space_id',id)
     .order('updated_at',ascending:false).limit(200);
   if(!mounted||request!=_loadVersion||db.auth.currentUser?.id!=user)return;
   setState((){
    space=id;loading=false;error=null;trips=List<Map<String,dynamic>>.from(data);
   });
   _watch(id);
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
  if(space==null)return;
  final saved=await Navigator.of(context).push<bool>(MaterialPageRoute(
   builder:(_)=>TripEditor(spaceId:space!,existing:trip)));
  if(saved==true&&mounted)await load();
 }
 Future<void> open(Map<String,dynamic> trip)async{
  await Navigator.of(context).push<void>(MaterialPageRoute(
   builder:(_)=>TripDetail(tripId:trip['id'].toString())));
  if(mounted)await load();
 }
 /// R55: this screen's filter groups (drawn by the shared panel).
 List<FilterGroupSpec> _filterGroups()=>[FilterGroupSpec(id:'when',label:'Trips',options:const {'upcoming':'Upcoming','past':'Past','all':'All'},selected:filter,defaultValue:'upcoming')];

 @override Widget build(BuildContext context){
  final now=CalendarRules.day(DateTime.now());
  final visible=trips.where((trip){
   if(!RecordCollectionSearchRules.inHistory(trip,showArchived))return false;
   if(!RecordCollectionSearchRules.matches(trip,query,
    fields:const ['title','destination','origin','notes']))return false;
   if(showArchived||filter=='all')return true;
   final end=DateTime.tryParse((trip['end_on']??trip['start_on']??'').toString());
   final past=end!=null&&end.isBefore(now);
   if(filter=='past')return past||trip['status']=='completed';
   return !past&&trip['status']!='completed'&&trip['status']!='cancelled';
  }).toList();
  return Scaffold(
   appBar:AppBar(title:const Text('Trips & journeys'),actions:[
    RecordListTopActions(
     historyKinds:const ['trip'],historyTitle:'Trips',
     showHistory:showArchived,
     onToggleHistory:()=>setState(()=>showArchived=!showArchived),
     groups:_filterGroups(),
      onApply:(v)=>setState((){filter=v['when']!;}),
     ),
   ],bottom:filterShowingBar(_filterGroups(),removed:showArchived,onClear:()=>setState((){showArchived=false;filter='upcoming';}))),
   floatingActionButton:space==null?null:FloatingActionButton.extended(
    icon:const Icon(Icons.add),label:const Text('Plan a trip'),onPressed:()=>edit()),
   body:RefreshIndicator(onRefresh:load,child:ListView(
    physics:const AlwaysScrollableScrollPhysics(),
    padding:const EdgeInsets.fromLTRB(16,12,16,90),children:[
    Text('Our journeys',style:Theme.of(context).textTheme.titleLarge),
    const SizedBox(height:6),
    Text('From the next reunion to the smallest weekend getaway. Plan it together, one detail at a time.',
      style:Theme.of(context).textTheme.bodyMedium),
    const SizedBox(height:15),
    TextField(onChanged:(v)=>setState(()=>query=v),
     decoration:const InputDecoration(prefixIcon:Icon(Icons.search),
      labelText:'Find a trip or destination',border:OutlineInputBorder())),
    const SizedBox(height:8),
    if(showArchived)Padding(
     padding:const EdgeInsets.only(bottom:8),
     child:Text('Removed trips · Open one to restore it.',
      style:Theme.of(context).textTheme.bodySmall)),
    if(error!=null)Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
    if(loading)const Padding(padding:EdgeInsets.all(24),child:Center(child:CircularProgressIndicator()))
    else if(space==null)const Text('Connect your shared space first.')
    else if(visible.isEmpty)const Padding(padding:EdgeInsets.all(24),
     child:Text('No trips in this view yet. Your next adventure can start here.'))
    else for(final trip in visible)Card(elevation:0,clipBehavior:Clip.antiAlias,
     child:ListTile(
      contentPadding:const EdgeInsets.symmetric(horizontal:14,vertical:8),
      leading:CircleAvatar(child:StatusLook.mark(trip['status']?.toString())??Icon(trip['visibility']=='private'?
       Icons.lock_outline:Icons.flight_takeoff_outlined)),
      title:Text(trip['title'].toString(),
       style:StatusLook.title(context,trip['status']?.toString(),Theme.of(context).textTheme.titleMedium)),
      subtitle:Text([
       if((trip['destination']??'').toString().isNotEmpty)trip['destination'].toString(),
       tripStages[trip['status']]??'Planning',
       if(trip['start_on']!=null)trip['start_on'].toString()+
         (trip['end_on']!=null?' – '+trip['end_on'].toString():''),
       if(trip['visibility']=='private')'Only me',
      ].join(' · '),maxLines:4),
      trailing:const Icon(Icons.chevron_right),onTap:()=>open(trip),
     )),
   ])));
 }
}

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
 /// R55: current form values; Save turns on only when they change.
 @override String get signature=>[title.text,origin.text,destination.text,notes.text,from,to,status,visibility].join('|');

 final db=Supabase.instance.client;
 late final TextEditingController title,origin,destination,notes;
 late String status,visibility;
 DateTime? from,to;
 bool saving=false;
 String? error;
 @override void initState(){
  super.initState();
  final x=widget.existing??widget.prefill??{};
  title=TextEditingController(text:(x['title']??'').toString());
  origin=TextEditingController(text:(x['origin']??'').toString());
  destination=TextEditingController(text:(x['destination']??'').toString());
  notes=TextEditingController(text:(x['notes']??'').toString());
  status=(x['status']??'planning').toString();
  visibility=(x['visibility']??'shared').toString();
  from=DateTime.tryParse((x['start_on']??'').toString());
  to=DateTime.tryParse((x['end_on']??'').toString());
 }
 @override void dispose(){
  title.dispose();origin.dispose();destination.dispose();notes.dispose();
  super.dispose();
 }
 Future<void> pick(bool isEnd)async{
  final d=await showDatePicker(context:context,
    firstDate:DateTime(2000),lastDate:DateTime(2100),
    initialDate:(isEnd?to:from)??DateTime.now());
  if(d!=null&&mounted)setState((){
   if(isEnd){to=d;}else{from=d;}
  });
 }
 Future<void> save()async{
  if(saving)return;
  if(title.text.trim().isEmpty){
   setState(()=>error='Give the trip a title.');return;
  }
  if(from!=null&&to!=null&&to!.isBefore(from!)){
   setState(()=>error='The return date cannot be before departure.');return;
  }
  setState((){saving=true;error=null;});
  try{
   final values=<String,dynamic>{
    'title':title.text.trim(),'origin':origin.text.trim(),
    'destination':destination.text.trim(),'notes':notes.text.trim(),
    'status':status,
    'start_on':from==null?null:CalendarRules.sqlDate(from!),
    'end_on':to==null?null:CalendarRules.sqlDate(to!),
   };
   if(widget.existing==null){
    final created=await db.from('shared_trips').insert({
     ...values,'space_id':widget.spaceId,'visibility':visibility,
    }).select('id').single();
    await widget.onCreated?.call(created['id'].toString());
   }else{
    await db.from('shared_trips').update(values).eq('id',widget.existing!['id']);
   }
   if(mounted)Navigator.pop(context,true);
  }on PostgrestException catch(e){
   if(mounted)setState(()=>error=e.message);
  }catch(_){
   if(mounted)setState(()=>error='Unable to save trip.');
  }finally{
   if(mounted)setState(()=>saving=false);
  }
 }
 @override Widget build(BuildContext context)=>EditorScaffold(title:widget.existing==null?'Add new trip':'Edit trip',
   isNew:widget.existing==null,isChanged:()=>changed,isComplete:()=>title.text.trim().isNotEmpty,
   listenTo:[title,origin,destination,notes],saving:saving,onSave:save,
   body:ListView(padding:const EdgeInsets.all(16),children:[
   Text('The journey starts here',style:Theme.of(context).textTheme.titleLarge),
   const SizedBox(height:12),
   TextField(controller:title,maxLength:160,
    decoration:const InputDecoration(labelText:'Trip name *',border:OutlineInputBorder())),
   const SizedBox(height:8),
   TextField(controller:origin,maxLength:160,
    decoration:const InputDecoration(labelText:'Traveling from (optional)',border:OutlineInputBorder())),
   const SizedBox(height:8),
   TextField(controller:destination,maxLength:160,
    decoration:const InputDecoration(labelText:'Destination (optional)',border:OutlineInputBorder())),
   const SizedBox(height:12),
   ListTile(title:const Text('Departure date'),
    leading:const Icon(Icons.flight_takeoff_outlined),
    subtitle:Text(from==null?'Not set':CalendarRules.sqlDate(from!)),
    onTap:()=>pick(false),trailing:IconButton(tooltip:'Clear departure',
     icon:const Icon(Icons.clear),onPressed:()=>setState(()=>from=null))),
   ListTile(title:const Text('Return date'),
    leading:const Icon(Icons.flight_land_outlined),
    subtitle:Text(to==null?'Not set':CalendarRules.sqlDate(to!)),
    onTap:()=>pick(true),trailing:IconButton(tooltip:'Clear return',
     icon:const Icon(Icons.clear),onPressed:()=>setState(()=>to=null))),
   const SizedBox(height:8),
   DropdownButtonFormField<String>(
    initialValue:status,
    decoration:const InputDecoration(labelText:'Trip status',border:OutlineInputBorder()),
    items:[for(final stage in tripStages.entries)
     DropdownMenuItem(value:stage.key,child:Text(stage.value))],
    onChanged:(v)=>setState(()=>status=v??status)),
   const SizedBox(height:12),
   TextField(controller:notes,maxLength:5000,maxLines:4,
    decoration:const InputDecoration(labelText:'Plans, ideas and things to remember',
     border:OutlineInputBorder())),
   const SizedBox(height:12),
   if(widget.existing==null)SwitchListTile(
    contentPadding:EdgeInsets.zero,
    title:const Text('Only me'),
    subtitle:const Text('Off means both of us can plan and edit this journey.'),
    value:visibility=='private',
    onChanged:(v)=>setState(()=>visibility=v?'private':'shared'),
   )else ListTile(
    leading:Icon(visibility=='private'?Icons.lock_outline:Icons.people_outline),
    title:Text(visibility=='private'?'Only me':'Both of us'),
    subtitle:const Text('Privacy stays fixed to protect existing travel information.'),
   ),
   if(error!=null)Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
  ]));
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
 List<Map<String,dynamic>> items=[],messages=[],history=[];
 bool loading=true,busy=false,showRemoved=false,showHistory=false;
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
    table:'trip_messages',filter:PostgresChangeFilter(
     type:PostgresChangeFilterType.eq,column:'trip_id',value:widget.tripId),
    callback:(_)=>_scheduleRefresh())
   .subscribe();
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
    // Only request the audit fields used by the collapsed history UI.
    safe(db.from('trip_revisions')
     .select('id,record_kind,changed_by,changed_at')
     .eq('trip_id',widget.tripId).order('changed_at',ascending:false).limit(60)),
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
    if(results[2]!=null)history=List<Map<String,dynamic>>.from(results[2]);
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
   builder:(_)=>TripEditor(spaceId:trip!['space_id'].toString(),existing:trip)));
  if(saved==true&&mounted)await load();
 }
 Future<void> editItem([Map<String,dynamic>? item])async{
  final saved=await Navigator.of(context).push<bool>(MaterialPageRoute(
   builder:(_)=>TripItemEditor(tripId:widget.tripId,existing:item)));
  if(saved==true&&mounted)await load();
 }
 Future<void> setTripRemoved()async{
  final t=trip;if(t==null)return;
  await mutate(()async{
   await db.from('shared_trips').update({
    'archived_at':t['archived_at']==null?DateTime.now().toUtc().toIso8601String():null,
   }).eq('id',widget.tripId);
  });
 }
 Future<void> setItemRemoved(Map<String,dynamic> item)async{
  await mutate(()async{
   await db.from('trip_items').update({
    'archived_at':item['archived_at']==null?DateTime.now().toUtc().toIso8601String():null,
   }).eq('id',item['id']).eq('trip_id',widget.tripId);
  });
 }
 Future<void> toggleItem(Map<String,dynamic> item)async{
  await mutate(()async{
   await db.from('trip_items').update({'done':item['done']!=true})
    .eq('id',item['id']).eq('trip_id',widget.tripId);
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
     const SnackBar(content:Text('Could not open this link.')));
   }
  }catch(_){
   if(mounted)ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content:Text('Could not open this link.')));
  }
 }
 String label(Object? user)=>user==db.auth.currentUser?.id?'You':'Partner';
 String _date(Object? raw)=>raw==null?'Unscheduled':raw.toString();
 IconData kindIcon(String kind)=>switch(kind){
  'flight'=>Icons.flight_outlined,
  'stay'=>Icons.hotel_outlined,
  'transport'=>Icons.directions_car_outlined,
  'activity'=>Icons.place_outlined,
  'booking'=>Icons.book_online_outlined,
  _=>Icons.note_alt_outlined,
 };
 Widget itineraryCard(Map<String,dynamic> entry){
  final deleted=entry['archived_at']!=null;
  final title=entry['title'].toString();
  final start=entry['local_date']==null?'Date not set':
   _date(entry['local_date'])+
   (entry['local_time']!=null?' · '+entry['local_time'].toString().substring(0,5):'');
  final amount=entry['estimated_cost']==null?'':entry['currency'].toString()+
    ' '+entry['estimated_cost'].toString();
  return Card(elevation:0,child:Padding(padding:const EdgeInsets.all(10),
   child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Row(children:[
     CircleAvatar(radius:18,child:Icon(kindIcon(entry['kind'].toString()),size:20)),
     const SizedBox(width:10),
     Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(title,style:Theme.of(context).textTheme.titleMedium),
      Text((tripItemKinds[entry['kind']]??'Travel item')+' · '+start,
       style:Theme.of(context).textTheme.bodySmall),
     ])),
     IconButton(onPressed:deleted||busy?null:()=>editItem(entry),
      tooltip:'Edit itinerary item',icon:const Icon(Icons.edit_outlined)),
    ]),
    if(entry['location'].toString().isNotEmpty||entry['destination'].toString().isNotEmpty)
     Padding(padding:const EdgeInsets.only(top:5),child:Text(
      [if(entry['location'].toString().isNotEmpty)entry['location'].toString(),
       if(entry['destination'].toString().isNotEmpty)entry['destination'].toString()].join(' → '))),
    if(entry['end_date']!=null)Text('Ends / arrives: '+_date(entry['end_date'])+
      (entry['end_time']!=null?' · '+entry['end_time'].toString().substring(0,5):'')),
    if(entry['provider'].toString().isNotEmpty)
     Text('Provider: '+entry['provider'].toString()),
    if(entry['booking_reference'].toString().isNotEmpty)
     Row(children:[
      Expanded(child:Text('Reference: '+entry['booking_reference'].toString())),
      IconButton(tooltip:'Copy booking reference',icon:const Icon(Icons.copy_outlined),
       onPressed:()=>Clipboard.setData(ClipboardData(text:entry['booking_reference'].toString()))),
     ]),
    if(amount.isNotEmpty)Text('Estimated cost: '+amount),
    if(entry['details'].toString().isNotEmpty)
     Padding(padding:const EdgeInsets.symmetric(vertical:6),
      child:SelectableText(entry['details'].toString())),
    if(entry['source_url'].toString().isNotEmpty)
     TextButton.icon(onPressed:()=>openLink(entry['source_url'].toString()),
      icon:const Icon(Icons.open_in_new),label:const Text('Open booking link')),
    Wrap(spacing:5,children:[
     OutlinedButton.icon(onPressed:deleted||busy?null:()=>toggleItem(entry),
      icon:Icon(entry['done']==true?Icons.check_circle:Icons.circle_outlined),
      label:Text(entry['done']==true?'Done':'Mark done')),
     TextButton.icon(onPressed:busy?null:()=>setItemRemoved(entry),
      icon:Icon(deleted?Icons.restore_outlined:Icons.archive_outlined),
      label:Text(deleted?'Restore':'Remove')),
    ]),
   ])));
 }

 @override Widget build(BuildContext context){
  final t=trip;
  final active=items.where((i)=>i['archived_at']==null).toList();
  final shown=items.where((i)=>showRemoved||i['archived_at']==null).toList();
  final amounts=TripRules.sumByCurrency(active);
  return Scaffold(
   appBar:AppBar(title:const Text('Trip details'),actions:[
    if(t!=null&&t['space_id']!=null)CreateFromThisButton(kind:LinkKind.trip,id:widget.tripId,spaceId:t['space_id'].toString(),title:t['title'].toString(),date:DateTime.tryParse(t['start_on']?.toString()??''),shared:t['visibility']!='private',stripKey:_links),
    if(t!=null)RecordActionHistoryButton(
     kind:'trip',recordId:widget.tripId),
    IconButton(tooltip:'Refresh trip',icon:const Icon(Icons.refresh),onPressed:load),
    if(t!=null)IconButton(tooltip:'Edit trip',icon:const Icon(Icons.edit_outlined),onPressed:editTrip),
    if(t!=null)IconButton(tooltip:t['archived_at']==null?'Remove trip':'Restore trip',
     icon:Icon(t['archived_at']==null?Icons.archive_outlined:Icons.restore_outlined),
     onPressed:busy?null:setTripRemoved),
   ]),
   body:loading?const Center(child:CircularProgressIndicator()):
   t==null?Center(child:Text(error??'Trip not available')):RefreshIndicator(
    onRefresh:load,child:ListView(
    physics:const AlwaysScrollableScrollPhysics(),
    padding:const EdgeInsets.fromLTRB(16,14,16,32),children:[
     Text(t['title'].toString(),style:Theme.of(context).textTheme.headlineSmall),
     LinkedItemsStrip(key:_links,kind:LinkKind.trip,id:widget.tripId),
     const SizedBox(height:6),
     Text((tripStages[t['status']]??'Planning')+' · '+
       (t['visibility']=='private'?'Only me':'Both of us')),
     if((t['origin']??'').toString().isNotEmpty||(t['destination']??'').toString().isNotEmpty)
      Text([if((t['origin']??'').toString().isNotEmpty)t['origin'].toString(),
        if((t['destination']??'').toString().isNotEmpty)t['destination'].toString()].join(' → ')),
     if(t['start_on']!=null)Text('Departure: '+_date(t['start_on'])),
     if(t['end_on']!=null)Text('Return: '+_date(t['end_on'])),
     if(t['start_on']!=null)Text(
       TripRules.countdownLabel(DateTime.tryParse(t['start_on'].toString()),DateTime.now())),
     if((t['notes']??'').toString().isNotEmpty)
      Card(elevation:0,child:Padding(padding:const EdgeInsets.all(14),
       child:SelectableText(t['notes'].toString()))),
     const Divider(height:26),
     TripFlightOptionsSection(tripId:widget.tripId,trip:t),
     const Divider(height:26),
     Wrap(spacing:10,runSpacing:6,
      alignment:WrapAlignment.spaceBetween,crossAxisAlignment:WrapCrossAlignment.center,
      children:[
       Text('Itinerary ('+active.length.toString()+')',
        style:Theme.of(context).textTheme.titleLarge),
       TextButton.icon(onPressed:()=>editItem(),icon:const Icon(Icons.add),
        label:const Text('Add item')),
      ]),
     Text('Local times match the booking and do not convert between time zones.',
      style:Theme.of(context).textTheme.bodySmall),
     SwitchListTile(contentPadding:EdgeInsets.zero,
      title:const Text('Show removed items'),value:showRemoved,
      onChanged:(v)=>setState(()=>showRemoved=v)),
     if(shown.isEmpty)const Card(child:Padding(padding:EdgeInsets.all(18),
       child:Text('Add a flight, stay, activity or reservation to build the journey.'))),
     for(final entry in shown)itineraryCard(entry),
     if(amounts.isNotEmpty)...[
      const SizedBox(height:10),
      Text('Estimated costs',style:Theme.of(context).textTheme.titleMedium),
      Text(TripRules.formatTotals(amounts)),
     ],
     const Divider(height:30),
     TripPreparationSection(tripId:widget.tripId),
     const Divider(height:30),
     TripDocumentsSection(tripId:widget.tripId,itineraryItems:items),
     const Divider(height:30),
     Text('Trip conversation',style:Theme.of(context).textTheme.titleLarge),
     const SizedBox(height:8),
     if(messages.where((m)=>m['archived_at']==null).isEmpty)
      const Text('Share ideas or updates for this trip.'),
     for(final m in messages.where((m)=>m['archived_at']==null))
      Card(elevation:0,child:ListTile(
       title:Text(label(m['created_by'])),
       subtitle:Text(m['body'].toString()),
       trailing:m['created_by']==db.auth.currentUser?.id?
        IconButton(tooltip:'Retract my message',icon:const Icon(Icons.delete_outline),
         onPressed:busy?null:()=>retract(m)):null)),
     const SizedBox(height:10),
     TextField(controller:message,maxLength:3000,minLines:2,maxLines:4,
      decoration:const InputDecoration(labelText:'Share a thought',
       border:OutlineInputBorder())),
     Align(alignment:Alignment.centerRight,child:FilledButton.icon(
      onPressed:busy?null:postMessage,
      icon:const Icon(Icons.send_outlined),label:const Text('Send'))),
     const Divider(height:28),
     ListTile(leading:const Icon(Icons.history),title:const Text('Change history'),
      trailing:Icon(showHistory?Icons.expand_less:Icons.expand_more),
      onTap:()=>setState(()=>showHistory=!showHistory)),
     if(showHistory)...[
      if(history.isEmpty)const Text('No changes recorded yet.'),
      for(final event in history)ListTile(
       dense:true,
       title:Text((event['record_kind']??'Item').toString()+' edited by '+
         label(event['changed_by'])),
       subtitle:Text((event['changed_at']??'').toString().replaceFirst('T',' ').split('.').first)),
     ],
     if(error!=null)Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
    ])),
   );
 }
}

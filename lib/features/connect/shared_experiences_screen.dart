import '../../core/form_kit.dart';
import '../../core/item_menu.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/editor_scaffold.dart';
import '../../core/linked_items.dart';
import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/current_space_cache.dart';
import '../../core/record_collection_search_rules.dart';
import '../../core/record_list_top_actions.dart';
import 'experience_picker_rules.dart';
import 'experience_interest_rules.dart';
import 'experience_comment_rules.dart';
import '../notes/related_notes_panel.dart';
import '../../core/record_action_history_view.dart';
import '../mentions/partner_mention_button.dart';

const experienceTypes={'movie':'Movie Watchlist','show':'TV Shows','music':'Music Playlist','book':'Books and articles','game':'Games','other':'Others'};
const experienceStates={'suggested':'Suggested','planned':'Planned','enjoyed':'Enjoyed'};

class SharedExperiencesScreen extends StatefulWidget {
 const SharedExperiencesScreen({super.key,this.initialExperienceId,this.collection});
 final String? initialExperienceId;
 /// R55: one watchlist/collection on its own page (null = the home page).
 final String? collection;
 @override State<SharedExperiencesScreen> createState()=>_SharedExperiencesScreenState();
}
class _SharedExperiencesScreenState extends State<SharedExperiencesScreen>{
 final db=Supabase.instance.client;
 String? space,error;
 bool loading=true,showArchived=false,opened=false,busy=false,mutualOnly=false;
 String kind='all',status='open',search='';
 int suggestionOffset=0;
 List<Map<String,dynamic>> rows=[],interests=[];
 RealtimeChannel? _changes;
 Timer? _refreshTimer;
 String? _watchedSpace;
 int _loadVersion=0;
 @override void initState(){
  super.initState();
  if(widget.collection!=null)kind=widget.collection!;
  load().then((_){if(mounted)_maybeSuggest();});
 }

 /// R55: "What shall we do together?" as a pop-up on the home page, at most
 /// once every 30 minutes; dismiss with ✕ or by tapping outside.
 static const _suggestKey='onespace_experience_suggestion_shown_v1';
 Future<void> _maybeSuggest()async{
  if(widget.collection!=null||widget.initialExperienceId!=null||rows.isEmpty)return;
  final prefs=SharedPreferencesAsync();
  try{
   final last=DateTime.tryParse(await prefs.getString(_suggestKey)??'');
   if(last!=null&&DateTime.now().difference(last).inMinutes<30)return;
  }catch(_){}
  final candidates=ExperiencePickerRules.shortlist(rows,category:'all');
  final mutual=candidates.where((r)=>
   ExperienceInterestRules.mutuallyInterested(interests,r['id'])).toList();
  final pool=mutual.isNotEmpty?mutual:candidates;
  if(pool.isEmpty||!mounted)return;
  try{await prefs.setString(_suggestKey,DateTime.now().toIso8601String());}catch(_){}
  if(!mounted)return;
  var offset=0;
  await showDialog<void>(context:context,barrierDismissible:true,
   builder:(ctx)=>StatefulBuilder(builder:(ctx,refresh){
    final pick=ExperiencePickerRules.pick(pool,offset:offset);
    if(pick==null)return const SizedBox.shrink();
    final scheme=Theme.of(ctx).colorScheme;
    return Dialog(
     shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(22)),
     child:Padding(padding:const EdgeInsets.fromLTRB(20,10,10,18),child:Column(
      mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
       Row(children:[
        Icon(Icons.auto_awesome,color:scheme.primary),
        const SizedBox(width:8),
        Expanded(child:Text('What shall we do together?',
         style:Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight:FontWeight.w700))),
        IconButton(tooltip:'Close',icon:const Icon(Icons.close),
         onPressed:()=>Navigator.pop(ctx)),
       ]),
       Padding(padding:const EdgeInsets.only(right:10),child:Column(
        crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(mutual.isNotEmpty?'From the things you both picked.':'From your own collection.',
         style:Theme.of(ctx).textTheme.bodySmall),
        const SizedBox(height:14),
        Row(children:[
         Icon(typeIcon(pick['category'].toString()),color:scheme.primary,size:30),
         const SizedBox(width:10),
         Expanded(child:Text(pick['title'].toString(),
          style:Theme.of(ctx).textTheme.headlineSmall)),
        ]),
        const SizedBox(height:18),
        // R57: three small chips on one line.
        Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
         ActionChip(avatar:const Icon(Icons.event_available_outlined,size:18),
          label:const Text('Plan'),visualDensity:VisualDensity.compact,
          onPressed:(){Navigator.pop(ctx);planSuggestion(pick);}),
         ActionChip(avatar:const Icon(Icons.shuffle,size:18),
          label:const Text('Another'),visualDensity:VisualDensity.compact,
          onPressed:()=>refresh(()=>offset++)),
         ActionChip(avatar:const Icon(Icons.open_in_new,size:18),
          label:const Text('View'),visualDensity:VisualDensity.compact,
          onPressed:(){Navigator.pop(ctx);open(pick);}),
        ]),
       ])),
      ])));
   }));
 }
 @override void dispose(){
  _loadVersion++;
  _refreshTimer?.cancel();
  if(_changes!=null)unawaited(db.removeChannel(_changes!));
  super.dispose();
 }
 void _watch(String spaceId){
  if(_watchedSpace==spaceId)return;
  final old=_changes;
  if(old!=null)unawaited(db.removeChannel(old));
  _watchedSpace=spaceId;
  _changes=db.channel('experience-list-'+spaceId)
   .onPostgresChanges(event:PostgresChangeEvent.all,schema:'public',
    table:'shared_experiences',filter:PostgresChangeFilter(
     type:PostgresChangeFilterType.eq,column:'space_id',value:spaceId),
    callback:(_)=>_scheduleRefresh())
   .onPostgresChanges(event:PostgresChangeEvent.all,schema:'public',
    table:'shared_experience_interests',callback:(_)=>_scheduleRefresh())
   .subscribe();
 }
 void _scheduleRefresh(){
  _refreshTimer?.cancel();
  _refreshTimer=Timer(const Duration(milliseconds:650),(){
   if(mounted)unawaited(load());
  });
 }
 Future<void> load()async{
  final request=++_loadVersion;
  final account=db.auth.currentUser?.id;
  if(account==null){
   if(_changes!=null)unawaited(db.removeChannel(_changes!));
   _changes=null;_watchedSpace=null;
   if(mounted)setState((){space=null;rows=[];interests=[];loading=false;error=null;});
   return;
  }
  try{
   final id=await CurrentSpaceCache.instance.get();
   if(!mounted||request!=_loadVersion||db.auth.currentUser?.id!=account)return;
   if(id==null){
    if(_changes!=null)unawaited(db.removeChannel(_changes!));
    _changes=null;_watchedSpace=null;
    setState((){space=null;rows=[];interests=[];loading=false;error=null;});
    return;
   }
   final result=await db.from('shared_experiences').select().eq('space_id',id)
      .order('updated_at',ascending:false).limit(250);
   final currentRows=List<Map<String,dynamic>>.from(result);
   final ids=currentRows.map((x)=>x['id'].toString()).toList();
   final currentInterests=ids.isEmpty?<Map<String,dynamic>>[]:
    List<Map<String,dynamic>>.from(
     await db.from('shared_experience_interests')
      .select('experience_id,user_id,choice').inFilter('experience_id',ids));
   if(!mounted||request!=_loadVersion||db.auth.currentUser?.id!=account)return;
   setState((){space=id;rows=currentRows;interests=currentInterests;
    loading=false;error=null;});
   _watch(id);
   if(!opened&&widget.initialExperienceId!=null){
    opened=true;
    final found=rows.where((x)=>x['id']==widget.initialExperienceId).firstOrNull;
    WidgetsBinding.instance.addPostFrameCallback((_){
     if(!mounted)return;
     if(found!=null){
      open(found);
     }else{
      // An authorized notification can reference an older experience
      // beyond the initial list page. Its detail query is RLS-protected.
      Navigator.of(context).push<void>(MaterialPageRoute(
       builder:(_)=>ExperienceDetail(id:widget.initialExperienceId!)));
     }
    });
   }
  }catch(_){
   if(mounted&&request==_loadVersion&&db.auth.currentUser?.id==account)
    setState((){error='Unable to load experiences. Pull down to retry.';
     loading=false;});
  }
 }
 IconData typeIcon(String c)=>switch(c){
  'movie'=>Icons.movie_creation_outlined,
  'show'=>Icons.live_tv_outlined,
  'music'=>Icons.queue_music_outlined,
  'book'=>Icons.menu_book_outlined,
  'game'=>Icons.sports_esports_outlined,
  _=>Icons.explore_outlined,
 };

 Future<void> markWatched(Map<String,dynamic> row)async{
  if(busy)return;
  setState(()=>busy=true);
  try{
   final changed=await updateSafely(row,{
    'status':'enjoyed',
    'enjoyed_on':ExperiencePickerRules.dateOnly(DateTime.now()),
   });
   if(changed&&mounted)await quickRate(row);
  }catch(_){
   if(mounted)ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content:Text('Could not mark as watched.')));
  }finally{if(mounted)setState(()=>busy=false);}
 }
 Future<void> openPlatform(Map<String,dynamic> row)async{
  final raw=(row['source_url']??'').toString();
  final url=Uri.tryParse(raw);
  if(url==null||!['http','https'].contains(url.scheme)||url.host.isEmpty){
   ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
    content:Text('Add a valid platform link in Edit first.')));
   return;
  }
  if(!await launchUrl(url,mode:LaunchMode.externalApplication)&&mounted){
   ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content:Text('Could not open this platform.')));
  }
 }
 Future<void> quickRate(Map<String,dynamic> row)async{
  int? rating;
  final review=TextEditingController();
  try{
   final old=await db.from('shared_experience_reviews')
    .select('rating,review').eq('experience_id',row['id'])
    .eq('user_id',db.auth.currentUser!.id).limit(1);
   rating=(old.firstOrNull?['rating'] as num?)?.toInt();
   review.text=(old.firstOrNull?['review']??'').toString();
   if(!mounted)return;
   final confirm=await showDialog<bool>(context:context,builder:(ctx)=>
    StatefulBuilder(builder:(ctx,update)=>AlertDialog(
     title:Text('Rate '+row['title'].toString()),
     content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
      Wrap(children:[for(var i=1;i<=5;i++)IconButton(
       tooltip:'Rate '+i.toString(),
       icon:Icon((rating??0)>=i?Icons.star:Icons.star_border),
       onPressed:()=>update(()=>rating=i))]),
      TextField(controller:review,maxLength:2000,maxLines:3,
       decoration:const InputDecoration(labelText:'Review (optional)')),
     ])),
     actions:[
      TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),
      FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Save rating')),
     ],
    )));
   if(confirm!=true||rating==null)return;
   final me=db.auth.currentUser!.id;
   final found=await db.from('shared_experience_reviews')
    .select('user_id').eq('experience_id',row['id']).eq('user_id',me).limit(1);
   final fields={'rating':rating,'review':review.text.trim()};
   if(found.isNotEmpty){
    await db.from('shared_experience_reviews').update(fields)
     .eq('experience_id',row['id']).eq('user_id',me);
   }else{
    try{
     await db.from('shared_experience_reviews').insert({
      'experience_id':row['id'],'user_id':me,...fields});
    }on PostgrestException catch(e){
     if(e.code!='23505')rethrow;
     await db.from('shared_experience_reviews').update(fields)
      .eq('experience_id',row['id']).eq('user_id',me);
    }
   }
  }catch(_){
   if(mounted)ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content:Text('Unable to save review. Try again.')));
  }finally{review.dispose();}
 }
 Future<void> archiveFromList(Map<String,dynamic> row)async{
  final archived=row['archived_at']!=null;
  if(!archived){
   final yes=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
    title:const Text('Remove this experience?'),
    content:const Text('It will move to experience history. Reviews remain saved.'),
    actions:[
     TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Keep')),
     FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Remove')),
    ]));
   if(yes!=true)return;
  }
  try{
   await updateSafely(row,{
    'archived_at':archived?null:DateTime.now().toUtc().toIso8601String()
   });
  }catch(_){
   if(mounted)ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content:Text('Could not remove or restore this item.')));
  }
 }
 Future<void> openHistory()async{
  if(space==null)return;
  try{
   final ids=rows.map((r)=>r['id'].toString()).take(250).toList();
   if(ids.isEmpty)return;
   final records=await db.from('shared_experience_revisions')
    .select('experience_id,changed_by,changed_at,before_snapshot,after_snapshot')
    .inFilter('experience_id',ids).order('changed_at',ascending:false).limit(80);
   if(!mounted)return;
   await showModalBottomSheet<void>(context:context,showDragHandle:true,
    isScrollControlled:true,builder:(ctx)=>SafeArea(
     child:SizedBox(height:MediaQuery.sizeOf(ctx).height*.68,
      child:ListView(padding:const EdgeInsets.all(16),children:[
       Text('Our experience history',style:Theme.of(ctx).textTheme.titleLarge),
       const Text('Only changes to Movies, TV, Music, Books, Games and Others.'),
       for(final r in records)ListTile(
        leading:const Icon(Icons.history_outlined),
        title:Text(rows.where((x)=>x['id']==r['experience_id'])
         .map((x)=>x['title'].toString()).firstOrNull??'Experience'),
        subtitle:Text(((r['before_snapshot'] as Map?)?['status']??'').toString()+
         ' → '+((r['after_snapshot'] as Map?)?['status']??'').toString()+
         ' · '+(r['changed_at']??'').toString().split('T').first),
       ),
      ]))));
  }catch(_){
   if(mounted)ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content:Text('Experience history is unavailable.')));
  }
 }
 Future<bool> updateSafely(
  Map<String,dynamic> row,Map<String,dynamic> values)async{
  final updated=await db.from('shared_experiences').update(values)
   .eq('id',row['id']).eq('updated_at',row['updated_at'])
   .select('id');
  if(updated.isEmpty){
   await load();
   if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
    content:Text('Your partner changed this experience. Refreshed the latest version.')));
   return false;
  }
  await load();
  return true;
 }
 Future<void> planSuggestion(Map<String,dynamic> row)async{
  if(busy||space==null)return;
  final initial=DateTime.tryParse((row['planned_on']??'').toString())??DateTime.now();
  final day=await showDatePicker(context:context,initialDate:initial,
   firstDate:DateTime(2000),lastDate:DateTime(2100));
  if(day==null||!mounted)return;
  setState(()=>busy=true);
  try{
   final updated=await updateSafely(row,{
    'status':'planned','planned_on':ExperiencePickerRules.dateOnly(day)});
   if(updated&&mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
    content:Text('Saved your plan. Your partner can see it too.')));
  }catch(_){
   if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
    content:Text('Unable to save this plan. Try again.')));
  }finally{if(mounted)setState(()=>busy=false);}
 }
 Future<void> edit([Map<String,dynamic>? row])async{
  if(space==null)return;
  final result=await Navigator.of(context).push<bool>(MaterialPageRoute(
   builder:(_)=>ExperienceEditor(spaceId:space!,original:row,initialKind:widget.collection)));
  if(result==true&&mounted)await load();
 }
 Future<void> open(Map<String,dynamic> row)async{
  await Navigator.of(context).push<void>(MaterialPageRoute(
    builder:(_)=>ExperienceDetail(id:row['id'].toString())));
  if(mounted)await load();
 }
 /// R55: this screen's filter groups (drawn by the shared panel).
 List<FilterGroupSpec> _filterGroups()=>[FilterGroupSpec(id:'progress',label:'Show',options:const {'open':'Still to enjoy','suggested':'Suggested','planned':'Planned','enjoyed':'Enjoyed','all':'All'},selected:status,defaultValue:'open'),FilterGroupSpec(id:'picks',label:'Picks',options:const {'all':'All','mutual':'Both interested'},selected:mutualOnly?'mutual':'all',defaultValue:'all')];

 @override Widget build(BuildContext context){
  final scheme=Theme.of(context).colorScheme;
  final filtered=rows.where((r)=>
   RecordCollectionSearchRules.inHistory(r,showArchived)&&
   (kind=='all'||r['category']==kind)&&(status=='all'||(status=='open'?r['status']!='enjoyed':r['status']==status))&&
   (!mutualOnly||ExperienceInterestRules.mutuallyInterested(interests,r['id']))&&
   RecordCollectionSearchRules.matches(r,search,
    fields:const ['title','platform','description'])).toList();
  return Scaffold(
   appBar:AppBar(title:Text(widget.collection==null?'Shared experiences':experienceTypes[widget.collection]??'Collection'),actions:[
    RecordListTopActions(
     historyKinds:const ['experience'],historyTitle:'Shared experiences',
     showHistory:showArchived,
     onToggleHistory:()=>setState(()=>showArchived=!showArchived),
     groups:_filterGroups(),
      onApply:(v)=>setState((){status=v['progress']!;mutualOnly=v['picks']=='mutual';}),
     ),
   ],bottom:filterShowingBar(_filterGroups(),removed:showArchived,onClear:()=>setState((){showArchived=false;status='open';kind=widget.collection??'all';mutualOnly=false;}))),
   floatingActionButton:space==null?null:FloatingActionButton.extended(
    heroTag:'add-experience',
    onPressed:()=>edit(),icon:const Icon(Icons.add),
    label:const Text('Add experience')),
   body:RefreshIndicator(onRefresh:load,child:ListView(
    physics:const AlwaysScrollableScrollPhysics(),
    padding:const EdgeInsets.fromLTRB(16,12,16,110),children:[
    Text('Discover, watch, play, read',style:Theme.of(context).textTheme.titleLarge),
    const SizedBox(height:8),
    TextField(onChanged:(v)=>setState(()=>search=v),
     decoration:const InputDecoration(prefixIcon:Icon(Icons.search),
      labelText:'Search experiences',
      hintText:'Title, platform or description')),
    const SizedBox(height:8),
    Text('Mutual picks · '+
      ExperienceInterestRules.mutualCount(rows,interests).toString(),
      style:Theme.of(context).textTheme.bodyMedium),
    const SizedBox(height:15),
    if(widget.collection==null&&search.trim().isEmpty)LayoutBuilder(builder:(ctx,size)=>GridView.count(
     shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),
     crossAxisCount:size.maxWidth>=600?3:2,childAspectRatio:1.75,
     mainAxisSpacing:9,crossAxisSpacing:9,
     children:[
      for(final e in experienceTypes.entries)
       Card(clipBehavior:Clip.antiAlias,
        color:Color.alphaBlend(
         scheme.primary.withValues(alpha:kind==e.key ? .20 : .05),
         scheme.surface),
        child:InkWell(
         onTap:()async{
          await Navigator.of(context).push<void>(MaterialPageRoute<void>(
           builder:(_)=>SharedExperiencesScreen(collection:e.key)));
          if(mounted)await load();
         },
         child:Padding(padding:const EdgeInsets.all(8),
          child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
           Icon(typeIcon(e.key),size:25,color:scheme.primary),
           const SizedBox(height:6),
           Text(e.value,maxLines:2,textAlign:TextAlign.center,
            style:Theme.of(context).textTheme.labelLarge),
           Text('${rows.where((r)=>r['category']==e.key&&r['archived_at']==null&&r['status']!='enjoyed').length} to enjoy',
            style:Theme.of(context).textTheme.labelSmall),
          ])))),
     ])),
    const SizedBox(height:12),
    if(widget.collection==null&&search.trim().isNotEmpty)Text('Search results',
      style:Theme.of(context).textTheme.titleMedium),
    if(error!=null)Text(error!,style:TextStyle(color:scheme.error)),
    if(loading)const Center(child:CircularProgressIndicator())
    else if(space==null)const Text('Connect your shared space first.')
    else if(widget.collection==null&&search.trim().isEmpty)const SizedBox.shrink()
    else if(filtered.isEmpty)const Padding(padding:EdgeInsets.all(22),
      child:Text('Nothing in this collection yet. Add the first title.'))
    else for(final r in filtered)Card(child:Padding(
     padding:const EdgeInsets.fromLTRB(12,10,12,10),
     child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      ListTile(contentPadding:EdgeInsets.zero,
       leading:Icon(typeIcon(r['category'].toString()),color:scheme.primary,size:29),
       title:Text(r['title'].toString(),
        style:Theme.of(context).textTheme.titleMedium),
       subtitle:Text([
        experienceTypes[r['category']]??'Other',
        experienceStates[r['status']]??'Suggested',
        if((r['platform']??'').toString().trim().isNotEmpty)r['platform'].toString(),
        if(r['status']=='planned'&&r['planned_on']!=null)
         'Planned: '+r['planned_on'].toString(),
        if(r['status']=='enjoyed'&&r['enjoyed_on']!=null)
         ExperiencePickerRules.completionState(r['category'].toString())+
          ': '+r['enjoyed_on'].toString(),
       ].join(' · ')),
       trailing:ItemMenu(kind:'experience',recordId:r['id'].toString(),title:r['title']?.toString(),
        statusActions:[ItemMenuAction('Rate & review',Icons.star_outline,()=>quickRate(r))],
        onOpen:()=>edit(r),removed:r['archived_at']!=null,onRemove:()=>archiveFromList(r)),
       onTap:()=>open(r)),
      if(ExperienceInterestRules.summary(interests,r['id'])!='No picks yet')
       Padding(padding:const EdgeInsets.only(left:6,bottom:8),child:Row(children:[
        Icon(ExperienceInterestRules.mutuallyInterested(interests,r['id'])?
         Icons.favorite:Icons.favorite_border,size:17,color:scheme.primary),
        const SizedBox(width:6),
        Expanded(child:Text(ExperienceInterestRules.summary(interests,r['id']),
         style:Theme.of(context).textTheme.labelMedium)),
       ])),
      Wrap(spacing:8,runSpacing:6,children:[
       if((r['source_url']??'').toString().trim().isNotEmpty)
       OutlinedButton.icon(
        onPressed:()=>openPlatform(r),
        icon:Icon(r['category']=='music'?Icons.play_arrow:
         r['category']=='movie'||r['category']=='show'?Icons.play_circle_outline:
         Icons.open_in_new),
        label:Text(r['category']=='music'?'Play':
         r['category']=='movie'||r['category']=='show'?'Watch':'Open')),
       if(r['status']!='enjoyed')OutlinedButton.icon(
        onPressed:busy?null:()=>planSuggestion(r),
        icon:const Icon(Icons.event_outlined),label:const Text('Plan')),
       if(r['status']!='enjoyed')FilledButton.tonalIcon(
        onPressed:busy?null:()=>markWatched(r),
        icon:const Icon(Icons.check_circle_outline),
        label:Text(ExperiencePickerRules.completionAction(
         r['category'].toString()))),
       if(r['status']=='enjoyed')
        OutlinedButton.icon(onPressed:()=>quickRate(r),
         icon:const Icon(Icons.star_border),label:const Text('Rate & review')),
      ]),
     ]))),
   ])));
 }
}

class ExperienceEditor extends StatefulWidget{
 const ExperienceEditor({super.key,required this.spaceId,this.original,this.initialKind});
 final String spaceId;final Map<String,dynamic>? original;
 /// R57: adding from inside a watchlist starts in that watchlist.
 final String? initialKind;
 @override State<ExperienceEditor> createState()=>_ExperienceEditorState();
}
class _ExperienceEditorState extends State<ExperienceEditor> with FormChangeTracker<ExperienceEditor>{
 /// R55: current form values; Save turns on only when they change.
 @override String get signature=>[title.text,description.text,platform.text,url.text,kind,status,planned,enjoyed].join('|');

 final db=Supabase.instance.client;
 late final TextEditingController title,description,platform,url;
 late String kind,status;
 DateTime? planned,enjoyed;
 bool saving=false;
 String? error;
 @override void initState(){super.initState();
  final r=widget.original??{};
  title=TextEditingController(text:(r['title']??'').toString());
  description=TextEditingController(text:(r['description']??'').toString());
  platform=TextEditingController(text:(r['platform']??'').toString());
  url=TextEditingController(text:(r['source_url']??'').toString());
  kind=(r['category']??widget.initialKind??'movie').toString();status=(r['status']??'suggested').toString();
  planned=DateTime.tryParse((r['planned_on']??'').toString());
  enjoyed=DateTime.tryParse((r['enjoyed_on']??'').toString());
 }
 @override void dispose(){title.dispose();description.dispose();platform.dispose();url.dispose();super.dispose();}
 String format(DateTime? d)=>d==null?'Not set':ExperiencePickerRules.dateOnly(d);
 Future<void> choose(bool plan)async{
  final date=await showDatePicker(context:context,firstDate:DateTime(2000),
    lastDate:DateTime(2100),initialDate:(plan?planned:enjoyed)??DateTime.now());
  if(date!=null&&mounted)setState((){if(plan){planned=date;}else{enjoyed=date;}});
 }
 Future<void> save()async{
  if(saving||title.text.trim().isEmpty)return;
  final uri=Uri.tryParse(url.text.trim());
  if(url.text.trim().isNotEmpty&&(uri==null||!['http','https'].contains(uri.scheme)||uri.host.isEmpty)){
   setState(()=>error='Enter an http or https link.');return;
  }
  setState((){saving=true;error=null;});
  try{
   final values=<String,dynamic>{'title':title.text.trim(),'category':kind,
    'description':description.text.trim(),'platform':platform.text.trim(),
    'source_url':url.text.trim(),'status':status,
    'planned_on':planned==null?null:ExperiencePickerRules.dateOnly(planned!),
    'enjoyed_on':enjoyed==null?null:ExperiencePickerRules.dateOnly(enjoyed!)};
   if(widget.original==null){
    await db.from('shared_experiences').insert({...values,'space_id':widget.spaceId});
   }else{
    final changed=await db.from('shared_experiences').update(values)
     .eq('id',widget.original!['id'])
     .eq('updated_at',widget.original!['updated_at']).select('id');
    if(changed.isEmpty){
     if(mounted)setState(()=>error='This experience was changed on the other phone. Go back and reopen it before editing.');
     return;
    }
   }
   if(mounted)Navigator.pop(context,true);
  }on PostgrestException catch(e){if(mounted)setState(()=>error=e.message);}
   catch(_){if(mounted)setState(()=>error='Could not save experience.');}
   finally{if(mounted)setState(()=>saving=false);}
 }
 Map<String,String> get words=>switch(kind){
  'movie'=>{'title':'Movie title','platform':'Where to watch','hint':'Netflix, cinema…'},
  'show'=>{'title':'Show title','platform':'Where to watch','hint':'Netflix, Shahid…'},
  'music'=>{'title':'Song, album or playlist','platform':'App','hint':'Spotify, Anghami…'},
  'book'=>{'title':'Book or article','platform':'Author or source','hint':''},
  'game'=>{'title':'Game','platform':'Console or app','hint':'PlayStation, phone…'},
  _=>{'title':'What is it?','platform':'Where','hint':''},
 };
 @override Widget build(BuildContext context){
  final w=words;
  return EditorScaffold(title:widget.original==null?'Add experience':'Edit experience',
   isNew:widget.original==null,isChanged:()=>changed,isComplete:()=>title.text.trim().isNotEmpty,
   listenTo:[title,description,platform,url],saving:saving,onSave:save,
   meta:MetaStrip(value:MetaValues(date:planned),showVisibility:false,showBelongs:false,
    dateLabel:'Plan a date',onChanged:(v)=>setState(()=>planned=v.date)),
   body:ListView(padding:const EdgeInsets.all(18),children:[
   ChoiceRow<String>(label:'Watchlist',options:experienceTypes,selected:kind,
    icons:{for(final k in experienceTypes.keys)k:switch(k){
     'movie'=>Icons.movie_creation_outlined,'show'=>Icons.live_tv_outlined,
     'music'=>Icons.queue_music_outlined,'book'=>Icons.menu_book_outlined,
     'game'=>Icons.sports_esports_outlined,_=>Icons.explore_outlined}},
    onSelected:(v){if(v!=null)setState(()=>kind=v);}),
   TextField(controller:title,maxLength:160,autofocus:widget.original==null,
    textCapitalization:TextCapitalization.sentences,
    decoration:InputDecoration(labelText:'${w['title']} *',border:const OutlineInputBorder())),
   const SizedBox(height:6),
   TextField(controller:platform,maxLength:100,
    decoration:InputDecoration(labelText:w['platform'],hintText:w['hint']!.isEmpty?null:w['hint'],
     prefixIcon:const Icon(Icons.live_tv_outlined),border:const OutlineInputBorder())),
   const SizedBox(height:10),
   TextField(controller:url,maxLength:1800,keyboardType:TextInputType.url,
    decoration:const InputDecoration(labelText:'Link',prefixIcon:Icon(Icons.link),
     border:OutlineInputBorder())),
   const SizedBox(height:10),
   ChoiceRow<String>(label:'Progress',options:experienceStates,selected:status,
    icons:const {'suggested':Icons.lightbulb_outline,'planned':Icons.event_available_outlined,
     'enjoyed':Icons.task_alt},
    onSelected:(v){if(v!=null)setState((){
     status=v;
     if(v=='enjoyed')enjoyed??=DateTime.now();
    });}),
   if(status=='enjoyed')DateField(label:'Enjoyed on',value:enjoyed,
    onChanged:(v)=>setState(()=>enjoyed=v)),
   TextField(controller:description,maxLength:5000,minLines:2,maxLines:6,
    decoration:const InputDecoration(labelText:'Why this one?',alignLabelWithHint:true,
     border:OutlineInputBorder())),
   Align(alignment:Alignment.centerLeft,
    child:PartnerMentionButton(spaceId:widget.spaceId,controller:description)),
   if(error!=null)Padding(padding:const EdgeInsets.only(top:10),
    child:Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error))),
  ]));
 }
}

class ExperienceDetail extends StatefulWidget{
 const ExperienceDetail({super.key,required this.id});
 final String id;
 @override State<ExperienceDetail> createState()=>_ExperienceDetailState();
}
class _ExperienceDetailState extends State<ExperienceDetail>{
 final _links=GlobalKey<LinkedItemsStripState>();
 final db=Supabase.instance.client;
 final comment=TextEditingController(),review=TextEditingController();
 Map<String,dynamic>? item;
 List<Map<String,dynamic>> comments=[],reviews=[],audit=[],interests=[];
 int? rating;
 bool loading=true,busy=false,showAudit=false,showMyRetracted=false;
 String commentSearch='';
 bool _reviewDraftDirty=false;
 String? error;
 RealtimeChannel? _changes;
 Timer? _refreshTimer;
 int _loadVersion=0;
 @override void initState(){super.initState();load();}
 @override void dispose(){
  _loadVersion++;
  _refreshTimer?.cancel();
  if(_changes!=null)unawaited(db.removeChannel(_changes!));
  comment.dispose();review.dispose();
  super.dispose();
 }
 void _watchDetail(){
  if(_changes!=null)return;
  final experienceId=widget.id;
  final filter=PostgresChangeFilter(type:PostgresChangeFilterType.eq,
   column:'experience_id',value:experienceId);
  _changes=db.channel('experience-detail-'+experienceId)
   .onPostgresChanges(event:PostgresChangeEvent.all,schema:'public',
    table:'shared_experiences',filter:PostgresChangeFilter(
     type:PostgresChangeFilterType.eq,column:'id',value:experienceId),
    callback:(_)=>_refreshSoon())
   .onPostgresChanges(event:PostgresChangeEvent.all,schema:'public',
    table:'shared_experience_comments',filter:filter,
    callback:(_)=>_refreshSoon())
   .onPostgresChanges(event:PostgresChangeEvent.all,schema:'public',
    table:'shared_experience_reviews',filter:filter,
    callback:(_)=>_refreshSoon())
   .onPostgresChanges(event:PostgresChangeEvent.all,schema:'public',
    table:'shared_experience_interests',filter:filter,
    callback:(_)=>_refreshSoon())
   .subscribe();
 }
 void _refreshSoon(){
  _refreshTimer?.cancel();
  _refreshTimer=Timer(const Duration(milliseconds:550),(){
   if(mounted)unawaited(load());
  });
 }
 String who(Object? id)=>id==db.auth.currentUser?.id?'You':'Partner';
 Future<void> load()async{
  final request=++_loadVersion;
  final account=db.auth.currentUser?.id;
  if(account==null){
   if(mounted)setState((){
    item=null;comments=[];reviews=[];audit=[];interests=[];
    loading=false;error='Sign in to view this experience.';
   });
   return;
  }
  try{
   final r=await db.from('shared_experiences').select()
    .eq('id',widget.id).single();
   final v=await Future.wait([
    db.from('shared_experience_comments').select().eq('experience_id',widget.id)
     .order('created_at'),
    db.from('shared_experience_reviews').select().eq('experience_id',widget.id),
    db.from('shared_experience_revisions').select().eq('experience_id',widget.id)
     .order('changed_at',ascending:false).limit(60),
    db.from('shared_experience_interests')
     .select('experience_id,user_id,choice').eq('experience_id',widget.id),
   ]);
   if(!mounted||request!=_loadVersion||db.auth.currentUser?.id!=account)return;
   final myReview=v[1].where((a)=>a['user_id']==account).firstOrNull;
   setState((){
    item=r;comments=List<Map<String,dynamic>>.from(v[0]);
    reviews=List<Map<String,dynamic>>.from(v[1]);
    audit=List<Map<String,dynamic>>.from(v[2]);
    interests=List<Map<String,dynamic>>.from(v[3]);
    if(!_reviewDraftDirty){
     rating=(myReview?['rating'] as num?)?.toInt();
     review.text=(myReview?['review']??'').toString();
    }
    loading=false;error=null;
   });
   _watchDetail();
  }catch(_){
   if(mounted&&request==_loadVersion&&db.auth.currentUser?.id==account)
    setState((){loading=false;error='Could not refresh experience.';});
  }
 }
 Future<bool> mutate(Future<void> Function() action)async{
  if(busy)return false;
  setState((){busy=true;error=null;});
  try{
   await action();
   await load();
   return true;
  }on PostgrestException catch(e){
   if(mounted)setState(()=>error=e.message);
  }on StateError catch(e){
   if(mounted)setState(()=>error=e.message.toString());
  }catch(_){
   if(mounted)setState(()=>error='Could not save change.');
  }finally{if(mounted)setState(()=>busy=false);}
  return false;
 }
 Future<void> setInterest(String choice)async{
  if(busy||db.auth.currentUser==null)return;
  final me=db.auth.currentUser!.id;
  if(ExperienceInterestRules.choiceForUser(interests,widget.id,me)==choice)return;
  await mutate(()async{
   final present=interests.any((row)=>row['user_id']==me);
   if(present){
    await db.from('shared_experience_interests')
     .update({'choice':choice}).eq('experience_id',widget.id)
     .eq('user_id',me);
   }else{
    try{
     await db.from('shared_experience_interests').insert({
      'experience_id':widget.id,'choice':choice});
    }on PostgrestException catch(e){
     if(e.code!='23505')rethrow;
     await db.from('shared_experience_interests')
      .update({'choice':choice}).eq('experience_id',widget.id)
      .eq('user_id',me);
    }
   }
  });
 }
 Future<void> saveReview()async{
  if(rating==null&&review.text.trim().isEmpty)return;
  final saved=await mutate(()async{
   final me=db.auth.currentUser!.id;
   final values={'rating':rating,'review':review.text.trim()};
   final existing=await db.from('shared_experience_reviews')
    .select('experience_id').eq('experience_id',widget.id).eq('user_id',me)
    .limit(1);
   if(existing.isEmpty){
    try{
     await db.from('shared_experience_reviews').insert({
      'experience_id':widget.id,'user_id':me,...values});
    }on PostgrestException catch(e){
     if(e.code!='23505')rethrow;
     await db.from('shared_experience_reviews').update(values)
      .eq('experience_id',widget.id).eq('user_id',me);
    }
   }else{
    await db.from('shared_experience_reviews').update(values)
     .eq('experience_id',widget.id).eq('user_id',me);
   }
  });
  if(saved)_reviewDraftDirty=false;
 }
 Future<void> send()async{
  final body=comment.text.trim();if(body.isEmpty)return;
  await mutate(()async{
   await db.from('shared_experience_comments').insert({'experience_id':widget.id,'body':body});
   comment.clear();
  });
 }
 Future<void> editComment(Map<String,dynamic> row)async{
  final me=db.auth.currentUser?.id;
  if(!ExperienceCommentRules.canEdit(row,me))return;
  final controller=TextEditingController(text:(row['body']??'').toString());
  final next=await showDialog<String>(context:context,builder:(ctx)=>
   AlertDialog(title:const Text('Edit your comment'),
    content:TextField(controller:controller,maxLength:2000,maxLines:4,
     autofocus:true,decoration:const InputDecoration(labelText:'Comment')),
    actions:[
     TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel')),
     FilledButton(onPressed:(){
      final value=controller.text.trim();
      if(value.isNotEmpty)Navigator.pop(ctx,value);
     },child:const Text('Save')),
    ]));
  controller.dispose();
  if(next==null||next==(row['body']??'').toString())return;
  await mutate(()async{
   final result=await db.from('shared_experience_comments')
    .update({'body':next}).eq('id',row['id'])
    .eq('created_by',me!)
    .eq('updated_at',row['updated_at']).isFilter('archived_at',null)
    .select('id');
   if(result.isEmpty)throw StateError(
    'This comment changed on the other phone. Refresh before editing.');
  });
 }
 Future<void> changeCommentArchive(Map<String,dynamic> row)async{
  final me=db.auth.currentUser?.id;
  final retracted=ExperienceCommentRules.isRetracted(row);
  if(retracted?
    !ExperienceCommentRules.canRestore(row,me):
    !ExperienceCommentRules.canRetract(row,me))return;
  if(!retracted){
   final confirmed=await showDialog<bool>(context:context,builder:(ctx)=>
    AlertDialog(title:const Text('Retract this comment?'),
     content:const Text('Your partner will no longer see it. You can restore it later.'),
     actions:[
      TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Keep')),
      FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Retract')),
     ]));
   if(confirmed!=true)return;
  }
  await mutate(()async{
   final q=db.from('shared_experience_comments').update({
    'archived_at':retracted?null:DateTime.now().toUtc().toIso8601String()
   }).eq('id',row['id']).eq('created_by',me!)
    .eq('updated_at',row['updated_at']);
   final changed=retracted?await q.not('archived_at','is',null).select('id'):
    await q.isFilter('archived_at',null).select('id');
   if(changed.isEmpty)throw StateError(
    'This comment changed on the other phone. Refresh and try again.');
  });
 }
 Future<void> edit()async{
  final r=item;if(r==null)return;
  final ok=await Navigator.push<bool>(context,MaterialPageRoute(
   builder:(_)=>ExperienceEditor(spaceId:r['space_id'].toString(),original:r)));
  if(ok==true&&mounted)await load();
 }
 Future<void> archive()async{
  final r=item;if(r==null)return;
  await mutate(()async{
   final updated=await db.from('shared_experiences').update({
    'archived_at':r['archived_at']==null?DateTime.now().toUtc().toIso8601String():null
   }).eq('id',widget.id).eq('updated_at',r['updated_at']).select('id');
   if(updated.isEmpty)throw StateError(
    'Another edit was saved on the other phone. Refresh before trying again.');
  });
 }
 Future<void> openLink()async{
  final u=Uri.tryParse((item?['source_url']??'').toString());
  if(u!=null&&['http','https'].contains(u.scheme))await launchUrl(u,mode:LaunchMode.externalApplication);
 }
 @override Widget build(BuildContext context){
  final r=item;
  final myId=db.auth.currentUser?.id;
  final myPick=ExperienceInterestRules.choiceForUser(interests,widget.id,myId);
  final partnerPick=interests.where((x)=>x['user_id']!=myId)
   .map((x)=>x['choice']?.toString()??'undecided').firstOrNull??'undecided';
  return Scaffold(appBar:AppBar(title:const Text('Our experience'),actions:[
   if(r!=null&&r['space_id']!=null)CreateFromThisButton(kind:LinkKind.experience,id:widget.id,spaceId:r['space_id'].toString(),title:r['title'].toString(),date:DateTime.tryParse(r['planned_on']?.toString()??''),shared:r['visibility']!='private',stripKey:_links),
    if(r!=null)RecordActionHistoryButton(kind:'experience',recordId:widget.id),
   if(r!=null)IconButton(tooltip:'Edit',onPressed:edit,icon:const Icon(Icons.edit_outlined)),
   if(r!=null)IconButton(tooltip:'Remove or restore',onPressed:archive,
    icon:Icon(r['archived_at']==null?Icons.archive_outlined:Icons.restore_outlined)),
  ]),body:loading?const Center(child:CircularProgressIndicator()):
   r==null?Center(child:Text(error??'Not found')):ListView(
    padding:const EdgeInsets.all(16),children:[
    Text(r['title'].toString(),style:Theme.of(context).textTheme.headlineSmall),
     LinkedItemsStrip(key:_links,kind:LinkKind.experience,id:widget.id),
    Text((experienceTypes[r['category']]??'Other')+' · '+(experienceStates[r['status']]??'Suggested')),
    if(r['planned_on']!=null)Text('Planned together: '+r['planned_on'].toString()),
    if(r['enjoyed_on']!=null)Text(
     ExperiencePickerRules.completionState(r['category'].toString())+
     ' on: '+r['enjoyed_on'].toString()),
    if((r['description']??'').toString().isNotEmpty)Text(r['description'].toString()),
    if((r['platform']??'').toString().isNotEmpty)Text('Platform: '+r['platform'].toString()),
    if((r['source_url']??'').toString().isNotEmpty)TextButton.icon(
     onPressed:openLink,icon:const Icon(Icons.open_in_new),label:const Text('Open link')),
    const Divider(height:28),
    RelatedNotesPanel(sourceKind:'experience',sourceId:widget.id),
    const SizedBox(height:12),
    Text('Our picks',style:Theme.of(context).textTheme.titleLarge),
    const SizedBox(height:6),
    const Text('Each of you chooses independently. A mutual pick means you both selected Interested.'),
    const SizedBox(height:8),
    Wrap(spacing:8,runSpacing:6,children:[
     for(final entry in ExperienceInterestRules.choices.entries)
      ChoiceChip(label:Text(entry.value),selected:myPick==entry.key,
       onSelected:busy?null:(_)=>setInterest(entry.key)),
    ]),
    const SizedBox(height:6),
    Text('You: '+(ExperienceInterestRules.choices[myPick]??'Clear pick')+
     ' · Partner: '+(ExperienceInterestRules.choices[partnerPick]??'No pick yet')),
    if(ExperienceInterestRules.mutuallyInterested(interests,widget.id))
     Padding(padding:const EdgeInsets.only(top:8),child:Row(children:[
      Icon(Icons.favorite,color:Theme.of(context).colorScheme.primary,size:20),
      const SizedBox(width:7),
      const Expanded(child:Text('A mutual pick! You both want to enjoy this together.')),
     ])),
    const Divider(height:28),
    Text('Our ratings and reviews',style:Theme.of(context).textTheme.titleLarge),
    for(final x in reviews)Card(elevation:0,child:ListTile(
      title:Text(who(x['user_id'])+' · '+(x['rating']??'No rating').toString()),
      subtitle:Text((x['review']??'').toString()))),
    const Text('My rating'),
    Wrap(children:[
     for(var i=1;i<=5;i++)IconButton(tooltip:'Rate '+i.toString(),
      onPressed:()=>setState((){rating=i;_reviewDraftDirty=true;}),
      icon:Icon((rating??0)>=i?Icons.star:Icons.star_border)),
     TextButton(onPressed:()=>setState((){
      rating=null;_reviewDraftDirty=true;
     }),child:const Text('Clear')),
    ]),
    TextField(controller:review,maxLength:2000,maxLines:3,
     onChanged:(_)=>_reviewDraftDirty=true,
     decoration:const InputDecoration(labelText:'My review')),
    Align(alignment:Alignment.centerRight,child:FilledButton(
     onPressed:busy?null:saveReview,child:const Text('Save my review'))),
    const Divider(height:28),
    Text('Our conversation',style:Theme.of(context).textTheme.titleLarge),
    TextField(onChanged:(value)=>setState(()=>commentSearch=value),
     decoration:const InputDecoration(prefixIcon:Icon(Icons.search),
      labelText:'Search conversation')),
    SwitchListTile.adaptive(contentPadding:EdgeInsets.zero,
     title:const Text('My retracted comments'),
     subtitle:const Text('Only you can see and restore your retracted comments'),
     value:showMyRetracted,onChanged:(v)=>setState(()=>showMyRetracted=v)),
    for(final x in ExperienceCommentRules.visible(
     comments,myId,showMyRetracted:showMyRetracted,query:commentSearch))
     Card(elevation:0,child:ListTile(
      title:Text(who(x['created_by'])+
       (ExperienceCommentRules.isRetracted(x)?' · Retracted':'')),
      subtitle:Text(x['body'].toString()),
      trailing:ExperienceCommentRules.isAuthor(x,myId)?
       PopupMenuButton<String>(tooltip:'Comment actions',
        onSelected:(action){
         if(action=='edit')editComment(x);
         if(action=='archive')changeCommentArchive(x);
         if(action=='history')showModalBottomSheet<void>(
          context:context,showDragHandle:true,isScrollControlled:true,
          builder:(_)=>FractionallySizedBox(heightFactor:.78,
           child:RecordActionHistoryView(kind:'experience_comment',
            recordId:x['id'].toString())));
        },
        itemBuilder:(_)=>[
         if(ExperienceCommentRules.canEdit(x,myId))
          const PopupMenuItem(value:'edit',child:Text('Edit')),
         PopupMenuItem(value:'archive',child:Text(
          ExperienceCommentRules.isRetracted(x)?'Restore':'Retract')),
         const PopupMenuItem(value:'history',
          child:Text('Comment action history')),
        ]):null)),
    TextField(controller:comment,maxLength:2000,maxLines:3,
     decoration:const InputDecoration(labelText:'Share your thoughts')),
    if(r['space_id']!=null)PartnerMentionButton(
     spaceId:r['space_id'].toString(),controller:comment),
    Align(alignment:Alignment.centerRight,child:FilledButton.icon(
     onPressed:busy?null:send,icon:const Icon(Icons.send_outlined),
     label:const Text('Send'))),
    if(error!=null)Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
  ]));
 }
}

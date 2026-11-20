import '../../core/form_kit.dart';
import '../../core/item_menu.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/editor_scaffold.dart';
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
import 'experience_picker_rules.dart';
import 'experience_interest_rules.dart';
import 'experience_comment_rules.dart';
import '../mentions/partner_mention_button.dart';
import '../mentions/inline_mention_field.dart';
import 'package:onespace/l10n/phrases.dart';

const experienceTypes={'movie':'Movie Watchlist','show':'TV Shows','music':'Music Playlist','book':'Books and articles','game':'Games','other':'Others'};
/// R71: short names for the Kind chips in the form.
const experienceKinds={'movie':'Movie','show':'TV show','music':'Music','book':'Book','game':'Game','other':'Other'};
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
 bool personalReady=false;
 bool loading=true,showArchived=false,opened=false,busy=false,mutualOnly=false;
 String kind='all',status='open',search='';
 int suggestionOffset=0;
 List<Map<String,dynamic>> rows=[],interests=[];
 /// R73: both people's ratings, shown on the cards.
 List<Map<String,dynamic>> ratings=[];
 SpacePeople? people;
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
     child:Padding(padding:const EdgeInsetsDirectional.fromSTEB(20,10,10,18),child:Column(
      mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
       Row(children:[
        Icon(Icons.auto_awesome,color:scheme.primary),
        const SizedBox(width:8),
        Expanded(child:Text(tt('What shall we do together?'),
         style:Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight:FontWeight.w700))),
        IconButton(tooltip:tt('Close'),icon:const Icon(Icons.close),
         onPressed:()=>Navigator.pop(ctx)),
       ]),
       Padding(padding:const EdgeInsetsDirectional.only(end:10),child:Column(
        crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(tt(mutual.isNotEmpty?tt('From the things you both picked.'):tt('From your own collection.')),
         style:Theme.of(ctx).textTheme.bodySmall),
        const SizedBox(height:14),
        Row(children:[
         Icon(typeIcon(pick['category'].toString()),color:scheme.primary,size:30),
         const SizedBox(width:10),
         Expanded(child:Text(tt(pick['title'].toString()),
          style:Theme.of(ctx).textTheme.headlineSmall)),
        ]),
        const SizedBox(height:18),
        // R57: three small chips on one line.
        // R60: three equal blocks that always fit inside the card.
        Row(children:[
         for(final a in <(IconData,String,VoidCallback)>[
          (Icons.event_available_outlined,'Plan',(){Navigator.pop(ctx);planSuggestion(pick);}),
          (Icons.shuffle,'Another',()=>refresh(()=>offset++)),
          (Icons.open_in_new,'View',(){Navigator.pop(ctx);open(pick);}),
         ])Expanded(child:Padding(padding:const EdgeInsets.symmetric(horizontal:3),
          child:Material(color:scheme.secondaryContainer,borderRadius:BorderRadius.circular(14),
           child:InkWell(borderRadius:BorderRadius.circular(14),onTap:a.$3,
            child:Padding(padding:const EdgeInsets.symmetric(vertical:10),child:Column(
             mainAxisSize:MainAxisSize.min,children:[
              Icon(a.$1,size:22,color:scheme.onSecondaryContainer),
              const SizedBox(height:4),
              Text(tt(a.$2),maxLines:1,overflow:TextOverflow.ellipsis,
               style:Theme.of(ctx).textTheme.labelMedium?.copyWith(color:scheme.onSecondaryContainer)),
             ])))))),
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
   var id=await CurrentSpaceCache.instance.get();
   var privateReady=false;
   if(!OneSpaceEnv.isProduction){
    final scopes=await db.rpc('my_storage_scopes');
    if(scopes is! Map||
       scopes['private_space_id']?.toString()!=account){
      throw StateError('Personal Experiences scope unavailable');
    }
    id=scopes['shared_space_id']?.toString();privateReady=true;
   }
   if(!mounted||request!=_loadVersion||db.auth.currentUser?.id!=account)return;
   if(id==null&&!privateReady){
    if(_changes!=null)unawaited(db.removeChannel(_changes!));
    _changes=null;_watchedSpace=null;
    setState((){space=null;personalReady=false;rows=[];interests=[];loading=false;error=null;});
    return;
   }
   final rootQuery=OneSpaceEnv.isProduction
     ?db.from('shared_experiences').select().eq('space_id',id!)
     :db.from('shared_experiences').select();
   final result=await rootQuery.order('updated_at',ascending:false).limit(250);
   final currentRows=List<Map<String,dynamic>>.from(result);
   final ids=currentRows.map((x)=>x['id'].toString()).toList();
   final currentInterests=ids.isEmpty?<Map<String,dynamic>>[]:
    List<Map<String,dynamic>>.from(
     await db.from('shared_experience_interests')
      .select('experience_id,user_id,choice').inFilter('experience_id',ids));
   var currentRatings=<Map<String,dynamic>>[];
   if(ids.isNotEmpty){
    try{
     currentRatings=List<Map<String,dynamic>>.from(await db.from('shared_experience_reviews')
      .select('experience_id,user_id,rating').inFilter('experience_id',ids));
    }catch(_){}
   }
   final pp=await SpacePeople.load();
   if(!mounted||request!=_loadVersion||db.auth.currentUser?.id!=account)return;
   setState((){
    space=id;personalReady=privateReady;
    rows=currentRows;interests=currentInterests;ratings=currentRatings;people=pp;
    loading=false;error=null;
   });
   if(id!=null)_watch(id);
   else {
     if(_changes!=null)unawaited(db.removeChannel(_changes!));
     _changes=null;_watchedSpace=null;
   }
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
    SnackBar(content:Text(tt('Could not mark as watched.'))));
  }finally{if(mounted)setState(()=>busy=false);}
 }
 Future<void> openPlatform(Map<String,dynamic> row)async{
  final raw=(row['source_url']??'').toString();
  final url=Uri.tryParse(raw);
  if(url==null||!['http','https'].contains(url.scheme)||url.host.isEmpty){
   ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content:Text(tt('Add a valid platform link in Edit first.'))));
   return;
  }
  if(!await launchUrl(url,mode:LaunchMode.externalApplication)&&mounted){
   ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content:Text(tt('Could not open this platform.'))));
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
     title:Text(tt('Rate ')+row['title'].toString()),
     content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
      StarRating(value:rating,onChanged:(v)=>update(()=>rating=v)),
      const SizedBox(height:12),
      TextField(controller:review,maxLength:2000,minLines:2,maxLines:4,
       textCapitalization:TextCapitalization.sentences,
       decoration:InputDecoration(labelText:tt('Review (optional)'),border:OutlineInputBorder())),
     ])),
     actions:[
      TextButton(onPressed:()=>Navigator.pop(ctx,false),child:Text(tt('Cancel'))),
      FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:Text(tt('Save rating'))),
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
    SnackBar(content:Text(tt('Unable to save review. Try again.'))));
  }finally{review.dispose();}
 }
 Future<void> archiveFromList(Map<String,dynamic> row)async{
  final archived=row['archived_at']!=null;
  if(!archived){
   final yes=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
    title:Text(tt('Remove this experience?')),
    content:Text(tt('It will move to experience history. Reviews remain saved.')),
    actions:[
     TextButton(onPressed:()=>Navigator.pop(ctx,false),child:Text(tt('Keep'))),
     FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:Text(tt('Remove'))),
    ]));
   if(yes!=true)return;
  }
  try{
   await updateSafely(row,{
    'archived_at':archived?null:DateTime.now().toUtc().toIso8601String()
   });
  }catch(_){
   if(mounted)ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content:Text(tt('Could not remove or restore this item.'))));
  }
 }
 Future<void> openHistory()async{
  if(space==null&&!personalReady)return;
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
       Text(tt('Our experience history'),style:Theme.of(ctx).textTheme.titleLarge),
       Text(tt('Only changes to Movies, TV, Music, Books, Games and Others.')),
       for(final r in records)ListTile(
        leading:const Icon(Icons.history_outlined),
        title:Text(tt(rows.where((x)=>x['id']==r['experience_id'])
         .map((x)=>x['title'].toString()).firstOrNull??'Experience')),
        subtitle:Text(tt(((r['before_snapshot'] as Map?)?['status']??'').toString()+
         ' → '+((r['after_snapshot'] as Map?)?['status']??'').toString()+
         ' · '+(r['changed_at']??'').toString().split('T').first)),
       ),
      ]))));
  }catch(_){
   if(mounted)ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content:Text(tt('Experience history is unavailable.'))));
  }
 }
 Future<bool> updateSafely(
  Map<String,dynamic> row,Map<String,dynamic> values)async{
  final updated=await db.from('shared_experiences').update(values)
   .eq('id',row['id']).eq('updated_at',row['updated_at'])
   .select('id');
  if(updated.isEmpty){
   await load();
   if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content:Text(tt('Your partner changed this experience. Refreshed the latest version.'))));
   return false;
  }
  await load();
  return true;
 }
 Future<void> planSuggestion(Map<String,dynamic> row)async{
  if(busy||(space==null&&!personalReady))return;
  final initial=DateTime.tryParse((row['planned_on']??'').toString())??DateTime.now();
  final day=await showDatePicker(context:context,initialDate:initial,
   firstDate:DateTime(2000),lastDate:DateTime(2100));
  if(day==null||!mounted)return;
  setState(()=>busy=true);
  try{
   final updated=await updateSafely(row,{
    'status':'planned','planned_on':ExperiencePickerRules.dateOnly(day)});
   if(updated&&mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content:Text(tt('Saved your plan. Your partner can see it too.'))));
  }catch(_){
   if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content:Text(tt('Unable to save this plan. Try again.'))));
  }finally{if(mounted)setState(()=>busy=false);}
 }
 Future<void> edit([Map<String,dynamic>? row])async{
  if(space==null&&!personalReady)return;
  final result=await Navigator.of(context).push<bool>(MaterialPageRoute(
   builder:(_)=>ExperienceEditor(spaceId:space??'',original:row,initialKind:widget.collection)));
  if(result==true&&mounted)await load();
 }
 Future<void> open(Map<String,dynamic> row)async{
  await Navigator.of(context).push<void>(MaterialPageRoute(
    builder:(_)=>ExperienceDetail(id:row['id'].toString())));
  if(mounted)await load();
 }
 /// R55: this screen's filter groups (drawn by the shared panel).
 List<FilterGroupSpec> _filterGroups()=>[FilterGroupSpec(id:'progress',label:tt('Show'),options:const {'open':'Still to enjoy','suggested':'Suggested','planned':'Planned','enjoyed':'Enjoyed','all':'All'},selected:status,defaultValue:'open'),FilterGroupSpec(id:'picks',label:tt('Picks'),options:const {'all':'All','mutual':'Both interested'},selected:mutualOnly?'mutual':'all',defaultValue:'all')];

 @override Widget build(BuildContext context){
  final scheme=Theme.of(context).colorScheme;
  final filtered=rows.where((r)=>
   RecordCollectionSearchRules.inHistory(r,showArchived)&&
   (kind=='all'||r['category']==kind)&&(status=='all'||(status=='open'?r['status']!='enjoyed':r['status']==status))&&
   (!mutualOnly||ExperienceInterestRules.mutuallyInterested(interests,r['id']))&&
   RecordCollectionSearchRules.matches(r,search,
    fields:const ['title','platform','description'])).toList();
  return Scaffold(
   appBar:AppBar(title:Text(tt(widget.collection==null?'Shared experiences':experienceTypes[widget.collection]??'Collection')),actions:[
    RecordListTopActions(
     historyKinds:const ['experience'],historyTitle:tt('Shared experiences'),
     showHistory:showArchived,
     onToggleHistory:()=>setState(()=>showArchived=!showArchived),
     groups:_filterGroups(),
      onApply:(v)=>setState((){status=v['progress']!;mutualOnly=v['picks']=='mutual';}),
     ),
   ],bottom:filterShowingBar(_filterGroups(),removed:showArchived,onClear:()=>setState((){showArchived=false;status='open';kind=widget.collection??'all';mutualOnly=false;}))),
   floatingActionButton:space==null&&!personalReady?null:FloatingActionButton.extended(
    heroTag:'add-experience',
    onPressed:()=>edit(),icon:const Icon(Icons.add),
    label:Text(tt('Add experience'))),
   body:RefreshIndicator(onRefresh:load,child:ListView(
    physics:const AlwaysScrollableScrollPhysics(),
    padding:const EdgeInsetsDirectional.fromSTEB(16,12,16,110),children:[
    Text(tt('Discover, watch, play, read'),style:Theme.of(context).textTheme.titleLarge),
    const SizedBox(height:8),
    TextField(onChanged:(v)=>setState(()=>search=v),
     decoration:InputDecoration(prefixIcon:Icon(Icons.search),
      labelText:tt('Search experiences'),
      hintText:tt('Title, platform or description'))),
    const SizedBox(height:8),
    Text(tt('Mutual picks · ')+
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
           Text(tt(e.value),maxLines:2,textAlign:TextAlign.center,
            style:Theme.of(context).textTheme.labelLarge),
           Text('${rows.where((r)=>r['category']==e.key&&r['archived_at']==null&&r['status']!='enjoyed').length} to enjoy',
            style:Theme.of(context).textTheme.labelSmall),
          ])))),
     ])),
    const SizedBox(height:12),
    if(widget.collection==null&&search.trim().isNotEmpty)Text(tt('Search results'),
      style:Theme.of(context).textTheme.titleMedium),
    if(error!=null)Text(tt(error!),style:TextStyle(color:scheme.error)),
    if(loading)const Center(child:CircularProgressIndicator())
    else if(space==null&&!personalReady)Text(tt('Connect your shared space first.'))
    else if(widget.collection==null&&search.trim().isEmpty)const SizedBox.shrink()
    else if(filtered.isEmpty)Padding(padding:EdgeInsets.all(22),
      child:Text(tt('Nothing in this collection yet. Add the first title.')))
    else for(final r in filtered)Card(child:Padding(
     padding:const EdgeInsetsDirectional.fromSTEB(12,10,12,10),
     child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      ListTile(contentPadding:EdgeInsets.zero,
       leading:Icon(typeIcon(r['category'].toString()),color:scheme.primary,size:29),
       title:Text(tt(r['title'].toString()),
        style:Theme.of(context).textTheme.titleMedium),
       subtitle:Text(tt([
        experienceTypes[r['category']]??'Other',
        experienceStates[r['status']]??'Suggested',
        if(!OneSpaceEnv.isProduction&&r['private_space_id']!=null)'Only me',
        if((r['platform']??'').toString().trim().isNotEmpty)r['platform'].toString(),
        if(r['status']=='planned'&&r['planned_on']!=null)
         'Planned: '+r['planned_on'].toString(),
        if(r['status']=='enjoyed'&&r['enjoyed_on']!=null)
         ExperiencePickerRules.completionState(r['category'].toString())+
          ': '+r['enjoyed_on'].toString(),
       ].join(' · '))),
       trailing:ItemMenu(kind:'experience',recordId:r['id'].toString(),title:r['title']?.toString(),
        statusActions:[ItemMenuAction(tt('Rate & review'),Icons.star_outline,()=>quickRate(r))],
        onOpen:()=>edit(r),removed:r['archived_at']!=null,onRemove:()=>archiveFromList(r)),
       onTap:()=>open(r)),
      // R73: ratings on the card (each of you).
      if(ratings.any((x)=>x['experience_id']==r['id']&&x['rating']!=null))
       Padding(padding:const EdgeInsetsDirectional.only(start:6,bottom:6),child:Wrap(spacing:14,children:[
        for(final x in ratings.where((x)=>x['experience_id']==r['id']&&x['rating']!=null))
         Row(mainAxisSize:MainAxisSize.min,children:[
          Text(tt(x['user_id']==db.auth.currentUser?.id?'You':(people?.partnerName??'Partner'))+' ',
           style:Theme.of(context).textTheme.labelMedium),
          for(var i=1;i<=5;i++)Icon(i<=(x['rating'] as num).toInt()?Icons.star:Icons.star_border,
           size:15,color:const Color(0xFFF2A900)),
         ]),
       ])),
      if(ExperienceInterestRules.summary(interests,r['id'])!='No picks yet')
       Padding(padding:const EdgeInsetsDirectional.only(start:6,bottom:8),child:Row(children:[
        Icon(ExperienceInterestRules.mutuallyInterested(interests,r['id'])?
         Icons.favorite:Icons.favorite_border,size:17,color:scheme.primary),
        const SizedBox(width:6),
        Expanded(child:Text(tt(ExperienceInterestRules.summary(interests,r['id'])),
         style:Theme.of(context).textTheme.labelMedium)),
       ])),
      Wrap(spacing:8,runSpacing:6,children:[
       if((r['source_url']??'').toString().trim().isNotEmpty)
       OutlinedButton.icon(
        onPressed:()=>openPlatform(r),
        icon:Icon(r['category']=='music'?Icons.play_arrow:
         r['category']=='movie'||r['category']=='show'?Icons.play_circle_outline:
         Icons.open_in_new),
        label:Text(tt(r['category']=='music'?'Play':
         r['category']=='movie'||r['category']=='show'?'Watch':'Open'))),
       if(r['status']!='enjoyed')OutlinedButton.icon(
        onPressed:busy?null:()=>planSuggestion(r),
        icon:const Icon(Icons.event_outlined),label:Text(tt('Plan'))),
       if(r['status']!='enjoyed')FilledButton.tonalIcon(
        onPressed:busy?null:()=>markWatched(r),
        icon:const Icon(Icons.check_circle_outline),
        label:Text(tt(ExperiencePickerRules.completionAction(
         r['category'].toString())))),
       if(r['status']=='enjoyed')
        OutlinedButton.icon(onPressed:()=>quickRate(r),
         icon:const Icon(Icons.star_border),label:Text(tt('Rate & review'))),
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
 @override String get signature=>[title.text,description.text,platform.text,url.text,kind,status,planned,enjoyed,visibility].join('|');

 final db=Supabase.instance.client;
 late final TextEditingController title,description,platform,url;
 late String kind,status,visibility;
 DateTime? planned,enjoyed;
 bool saving=false;
 String? error;
 @override void initState(){super.initState();
  final r=widget.original??{};
  title=TextEditingController(text:(r['title']??'').toString());
  description=TextEditingController(text:(r['description']??'').toString());
  platform=TextEditingController(text:(r['platform']??'').toString());
  url=TextEditingController(text:(r['source_url']??'').toString());
  kind=(r['category']??widget.initialKind??'movie').toString();
  status=(r['status']??'suggested').toString();
  visibility=(r['visibility']??(!OneSpaceEnv.isProduction&&widget.spaceId.isEmpty
   ?'private':'shared')).toString();
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
    final personal=!OneSpaceEnv.isProduction&&visibility=='private';
    if(!personal&&widget.spaceId.isEmpty){
      throw StateError('Connect with a partner before sharing an experience.');
    }
    await db.from('shared_experiences').insert({
     ...values,
     if(personal) 'private_space_id':db.auth.currentUser!.id
     else 'space_id':widget.spaceId,
     'created_by':db.auth.currentUser!.id,
     if(!OneSpaceEnv.isProduction) 'visibility':visibility,
    });
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
 static const platformChoices=<String,List<String>>{
  'movie':['Netflix','Cinema','Shahid','Prime Video','Disney+','Apple TV','OSN+'],
  'show':['Netflix','Shahid','Prime Video','Disney+','Apple TV','OSN+','YouTube'],
  'music':['Spotify','Anghami','Apple Music','YouTube Music','SoundCloud'],
  'book':['Kindle','Audible','Jarir','Paper book'],
  'game':['PlayStation','Xbox','Nintendo Switch','PC','Phone'],
 };
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
  return EditorScaffold(title:widget.original==null?tt('Add experience'):tt('Edit experience'),
   isNew:widget.original==null,isChanged:()=>changed,isComplete:()=>title.text.trim().isNotEmpty,
   listenTo:[title,description,platform,url],saving:saving,onSave:save,
   meta:MetaStrip(value:MetaValues(date:planned,shared:visibility=='shared'),
    showVisibility:!OneSpaceEnv.isProduction,showBelongs:false,
    dateLabel:tt('Plan a date'),onChanged:(v)=>setState((){
      planned=v.date;
      if(widget.original==null)visibility=
        !OneSpaceEnv.isProduction&&widget.spaceId.isEmpty?'private':
        (v.shared?'shared':'private');
    })),
   body:ListView(padding:const EdgeInsets.all(18),children:[
   ChoiceRow<String>(label:tt('Kind'),options:experienceKinds,selected:kind,
    icons:{for(final k in experienceTypes.keys)k:switch(k){
     'movie'=>Icons.movie_creation_outlined,'show'=>Icons.live_tv_outlined,
     'music'=>Icons.queue_music_outlined,'book'=>Icons.menu_book_outlined,
     'game'=>Icons.sports_esports_outlined,_=>Icons.explore_outlined}},
    onSelected:(v){if(v!=null)setState(()=>kind=v);}),
   TextField(controller:title,maxLength:160,autofocus:widget.original==null,
    textCapitalization:TextCapitalization.sentences,
    decoration:InputDecoration(labelText:'${w['title']} *',border:const OutlineInputBorder())),
   const SizedBox(height:6),
   // R71: the usual places for this kind are one tap; anything else can be typed.
   if((platformChoices[kind]??const []).isNotEmpty)Padding(padding:const EdgeInsets.only(bottom:8),
    child:Wrap(spacing:6,runSpacing:4,children:[
     for(final p in platformChoices[kind]!)ChoiceChip(label:Text(tt(p)),
      selected:platform.text.trim()==p,
      onSelected:(on)=>setState(()=>platform.text=on?p:'')),
    ])),
   TextField(controller:platform,maxLength:100,
    onChanged:(_)=>setState((){}),
    decoration:InputDecoration(labelText:w['platform'],hintText:w['hint']!.isEmpty?null:w['hint'],
     prefixIcon:const Icon(Icons.live_tv_outlined),border:const OutlineInputBorder())),
   const SizedBox(height:10),
   TextField(controller:url,maxLength:1800,keyboardType:TextInputType.url,
    decoration:InputDecoration(labelText:tt('Link'),prefixIcon:Icon(Icons.link),
     border:OutlineInputBorder())),
   const SizedBox(height:10),
   ChoiceRow<String>(label:tt('Status'),options:experienceStates,selected:status,
    icons:const {'suggested':Icons.lightbulb_outline,'planned':Icons.event_available_outlined,
     'enjoyed':Icons.task_alt},
    onSelected:(v){if(v!=null)setState((){
     status=v;
     if(v=='enjoyed')enjoyed??=DateTime.now();
    });}),
   if(status=='enjoyed')DateField(label:tt('Enjoyed on'),value:enjoyed,
    onChanged:(v)=>setState(()=>enjoyed=v)),
   TextField(controller:description,maxLength:5000,minLines:2,maxLines:6,
    decoration:InputDecoration(labelText:tt('Why this one?'),alignLabelWithHint:true,
     border:OutlineInputBorder())),
   Align(alignment:AlignmentDirectional.centerStart,
    child:PartnerMentionButton(spaceId:widget.spaceId,controller:description)),
   if(error!=null)Padding(padding:const EdgeInsets.only(top:10),
    child:Text(tt(error!),style:TextStyle(color:Theme.of(context).colorScheme.error))),
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
 /// R73: replying to a message, Activity-style.
 Map<String,dynamic>? replyingTo;
 SpacePeople? people;
 String? error;
 RealtimeChannel? _changes;
 Timer? _refreshTimer;
 int _loadVersion=0;
 @override void initState(){super.initState();load();SpacePeople.load().then((p){if(mounted)setState(()=>people=p);});}
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
 String who(Object? id)=>id==db.auth.currentUser?.id?'You':(people?.partnerName??'Partner');
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
 Future<void> setInterest(String pick)async{
  var choice=pick;
  if(busy||db.auth.currentUser==null)return;
  final me=db.auth.currentUser!.id;
  // R73: tapping the chip that is already chosen clears the pick.
  if(ExperienceInterestRules.choiceForUser(interests,widget.id,me)==choice)choice='undecided';
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
   await db.from('shared_experience_comments').insert({'experience_id':widget.id,'body':body,
    if(replyingTo!=null)'reply_to':replyingTo!['id']});
   comment.clear();
   replyingTo=null;
  });
 }
 Future<void> editComment(Map<String,dynamic> row)async{
  final me=db.auth.currentUser?.id;
  if(!ExperienceCommentRules.canEdit(row,me))return;
  final controller=TextEditingController(text:(row['body']??'').toString());
  final next=await showDialog<String>(context:context,builder:(ctx)=>
   AlertDialog(title:Text(tt('Edit your comment')),
    content:TextField(controller:controller,maxLength:2000,maxLines:4,
     autofocus:true,decoration:InputDecoration(labelText:tt('Comment'))),
    actions:[
     TextButton(onPressed:()=>Navigator.pop(ctx),child:Text(tt('Cancel'))),
     FilledButton(onPressed:(){
      final value=controller.text.trim();
      if(value.isNotEmpty)Navigator.pop(ctx,value);
     },child:Text(tt('Save'))),
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
    AlertDialog(title:Text(tt('Retract this comment?')),
     content:Text(tt('Your partner will no longer see it. You can restore it later.')),
     actions:[
      TextButton(onPressed:()=>Navigator.pop(ctx,false),child:Text(tt('Keep'))),
      FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:Text(tt('Retract'))),
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
   builder:(_)=>ExperienceEditor(spaceId:r['space_id']?.toString()??'',original:r)));
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
 String _when(Object? raw){
  final at=DateTime.tryParse((raw??'').toString())?.toLocal();
  if(at==null)return '';
  final loc=MaterialLocalizations.of(context);
  final today=DateUtils.dateOnly(DateTime.now());
  final time=loc.formatTimeOfDay(TimeOfDay.fromDateTime(at));
  return DateUtils.isSameDay(at,today)?time:'${loc.formatShortMonthDay(at)} · $time';
 }
 /// R73: the conversation looks and works like an Activity's: bubbles,
 /// tap to reply, long-press for Reply · Copy · Edit · Remove.
 Widget bubble(Map<String,dynamic> x,String? myId){
  final theme=Theme.of(context);
  final mine=x['created_by']==myId;
  final retracted=ExperienceCommentRules.isRetracted(x);
  final quoted=x['reply_to']==null?null:comments.where((c)=>c['id']==x['reply_to']).firstOrNull;
  final name=who(x['created_by']);
  return Align(
   alignment:mine?AlignmentDirectional.centerEnd:AlignmentDirectional.centerStart,
   child:GestureDetector(
    onTap:retracted?null:()=>setState(()=>replyingTo=x),
    onLongPress:()async{
     final action=await showModalBottomSheet<String>(context:context,showDragHandle:true,
      builder:(ctx)=>SafeArea(child:Column(mainAxisSize:MainAxisSize.min,children:[
       if(!retracted)ListTile(leading:const Icon(Icons.reply_outlined),title:Text(tt('Reply')),
        onTap:()=>Navigator.pop(ctx,'reply')),
       if(!retracted)ListTile(leading:const Icon(Icons.copy_outlined),title:Text(tt('Copy message')),
        onTap:()=>Navigator.pop(ctx,'copy')),
       if(ExperienceCommentRules.canEdit(x,myId))ListTile(leading:const Icon(MenuIcons.edit),
        title:Text(tt('Edit')),onTap:()=>Navigator.pop(ctx,'edit')),
       if(ExperienceCommentRules.isAuthor(x,myId))ListTile(
        leading:Icon(retracted?MenuIcons.restore:MenuIcons.remove),
        title:Text(tt(retracted?'Restore':'Remove')),onTap:()=>Navigator.pop(ctx,'archive')),
      ])));
     if(!mounted)return;
     if(action=='reply'){setState(()=>replyingTo=x);}
     else if(action=='copy'){await Clipboard.setData(ClipboardData(text:(x['body']??'').toString()));}
     else if(action=='edit'){await editComment(x);}
     else if(action=='archive'){await changeCommentArchive(x);}
    },
    child:Container(
     constraints:const BoxConstraints(maxWidth:350),
     margin:const EdgeInsets.only(bottom:7),
     padding:const EdgeInsets.symmetric(horizontal:12,vertical:9),
     decoration:BoxDecoration(
      color:retracted?theme.colorScheme.surfaceContainerLow:
       mine?theme.colorScheme.primaryContainer:theme.colorScheme.surfaceContainerHigh,
      borderRadius:BorderRadius.circular(13)),
     child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Wrap(crossAxisAlignment:WrapCrossAlignment.center,spacing:6,children:[
       CircleAvatar(radius:12,backgroundColor:theme.colorScheme.surface,
        child:Text(name.isEmpty?'?':name.characters.first.toUpperCase(),
         style:theme.textTheme.labelSmall?.copyWith(fontWeight:FontWeight.bold,color:theme.colorScheme.primary))),
       Text(_when(x['created_at']),style:theme.textTheme.labelSmall),
       if(retracted)Text(tt('Removed · only you see it'),style:theme.textTheme.labelSmall),
      ]),
      if(quoted!=null)Container(
       margin:const EdgeInsets.only(top:4),
       padding:const EdgeInsetsDirectional.fromSTEB(8,4,6,4),
       decoration:BoxDecoration(border:BorderDirectional(start:BorderSide(width:2,color:theme.colorScheme.outline))),
       child:Text(tt((quoted['body']??'').toString()),maxLines:2,overflow:TextOverflow.ellipsis,
        style:theme.textTheme.labelSmall)),
      const SizedBox(height:4),
      Text(tt((x['body']??'').toString()),style:theme.textTheme.bodyMedium?.copyWith(
       decoration:retracted?TextDecoration.lineThrough:null)),
     ]))));
 }
 Widget composer(String? spaceId)=>SafeArea(top:false,child:Container(
  padding:const EdgeInsetsDirectional.fromSTEB(9,5,9,8),
  decoration:BoxDecoration(color:Theme.of(context).colorScheme.surface,
   border:Border(top:BorderSide(color:Theme.of(context).colorScheme.outlineVariant))),
  child:Column(mainAxisSize:MainAxisSize.min,children:[
   if(replyingTo!=null)Row(children:[
    Expanded(child:Text(tt('Replying to: ')+(replyingTo!['body']??'').toString(),
     maxLines:1,overflow:TextOverflow.ellipsis,style:Theme.of(context).textTheme.labelSmall)),
    IconButton(icon:const Icon(Icons.close,size:16),tooltip:tt('Cancel reply'),
     onPressed:()=>setState(()=>replyingTo=null)),
   ]),
   Row(crossAxisAlignment:CrossAxisAlignment.end,children:[
    // R76 (Ahmed): the mention lives inside the box — type @.
    Expanded(child:InlineMentionField(spaceId:spaceId,controller:comment)),
    IconButton(tooltip:tt('Send message'),onPressed:busy?null:send,icon:const Icon(Icons.send_rounded)),
   ]),
  ])));

 @override Widget build(BuildContext context){
  final r=item;
  final myId=db.auth.currentUser?.id;
  final myPick=ExperienceInterestRules.choiceForUser(interests,widget.id,myId);
  final partnerPick=interests.where((x)=>x['user_id']!=myId)
   .map((x)=>x['choice']?.toString()??'undecided').firstOrNull??'undecided';
  // R73 (Ahmed): one ⋮ in the top bar, like every other page.
  return Scaffold(appBar:AppBar(title:Text(tt('Our experience')),actions:[
   if(r!=null)ItemMenu(kind:'experience',recordId:widget.id,title:r['title']?.toString(),
    onOpen:edit,
    moreActions:[
     if(r['space_id']!=null)ItemMenuAction(tt('Create from this'),MenuIcons.createFrom,
      ()=>createFromThis(context,kind:LinkKind.experience,id:widget.id,spaceId:r['space_id'].toString(),
       title:r['title'].toString(),date:DateTime.tryParse(r['planned_on']?.toString()??''),
       shared:r['visibility']!='private',onLinked:()=>_links.currentState?.reload())),
    ],
    removed:r['archived_at']!=null,onRemove:busy?null:archive),
  ]),body:loading?const Center(child:CircularProgressIndicator()):
   r==null?Center(child:Text(tt(error??'Not found'))):Column(children:[Expanded(child:ListView(
    padding:const EdgeInsets.all(16),children:[
    Text(tt(r['title'].toString()),style:Theme.of(context).textTheme.headlineSmall),
     if(OneSpaceEnv.isProduction||r['private_space_id']==null)
      LinkedItemsStrip(key:_links,kind:LinkKind.experience,id:widget.id),
    Text(tt((experienceTypes[r['category']]??'Other')+' · '+(experienceStates[r['status']]??'Suggested'))),
    if(r['planned_on']!=null)Text(tt('Planned together: ')+r['planned_on'].toString()),
    if(r['enjoyed_on']!=null)Text(
     tt(ExperiencePickerRules.completionState(r['category'].toString())+
     ' on: '+r['enjoyed_on'].toString())),
    if((r['description']??'').toString().isNotEmpty)Text(tt(r['description'].toString())),
    if((r['platform']??'').toString().isNotEmpty)Text(tt('Platform: ')+r['platform'].toString()),
    if((r['source_url']??'').toString().isNotEmpty)TextButton.icon(
     onPressed:openLink,icon:const Icon(Icons.open_in_new),label:Text(tt('Open link'))),
    const Divider(height:28),
    Text(tt('Our picks'),style:Theme.of(context).textTheme.titleLarge),
    const SizedBox(height:6),
    Text(tt('Each of you chooses independently. A mutual pick means you both selected Interested.')),
    const SizedBox(height:8),
    Wrap(spacing:8,runSpacing:6,children:[
     for(final entry in ExperienceInterestRules.choices.entries)
      if(entry.key!='undecided')ChoiceChip(label:Text(tt(entry.value)),selected:myPick==entry.key,
       onSelected:busy?null:(_)=>setInterest(entry.key)),
    ]),
    const SizedBox(height:6),
    Text(tt('You: ')+tt(myPick=='undecided'?'No pick yet':ExperienceInterestRules.choices[myPick]??'No pick yet')+
     ' · '+tt(people?.partnerName??'Partner')+': '+tt(partnerPick=='undecided'?'No pick yet':ExperienceInterestRules.choices[partnerPick]??'No pick yet')),
    Text(tt('Tap your choice again to clear it.'),style:Theme.of(context).textTheme.bodySmall),
    if(ExperienceInterestRules.mutuallyInterested(interests,widget.id))
     Padding(padding:const EdgeInsets.only(top:8),child:Row(children:[
      Icon(Icons.favorite,color:Theme.of(context).colorScheme.primary,size:20),
      const SizedBox(width:7),
      Expanded(child:Text(tt('A mutual pick! You both want to enjoy this together.'))),
     ])),
    const Divider(height:28),
    Text(tt('Our ratings and reviews'),style:Theme.of(context).textTheme.titleLarge),
    for(final x in reviews)Card(elevation:0,child:ListTile(
      title:Text(tt(who(x['user_id'])+' · '+(x['rating']??'No rating').toString())),
      subtitle:Text(tt((x['review']??'').toString())))),
    Text(tt('My rating')),
    Row(children:[
     Expanded(child:StarRating(value:rating,onChanged:(v)=>setState((){rating=v;_reviewDraftDirty=true;}))),
     TextButton(onPressed:()=>setState((){
      rating=null;_reviewDraftDirty=true;
     }),child:Text(tt('Clear'))),
    ]),
    TextField(controller:review,maxLength:2000,maxLines:3,
     onChanged:(_)=>_reviewDraftDirty=true,
     decoration:InputDecoration(labelText:tt('My review'))),
    Align(alignment:AlignmentDirectional.centerEnd,child:FilledButton(
     onPressed:busy?null:saveReview,child:Text(tt('Save my review')))),
    const Divider(height:28),
    Row(children:[
     Expanded(child:Text(tt('Conversation'),style:Theme.of(context).textTheme.titleMedium)),
     if(comments.any((c)=>ExperienceCommentRules.isRetracted(c)&&ExperienceCommentRules.isAuthor(c,myId)))
      IconButton(tooltip:tt(showMyRetracted?'Hide my removed messages':'Show my removed messages'),
       isSelected:showMyRetracted,icon:const Icon(Icons.delete_outline),selectedIcon:const Icon(Icons.delete),
       onPressed:()=>setState(()=>showMyRetracted=!showMyRetracted)),
    ]),
    const SizedBox(height:6),
    if(ExperienceCommentRules.visible(comments,myId,showMyRetracted:showMyRetracted,query:'').isEmpty)
     Padding(padding:const EdgeInsets.symmetric(vertical:10),
      child:Text(tt('Start talking here. Every message stays with this experience.'))),
    for(final x in ExperienceCommentRules.visible(comments,myId,showMyRetracted:showMyRetracted,query:''))
     bubble(x,myId),
    if(error!=null)Text(tt(error!),style:TextStyle(color:Theme.of(context).colorScheme.error)),
  ])),composer(r['space_id']?.toString())]));
 }
}

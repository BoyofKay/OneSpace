import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/current_space_cache.dart';

const experienceTypes={'movie':'Movie Watchlist','show':'TV Shows','music':'Music Playlist','book':'Books and articles','game':'Games','other':'Others'};
const experienceStates={'suggested':'Suggested','planned':'Planned','enjoyed':'Enjoyed'};

class SharedExperiencesScreen extends StatefulWidget {
 const SharedExperiencesScreen({super.key,this.initialExperienceId});
 final String? initialExperienceId;
 @override State<SharedExperiencesScreen> createState()=>_SharedExperiencesScreenState();
}
class _SharedExperiencesScreenState extends State<SharedExperiencesScreen>{
 final db=Supabase.instance.client;
 String? space,error;
 bool loading=true,showArchived=false,opened=false,busy=false;
 String kind='all',status='all',search='';
 List<Map<String,dynamic>> rows=[];
 @override void initState(){super.initState();load();}
 Future<void> load()async{
  try{
   final id=await CurrentSpaceCache.instance.get();
   if(id==null){if(mounted)setState(()=>loading=false);return;}
   final result=await db.from('shared_experiences').select().eq('space_id',id)
      .order('updated_at',ascending:false).limit(250);
   if(!mounted)return;
   setState((){space=id;rows=List<Map<String,dynamic>>.from(result);loading=false;error=null;});
   if(!opened&&widget.initialExperienceId!=null){
    opened=true;
    final found=rows.where((x)=>x['id']==widget.initialExperienceId).firstOrNull;
    if(found!=null)WidgetsBinding.instance.addPostFrameCallback((_){
      if(mounted)open(found);
    });
   }
  }catch(_){if(mounted)setState((){error='Unable to load experiences.';loading=false;});}
 }
 IconData typeIcon(String c)=>switch(c){
  'movie'=>Icons.movie_creation_outlined,
  'show'=>Icons.live_tv_outlined,
  'music'=>Icons.queue_music_outlined,
  'book'=>Icons.menu_book_outlined,
  'game'=>Icons.sports_esports_outlined,
  _=>Icons.explore_outlined,
 };
 bool canWatch(Map<String,dynamic> row)=>
  row['category']=='movie'||row['category']=='show';
 Future<void> markWatched(Map<String,dynamic> row)async{
  if(busy)return;
  setState(()=>busy=true);
  try{
   await db.from('shared_experiences').update({
    'status':'enjoyed',
    'enjoyed_on':DateTime.now().toIso8601String().substring(0,10),
   }).eq('id',row['id']);
   await load();
   if(mounted)await quickRate(row);
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
    title:const Text('Archive this experience?'),
    content:const Text('It will move to experience history. Reviews remain saved.'),
    actions:[
     TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Keep')),
     FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Archive')),
    ]));
   if(yes!=true)return;
  }
  try{
   await db.from('shared_experiences').update({
    'archived_at':archived?null:DateTime.now().toUtc().toIso8601String()
   }).eq('id',row['id']);
   await load();
  }catch(_){
   if(mounted)ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content:Text('Could not change archive status.')));
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
 Future<void> edit([Map<String,dynamic>? row])async{
  if(space==null)return;
  final result=await Navigator.of(context).push<bool>(MaterialPageRoute(
   builder:(_)=>ExperienceEditor(spaceId:space!,original:row)));
  if(result==true&&mounted)await load();
 }
 Future<void> open(Map<String,dynamic> row)async{
  await Navigator.of(context).push<void>(MaterialPageRoute(
    builder:(_)=>ExperienceDetail(id:row['id'].toString())));
  if(mounted)await load();
 }
 @override Widget build(BuildContext context){
  final scheme=Theme.of(context).colorScheme;
  final filtered=rows.where((r)=>
   (showArchived?r['archived_at']!=null:r['archived_at']==null)&&
   (kind=='all'||r['category']==kind)&&(status=='all'||r['status']==status)&&
   (r['title'].toString().toLowerCase().contains(search.toLowerCase())||
    (r['platform']??'').toString().toLowerCase().contains(search.toLowerCase()))).toList();
  return Scaffold(
   appBar:AppBar(title:const Text('Our experience'),actions:[
    IconButton(tooltip:'Experience filters',icon:const Icon(Icons.tune_outlined),
     onPressed:()=>showModalBottomSheet<void>(context:context,showDragHandle:true,
      builder:(_)=>StatefulBuilder(builder:(ctx,refresh)=>SafeArea(
       child:Padding(padding:const EdgeInsets.all(18),
        child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
         Text('Filter collection',style:Theme.of(ctx).textTheme.titleLarge),
         const SizedBox(height:10),
         Wrap(spacing:8,runSpacing:5,children:[
          for(final e in <String,String>{'all':'All',...experienceStates}.entries)
           ChoiceChip(label:Text(e.value),selected:status==e.key,
            onSelected:(_){setState(()=>status=e.key);refresh((){});}),
         ]),
         SwitchListTile(title:const Text('Archived experiences'),
          value:showArchived,onChanged:(v){setState(()=>showArchived=v);refresh((){});}),
        ]))))),
    IconButton(tooltip:'Experience edit history',
     icon:const Icon(Icons.history_outlined),onPressed:openHistory),
   ]),
   floatingActionButton:space==null?null:FloatingActionButton.extended(
    onPressed:()=>edit(),icon:const Icon(Icons.add),
    label:const Text('Add an experience')),
   body:RefreshIndicator(onRefresh:load,child:ListView(
    physics:const AlwaysScrollableScrollPhysics(),
    padding:const EdgeInsets.fromLTRB(16,12,16,110),children:[
    Text('Discover, watch, play, read',style:Theme.of(context).textTheme.titleLarge),
    const SizedBox(height:8),
    TextField(onChanged:(v)=>setState(()=>search=v),
     decoration:const InputDecoration(prefixIcon:Icon(Icons.search),
      labelText:'Search by title or platform')),
    const SizedBox(height:15),
    LayoutBuilder(builder:(ctx,size)=>GridView.count(
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
         onTap:()=>setState(()=>kind=kind==e.key?'all':e.key),
         child:Padding(padding:const EdgeInsets.all(8),
          child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
           Icon(typeIcon(e.key),size:25,color:scheme.primary),
           const SizedBox(height:6),
           Text(e.value,maxLines:2,textAlign:TextAlign.center,
            style:Theme.of(context).textTheme.labelLarge),
          ])))),
     ])),
    const SizedBox(height:12),
    Row(children:[
     Expanded(child:Text(kind=='all'?'All experiences':experienceTypes[kind]??'Other',
      style:Theme.of(context).textTheme.titleMedium)),
     if(kind!='all')TextButton(onPressed:()=>setState(()=>kind='all'),
      child:const Text('All collections')),
    ]),
    if(error!=null)Text(error!,style:TextStyle(color:scheme.error)),
    if(loading)const Center(child:CircularProgressIndicator())
    else if(space==null)const Text('Connect your shared space first.')
    else if(filtered.isEmpty)const Padding(padding:EdgeInsets.all(22),
      child:Text('Nothing in this collection yet. Add the first title.'))
    else for(final r in filtered)Card(child:Padding(
     padding:const EdgeInsets.fromLTRB(12,10,12,10),
     child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      ListTile(contentPadding:EdgeInsets.zero,
       leading:Icon(typeIcon(r['category'].toString()),color:scheme.primary,size:29),
       title:Text(r['title'].toString(),
        style:Theme.of(context).textTheme.titleMedium),
       subtitle:Text((r['platform']??'').toString().isEmpty?
        (experienceTypes[r['category']]??'Other'):
        (experienceTypes[r['category']]??'Other')+' · '+r['platform'].toString()),
       trailing:PopupMenuButton<String>(
        tooltip:'Experience actions',
        onSelected:(choice){
         if(choice=='edit'){edit(r);}
         if(choice=='archive'){archiveFromList(r);}
         if(choice=='rate'){quickRate(r);}
        },
        itemBuilder:(_)=>[
         const PopupMenuItem(value:'edit',child:Text('Edit details')),
         const PopupMenuItem(value:'rate',child:Text('Rate & review')),
         PopupMenuItem(value:'archive',child:Text(
          r['archived_at']==null?'Archive':'Restore')),
        ]),
       onTap:()=>open(r)),
      Wrap(spacing:8,runSpacing:6,children:[
       OutlinedButton.icon(
        onPressed:()=>openPlatform(r),
        icon:Icon(r['category']=='music'?Icons.play_arrow:
         r['category']=='movie'||r['category']=='show'?Icons.play_circle_outline:
         Icons.open_in_new),
        label:Text(r['category']=='music'?'Play':
         r['category']=='movie'||r['category']=='show'?'Watch':'Open')),
       if(canWatch(r))FilledButton.tonalIcon(
        onPressed:busy||r['status']=='enjoyed'?null:()=>markWatched(r),
        icon:Icon(r['status']=='enjoyed'?Icons.check_circle:Icons.visibility_outlined),
        label:Text(r['status']=='enjoyed'?'Watched':'Mark watched')),
       if(r['status']=='enjoyed'&&canWatch(r))
        OutlinedButton.icon(onPressed:()=>quickRate(r),
         icon:const Icon(Icons.star_border),label:const Text('Rate')),
      ]),
     ]))),
   ])));
 }
}

class ExperienceEditor extends StatefulWidget{
 const ExperienceEditor({super.key,required this.spaceId,this.original});
 final String spaceId;final Map<String,dynamic>? original;
 @override State<ExperienceEditor> createState()=>_ExperienceEditorState();
}
class _ExperienceEditorState extends State<ExperienceEditor>{
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
  kind=(r['category']??'movie').toString();status=(r['status']??'suggested').toString();
  planned=DateTime.tryParse((r['planned_on']??'').toString());
  enjoyed=DateTime.tryParse((r['enjoyed_on']??'').toString());
 }
 @override void dispose(){title.dispose();description.dispose();platform.dispose();url.dispose();super.dispose();}
 String format(DateTime? d)=>d==null?'Not set':
   d.year.toString().padLeft(4,'0')+'-'+d.month.toString().padLeft(2,'0')+'-'+d.day.toString().padLeft(2,'0');
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
    'source_url':url.text.trim(),'status':status};
   if(widget.original==null){
    await db.from('shared_experiences').insert({...values,'space_id':widget.spaceId});
   }else{
    await db.from('shared_experiences').update(values).eq('id',widget.original!['id']);
   }
   if(mounted)Navigator.pop(context,true);
  }on PostgrestException catch(e){if(mounted)setState(()=>error=e.message);}
   catch(_){if(mounted)setState(()=>error='Could not save experience.');}
   finally{if(mounted)setState(()=>saving=false);}
 }
 @override Widget build(BuildContext context)=>Scaffold(
   appBar:AppBar(title:Text(widget.original==null?'Suggest an experience':'Edit experience')),
   body:ListView(padding:const EdgeInsets.all(16),children:[
   TextField(controller:title,maxLength:160,decoration:const InputDecoration(labelText:'Title')),
   DropdownButtonFormField<String>(initialValue:kind,
    decoration:const InputDecoration(labelText:'Type'),
    items:[for(final e in experienceTypes.entries)DropdownMenuItem(value:e.key,child:Text(e.value))],
    onChanged:(v)=>setState(()=>kind=v??kind)),
   TextField(controller:description,maxLength:5000,maxLines:4,
    decoration:const InputDecoration(labelText:'Why this one? Details or ideas')),
   TextField(controller:platform,maxLength:100,
    decoration:const InputDecoration(labelText:'Platform (optional)')),
   TextField(controller:url,maxLength:1800,keyboardType:TextInputType.url,
    decoration:const InputDecoration(labelText:'Link (optional)')),
   if(error!=null)Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
   FilledButton.icon(onPressed:saving?null:save,icon:const Icon(Icons.save),
    label:Text(saving?'Saving…':'Save')),
  ]));
}

class ExperienceDetail extends StatefulWidget{
 const ExperienceDetail({super.key,required this.id});
 final String id;
 @override State<ExperienceDetail> createState()=>_ExperienceDetailState();
}
class _ExperienceDetailState extends State<ExperienceDetail>{
 final db=Supabase.instance.client;
 final comment=TextEditingController(),review=TextEditingController();
 Map<String,dynamic>? item;
 List<Map<String,dynamic>> comments=[],reviews=[],audit=[];
 int? rating;
 bool loading=true,busy=false,showAudit=false;
 String? error;
 @override void initState(){super.initState();load();}
 @override void dispose(){comment.dispose();review.dispose();super.dispose();}
 String who(Object? id)=>id==db.auth.currentUser?.id?'You':'Partner';
 Future<void> load()async{
  try{
   final r=await db.from('shared_experiences').select().eq('id',widget.id).single();
   final v=await Future.wait([
    db.from('shared_experience_comments').select().eq('experience_id',widget.id).order('created_at'),
    db.from('shared_experience_reviews').select().eq('experience_id',widget.id),
    db.from('shared_experience_revisions').select().eq('experience_id',widget.id)
      .order('changed_at',ascending:false).limit(60),
   ]);
   if(!mounted)return;
   final myReview=v[1].where((a)=>a['user_id']==db.auth.currentUser?.id).firstOrNull;
   setState((){
    item=r;comments=List<Map<String,dynamic>>.from(v[0]);
    reviews=List<Map<String,dynamic>>.from(v[1]);
    audit=List<Map<String,dynamic>>.from(v[2]);
    rating=(myReview?['rating'] as num?)?.toInt();
    review.text=(myReview?['review']??'').toString();
    loading=false;error=null;
   });
  }catch(_){if(mounted)setState((){loading=false;error='Could not open experience.';});}
 }
 Future<void> mutate(Future<void> Function() action)async{
  if(busy)return;
  setState((){busy=true;error=null;});
  try{await action();await load();}
  on PostgrestException catch(e){if(mounted)setState(()=>error=e.message);}
  catch(_){if(mounted)setState(()=>error='Could not save change.');}
  finally{if(mounted)setState(()=>busy=false);}
 }
 Future<void> saveReview()async{
  if(rating==null&&review.text.trim().isEmpty)return;
  await mutate(()async{
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
 }
 Future<void> send()async{
  final body=comment.text.trim();if(body.isEmpty)return;
  await mutate(()async{
   await db.from('shared_experience_comments').insert({'experience_id':widget.id,'body':body});
   comment.clear();
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
   await db.from('shared_experiences').update({
    'archived_at':r['archived_at']==null?DateTime.now().toUtc().toIso8601String():null
   }).eq('id',widget.id);
  });
 }
 Future<void> openLink()async{
  final u=Uri.tryParse((item?['source_url']??'').toString());
  if(u!=null&&['http','https'].contains(u.scheme))await launchUrl(u,mode:LaunchMode.externalApplication);
 }
 @override Widget build(BuildContext context){
  final r=item;
  return Scaffold(appBar:AppBar(title:const Text('Our experience'),actions:[
   if(r!=null)IconButton(tooltip:'Edit',onPressed:edit,icon:const Icon(Icons.edit_outlined)),
   if(r!=null)IconButton(tooltip:'Archive or restore',onPressed:archive,
    icon:Icon(r['archived_at']==null?Icons.archive_outlined:Icons.restore_outlined)),
  ]),body:loading?const Center(child:CircularProgressIndicator()):
   r==null?Center(child:Text(error??'Not found')):ListView(
    padding:const EdgeInsets.all(16),children:[
    Text(r['title'].toString(),style:Theme.of(context).textTheme.headlineSmall),
    Text((experienceTypes[r['category']]??'Other')+' · '+(experienceStates[r['status']]??'Suggested')),
    if((r['description']??'').toString().isNotEmpty)Text(r['description'].toString()),
    if((r['platform']??'').toString().isNotEmpty)Text('Platform: '+r['platform'].toString()),
    if((r['source_url']??'').toString().isNotEmpty)TextButton.icon(
     onPressed:openLink,icon:const Icon(Icons.open_in_new),label:const Text('Open link')),
    const Divider(height:28),
    Text('Our ratings and reviews',style:Theme.of(context).textTheme.titleLarge),
    for(final x in reviews)Card(elevation:0,child:ListTile(
      title:Text(who(x['user_id'])+' · '+(x['rating']??'No rating').toString()),
      subtitle:Text((x['review']??'').toString()))),
    const Text('My rating'),
    Wrap(children:[
     for(var i=1;i<=5;i++)IconButton(tooltip:'Rate '+i.toString(),
      onPressed:()=>setState(()=>rating=i),
      icon:Icon((rating??0)>=i?Icons.star:Icons.star_border)),
     TextButton(onPressed:()=>setState(()=>rating=null),child:const Text('Clear')),
    ]),
    TextField(controller:review,maxLength:2000,maxLines:3,
     decoration:const InputDecoration(labelText:'My review')),
    Align(alignment:Alignment.centerRight,child:FilledButton(
     onPressed:busy?null:saveReview,child:const Text('Save my review'))),
    const Divider(height:28),
    Text('Our conversation',style:Theme.of(context).textTheme.titleLarge),
    for(final x in comments.where((c)=>c['archived_at']==null))
     Card(elevation:0,child:ListTile(
      title:Text(who(x['created_by'])),subtitle:Text(x['body'].toString()),
      trailing:x['created_by']==db.auth.currentUser?.id?
       IconButton(tooltip:'Retract',icon:const Icon(Icons.delete_outline),
        onPressed:busy?null:()=>mutate(()async{
         await db.from('shared_experience_comments').update({
          'archived_at':DateTime.now().toUtc().toIso8601String()}).eq('id',x['id']);
        })):null)),
    TextField(controller:comment,maxLength:2000,maxLines:3,
     decoration:const InputDecoration(labelText:'Share your thoughts')),
    Align(alignment:Alignment.centerRight,child:FilledButton.icon(
     onPressed:busy?null:send,icon:const Icon(Icons.send_outlined),
     label:const Text('Send'))),
    if(error!=null)Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
  ]));
 }
}

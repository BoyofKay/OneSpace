import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'memory_photo_gallery.dart';
import 'memory_photo_service.dart';
import 'scrapbook_templates.dart';
import 'scrapbook_page_canvas.dart';
import 'package:onespace/l10n/phrases.dart';

/// A scrapbook is a first-class Memory containing collaborative designed pages.
/// All photo bytes remain in the existing RLS-protected memory storage bucket.
class ScrapbookStudioScreen extends StatefulWidget {
 const ScrapbookStudioScreen({super.key,required this.spaceId,this.memoryId});
 final String spaceId;
 final String? memoryId;
 @override State<ScrapbookStudioScreen> createState()=>_ScrapbookStudioScreenState();
}
class _ScrapbookStudioScreenState extends State<ScrapbookStudioScreen>{
 final db=Supabase.instance.client;
 final boundary=GlobalKey();
 String? id,error;
 Map<String,dynamic>? memory;
 List<Map<String,dynamic>> photoRows=[];
 List<Map<String,dynamic>> invites=[];
 final signed=<String,String>{};
 final signedTimes=<String,DateTime>{};
 Stream<List<Map<String,dynamic>>>? pageStream;
 StreamSubscription<List<Map<String,dynamic>>>? photoChanges,inviteChanges;
 int selectedPage=0;
 bool busy=false,loading=true,showPhotoManager=false,showWelcome=false;
 String get me=>db.auth.currentUser?.id??'';
 bool get isOwner=>memory?['created_by']==me;
 bool get isShared=>memory?['visibility']=='shared';
 bool get canEdit=>isOwner||invites.any((i)=>i['invited_user_id']==me&&i['status']=='accepted');
 bool get awaiting=>invites.any((i)=>i['invited_user_id']==me&&i['status']=='pending');
 String get inviteState{
  if(isOwner)return invites.isEmpty?'Not invited yet':invites.first['status'].toString();
  return invites.isEmpty?'Not invited':invites.first['status'].toString();
 }
 @override void initState(){
  super.initState();id=widget.memoryId;
  if(id!=null){_load();}else{loading=false;}
 }
 @override void dispose(){
  photoChanges?.cancel();inviteChanges?.cancel();super.dispose();
 }
 Future<void> _load()async{
  final current=id;
  if(current==null)return;
  if(mounted)setState((){loading=true;error=null;});
  try{
   final row=await db.from('memories').select(
    'id,space_id,title,created_by,visibility,memory_type,archived_at')
    .eq('id',current).eq('space_id',widget.spaceId).single();
   if(row['memory_type']!='scrapbook')throw StateError('Not a scrapbook');
   final photos=await db.from('memory_photos')
    .select('id,object_path,caption,display_order,people_tags,place_tag,other_tags')
    .eq('memory_id',current).isFilter('archived_at',null)
    .order('created_at',ascending:false).limit(150);
   final people=await db.from('scrapbook_invites')
    .select('memory_id,invited_user_id,invited_by,status')
    .eq('memory_id',current).limit(2);
   if(!mounted)return;
   setState((){
    memory=row;photoRows=List<Map<String,dynamic>>.from(photos);
    invites=List<Map<String,dynamic>>.from(people);
    pageStream=db.from('scrapbook_pages').stream(primaryKey:['id'])
     .eq('memory_id',current).order('page_order');
    loading=false;
   });
   photoChanges?.cancel();inviteChanges?.cancel();
   photoChanges=db.from('memory_photos').stream(primaryKey:['id'])
    .eq('memory_id',current).limit(150).listen((rows){
     if(!mounted)return;
     setState(()=>photoRows=rows.where((x)=>x['archived_at']==null).toList());
   },onError:(Object e,StackTrace st){});
   inviteChanges=db.from('scrapbook_invites').stream(
    primaryKey:['memory_id','invited_user_id'])
    .eq('memory_id',current).limit(2).listen((rows){
     if(mounted)setState(()=>invites=rows);
   },onError:(Object e,StackTrace st){});
  }on PostgrestException catch(e){
   if(mounted)setState((){loading=false;error=e.message;});
  }catch(_){
   if(mounted)setState((){
    loading=false;error='Could not open this scrapbook. Check access and retry.';
   });
  }
 }
 Future<void> _create(ScrapbookDesign design)async{
  if(busy)return;
  final input=TextEditingController();
  var sharing=true;
  final requested=await showDialog<(String,bool)>(
   context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,update)=>AlertDialog(
    title:Text(tt('Start ')+design.name),
    content:Column(mainAxisSize:MainAxisSize.min,children:[
     Text(tt(design.subtitle)),
     const SizedBox(height:12),
     TextField(controller:input,maxLength:120,autofocus:true,
      decoration:InputDecoration(labelText:tt('Scrapbook title'),
       hintText:tt('Our November memories'),border:OutlineInputBorder())),
     SwitchListTile(
      contentPadding:EdgeInsets.zero,value:sharing,
      title:Text(tt('Shared with partner')),
      subtitle:Text(tt('Only you can edit until your invitation is accepted.')),
      onChanged:(v)=>update(()=>sharing=v)),
    ]),
    actions:[
     TextButton(onPressed:()=>Navigator.pop(ctx),child:Text(tt('Cancel'))),
     FilledButton(onPressed:()=>Navigator.pop(ctx,(input.text.trim(),sharing)),
      child:Text(tt('Create scrapbook'))),
    ],
   )));
  input.dispose();
  if(requested==null||!mounted)return;
  final problem=ScrapbookTemplates.validateTitle(requested.$1);
  if(problem!=null){setState(()=>error=problem);return;}
  setState((){busy=true;error=null;});
  try{
   final key=await db.rpc('create_scrapbook',params:{
    'p_space_id':widget.spaceId,'p_title':requested.$1,
    'p_template_key':design.key,'p_visibility':requested.$2?'shared':'private',
    'p_memory_date':ScrapbookTemplates.compactDate(DateTime.now()),
   });
   if(!mounted)return;
   id=key.toString();showWelcome=true;selectedPage=0;
   await _load();
  }on PostgrestException catch(e){if(mounted)setState(()=>error=e.message);}
  catch(_){if(mounted)setState(()=>error='Could not create your scrapbook.');}
  finally{if(mounted)setState(()=>busy=false);}
 }
 Future<void> _respond(bool accept)async{
  if(id==null||busy)return;
  setState(()=>busy=true);
  try{
   await db.rpc('respond_scrapbook_invite',params:{
    'p_memory_id':id,'p_accept':accept,
   });
   await _load();
  }on PostgrestException catch(e){if(mounted)setState(()=>error=e.message);}
  finally{if(mounted)setState(()=>busy=false);}
 }
 Future<void> _invite()async{
  if(id==null||busy||!isOwner||!isShared)return;
  setState(()=>busy=true);
  try{
   await db.rpc('invite_scrapbook_partner',params:{'p_memory_id':id});
   if(mounted)ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content:Text(tt('Invitation sent to your partner.'))));
   await _load();
  }on PostgrestException catch(e){if(mounted)setState(()=>error=e.message);}
  finally{if(mounted)setState(()=>busy=false);}
 }
 Future<void> _addPage(List<Map<String,dynamic>> pages)async{
  if(!canEdit||busy||id==null||pages.length>=12)return;
  final next=pages.isEmpty?0:pages.map((p)=>(p['page_order'] as num).toInt())
   .reduce((a,b)=>a>b?a:b)+1;
  final template=pages.isEmpty?'polaroid_letters':
   (pages[selectedPage.clamp(0,pages.length-1)]['template_key']??'polaroid_letters').toString();
  setState(()=>busy=true);
  try{
   await db.from('scrapbook_pages').insert({
    'memory_id':id,'page_order':next,'template_key':template,
   });
   if(mounted)setState(()=>selectedPage=pages.length);
  }on PostgrestException catch(e){
   if(mounted)setState(()=>error='Could not create a page: '+e.message);
  }finally{if(mounted)setState(()=>busy=false);}
 }
 Future<void> _changeTemplate(Map<String,dynamic> page)async{
  if(!canEdit||busy)return;
  final key=await showModalBottomSheet<String>(context:context,
   showDragHandle:true,builder:(ctx)=>SafeArea(child:ListView(
    shrinkWrap:true,children:[
     ListTile(title:Text(tt('Choose a page design')),
      subtitle:Text(tt('Photos and writing stay intact when you change designs.'))),
     for(final d in ScrapbookTemplates.designs)ListTile(
      leading:Icon(d.icon,color:d.accent),
      title:Text(tt(d.name)),subtitle:Text(tt(d.subtitle)),
      trailing:page['template_key']==d.key?const Icon(Icons.check):null,
      onTap:()=>Navigator.pop(ctx,d.key)),
   ])));
  if(key==null||page['template_key']==key)return;
  await _savePage(page,{'template_key':key});
 }
 Future<void> _editWords(Map<String,dynamic> page)async{
  if(!canEdit||busy)return;
  final title=TextEditingController(text:(page['title']??'').toString());
  final sub=TextEditingController(text:(page['subtitle']??'').toString());
  final story=TextEditingController(text:(page['story_text']??'').toString());
  final highlight=TextEditingController(text:(page['highlight_text']??'').toString());
  final next=await showDialog<Map<String,dynamic>>(context:context,
   builder:(ctx)=>AlertDialog(
    title:Text(tt('Write your scrapbook page')),
    content:SizedBox(width:520,child:SingleChildScrollView(child:Column(children:[
     TextField(controller:title,maxLength:120,
      decoration:InputDecoration(labelText:tt('Page title'))),
     TextField(controller:sub,maxLength:180,
      decoration:InputDecoration(labelText:tt('Subtitle'))),
     TextField(controller:highlight,maxLength:360,maxLines:2,
      decoration:InputDecoration(labelText:tt('Favorite quote / highlight'))),
     TextField(controller:story,maxLength:2200,maxLines:7,minLines:4,
      decoration:InputDecoration(labelText:tt('Your story'))),
    ]))),
    actions:[
     TextButton(onPressed:()=>Navigator.pop(ctx),child:Text(tt('Cancel'))),
     FilledButton(onPressed:()=>Navigator.pop(ctx,{
      'title':title.text.trim(),'subtitle':sub.text.trim(),
      'story_text':story.text.trim(),'highlight_text':highlight.text.trim(),
     }),child:Text(tt('Save page'))),
    ],
   ));
  title.dispose();sub.dispose();story.dispose();highlight.dispose();
  if(next!=null)await _savePage(page,next);
 }
 Future<void> _savePage(Map<String,dynamic> page,Map<String,dynamic> fields)async{
  if(!canEdit||busy)return;
  setState((){busy=true;error=null;});
  try{
   // Optimistic concurrency prevents accidental overwrite of partner changes.
   final rows=await db.from('scrapbook_pages').update(fields)
    .eq('id',page['id']).eq('updated_at',page['updated_at'])
    .select('id');
   if(rows.isEmpty&&mounted)setState(()=>error=
    'Your partner updated this page. Refresh before saving again.');
  }on PostgrestException catch(e){
   if(mounted)setState(()=>error=e.message);
  }finally{if(mounted)setState(()=>busy=false);}
 }
 Future<void> _pickPhoto(Map<String,dynamic> page,int slot)async{
  if(!canEdit||busy||id==null)return;
  final choice=await showModalBottomSheet<String>(context:context,
   showDragHandle:true,builder:(ctx)=>SafeArea(child:Column(
    mainAxisSize:MainAxisSize.min,children:[
     ListTile(title:Text(tt('Fill a photo slot'))),
     ListTile(leading:const Icon(Icons.photo_camera_outlined),
      title:Text(tt('Take a photo')),onTap:()=>Navigator.pop(ctx,'camera')),
     ListTile(leading:const Icon(Icons.photo_library_outlined),
      title:Text(tt('Choose from gallery')),onTap:()=>Navigator.pop(ctx,'gallery')),
     if(photoRows.isNotEmpty)ListTile(
      leading:const Icon(Icons.collections_outlined),
      title:Text(tt('Use an existing scrapbook photo')),
      onTap:()=>Navigator.pop(ctx,'existing')),
     ListTile(leading:const Icon(Icons.remove_circle_outline),
      title:Text(tt('Clear this slot')),onTap:()=>Navigator.pop(ctx,'clear')),
   ])));
  if(choice==null||!mounted)return;
  String? photoId;
  if(choice=='existing'){
   photoId=await showDialog<String>(context:context,builder:(ctx)=>SimpleDialog(
    title:Text(tt('Select an existing photo')),
    children:[for(final p in photoRows)SimpleDialogOption(
     onPressed:()=>Navigator.pop(ctx,p['id'].toString()),
     child:Text(tt(((p['caption']??'').toString().isEmpty?'Photo':'Photo · '+p['caption'].toString())+
      ((p['place_tag']??'').toString().isEmpty?'':' · '+p['place_tag'].toString())),
       maxLines:2,overflow:TextOverflow.ellipsis)),
    ],
   ));
   if(photoId==null)return;
  }else if(choice=='clear'){
   await _savePage(page,{'photo_'+slot.toString()+'_id':null});
   return;
  }else{
   final selected=await ImagePicker().pickImage(
    source:choice=='camera'?ImageSource.camera:ImageSource.gallery,
    imageQuality:82,maxHeight:1600,maxWidth:1600);
   if(selected==null||!mounted)return;
   setState(()=>busy=true);
   try{
    photoId=await MemoryPhotoService(db).addFileReturningId(id!,selected);
   }on PostgrestException catch(e){
    if(mounted)setState(()=>error='Photo upload failed: '+e.message);
   }catch(_){
    if(mounted)setState(()=>error='Photo could not be uploaded.');
   }finally{if(mounted)setState(()=>busy=false);}
   if(photoId==null||!mounted)return;
   await _loadPhotos();
  }
  await _savePage(page,{'photo_'+slot.toString()+'_id':photoId});
 }
 Future<void> _loadPhotos()async{
  if(id==null)return;
  final rows=await db.from('memory_photos')
   .select('id,object_path,caption,people_tags,place_tag,other_tags,archived_at')
   .eq('memory_id',id!).isFilter('archived_at',null).limit(150);
  if(mounted)setState(()=>photoRows=List<Map<String,dynamic>>.from(rows));
 }
 void _resolveUrls(Map<String,dynamic> page){
  final paths=<String,String>{};
  final now=DateTime.now();
  for(var n=1;n<=3;n++){
   final pid=page['photo_'+n.toString()+'_id']?.toString();
   if(pid==null)continue;
   final row=photoRows.where((x)=>x['id'].toString()==pid).toList();
   if(row.isEmpty)continue;
   final issued=signedTimes[pid];
   if(issued!=null&&now.difference(issued)<const Duration(seconds:65))continue;
   paths[pid]=row.first['object_path'].toString();
  }
  if(paths.isEmpty)return;
  for(final entry in paths.entries){
   signedTimes[entry.key]=DateTime.now();
   MemoryPhotoService(db).signedUrl(entry.value).then((url){
    if(mounted)setState(()=>signed[entry.key]=url);
   },onError:(Object e,StackTrace stack){
    signedTimes.remove(entry.key);
   });
  }
 }
 Future<void> _export(Map<String,dynamic> page)async{
  if(busy)return;
  setState((){busy=true;error=null;});
  try{
   _resolveUrls(page);
   // Every populated photo must have a ready signed URL before capturing.
   final photoIds=<String>[];
   for(var n=1;n<=3;n++){
    final photo=page['photo_'+n.toString()+'_id']?.toString();
    if(photo!=null)photoIds.add(photo);
   }
   if(photoIds.any((key)=>signed[key]==null)){
    throw StateError('Photo previews are still loading. Retry the export.');
   }
   await Future.wait(photoIds.map((key)=>precacheImage(
     NetworkImage(signed[key]!),context)));
   await WidgetsBinding.instance.endOfFrame;
   final contextOfCanvas=boundary.currentContext;
   if(contextOfCanvas==null)throw StateError('Page is not ready.');
   final renderer=contextOfCanvas.findRenderObject() as RenderRepaintBoundary;
   final img=await renderer.toImage(pixelRatio:3);
   final encoded=await img.toByteData(format:ui.ImageByteFormat.png);
   img.dispose();
   if(encoded==null)throw StateError('Could not create PNG.');
   if(!Platform.isAndroid){
    throw StateError('PNG export is currently supported in the Android preview.');
   }
   await const MethodChannel('onespace/scrapbook_export').invokeMethod<void>(
    'saveAndShare',{'bytes':encoded.buffer.asUint8List(),
     'name':(memory?['title']??'OneSpace-Scrapbook').toString()});
   if(mounted)ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content:Text(tt('Scrapbook page saved as a PNG.'))));
  }catch(e){
   if(mounted)setState(()=>error=e is StateError?e.message:
    tt('Could not export the page. Make sure all photos are loaded.'));
  }finally{if(mounted)setState(()=>busy=false);}
 }
 Widget _welcome(){
  return ListView(padding:const EdgeInsets.all(18),children:[
   Text(tt('Scrapbook Studio'),style:Theme.of(context).textTheme.headlineMedium),
   const SizedBox(height:6),
   Text(tt('Pick a beautiful starting point. Add photos and words, then invite your partner to write the next chapter.')),
   const SizedBox(height:14),
   for(final d in ScrapbookTemplates.designs)Card(
    child:InkWell(onTap:busy?null:()=>_create(d),
     child:Padding(padding:const EdgeInsets.all(16),child:Row(children:[
      SizedBox(width:116,height:152,child:ClipRRect(
       borderRadius:BorderRadius.circular(7),
       child:FittedBox(fit:BoxFit.contain,
        child:SizedBox(width:340,height:447,child:ScrapbookPageCanvas(
         page:{'template_key':d.key,'title':d.name,
          'subtitle':d.subtitle,'story_text':'A beautiful page for the moments we share.'},
         photos:const {},signedUrls:const {}))))),
      const SizedBox(width:16),
      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
       Text(tt(d.name),style:Theme.of(context).textTheme.titleMedium),
       const SizedBox(height:4),
       Text(tt(d.subtitle)),
       const SizedBox(height:4),
       Text(tt(d.photoCount.toString()+' photo slots per page'),
        style:Theme.of(context).textTheme.bodySmall),
      ])),
      const Icon(Icons.chevron_right),
     ]))),
   ),
   if(busy)const LinearProgressIndicator(),
  ]);
 }
 Widget _collaboration(){
  if(!isShared)return ListTile(leading:Icon(Icons.lock_outline),
   title:Text(tt('Private scrapbook')),subtitle:Text(tt('Only you can view and edit it.')));
  if(isOwner)return ListTile(
   contentPadding:EdgeInsets.zero,leading:const Icon(Icons.people_outline),
   title:Text(tt(inviteState=='accepted'?'Creating together':
    inviteState=='pending'?'Invitation sent':'Invite your partner')),
   subtitle:Text(tt(inviteState=='accepted'?'Both of you can edit every page.':
    inviteState=='pending'?'Your partner can accept or decline.':
    'Ask your partner to contribute photos and stories.')),
   trailing:inviteState=='accepted'?const Icon(Icons.check_circle_outline):
    TextButton(onPressed:busy?null:_invite,child:Text(
     tt(inviteState=='pending'?'Resend':'Invite'))),
  );
  if(awaiting)return Card(child:Padding(padding:const EdgeInsets.all(12),
   child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Text(tt('Your partner invited you to this scrapbook!'),
     style:TextStyle(fontWeight:FontWeight.bold)),
    Text(tt('Accept to add your own photos and words to any page.')),
    Wrap(spacing:8,children:[
     OutlinedButton(onPressed:busy?null:()=>_respond(false),
      child:Text(tt('Decline'))),
     FilledButton(onPressed:busy?null:()=>_respond(true),
      child:Text(tt('Accept invitation'))),
    ]),
   ])));
  return ListTile(leading:Icon(canEdit?Icons.edit_note:Icons.visibility_outlined),
   title:Text(tt(canEdit?tt('You can contribute'):tt('Shared view'))),
   subtitle:Text(tt(canEdit?'Your changes are visible to both of you.':
    'Only invited collaborators can edit scrapbook pages.')));
 }
 Widget _studio(){
  final myId=id;
  if(myId==null||memory==null||pageStream==null)return _welcome();
  return StreamBuilder<List<Map<String,dynamic>>>(
   stream:pageStream,builder:(ctx,snapshot){
    if(snapshot.hasError)return Center(child:Text(tt('Could not load scrapbook pages.')));
    if(!snapshot.hasData)return const Center(child:CircularProgressIndicator());
    final pages=snapshot.data!;
    if(pages.isEmpty)return Center(child:Text(tt('This scrapbook has no pages yet.')));
    final idx=selectedPage.clamp(0,pages.length-1);
    final page=pages[idx];
    WidgetsBinding.instance.addPostFrameCallback((_){
     if(mounted)_resolveUrls(page);
    });
    final pics=<String,Map<String,dynamic>>{
     for(final x in photoRows)x['id'].toString():x
    };
    final scheme=ScrapbookTemplates.get(page['template_key']?.toString());
    return ListView(padding:const EdgeInsetsDirectional.fromSTEB(14,10,14,90),children:[
     Text(tt(memory!['title'].toString()),style:Theme.of(context).textTheme.headlineSmall),
     const SizedBox(height:8),
     _collaboration(),
     const SizedBox(height:8),
     SingleChildScrollView(scrollDirection:Axis.horizontal,child:Row(children:[
      for(var n=0;n<pages.length;n++)Padding(padding:const EdgeInsetsDirectional.only(end:6),
       child:ChoiceChip(
        label:Text(tt('Page ')+(n+1).toString()),
        selected:idx==n,onSelected:(_)=>setState(()=>selectedPage=n))),
      if(canEdit&&pages.length<12)ActionChip(
       avatar:const Icon(Icons.add,size:18),
       label:Text(tt('New page')),
       onPressed:busy?null:()=>_addPage(pages)),
     ])),
     const SizedBox(height:14),
     Text(tt(scheme.name+' · '+(idx+1).toString()+'/'+pages.length.toString()),
      style:Theme.of(context).textTheme.titleMedium),
     const SizedBox(height:8),
     Center(child:ConstrainedBox(
      constraints:const BoxConstraints(maxWidth:430),
      child:RepaintBoundary(key:boundary,child:ScrapbookPageCanvas(
       page:page,photos:pics,signedUrls:signed)),
     )),
     const SizedBox(height:12),
     if(canEdit)Wrap(spacing:8,runSpacing:4,children:[
      OutlinedButton.icon(onPressed:busy?null:()=>_editWords(page),
       icon:const Icon(Icons.edit_note_outlined),label:Text(tt('Write'))),
      OutlinedButton.icon(onPressed:busy?null:()=>_changeTemplate(page),
       icon:const Icon(Icons.dashboard_customize_outlined),
       label:Text(tt('Change design'))),
      for(var n=1;n<=scheme.photoCount;n++)
       OutlinedButton.icon(onPressed:busy?null:()=>_pickPhoto(page,n),
        icon:const Icon(Icons.add_photo_alternate_outlined),
        label:Text(tt('Photo ')+n.toString())),
     ]),
     const SizedBox(height:8),
     FilledButton.icon(onPressed:busy?null:()=>_export(page),
      icon:const Icon(Icons.ios_share_outlined),
      label:Text(tt('Export this page as PNG'))),
     const SizedBox(height:8),
     if(canEdit)ExpansionTile(
      title:Text(tt('Photo library & searchable tags')),
      subtitle:Text(tt('People, location, tags and captions')),
      children:[MemoryPhotoGallery(memoryId:myId,
       editable:canEdit,layout:'grid')],
     ),
     if(busy)const LinearProgressIndicator(),
     if(error!=null)Padding(padding:const EdgeInsets.all(8),
      child:Text(tt(error!),style:TextStyle(color:Theme.of(context).colorScheme.error))),
    ]);
   });
 }
 @override Widget build(BuildContext context)=>Scaffold(
  appBar:AppBar(title:Text(tt('Scrapbook Studio')),
   actions:[if(id!=null)IconButton(
    tooltip:tt('Refresh scrapbook'),onPressed:busy?null:_load,
    icon:const Icon(Icons.refresh))]),
  body:loading?const Center(child:CircularProgressIndicator()):
   id==null?_welcome():_studio(),
  bottomNavigationBar:error!=null&&id==null?SafeArea(
   child:Padding(padding:const EdgeInsets.all(8),child:Text(tt(error!),
    style:TextStyle(color:Theme.of(context).colorScheme.error)))):null,
 );
}

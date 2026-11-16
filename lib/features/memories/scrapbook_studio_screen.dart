import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/item_menu.dart';
import 'memory_photo_gallery.dart';
import 'memory_photo_service.dart';
import 'scrapbook_templates.dart';
import 'scrapbook_page_canvas.dart';
import 'scrapbook_viewer_screen.dart';
import 'package:onespace/l10n/phrases.dart';

/// A scrapbook is a first-class Memory containing collaborative designed pages.
/// All photo bytes remain in the existing RLS-protected memory storage bucket.
///
/// R70 (Ahmed): no title pop-up (the title is typed on the page itself);
/// photos and words are tapped right on the page; changes wait for Save;
/// pages can be removed; View opens the reader with PDF and email.
class ScrapbookStudioScreen extends StatefulWidget {
 const ScrapbookStudioScreen({super.key,required this.spaceId,this.memoryId});
 final String spaceId;
 final String? memoryId;
 @override State<ScrapbookStudioScreen> createState()=>_ScrapbookStudioScreenState();
}
class _ScrapbookStudioScreenState extends State<ScrapbookStudioScreen>{
 final db=Supabase.instance.client;
 String? id,error,selectedPageId;
 Map<String,dynamic>? memory;
 List<Map<String,dynamic>> pages=[],photoRows=[],invites=[];
 /// Unsaved changes per page id.
 final drafts=<String,Map<String,dynamic>>{};
 final signed=<String,String>{};
 final signedTimes=<String,DateTime>{};
 StreamSubscription<List<Map<String,dynamic>>>? pageChanges,photoChanges,inviteChanges;
 bool busy=false,loading=true,shared=true,justCreated=false;
 String get me=>db.auth.currentUser?.id??'';
 bool get isOwner=>memory?['created_by']==me;
 bool get isShared=>memory?['visibility']=='shared';
 bool get canEdit=>isOwner||invites.any((i)=>i['invited_user_id']==me&&i['status']=='accepted');
 bool get awaiting=>invites.any((i)=>i['invited_user_id']==me&&i['status']=='pending');
 bool get dirty=>drafts.values.any((d)=>d.isNotEmpty);
 String get inviteState{
  if(isOwner)return invites.isEmpty?'Not invited yet':invites.first['status'].toString();
  return invites.isEmpty?'Not invited':invites.first['status'].toString();
 }
 @override void initState(){
  super.initState();id=widget.memoryId;
  if(id!=null){_load();}else{loading=false;}
 }
 @override void dispose(){
  pageChanges?.cancel();photoChanges?.cancel();inviteChanges?.cancel();super.dispose();
 }
 /// Pages always in their order (the live stream may deliver them in any order).
 List<Map<String,dynamic>> _sorted(List<Map<String,dynamic>> rows)=>
  [...rows]..sort((a,b)=>((a['page_order'] as num?)??0).compareTo((b['page_order'] as num?)??0));
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
    .select('id,object_path,caption,display_order,people_tags,place_tag,other_tags,archived_at')
    .eq('memory_id',current).isFilter('archived_at',null).limit(150);
   final people=await db.from('scrapbook_invites')
    .select('memory_id,invited_user_id,invited_by,status').eq('memory_id',current).limit(2);
   final pageRows=await db.from('scrapbook_pages').select().eq('memory_id',current).order('page_order');
   if(!mounted)return;
   setState((){
    memory=row;photoRows=List<Map<String,dynamic>>.from(photos);
    invites=List<Map<String,dynamic>>.from(people);
    pages=_sorted(List<Map<String,dynamic>>.from(pageRows));
    selectedPageId??=pages.isEmpty?null:pages.first['id'].toString();
    loading=false;
   });
   pageChanges?.cancel();photoChanges?.cancel();inviteChanges?.cancel();
   pageChanges=db.from('scrapbook_pages').stream(primaryKey:['id']).eq('memory_id',current).listen((rows){
    if(!mounted)return;
    setState((){
     pages=_sorted(rows);
     if(pages.isNotEmpty&&!pages.any((p)=>p['id'].toString()==selectedPageId)){
      selectedPageId=pages.first['id'].toString();
     }
    });
   },onError:(Object e,StackTrace st){});
   photoChanges=db.from('memory_photos').stream(primaryKey:['id'])
    .eq('memory_id',current).limit(150).listen((rows){
     if(mounted)setState(()=>photoRows=rows.where((x)=>x['archived_at']==null).toList());
   },onError:(Object e,StackTrace st){});
   inviteChanges=db.from('scrapbook_invites').stream(primaryKey:['memory_id','invited_user_id'])
    .eq('memory_id',current).limit(2).listen((rows){
     if(mounted)setState(()=>invites=rows);
   },onError:(Object e,StackTrace st){});
  }on PostgrestException catch(e){
   if(mounted)setState((){loading=false;error=e.message;});
  }catch(_){
   if(mounted)setState((){loading=false;error='Could not open this scrapbook. Check access and retry.';});
  }
 }
 /// Picking a design creates the scrapbook at once; the title is typed on the page.
 Future<void> _create(ScrapbookDesign design)async{
  if(busy)return;
  setState((){busy=true;error=null;});
  try{
   final key=await db.rpc('create_scrapbook',params:{
    'p_space_id':widget.spaceId,'p_title':tt('Our scrapbook'),
    'p_template_key':design.key,'p_visibility':shared?'shared':'private',
    'p_memory_date':ScrapbookTemplates.compactDate(DateTime.now()),
   });
   if(!mounted)return;
   id=key.toString();justCreated=true;selectedPageId=null;
   await _load();
   // The first page starts with an empty title so it can be typed in place.
   final first=pages.firstOrNull;
   if(first!=null)drafts[first['id'].toString()]={'title':''};
   if(mounted)setState((){});
  }on PostgrestException catch(e){if(mounted)setState(()=>error=e.message);}
  catch(_){if(mounted)setState(()=>error='Could not create your scrapbook.');}
  finally{if(mounted)setState(()=>busy=false);}
 }
 Future<void> _respond(bool accept)async{
  if(id==null||busy)return;
  setState(()=>busy=true);
  try{
   await db.rpc('respond_scrapbook_invite',params:{'p_memory_id':id,'p_accept':accept});
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
 Map<String,dynamic> _merged(Map<String,dynamic> page)=>{...page,...?drafts[page['id'].toString()]};
 void _draft(Map<String,dynamic> page,String field,Object? value){
  final key=page['id'].toString();
  final d=drafts.putIfAbsent(key,()=>{});
  if(page[field]==value){d.remove(field);}else{d[field]=value;}
  setState((){});
 }
 Future<void> _addPage()async{
  if(!canEdit||busy||id==null||pages.length>=30)return;
  final next=pages.isEmpty?0:pages.map((p)=>(p['page_order'] as num).toInt()).reduce((a,b)=>a>b?a:b)+1;
  final current=pages.where((p)=>p['id'].toString()==selectedPageId).firstOrNull;
  final template=(current?['template_key']??'polaroid_letters').toString();
  setState(()=>busy=true);
  try{
   // A new page is blank: it never takes photos from another page.
   final row=await db.from('scrapbook_pages').insert({
    'memory_id':id,'page_order':next,'template_key':template,
   }).select().single();
   if(mounted)setState((){
    if(!pages.any((p)=>p['id']==row['id']))pages=_sorted([...pages,row]);
    selectedPageId=row['id'].toString();
   });
  }on PostgrestException catch(e){
   if(mounted)setState(()=>error='Could not create a page: '+e.message);
  }finally{if(mounted)setState(()=>busy=false);}
 }
 Future<void> _removePage(Map<String,dynamic> page)async{
  if(!canEdit||busy)return;
  if(pages.length<=1){
   setState(()=>error='A scrapbook keeps at least one page.');return;
  }
  final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
   title:Text(tt('Remove this page?')),
   content:Text(tt('Its words and photo choices are removed. The photos stay in the scrapbook library.')),
   actions:[
    TextButton(onPressed:()=>Navigator.pop(ctx,false),child:Text(tt('Cancel'))),
    FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:Text(tt('Remove page'))),
   ]));
  if(ok!=true)return;
  setState((){busy=true;error=null;});
  try{
   await db.rpc('remove_scrapbook_page',params:{'p_page_id':page['id']});
   drafts.remove(page['id'].toString());
   final at=pages.indexWhere((p)=>p['id']==page['id']);
   final rest=pages.where((p)=>p['id']!=page['id']).toList();
   if(mounted)setState((){
    pages=rest;
    selectedPageId=rest.isEmpty?null:rest[(at-1).clamp(0,rest.length-1)]['id'].toString();
   });
  }on PostgrestException catch(e){if(mounted)setState(()=>error=e.message);}
  finally{if(mounted)setState(()=>busy=false);}
 }
 Future<void> _changeTemplate(Map<String,dynamic> page)async{
  if(!canEdit)return;
  final key=await showModalBottomSheet<String>(context:context,isScrollControlled:true,
   showDragHandle:true,builder:(ctx)=>SizedBox(height:MediaQuery.sizeOf(ctx).height*.8,child:ListView(children:[
     ListTile(title:Text(tt('Choose a page design')),
      subtitle:Text(tt('Words and photos stay when you change the design.'))),
     for(final group in ScrapbookTemplates.groups)...[
      Padding(padding:const EdgeInsets.fromLTRB(16,8,16,0),child:Text(tt(group),
       style:Theme.of(ctx).textTheme.titleSmall)),
      for(final d in ScrapbookTemplates.designs.where((d)=>d.group==group))ListTile(
       leading:CircleAvatar(backgroundColor:d.paper,child:Icon(d.icon,color:d.accent)),
       title:Text(tt(d.name)),subtitle:Text(tt(d.subtitle)+' · '+d.photoCount.toString()+tt(' photos')),
       trailing:_merged(page)['template_key']==d.key?const Icon(Icons.check):null,
       onTap:()=>Navigator.pop(ctx,d.key)),
     ],
   ])));
  if(key!=null)_draft(page,'template_key',key);
 }
 Future<void> _editText(Map<String,dynamic> page,String field)async{
  if(!canEdit)return;
  const labels={'title':'Page title','subtitle':'Subtitle','highlight_text':'Favourite quote','story_text':'Your story'};
  const limits={'title':120,'subtitle':180,'highlight_text':360,'story_text':2200};
  final ctl=TextEditingController(text:(_merged(page)[field]??'').toString());
  final value=await showModalBottomSheet<String>(context:context,isScrollControlled:true,showDragHandle:true,
   builder:(ctx)=>Padding(padding:EdgeInsets.fromLTRB(16,0,16,MediaQuery.viewInsetsOf(ctx).bottom+16),
    child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
     TextField(controller:ctl,autofocus:true,maxLength:limits[field],
      minLines:field=='story_text'?4:1,maxLines:field=='story_text'?8:2,
      textCapitalization:TextCapitalization.sentences,
      decoration:InputDecoration(labelText:tt(labels[field]!),border:const OutlineInputBorder())),
     FilledButton(onPressed:()=>Navigator.pop(ctx,ctl.text.trim()),child:Text(tt('Done'))),
    ])));
  ctl.dispose();
  if(value!=null)_draft(page,field,value);
 }
 Future<void> _pickPhoto(Map<String,dynamic> page,int slot)async{
  if(!canEdit||busy||id==null)return;
  final has=_merged(page)['photo_${slot}_id']!=null;
  final choice=await showModalBottomSheet<String>(context:context,
   showDragHandle:true,builder:(ctx)=>SafeArea(child:Column(
    mainAxisSize:MainAxisSize.min,children:[
     ListTile(leading:const Icon(Icons.photo_camera_outlined),
      title:Text(tt('Take a photo')),onTap:()=>Navigator.pop(ctx,'camera')),
     ListTile(leading:const Icon(Icons.photo_library_outlined),
      title:Text(tt('Choose from gallery')),onTap:()=>Navigator.pop(ctx,'gallery')),
     if(photoRows.isNotEmpty)ListTile(
      leading:const Icon(Icons.collections_outlined),
      title:Text(tt('Use a photo already in this scrapbook')),
      onTap:()=>Navigator.pop(ctx,'existing')),
     if(has)ListTile(leading:const Icon(Icons.remove_circle_outline),
      title:Text(tt('Empty this spot')),onTap:()=>Navigator.pop(ctx,'clear')),
   ])));
  if(choice==null||!mounted)return;
  String? photoId;
  if(choice=='existing'){
   for(final p in photoRows){_sign(p);}
   photoId=await showModalBottomSheet<String>(context:context,showDragHandle:true,builder:(ctx)=>
    StatefulBuilder(builder:(ctx,_)=>GridView.count(crossAxisCount:3,padding:const EdgeInsets.all(10),
     mainAxisSpacing:6,crossAxisSpacing:6,children:[
      for(final p in photoRows)InkWell(onTap:()=>Navigator.pop(ctx,p['id'].toString()),
       child:ClipRRect(borderRadius:BorderRadius.circular(8),child:signed[p['id'].toString()]==null
        ?const ColoredBox(color:Color(0x11000000),child:Center(child:Icon(Icons.photo_outlined)))
        :Image.network(signed[p['id'].toString()]!,fit:BoxFit.cover))),
     ])));
   if(photoId==null)return;
  }else if(choice=='clear'){
   _draft(page,'photo_${slot}_id',null);
   return;
  }else{
   final selected=await ImagePicker().pickImage(
    source:choice=='camera'?ImageSource.camera:ImageSource.gallery,
    imageQuality:82,maxHeight:1600,maxWidth:1600);
   if(selected==null||!mounted)return;
   setState(()=>busy=true);
   try{
    photoId=await MemoryPhotoService(db).addFileReturningId(id!,selected);
    final row=await db.from('memory_photos').select('id,object_path,caption,archived_at').eq('id',photoId).single();
    if(mounted)setState(()=>photoRows=[...photoRows.where((x)=>x['id']!=row['id']),row]);
   }on PostgrestException catch(e){
    if(mounted)setState(()=>error='Photo upload failed: '+e.message);
   }catch(_){
    if(mounted)setState(()=>error='Photo could not be uploaded.');
   }finally{if(mounted)setState(()=>busy=false);}
   if(photoId==null||!mounted)return;
  }
  _draft(page,'photo_${slot}_id',photoId);
 }
 /// Save: every changed page, and page 1's title becomes the scrapbook's name.
 Future<bool> _save()async{
  if(!canEdit||busy||!dirty)return true;
  setState((){busy=true;error=null;});
  var conflict=false;
  try{
   for(final entry in drafts.entries.toList()){
    if(entry.value.isEmpty)continue;
    final page=pages.where((p)=>p['id'].toString()==entry.key).firstOrNull;
    if(page==null)continue;
    final rows=await db.from('scrapbook_pages').update(entry.value)
     .eq('id',page['id']).eq('updated_at',page['updated_at']).select();
    if(rows.isEmpty){conflict=true;continue;}
    if((page['page_order'] as num?)==0&&entry.value.containsKey('title')){
     final t=(entry.value['title']??'').toString().trim();
     if(t.isNotEmpty)await db.from('memories').update({'title':t}).eq('id',id!);
    }
    drafts.remove(entry.key);
    final fresh=rows.first;
    pages=_sorted([...pages.where((p)=>p['id']!=fresh['id']),fresh]);
   }
   if(!mounted)return false;
   if(conflict){
    setState(()=>error='Your partner changed a page meanwhile. Their version is shown; your other changes were saved.');
    drafts.clear();
    await _load();
    return false;
   }
   ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(tt('Scrapbook saved.'))));
   justCreated=false;
   return true;
  }on PostgrestException catch(e){
   if(mounted)setState(()=>error=e.message);
   return false;
  }finally{if(mounted)setState(()=>busy=false);}
 }
 Future<bool> _confirmLeave()async{
  if(!dirty)return true;
  final choice=await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(
   title:Text(tt('Save your changes?')),
   content:Text(tt('You changed this scrapbook. Save before leaving?')),
   actions:[
    TextButton(onPressed:()=>Navigator.pop(ctx,'discard'),child:Text(tt('Discard'))),
    FilledButton(onPressed:()=>Navigator.pop(ctx,'save'),child:Text(tt('Save'))),
   ]));
  if(choice=='save')return _save();
  return choice=='discard';
 }
 Future<void> _view()async{
  if(id==null)return;
  if(dirty&&!await _save())return;
  if(!mounted)return;
  await Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>
   ScrapbookViewerScreen(spaceId:widget.spaceId,memoryId:id!)));
 }
 void _sign(Map<String,dynamic> row){
  final pid=row['id'].toString();
  final issued=signedTimes[pid];
  if(issued!=null&&DateTime.now().difference(issued)<const Duration(seconds:65))return;
  signedTimes[pid]=DateTime.now();
  MemoryPhotoService(db).signedUrl(row['object_path'].toString()).then((url){
   if(mounted)setState(()=>signed[pid]=url);
  },onError:(Object e,StackTrace s){signedTimes.remove(pid);});
 }
 void _resolveUrls(Map<String,dynamic> page){
  for(var n=1;n<=4;n++){
   final pid=page['photo_${n}_id']?.toString();
   if(pid==null)continue;
   final row=photoRows.where((x)=>x['id'].toString()==pid).firstOrNull;
   if(row!=null)_sign(row);
  }
 }
 Widget _welcome(){
  final theme=Theme.of(context);
  return ListView(padding:const EdgeInsets.all(18),children:[
   Text(tt('Pick a design to start. You can name it and fill it right on the page.')),
   const SizedBox(height:10),
   Wrap(spacing:8,children:[
    ChoiceChip(avatar:const Icon(Icons.people_outline,size:18),label:Text(tt('Both of us')),selected:shared,
     onSelected:(_)=>setState(()=>shared=true)),
    ChoiceChip(avatar:const Icon(Icons.lock_outline,size:18),label:Text(tt('Only me')),selected:!shared,
     onSelected:(_)=>setState(()=>shared=false)),
   ]),
   const SizedBox(height:12),
   for(final group in ScrapbookTemplates.groups)...[
    Padding(padding:const EdgeInsets.only(top:10,bottom:6),child:Text(tt(group),style:theme.textTheme.titleMedium)),
    SizedBox(height:236,child:ListView(scrollDirection:Axis.horizontal,children:[
     for(final d in ScrapbookTemplates.designs.where((d)=>d.group==group))Padding(
      padding:const EdgeInsetsDirectional.only(end:12),
      child:InkWell(borderRadius:BorderRadius.circular(10),onTap:busy?null:()=>_create(d),
       child:SizedBox(width:140,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        SizedBox(width:140,height:184,child:ClipRRect(borderRadius:BorderRadius.circular(8),
         child:FittedBox(fit:BoxFit.contain,child:SizedBox(width:340,height:447,child:ScrapbookPageCanvas(
          page:{'template_key':d.key,'title':tt(d.name),'subtitle':tt(d.subtitle)},
          photos:const {},signedUrls:const {}))))),
        const SizedBox(height:4),
        Text(tt(d.name),maxLines:1,overflow:TextOverflow.ellipsis,style:theme.textTheme.titleSmall),
        Text(d.photoCount.toString()+tt(' photos'),style:theme.textTheme.bodySmall),
       ])))),
    ])),
   ],
   if(busy)const LinearProgressIndicator(),
   if(error!=null)Text(tt(error!),style:TextStyle(color:theme.colorScheme.error)),
  ]);
 }
 Widget _collaboration(){
  if(!isShared)return ListTile(contentPadding:EdgeInsets.zero,leading:const Icon(Icons.lock_outline),
   title:Text(tt('Private scrapbook')),subtitle:Text(tt('Only you can view and edit it.')));
  if(isOwner)return ListTile(
   contentPadding:EdgeInsets.zero,leading:const Icon(Icons.people_outline),
   title:Text(tt(inviteState=='accepted'?'Creating together':
    inviteState=='pending'?'Invitation sent':'Invite your partner')),
   subtitle:Text(tt(inviteState=='accepted'?'Both of you can edit every page.':
    inviteState=='pending'?'Your partner can accept or decline.':
    'Ask your partner to add photos and words.')),
   trailing:inviteState=='accepted'?const Icon(Icons.check_circle_outline):
    TextButton(onPressed:busy?null:_invite,child:Text(tt(inviteState=='pending'?'Resend':'Invite'))),
  );
  if(awaiting)return Card(child:Padding(padding:const EdgeInsets.all(12),
   child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Text(tt('Your partner invited you to this scrapbook!'),style:const TextStyle(fontWeight:FontWeight.bold)),
    Text(tt('Accept to add your own photos and words to any page.')),
    Wrap(spacing:8,children:[
     OutlinedButton(onPressed:busy?null:()=>_respond(false),child:Text(tt('Decline'))),
     FilledButton(onPressed:busy?null:()=>_respond(true),child:Text(tt('Accept invitation'))),
    ]),
   ])));
  return ListTile(contentPadding:EdgeInsets.zero,leading:Icon(canEdit?Icons.edit_note:Icons.visibility_outlined),
   title:Text(tt(canEdit?'You can contribute':'Shared view')),
   subtitle:Text(tt(canEdit?'Your changes are visible to both of you.':
    'Only invited collaborators can edit scrapbook pages.')));
 }
 Widget _studio(){
  final myId=id;
  if(myId==null||memory==null)return _welcome();
  if(pages.isEmpty)return Center(child:Text(tt('This scrapbook has no pages yet.')));
  final idx=pages.indexWhere((p)=>p['id'].toString()==selectedPageId).clamp(0,pages.length-1);
  final raw=pages[idx];
  final page=_merged(raw);
  WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)_resolveUrls(page);});
  final pics=<String,Map<String,dynamic>>{for(final x in photoRows)x['id'].toString():x};
  final design=ScrapbookTemplates.get(page['template_key']?.toString());
  return ListView(padding:const EdgeInsetsDirectional.fromSTEB(14,10,14,24),children:[
   _collaboration(),
   if(justCreated)Card(elevation:0,color:Theme.of(context).colorScheme.secondaryContainer,child:ListTile(
    leading:const Icon(Icons.touch_app_outlined),
    title:Text(tt('Tap the title on the page to name your scrapbook.')),
    subtitle:Text(tt('Tap any photo spot or text to fill it. Then tap Save.')))),
   const SizedBox(height:6),
   SingleChildScrollView(scrollDirection:Axis.horizontal,child:Row(children:[
    for(var n=0;n<pages.length;n++)Padding(padding:const EdgeInsetsDirectional.only(end:6),
     child:ChoiceChip(
      label:Text(tt('Page ')+(n+1).toString()+((drafts[pages[n]['id'].toString()]?.isNotEmpty??false)?' •':'')),
      selected:idx==n,onSelected:(_)=>setState(()=>selectedPageId=pages[n]['id'].toString()))),
    if(canEdit&&pages.length<30)ActionChip(
     avatar:const Icon(Icons.add,size:18),label:Text(tt('New page')),
     onPressed:busy?null:_addPage),
   ])),
   const SizedBox(height:10),
   Row(children:[
    Expanded(child:Text(tt(design.name)+' · '+(idx+1).toString()+'/'+pages.length.toString(),
     style:Theme.of(context).textTheme.titleMedium)),
    if(canEdit)AnchoredMenuButton<String>(tooltip:tt('Page options'),
     onSelected:(v){if(v=='design'){_changeTemplate(raw);}else if(v=='remove'){_removePage(raw);}},
     itemBuilder:(_)=>[
      iconMenuItem('design',Icons.dashboard_customize_outlined,'Change design'),
      if(pages.length>1)iconMenuItem('remove',MenuIcons.remove,'Remove page'),
     ]),
   ]),
   const SizedBox(height:6),
   Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:430),
    child:ScrapbookPageCanvas(page:page,photos:pics,signedUrls:signed,
     onPhotoTap:canEdit?(n)=>_pickPhoto(raw,n):null,
     onTextTap:canEdit?(f)=>_editText(raw,f):null))),
   const SizedBox(height:10),
   if(canEdit)ExpansionTile(
    title:Text(tt('Photo library & searchable tags')),
    subtitle:Text(tt('People, location, tags and captions')),
    children:[MemoryPhotoGallery(memoryId:myId,editable:canEdit,layout:'grid')]),
   if(busy)const LinearProgressIndicator(),
   if(error!=null)Padding(padding:const EdgeInsets.all(8),
    child:Text(tt(error!),style:TextStyle(color:Theme.of(context).colorScheme.error))),
  ]);
 }
 @override Widget build(BuildContext context)=>PopScope(
  canPop:!dirty,
  onPopInvokedWithResult:(didPop,_)async{
   if(didPop)return;
   if(await _confirmLeave()&&context.mounted)Navigator.of(context).pop();
  },
  child:Scaffold(
   appBar:AppBar(title:Text(tt(id==null?'New scrapbook':(memory?['title']??'Scrapbook').toString()),
    maxLines:1,overflow:TextOverflow.ellipsis),
    actions:[if(id!=null)IconButton(tooltip:tt('View'),onPressed:busy?null:_view,
     icon:const Icon(Icons.visibility_outlined))]),
   body:loading?const Center(child:CircularProgressIndicator()):id==null?_welcome():_studio(),
   bottomNavigationBar:id==null||!canEdit?null:SafeArea(child:Container(
    padding:const EdgeInsetsDirectional.fromSTEB(16,10,16,12),
    decoration:BoxDecoration(color:Theme.of(context).colorScheme.surface,
     border:Border(top:BorderSide(color:Theme.of(context).colorScheme.outlineVariant))),
    child:Row(children:[
     Expanded(child:OutlinedButton.icon(onPressed:busy?null:_view,
      icon:const Icon(Icons.auto_stories_outlined),label:Text(tt('View')))),
     const SizedBox(width:12),
     Expanded(child:FilledButton.icon(onPressed:busy||!dirty?null:_save,
      icon:const Icon(Icons.save_outlined),label:Text(tt(dirty?'Save':'Saved')))),
    ]))),
  ));
}

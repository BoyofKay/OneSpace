import '../../core/item_menu.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'memory_photo_service.dart';
import 'memory_photo_layouts.dart';
import 'memory_photo_layout_rules.dart';
import 'package:onespace/l10n/phrases.dart';

/// A private, RLS-backed gallery. The layout changes presentation only.
class MemoryPhotoGallery extends StatefulWidget{
 const MemoryPhotoGallery({super.key,required this.memoryId,
  required this.editable,required this.layout,this.onLayoutChanged});
 final String memoryId,layout;
 /// R71: when set, the layout choice shows here once there are photos.
 final ValueChanged<String>? onLayoutChanged;
 final bool editable;
 @override State<MemoryPhotoGallery> createState()=>_MemoryPhotoGalleryState();
}
class _MemoryPhotoGalleryState extends State<MemoryPhotoGallery>{
 final db=Supabase.instance.client;
 late MemoryPhotoService service;
 late Stream<List<Map<String,dynamic>>> photos;
 final Map<String,({DateTime issued,Future<String> value})> _urls={};
 bool showRemoved=false,busy=false;
 String? error;
 @override void initState(){
  super.initState();
  service=MemoryPhotoService(db);
  photos=_loadStream();
 }
 Stream<List<Map<String,dynamic>>> _loadStream()=>db.from('memory_photos')
  .stream(primaryKey:['id']).eq('memory_id',widget.memoryId)
  .order('display_order',ascending:true);
 @override void didUpdateWidget(covariant MemoryPhotoGallery oldWidget){
  super.didUpdateWidget(oldWidget);
  if(oldWidget.memoryId!=widget.memoryId){
   _urls.clear();photos=_loadStream();
  }
 }
 Future<String> _sign(String path,{String? bucketId}){
  final key='${bucketId??MemoryPhotoService.bucket}:$path';
  final cached=_urls[key];
  if(cached!=null&&DateTime.now().difference(cached.issued)<const Duration(seconds:65)){
   return cached.value;
  }
  final value=service.signedUrl(path,bucketId:bucketId);
  _urls[key]=(issued:DateTime.now(),value:value);
  return value;
 }
 void _refresh(String path)=>setState(()=>_urls.clear());
 Future<void> _open(Map<String,dynamic> p)async{
  try{
   final url=await service.signedUrl(p['object_path'].toString(),
    bucketId:p['storage_bucket_id']?.toString());
   if(!mounted)return;
   await showDialog<void>(context:context,builder:(ctx)=>Dialog(
    insetPadding:const EdgeInsets.all(12),child:Stack(children:[
     InteractiveViewer(minScale:.8,maxScale:5,
      child:Image.network(url,fit:BoxFit.contain,
       errorBuilder:(_,__,___)=>Padding(
        padding:EdgeInsets.all(20),child:Text(tt('Image unavailable.'))))),
     Positioned(right:4,top:4,child:IconButton(
      icon:const Icon(Icons.close),tooltip:tt('Close'),onPressed:()=>Navigator.pop(ctx))),
    ]),
   ));
  }catch(_){if(mounted)setState(()=>error='Could not open photo. Check your connection and access.');}
 }
 Future<void> add(int currentCount)async{
  if(busy||!widget.editable)return;
  setState((){busy=true;error=null;});
  try{
   final count=await service.addFromGallery(widget.memoryId,startOrder:currentCount);
   if(count>0&&mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content:Text(tt('Added ')+count.toString()+' photo'+(count==1?'':'s')+'.')));
  }on FormatException catch(e){if(mounted)setState(()=>error=e.message);}
  on PostgrestException catch(e){if(mounted)setState(()=>error=e.message);}
  catch(_){if(mounted)setState(()=>error='Some photos could not be added. Check the gallery and retry.');}
  finally{if(mounted)setState(()=>busy=false);}
 }
 Future<void> capture(int currentCount)async{
  if(busy||!widget.editable)return;
  setState((){busy=true;error=null;});
  try{
   final count=await service.addFromCamera(widget.memoryId,startOrder:currentCount);
   if(count>0&&mounted)ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content:Text(tt('Camera photo saved.'))));
  }on FormatException catch(e){if(mounted)setState(()=>error=e.message);}
  on PostgrestException catch(e){if(mounted)setState(()=>error=e.message);}
  catch(_){if(mounted)setState(()=>error='Camera capture could not be saved.');}
  finally{if(mounted)setState(()=>busy=false);}
 }
 Future<void> change(Future<void> Function() work)async{
  if(busy||!widget.editable)return;
  setState((){busy=true;error=null;});
  try{await work();}
  on PostgrestException catch(e){if(mounted)setState(()=>error=e.message);}
  catch(_){if(mounted)setState(()=>error='Could not update the photo.');}
  finally{if(mounted)setState(()=>busy=false);}
 }
 Future<void> editCaption(Map<String,dynamic> p)async{
  var caption=(p['caption']??'').toString();
  final ok=await showDialog<bool>(context:context,
   builder:(ctx)=>AlertDialog(
    title:Text(tt('Photo caption')),
    content:TextFormField(initialValue:caption,maxLength:500,
     minLines:2,maxLines:5,onChanged:(v)=>caption=v,
     decoration:InputDecoration(labelText:tt('A memory in words'))),
    actions:[
     TextButton(onPressed:()=>Navigator.pop(ctx,false),child:Text(tt('Cancel'))),
     FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:Text(tt('Save'))),
    ],
   ));
  if(ok!=true)return;
  await change(()async{
   await db.from('memory_photos').update({'caption':caption.trim()}).eq('id',p['id']);
  });
 }
 Future<void> editTags(Map<String,dynamic> photo)async{
  String people=(photo['people_tags'] as List? ?? const []).join(', ');
  String place=(photo['place_tag']??'').toString();
  String tags=(photo['other_tags'] as List? ?? const []).join(', ');
  final save=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
   title:Text(tt('Photo details & searchable tags')),
   content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
    TextFormField(initialValue:people,maxLength:1200,
     decoration:InputDecoration(labelText:tt('People in photo'),
      helperText:tt('Separate names with commas')),
     onChanged:(v)=>people=v),
    TextFormField(initialValue:place,maxLength:160,
     decoration:InputDecoration(labelText:tt('Where was this taken?')),
     onChanged:(v)=>place=v),
    TextFormField(initialValue:tags,maxLength:1200,
     decoration:InputDecoration(labelText:tt('Other tags'),
      helperText:tt('Places, events, themes — comma separated')),
     onChanged:(v)=>tags=v),
   ])),
   actions:[
    TextButton(onPressed:()=>Navigator.pop(ctx,false),child:Text(tt('Cancel'))),
    FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:Text(tt('Save tags'))),
   ]));
  if(save!=true)return;
  List<String> parse(String value)=>value.split(',')
    .map((v)=>v.trim()).where((v)=>v.isNotEmpty).toSet().toList();
  final peopleList=parse(people),tagList=parse(tags);
  if(peopleList.length>20||tagList.length>30){
   if(mounted)setState(()=>error='Too many tags. Maximum 20 people and 30 other tags.');
   return;
  }
  await change(()async{
   await db.from('memory_photos').update({
    'people_tags':peopleList,'place_tag':place.trim(),'other_tags':tagList,
   }).eq('id',photo['id']);
  });
 }
 Future<void> toggleArchive(Map<String,dynamic> p)async{
  await change(()async{
   await db.from('memory_photos').update({
    'archived_at':p['archived_at']==null?
     DateTime.now().toUtc().toIso8601String():null,
   }).eq('id',p['id']);
   _urls.clear();
  });
 }
 Widget _photo(Map<String,dynamic> p,{double height=165}){
  final path=p['object_path'].toString();
  if(p['archived_at']!=null)return Container(
   height:height,color:Theme.of(context).colorScheme.surfaceContainerHighest,
   child:const Center(child:Icon(Icons.archive_outlined)));
  return InkWell(onTap:()=>_open(p),child:FutureBuilder<String>(
   future:_sign(path,bucketId:p['storage_bucket_id']?.toString()),builder:(ctx,snapshot){
    if(snapshot.hasError)return SizedBox(height:height,child:Center(
     child:TextButton.icon(onPressed:()=>_refresh(path),
      icon:const Icon(Icons.refresh),label:Text(tt('Retry private photo')))));
    if(!snapshot.hasData)return SizedBox(height:height,child:
     const Center(child:CircularProgressIndicator()));
    return ClipRRect(borderRadius:BorderRadius.circular(12),
     child:Image.network(snapshot.data!,height:height,
      width:double.infinity,fit:BoxFit.cover,
      errorBuilder:(_,__,___)=>SizedBox(height:height,child:Center(
       child:TextButton.icon(onPressed:()=>_refresh(path),
        icon:const Icon(Icons.refresh),label:Text(tt('Refresh photo')))))));
   }));
 }
 Widget _layout(List<Map<String,dynamic>> active)=>MemoryPhotoLayout(
  layout:widget.layout,photos:active,photo:(p,h)=>_photo(p,height:h));
 @override Widget build(BuildContext context){
  return StreamBuilder<List<Map<String,dynamic>>>(stream:photos,builder:(ctx,snapshot){
   if(snapshot.hasError)return Text(tt('Unable to load private memory photos.'));
   final rows=List<Map<String,dynamic>>.from(snapshot.data??[]);
   rows.sort((a,b){
    final x=(a['display_order'] as num?)?.toInt()??0;
    final y=(b['display_order'] as num?)?.toInt()??0;
    final byOrder=x.compareTo(y);
    return byOrder!=0?byOrder:a['created_at'].toString().compareTo(b['created_at'].toString());
   });
   final active=rows.where((p)=>p['archived_at']==null).toList();
   return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    const Divider(height:26),
    Row(children:[
     Expanded(child:Text(tt('Photos & scrapbook'),style:Theme.of(context).textTheme.titleLarge)),
     if(widget.editable)IconButton(
      onPressed:busy?null:()=>capture(rows.length),
      icon:const Icon(Icons.photo_camera_outlined),tooltip:tt('Take photo')),
     if(widget.editable)TextButton.icon(onPressed:busy?null:()=>add(rows.length),
      icon:const Icon(Icons.add_photo_alternate_outlined),
      label:Text(tt('Gallery'))),
    ]),
    const SizedBox(height:5),
    if(!snapshot.hasData)const Center(child:CircularProgressIndicator()),
    if(active.isEmpty&&snapshot.hasData)Padding(padding:EdgeInsets.all(8),
     child:Text(tt('Add daily selfies, a favorite memory, or several photos for a collage.'))),
    if(active.isNotEmpty&&widget.onLayoutChanged!=null&&widget.editable)SizedBox(height:44,
     child:ListView(scrollDirection:Axis.horizontal,children:[
      for(final e in MemoryPhotoLayoutRules.names.entries)Padding(
       padding:const EdgeInsetsDirectional.only(end:6),
       child:ChoiceChip(label:Text(tt(e.value)),selected:widget.layout==e.key,
        onSelected:(_)=>widget.onLayoutChanged!(e.key))),
     ])),
    if(active.isNotEmpty)_layout(active),
    if(widget.editable)SwitchListTile(contentPadding:EdgeInsets.zero,
     title:Text(tt('Show removed photos')),value:showRemoved,
     onChanged:(v)=>setState(()=>showRemoved=v)),
    for(final p in rows.where((p)=>showRemoved||p['archived_at']==null))
     ListTile(contentPadding:EdgeInsets.zero,
      leading:Icon(p['archived_at']==null?Icons.photo_outlined:Icons.archive_outlined),
      title:Text(tt((p['caption']??'').toString().isEmpty?'Photo':'Photo · '+p['caption'].toString()),
       maxLines:2,overflow:TextOverflow.ellipsis),
      subtitle:Text(tt([
       p['created_by']==db.auth.currentUser?.id?'Added by you':'Added by partner',
       if((p['people_tags'] as List? ??const []).isNotEmpty)
        'People: '+(p['people_tags'] as List).join(', '),
       if((p['place_tag']??'').toString().isNotEmpty)
        'Place: '+p['place_tag'].toString(),
       if((p['other_tags'] as List? ??const []).isNotEmpty)
        'Tags: '+(p['other_tags'] as List).join(', '),
      ].join(' · '))),
      trailing:widget.editable?PopupMenuButton<String>(
       tooltip:tt('More'),
       onSelected:(v){if(v=='caption'){editCaption(p);}
        else if(v=='tags'){editTags(p);}
        else if(v=='archive'){toggleArchive(p);}},
       itemBuilder:(_)=>[
        iconMenuItem('caption',MenuIcons.edit,'Edit caption'),
        iconMenuItem('tags',Icons.sell_outlined,'People, place & tags'),
        p['archived_at']==null?iconMenuItem('archive',MenuIcons.remove,'Remove')
         :iconMenuItem('archive',MenuIcons.restore,'Restore'),
       ]):null),
    if(busy)const LinearProgressIndicator(),
    if(error!=null)Text(tt(error!),style:TextStyle(color:Theme.of(context).colorScheme.error)),
   ]);
  });
 }
}

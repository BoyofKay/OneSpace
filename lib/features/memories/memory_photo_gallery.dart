import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'memory_photo_service.dart';
import 'memory_photo_layout_rules.dart';

/// A private, RLS-backed gallery. The layout changes presentation only.
class MemoryPhotoGallery extends StatefulWidget{
 const MemoryPhotoGallery({super.key,required this.memoryId,
  required this.editable,required this.layout});
 final String memoryId,layout;
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
 Future<String> _sign(String path){
  final cached=_urls[path];
  if(cached!=null&&DateTime.now().difference(cached.issued)<const Duration(seconds:65)){
   return cached.value;
  }
  final value=service.signedUrl(path);
  _urls[path]=(issued:DateTime.now(),value:value);
  return value;
 }
 void _refresh(String path)=>setState(()=>_urls.remove(path));
 Future<void> _open(Map<String,dynamic> p)async{
  try{
   final url=await service.signedUrl(p['object_path'].toString());
   if(!mounted)return;
   await showDialog<void>(context:context,builder:(ctx)=>Dialog(
    insetPadding:const EdgeInsets.all(12),child:Stack(children:[
     InteractiveViewer(minScale:.8,maxScale:5,
      child:Image.network(url,fit:BoxFit.contain,
       errorBuilder:(_,__,___)=>const Padding(
        padding:EdgeInsets.all(20),child:Text('Image unavailable.')))),
     Positioned(right:4,top:4,child:IconButton(
      icon:const Icon(Icons.close),tooltip:'Close',onPressed:()=>Navigator.pop(ctx))),
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
    content:Text('Added '+count.toString()+' photo'+(count==1?'':'s')+'.')));
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
    const SnackBar(content:Text('Camera photo saved.')));
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
    title:const Text('Photo caption'),
    content:TextFormField(initialValue:caption,maxLength:500,
     minLines:2,maxLines:5,onChanged:(v)=>caption=v,
     decoration:const InputDecoration(labelText:'A memory in words')),
    actions:[
     TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),
     FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Save')),
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
   title:const Text('Photo details & searchable tags'),
   content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
    TextFormField(initialValue:people,maxLength:1200,
     decoration:const InputDecoration(labelText:'People in photo',
      helperText:'Separate names with commas'),
     onChanged:(v)=>people=v),
    TextFormField(initialValue:place,maxLength:160,
     decoration:const InputDecoration(labelText:'Where was this taken?'),
     onChanged:(v)=>place=v),
    TextFormField(initialValue:tags,maxLength:1200,
     decoration:const InputDecoration(labelText:'Other tags',
      helperText:'Places, events, themes — comma separated'),
     onChanged:(v)=>tags=v),
   ])),
   actions:[
    TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),
    FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Save tags')),
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
   _urls.remove(p['object_path']);
  });
 }
 Widget _photo(Map<String,dynamic> p,{double height=165}){
  final path=p['object_path'].toString();
  if(p['archived_at']!=null)return Container(
   height:height,color:Theme.of(context).colorScheme.surfaceContainerHighest,
   child:const Center(child:Icon(Icons.archive_outlined)));
  return InkWell(onTap:()=>_open(p),child:FutureBuilder<String>(
   future:_sign(path),builder:(ctx,snapshot){
    if(snapshot.hasError)return SizedBox(height:height,child:Center(
     child:TextButton.icon(onPressed:()=>_refresh(path),
      icon:const Icon(Icons.refresh),label:const Text('Retry private photo'))));
    if(!snapshot.hasData)return SizedBox(height:height,child:
     const Center(child:CircularProgressIndicator()));
    return ClipRRect(borderRadius:BorderRadius.circular(12),
     child:Image.network(snapshot.data!,height:height,
      width:double.infinity,fit:BoxFit.cover,
      errorBuilder:(_,__,___)=>SizedBox(height:height,child:Center(
       child:TextButton.icon(onPressed:()=>_refresh(path),
        icon:const Icon(Icons.refresh),label:const Text('Refresh photo'))))));
   }));
 }
 Widget _layout(List<Map<String,dynamic>> active){
  if(active.isEmpty)return const SizedBox.shrink();
  final layout=MemoryPhotoLayoutRules.safe(widget.layout);
  if(layout=='feature')return Column(children:[
   _photo(active.first,height:245),
   if(active.length>1)const SizedBox(height:6),
   if(active.length>1)SizedBox(height:110,child:ListView.separated(
    scrollDirection:Axis.horizontal,itemCount:active.length-1,
    separatorBuilder:(_,__)=>const SizedBox(width:7),
    itemBuilder:(ctx,i)=>SizedBox(width:120,child:_photo(active[i+1],height:110)))),
  ]);
  if(layout=='polaroid')return Wrap(spacing:12,runSpacing:12,
   alignment:WrapAlignment.center,children:[
   for(var i=0;i<active.length;i++)Transform.rotate(
    angle:(i.isEven?-1:1)*math.pi/72,
    child:SizedBox(width:160,child:Card(elevation:1,child:Padding(
     padding:const EdgeInsets.fromLTRB(6,6,6,16),
     child:Column(children:[
      _photo(active[i],height:145),
      if((active[i]['caption']??'').toString().isNotEmpty)
       Padding(padding:const EdgeInsets.only(top:5),child:Text(
        active[i]['caption'].toString(),maxLines:2,overflow:TextOverflow.ellipsis)),
     ]))))),
  ]);
  if(layout=='overlap'){
   final visible=active.take(3).toList();
   return SizedBox(height:235,child:LayoutBuilder(builder:(ctx,box){
    final width=math.min(235.0,box.maxWidth*.68);
    final maxLeft=math.max(0.0,box.maxWidth-width);
    return Stack(children:[
     for(var i=0;i<visible.length;i++)Positioned(
      left:maxLeft*(visible.length==1?0.5:i/(visible.length-1)),
      top:i*8.0,width:width,child:Transform.rotate(
       angle:(i-1)*math.pi/90,
       child:Card(elevation:2,child:_photo(visible[i],height:190)))),
    ]);
   }));
  }
  return LayoutBuilder(builder:(ctx,box){
   final two=box.maxWidth>=350;
   final width=two?(box.maxWidth-8)/2:box.maxWidth;
   return Wrap(spacing:8,runSpacing:8,children:[
    for(final p in active)SizedBox(width:width,child:_photo(p,height:175)),
   ]);
  });
 }
 @override Widget build(BuildContext context){
  return StreamBuilder<List<Map<String,dynamic>>>(stream:photos,builder:(ctx,snapshot){
   if(snapshot.hasError)return const Text('Unable to load private memory photos.');
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
     Expanded(child:Text('Photos & scrapbook',style:Theme.of(context).textTheme.titleLarge)),
     if(widget.editable)IconButton(
      onPressed:busy?null:()=>capture(rows.length),
      icon:const Icon(Icons.photo_camera_outlined),tooltip:'Take photo'),
     if(widget.editable)TextButton.icon(onPressed:busy?null:()=>add(rows.length),
      icon:const Icon(Icons.add_photo_alternate_outlined),
      label:const Text('Gallery')),
    ]),
    const SizedBox(height:5),
    if(!snapshot.hasData)const Center(child:CircularProgressIndicator()),
    if(active.isEmpty&&snapshot.hasData)const Padding(padding:EdgeInsets.all(8),
     child:Text('Add daily selfies, a favorite memory, or several photos for a collage.')),
    if(active.isNotEmpty)_layout(active),
    if(widget.editable)SwitchListTile(contentPadding:EdgeInsets.zero,
     title:const Text('Show removed photos'),value:showRemoved,
     onChanged:(v)=>setState(()=>showRemoved=v)),
    for(final p in rows.where((p)=>showRemoved||p['archived_at']==null))
     ListTile(contentPadding:EdgeInsets.zero,
      leading:Icon(p['archived_at']==null?Icons.photo_outlined:Icons.archive_outlined),
      title:Text((p['caption']??'').toString().isEmpty?'Photo':'Photo · '+p['caption'].toString(),
       maxLines:2,overflow:TextOverflow.ellipsis),
      subtitle:Text([
       p['created_by']==db.auth.currentUser?.id?'Added by you':'Added by partner',
       if((p['people_tags'] as List? ??const []).isNotEmpty)
        'People: '+(p['people_tags'] as List).join(', '),
       if((p['place_tag']??'').toString().isNotEmpty)
        'Place: '+p['place_tag'].toString(),
       if((p['other_tags'] as List? ??const []).isNotEmpty)
        'Tags: '+(p['other_tags'] as List).join(', '),
      ].join(' · ')),
      trailing:widget.editable?PopupMenuButton<String>(
       tooltip:'Photo options',
       onSelected:(v){if(v=='caption'){editCaption(p);}
        else if(v=='tags'){editTags(p);}
        else if(v=='archive'){toggleArchive(p);}},
       itemBuilder:(_)=>[
        const PopupMenuItem(value:'caption',child:Text('Edit caption')),
        const PopupMenuItem(value:'tags',child:Text('People, place & tags')),
        PopupMenuItem(value:'archive',child:Text(p['archived_at']==null?'Remove':'Restore')),
       ]):null),
    if(busy)const LinearProgressIndicator(),
    if(error!=null)Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
   ]);
  });
 }
}

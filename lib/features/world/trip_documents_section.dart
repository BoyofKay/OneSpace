import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import 'trip_document_rules.dart';

const tripDocumentKinds=<String,String>{
 'boarding_pass':'Boarding pass',
 'itinerary':'Itinerary',
 'ticket':'Ticket',
 'receipt':'Receipt',
 'photo':'Photo / scan',
 'other':'Other document',
};

class _PickedTravelFile {
 const _PickedTravelFile(this.filename,this.bytes,this.mime);
 final String filename,mime;
 final Uint8List bytes;
}

class TravelDocumentService {
 TravelDocumentService(this.db);
 final SupabaseClient db;
 static const picker=MethodChannel('onespace/travel_documents');

 Future<_PickedTravelFile?> pick() async{
  final result=await picker.invokeMethod<Map<dynamic,dynamic>>('pickDocument');
  if(result==null)return null;
  final data=result['bytes'];
  if(data is! Uint8List){
   throw const FormatException('Unable to read this document. Choose another file.');
  }
  final mime=TripDocumentRules.validatedMime(data);
  return _PickedTravelFile(
   TripDocumentRules.safeFileName((result['name']??'Travel document').toString()),
   data,mime);
 }

 Future<void> upload({
  required String tripId,required _PickedTravelFile file,
  required String title,required String kind,String? itineraryItemId,
 }) async{
  final user=db.auth.currentUser?.id;
  if(user==null)throw StateError('Sign in to add a document.');
  final objectPath=TripDocumentRules.path(
    tripId:tripId,userId:user,documentId:const Uuid().v4(),mime:file.mime);
  final bucket=db.storage.from(TripDocumentRules.bucket);
  await bucket.uploadBinary(objectPath,file.bytes,
    fileOptions:FileOptions(contentType:file.mime,upsert:false));
  try{
   await db.from('trip_attachments').insert({
    'trip_id':tripId,'item_id':itineraryItemId,
    'title':TripDocumentRules.safeTitle(title),
    'kind':kind,'file_name':file.filename,
    'mime_type':file.mime,'file_size':file.bytes.length,
    'object_path':objectPath,
   });
  }catch(_){
   // The RLS delete policy only allows removing own unreferenced uploads;
   // a referenced document can never be removed by this rollback.
   try{await bucket.remove([objectPath]);}catch(_){}
   rethrow;
  }
 }

 Future<String> privateUrl(String objectPath) =>
   db.storage.from(TripDocumentRules.bucket).createSignedUrl(objectPath,90);
}

class TripDocumentsSection extends StatefulWidget{
 const TripDocumentsSection({super.key,required this.tripId,
  this.itineraryItems=const []});
 final String tripId;
 final List<Map<String,dynamic>> itineraryItems;
 @override State<TripDocumentsSection> createState()=>_TripDocumentsSectionState();
}
class _TripDocumentsSectionState extends State<TripDocumentsSection>{
 final db=Supabase.instance.client;
 late final TravelDocumentService service;
 late Stream<List<Map<String,dynamic>>> changes;
 bool showArchived=false,busy=false;
 String? error;

 @override void initState(){
  super.initState();
  service=TravelDocumentService(db);
  changes=db.from('trip_attachments').stream(primaryKey:['id'])
    .eq('trip_id',widget.tripId).order('created_at',ascending:false);
 }
 @override void didUpdateWidget(covariant TripDocumentsSection oldWidget){
  super.didUpdateWidget(oldWidget);
  if(oldWidget.tripId!=widget.tripId){
   changes=db.from('trip_attachments').stream(primaryKey:['id'])
     .eq('trip_id',widget.tripId).order('created_at',ascending:false);
  }
 }

 Future<void> add() async{
  if(busy)return;
  setState((){busy=true;error=null;});
  try{
   final chosen=await service.pick();
   if(chosen==null)return;
   if(!mounted)return;
   var title=TripDocumentRules.safeTitle(chosen.filename);
   var kind=chosen.mime=='application/pdf'?'itinerary':'photo';
   var location='whole_trip';
   final accepted=await showDialog<bool>(context:context,
     builder:(ctx)=>StatefulBuilder(builder:(ctx,update)=>AlertDialog(
      title:const Text('Attach travel document'),
      content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
       Text(chosen.filename,style:Theme.of(ctx).textTheme.bodySmall),
       const SizedBox(height:12),
       TextField(controller:title,maxLength:160,
        decoration:const InputDecoration(labelText:'Document title')),
       DropdownButtonFormField<String>(initialValue:kind,
        decoration:const InputDecoration(labelText:'Type'),
        items:[for(final e in tripDocumentKinds.entries)
         DropdownMenuItem(value:e.key,child:Text(e.value))],
        onChanged:(v)=>update(()=>kind=v??kind)),
       const SizedBox(height:12),
       DropdownButtonFormField<String>(initialValue:location,
        decoration:const InputDecoration(labelText:'Attach to'),
        items:[
         const DropdownMenuItem(value:'whole_trip',child:Text('Whole trip')),
         for(final item in widget.itineraryItems.where((item)=>item['archived_at']==null))
          DropdownMenuItem(value:item['id'].toString(),
            child:Text(item['title'].toString(),overflow:TextOverflow.ellipsis)),
        ],
        onChanged:(v)=>update(()=>location=v??location)),
       const SizedBox(height:8),
       Text('Private file · Maximum 10 MB',style:Theme.of(ctx).textTheme.bodySmall),
      ])),
      actions:[
       TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),
       FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Upload')),
      ],
     )));
    if(accepted!=true)return;
    if(title.trim().isEmpty){
     if(mounted)setState(()=>error='Document title cannot be empty.');
     return;
    }
    await service.upload(tripId:widget.tripId,file:chosen,title:title.trim(),
      kind:kind,itineraryItemId:location=='whole_trip'?null:location);
    if(mounted)ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content:Text('Travel document added securely.')));
  }on PlatformException catch(e){
   if(mounted)setState(()=>error=e.message??'Document picker is unavailable.');
  }on FormatException catch(e){
   if(mounted)setState(()=>error=e.message);
  }on PostgrestException catch(e){
   if(mounted)setState(()=>error=e.message);
  }catch(_){
   if(mounted)setState(()=>error='Unable to attach the document. Try again.');
  }finally{if(mounted)setState(()=>busy=false);}
 }

 Future<void> edit(Map<String,dynamic> doc)async{
  if(busy)return;
  var title=doc['title'].toString();
  var kind=doc['kind'].toString();
  var location=doc['item_id']?.toString()??'whole_trip';
  if(location!='whole_trip'&&!widget.itineraryItems.any((e)=>e['id']==location)){
   location='whole_trip';
  }
  final accepted=await showDialog<bool>(context:context,
    builder:(ctx)=>StatefulBuilder(builder:(ctx,update)=>AlertDialog(
     title:const Text('Edit document details'),
     content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
      TextFormField(initialValue:title,maxLength:160,onChanged:(v)=>title=v,
       decoration:const InputDecoration(labelText:'Title')),
      DropdownButtonFormField<String>(initialValue:kind,
       decoration:const InputDecoration(labelText:'Type'),
       items:[for(final e in tripDocumentKinds.entries)
        DropdownMenuItem(value:e.key,child:Text(e.value))],
       onChanged:(v)=>update(()=>kind=v??kind)),
      DropdownButtonFormField<String>(initialValue:location,
       decoration:const InputDecoration(labelText:'Attached to'),
       items:[
        const DropdownMenuItem(value:'whole_trip',child:Text('Whole trip')),
        for(final item in widget.itineraryItems)
         DropdownMenuItem(value:item['id'].toString(),child:Text(
          item['title'].toString(),overflow:TextOverflow.ellipsis)),
       ],
       onChanged:(v)=>update(()=>location=v??location)),
     ])),
     actions:[
      TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),
      FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Save')),
     ],
    )));
   if(accepted!=true||title.trim().isEmpty)return;
   await change(()async{
    await db.from('trip_attachments').update({
     'title':title.trim(),'kind':kind,
     'item_id':location=='whole_trip'?null:location,
    }).eq('id',doc['id']);
   });
 }

 Future<void> change(Future<void> Function() action)async{
  if(busy)return;
  setState((){busy=true;error=null;});
  try{await action();}
  on PostgrestException catch(e){if(mounted)setState(()=>error=e.message);}
  catch(_){if(mounted)setState(()=>error='Could not save document change.');}
  finally{if(mounted)setState(()=>busy=false);}
 }

 Future<void> toggleArchive(Map<String,dynamic> doc)async{
  final isArchived=doc['archived_at']!=null;
  await change(()async{
   await db.from('trip_attachments').update({
    'archived_at':isArchived?null:DateTime.now().toUtc().toIso8601String(),
   }).eq('id',doc['id']);
  });
 }

 Future<void> view(Map<String,dynamic> doc)async{
  if(busy)return;
  setState(()=>error=null);
  try{
   final url=await service.privateUrl(doc['object_path'].toString());
   if(!mounted)return;
   if(doc['mime_type']=='application/pdf'){
    final opened=await launchUrl(Uri.parse(url),mode:LaunchMode.externalApplication);
    if(!opened)throw StateError('Unable to open PDF');
   }else{
    await showDialog<void>(context:context,builder:(ctx)=>Dialog(
     insetPadding:const EdgeInsets.all(12),
     child:Stack(children:[
      InteractiveViewer(minScale:0.8,maxScale:5,child:Image.network(url,
       fit:BoxFit.contain,errorBuilder:(context,error,stack)=>
        const Padding(padding:EdgeInsets.all(24),child:Text('Image unavailable.')))),
      Positioned(top:0,right:0,child:IconButton(
       tooltip:'Close',icon:const Icon(Icons.close),
       onPressed:()=>Navigator.pop(ctx))),
     ]),
    ));
   }
  }catch(_){
   if(mounted)setState(()=>error='Could not open private document. Try again.');
  }
 }

 String attachedTo(Map<String,dynamic> doc){
  final id=doc['item_id']?.toString();
  if(id==null)return 'Whole trip';
  final match=widget.itineraryItems.where((item)=>item['id']==id).firstOrNull;
  return match==null?'Itinerary item':match['title'].toString();
 }

 @override Widget build(BuildContext context){
  return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
   Row(children:[
    Expanded(child:Text('Travel documents',style:Theme.of(context).textTheme.titleLarge)),
    TextButton.icon(onPressed:busy?null:add,icon:const Icon(Icons.attach_file),
     label:const Text('Attach')),
   ]),
   const Text('Boarding passes, tickets, travel PDFs and photo scans. Files stay private to people who can view this trip.'),
   const SizedBox(height:8),
   SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('Show archived documents'),
    value:showArchived,onChanged:(v)=>setState(()=>showArchived=v)),
   if(error!=null)Padding(padding:const EdgeInsets.all(6),
    child:Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error))),
   if(busy)const LinearProgressIndicator(),
   StreamBuilder<List<Map<String,dynamic>>>(stream:changes,builder:(ctx,snapshot){
    if(snapshot.hasError)return const Text('Documents unavailable. Check your connection.');
    if(!snapshot.hasData)return const Center(child:CircularProgressIndicator());
    final visible=snapshot.data!.where(
     (r)=>showArchived||r['archived_at']==null).toList();
    if(visible.isEmpty)return const Card(child:Padding(
     padding:EdgeInsets.all(16),
     child:Text('No travel documents here yet. Attach a PDF or an image.')));
    return Column(children:[
     for(final doc in visible)Card(elevation:0,child:ListTile(
      leading:Icon(doc['mime_type']=='application/pdf'?
       Icons.picture_as_pdf_outlined:Icons.image_outlined),
      title:Text(doc['title'].toString(),maxLines:2),
      subtitle:Text([
       tripDocumentKinds[doc['kind']]??'Document',
       attachedTo(doc),
       if(doc['archived_at']!=null)'Archived',
       if(doc['file_size'] is num)
        ((doc['file_size'] as num)/1024).toStringAsFixed(0)+' KB',
      ].join(' · '),maxLines:3),
      onTap:doc['archived_at']!=null?null:()=>view(doc),
      trailing:PopupMenuButton<String>(
       tooltip:'Document options',
       onSelected:(choice){
        if(choice=='edit'){edit(doc);}
        else if(choice=='archive'){toggleArchive(doc);}
       },
       itemBuilder:(_)=>[
        const PopupMenuItem(value:'edit',child:Text('Edit details')),
        PopupMenuItem(value:'archive',child:Text(
         doc['archived_at']!=null?'Restore':'Archive')),
       ],
      ),
     )),
    ]);
   }),
  ]);
 }
}

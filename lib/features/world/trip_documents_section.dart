import '../../core/item_menu.dart';
import '../../core/form_kit.dart';
import '../../core/editor_scaffold.dart';
import '../../core/app_env.dart';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import 'trip_document_rules.dart';
import 'package:onespace/l10n/phrases.dart';

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
  // Revalidate immediately before each upload, not just when the screen opens.
  var selectedBucket=TripDocumentRules.bucket;
  if(!OneSpaceEnv.usesLegacyBackend){
    final trip=await db.from('shared_trips')
      .select('space_id,private_space_id,created_by,visibility')
      .eq('id',tripId).maybeSingle();
    final scopes=await db.rpc('my_storage_scopes');
    if(trip==null||scopes is! Map||
       scopes['private_space_id']?.toString()!=user){
      throw StateError('Travel document scope is unavailable.');
    }
    if(trip['private_space_id']!=null){
      if(trip['private_space_id']!=user||trip['created_by']!=user||
         trip['space_id']!=null||trip['visibility']!='private'){
        throw StateError('Personal trip documents belong only to the owner.');
      }
      selectedBucket='onespace-private-trip-documents';
    }else if(trip['visibility']!='shared'||trip['space_id']==null||
        scopes['shared_space_id']?.toString()!=trip['space_id']?.toString()){
      throw StateError('Shared travel documents require a current paired space.');
    }
  }
  final objectPath=TripDocumentRules.path(
    tripId:tripId,userId:user,documentId:const Uuid().v4(),mime:file.mime);
  final bucket=db.storage.from(selectedBucket);
  await bucket.uploadBinary(objectPath,file.bytes,
    fileOptions:FileOptions(contentType:file.mime,upsert:false));
  try{
   await db.from('trip_attachments').insert({
    'trip_id':tripId,'item_id':itineraryItemId,
    'title':TripDocumentRules.safeTitle(title),
    'kind':kind,'file_name':file.filename,
    'mime_type':file.mime,'file_size':file.bytes.length,
    'object_path':objectPath,
    if(!OneSpaceEnv.usesLegacyBackend)'storage_bucket_id':selectedBucket,
   });
  }catch(_){
   // The RLS delete policy only allows removing own unreferenced uploads;
   // a referenced document can never be removed by this rollback.
   try{await bucket.remove([objectPath]);}catch(_){}
   rethrow;
  }
 }

 Future<String> privateUrl(String objectPath,{String? bucketId}) =>
   db.storage.from(bucketId??TripDocumentRules.bucket).createSignedUrl(objectPath,90);
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
 bool showArchived=false,collapsed=false,busy=false;
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
   final accepted=await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(fullscreenDialog:true,builder:(ctx)=>StatefulBuilder(builder:(ctx,update)=>EditorPage(
      title:Text(tt('Attach travel document')),
      content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
       Text(tt(chosen.filename),style:Theme.of(ctx).textTheme.bodySmall),
       const SizedBox(height:12),
       TextFormField(initialValue:title,maxLength:160,
        onChanged:(value)=>title=value,
        decoration:InputDecoration(labelText:tt('Title *'),border:OutlineInputBorder())),
       const SizedBox(height:10),
       ChoiceRow<String>(label:tt('Type'),options:tripDocumentKinds,selected:kind,icons:const {'boarding_pass':Icons.airplane_ticket_outlined,'itinerary':Icons.route_outlined,'ticket':Icons.confirmation_number_outlined,'receipt':Icons.receipt_long_outlined,'photo':Icons.photo_camera_outlined,'other':Icons.description_outlined},
        onSelected:(v)=>update(()=>kind=v??kind)),
       ChoicePickerField<String>(label:tt('Belongs to'),icon:Icons.luggage_outlined,
        options:{'whole_trip':'The whole trip',
         for(final item in widget.itineraryItems.where((item)=>item['archived_at']==null))
          item['id'].toString():item['title'].toString()},
        selected:location,onSelected:(v)=>update(()=>location=v??location)),
       const SizedBox(height:8),
       Text(tt('Private file · Maximum 10 MB'),style:Theme.of(ctx).textTheme.bodySmall),
      ])),
      actions:[
       TextButton(onPressed:()=>Navigator.pop(ctx,false),child:Text(tt('Cancel'))),
       FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:Text(tt('Upload'))),
      ],
     ))));
    if(accepted!=true)return;
    if(title.trim().isEmpty){
     if(mounted)setState(()=>error='Document title cannot be empty.');
     return;
    }
    await service.upload(tripId:widget.tripId,file:chosen,title:title.trim(),
      kind:kind,itineraryItemId:location=='whole_trip'?null:location);
    if(mounted)ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content:Text(tt('Travel document added securely.'))));
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
  final accepted=await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(fullscreenDialog:true,builder:(ctx)=>StatefulBuilder(builder:(ctx,update)=>EditorPage(
     title:Text(tt('Edit document')),
     content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
      TextFormField(initialValue:title,maxLength:160,onChanged:(v)=>title=v,
       decoration:InputDecoration(labelText:tt('Title *'),border:OutlineInputBorder())),
      const SizedBox(height:10),
      ChoiceRow<String>(label:tt('Type'),options:tripDocumentKinds,selected:kind,icons:const {'boarding_pass':Icons.airplane_ticket_outlined,'itinerary':Icons.route_outlined,'ticket':Icons.confirmation_number_outlined,'receipt':Icons.receipt_long_outlined,'photo':Icons.photo_camera_outlined,'other':Icons.description_outlined},
       onSelected:(v)=>update(()=>kind=v??kind)),
      ChoicePickerField<String>(label:tt('Belongs to'),icon:Icons.luggage_outlined,
       options:{'whole_trip':'The whole trip',
        for(final item in widget.itineraryItems)item['id'].toString():item['title'].toString()},
       selected:location,onSelected:(v)=>update(()=>location=v??location)),
     ])),
     actions:[
      TextButton(onPressed:()=>Navigator.pop(ctx,false),child:Text(tt('Cancel'))),
      FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:Text(tt('Save'))),
     ],
    ))));
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
   final url=await service.privateUrl(doc['object_path'].toString(),
     bucketId:doc['storage_bucket_id']?.toString());
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
        Padding(padding:EdgeInsets.all(24),child:Text(tt('Image unavailable.'))))),
      Positioned(top:0,right:0,child:IconButton(
       tooltip:tt('Close'),icon:const Icon(Icons.close),
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
  final scheme=Theme.of(context).colorScheme;
  // R67: documents are the most important part of a trip, so they sit in
  // their own tinted card near the top, with Attach as the main button.
  return Card(elevation:0,color:scheme.secondaryContainer.withValues(alpha:.55),
   shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(18),
    side:BorderSide(color:scheme.secondary.withValues(alpha:.35))),
   child:Padding(padding:const EdgeInsets.fromLTRB(14,12,14,12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
   // Header on one line; tapping it folds the card.
   InkWell(borderRadius:BorderRadius.circular(12),
    onTap:()=>setState(()=>collapsed=!collapsed),
    child:Padding(padding:const EdgeInsets.symmetric(vertical:4),child:Row(children:[
     Icon(Icons.folder_special_outlined,color:scheme.secondary),
     const SizedBox(width:8),
     Expanded(child:Text(tt('Travel documents'),style:Theme.of(context).textTheme.titleLarge)),
     Icon(collapsed?Icons.expand_more:Icons.expand_less,
      semanticLabel:tt(collapsed?'Show travel documents':'Hide travel documents')),
    ]))),
   if(!collapsed)...[
   Text(tt('Boarding passes, tickets, visas and bookings. Only people who can see this trip can open them.'),
    style:Theme.of(context).textTheme.bodySmall),
   const SizedBox(height:8),
   if(error!=null)Padding(padding:const EdgeInsets.all(6),
    child:Text(tt(error!),style:TextStyle(color:Theme.of(context).colorScheme.error))),
   if(busy)const LinearProgressIndicator(),
   StreamBuilder<List<Map<String,dynamic>>>(stream:changes,builder:(ctx,snapshot){
    if(snapshot.hasError)return Text(tt('Documents unavailable. Check your connection.'));
    if(!snapshot.hasData)return const Center(child:CircularProgressIndicator());
    final visible=snapshot.data!.where(
     (r)=>showArchived||r['archived_at']==null).toList();
    if(visible.isEmpty)return Padding(
     padding:const EdgeInsets.symmetric(vertical:10),
     child:Text(tt('No travel documents yet. Attach a PDF or a photo.')));
    return Column(children:[
     for(final doc in visible)Card(elevation:0,margin:const EdgeInsets.only(bottom:6),child:ListTile(
      leading:CircleAvatar(backgroundColor:scheme.surface,child:Icon(doc['mime_type']=='application/pdf'?
       Icons.picture_as_pdf_outlined:Icons.image_outlined,color:scheme.secondary)),
      title:Text(tt(doc['title'].toString()),maxLines:2),
      subtitle:Text(tt([
       tripDocumentKinds[doc['kind']]??'Document',
       attachedTo(doc),
       if(doc['archived_at']!=null)'Removed',
      ].join(' · ')),maxLines:2),
      onTap:doc['archived_at']!=null?null:()=>view(doc),
      trailing:AnchoredMenuButton<String>(
       tooltip:tt('More'),
       onSelected:(choice){
        if(choice=='edit'){edit(doc);}
        else if(choice=='archive'){toggleArchive(doc);}
       },
       itemBuilder:(_)=>[
        iconMenuItem('edit',MenuIcons.edit,'Edit'),
        doc['archived_at']!=null?iconMenuItem('archive',MenuIcons.restore,'Restore')
         :iconMenuItem('archive',MenuIcons.remove,'Remove'),
       ],
      ),
     )),
    ]);
   }),
   const SizedBox(height:4),
   // Actions sit at the end of the card.
   Row(children:[
    TextButton.icon(
     onPressed:()=>setState(()=>showArchived=!showArchived),
     icon:Icon(showArchived?Icons.delete:Icons.delete_outline),
     label:Text(tt(showArchived?'Hide removed':'Show removed'))),
    const Spacer(),
    FilledButton.tonalIcon(onPressed:busy?null:add,icon:const Icon(Icons.attach_file),
     label:Text(tt('Attach'))),
   ]),
   ],
  ])));
 }
}

import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../coordinate/activity_image_rules.dart';
import 'package:onespace/l10n/phrases.dart';

/// Private, RLS-enforced photo attachments for a saved note.
class NotePhotosPanel extends StatefulWidget{
 const NotePhotosPanel({super.key,required this.noteId,required this.canEdit});
 final String noteId;
 final bool canEdit;
 @override State<NotePhotosPanel> createState()=>_NotePhotosPanelState();
}
class _NotePhotosPanelState extends State<NotePhotosPanel>{
 final db=Supabase.instance.client;
 static const bucket='onespace-note-images';
 late Stream<List<Map<String,dynamic>>> stream;
 bool busy=false;
 String? error;
 @override void initState(){super.initState();_listen();}
 void _listen(){
  stream=db.from('note_images').stream(primaryKey:['id'])
   .eq('note_id',widget.noteId).order('created_at').limit(100);
 }
 @override void didUpdateWidget(covariant NotePhotosPanel old){
  super.didUpdateWidget(old);
  if(old.noteId!=widget.noteId)_listen();
 }
 Future<void> add()async{
  if(busy||!widget.canEdit)return;
  setState((){busy=true;error=null;});
  try{
   final file=await ImagePicker().pickImage(source:ImageSource.gallery,
    imageQuality:82,maxWidth:1600,maxHeight:1600);
   if(file==null)return;
   final bytes=await file.readAsBytes();
   ActivityImageRules.validate(bytes);
   final mime=ActivityImageRules.mimeType(bytes)!;
   final uid=db.auth.currentUser?.id;
   if(uid==null)throw StateError('Sign in first.');
   final path=widget.noteId+'/'+uid+'/'+const Uuid().v4()+'.'+
    ActivityImageRules.extension(mime);
   final storage=db.storage.from(bucket);
   await storage.uploadBinary(path,bytes,
    fileOptions:FileOptions(contentType:mime,upsert:false));
   try{
    await db.from('note_images').insert({
     'note_id':widget.noteId,'object_path':path,'caption':''});
   }catch(_){
    try{await storage.remove([path]);}catch(_){}
    rethrow;
   }
  }on PostgrestException catch(e){
   if(mounted)setState(()=>error=e.message);
  }catch(_){
   if(mounted)setState(()=>error='Could not attach image. Please retry.');
  }finally{if(mounted)setState(()=>busy=false);}
 }
 Future<void> archive(String id)async{
  if(!widget.canEdit||busy)return;
  try{
   await db.from('note_images').update({
    'archived_at':DateTime.now().toUtc().toIso8601String()}).eq('id',id);
  }catch(_){
   if(mounted)setState(()=>error='Could not remove photo.');
  }
 }
 @override Widget build(BuildContext context){
  final theme=Theme.of(context);
  return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
   Row(children:[
    Icon(Icons.photo_library_outlined,color:theme.colorScheme.primary),
    const SizedBox(width:8),
    Expanded(child:Text(tt('Photos in this note'),style:theme.textTheme.titleMedium)),
    if(widget.canEdit)TextButton.icon(onPressed:busy?null:add,
     icon:const Icon(Icons.add_photo_alternate_outlined),
     label:Text(tt('Add photo'))),
   ]),
   if(busy)const LinearProgressIndicator(),
   if(error!=null)Text(tt(error!),style:TextStyle(color:theme.colorScheme.error)),
   StreamBuilder<List<Map<String,dynamic>>>(stream:stream,builder:(ctx,snapshot){
    if(snapshot.hasError)return Text(tt('Photos cannot be loaded.'));
    if(!snapshot.hasData)return const LinearProgressIndicator();
    final rows=snapshot.data!.where((x)=>x['archived_at']==null).toList();
    if(rows.isEmpty)return Text(tt('No photos attached yet.'));
    return Wrap(spacing:8,runSpacing:8,children:[
     for(final row in rows)SizedBox(width:160,child:Card(clipBehavior:Clip.antiAlias,
      child:Column(children:[
       FutureBuilder<String>(
        future:db.storage.from(bucket).createSignedUrl(row['object_path'].toString(),90),
        builder:(ctx,image)=>SizedBox(height:128,width:160,
         child:image.hasData?Image.network(image.data!,
          fit:BoxFit.cover,errorBuilder:(_,__,___)=>
           const Icon(Icons.broken_image_outlined)):
          const Center(child:CircularProgressIndicator()))),
       if(widget.canEdit)IconButton(tooltip:tt('Remove attached photo'),
        onPressed:()=>archive(row['id'].toString()),
        icon:const Icon(Icons.delete_outline)),
      ]))),
    ]);
   }),
  ]);
 }
}

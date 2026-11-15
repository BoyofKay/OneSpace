import '../../core/form_kit.dart';
import '../../core/editor_scaffold.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../sharing/object_permissions.dart';
import '../sharing/share_grant_watcher.dart';
import 'note_draft_rules.dart';
import 'note_photos_panel.dart';
import 'note_references_panel.dart';
import '../mentions/rich_note_mention_button.dart';
import 'dart:async';

/// OneSpace Notes 2.0: real rich-text editing, native selection/copy/paste,
/// lists, headings, links and basic formatting, not markdown-in-text fields.
class QuillNoteEditorScreen extends StatefulWidget {
 const QuillNoteEditorScreen({super.key,required this.spaceId,this.existing,this.initialTitle='',this.initialBody=''});
 final String spaceId;
 /// R60: pre-filled by voice ("take a note …").
 final String initialTitle,initialBody;
 final Map<String,dynamic>? existing;
 @override State<QuillNoteEditorScreen> createState()=>_QuillNoteEditorState();
}
class _QuillNoteEditorState extends State<QuillNoteEditorScreen> with FormChangeTracker<QuillNoteEditorScreen>{
 /// R55: current form values; Save turns on only when they change.
 @override String get signature=>[title.text,editor.document.toDelta().toJson().toString(),visibility,pinned].join('|');

 final db=Supabase.instance.client;
 late final TextEditingController title;
 late final quill.QuillController editor;
 late String visibility;
 late bool pinned;
 bool busy=false;
 String? error;
 StreamSubscription<List<Map<String,dynamic>>>? revocationWatcher;
 bool get editing=>widget.existing!=null;
 bool get archived=>widget.existing?['archived_at']!=null;
 bool get canEdit=>widget.existing==null||ObjectPermissions.canEdit(
  visibility:widget.existing!['visibility'].toString(),
  createdBy:widget.existing!['created_by'].toString(),
  userId:db.auth.currentUser?.id??'');
 @override void initState(){
  super.initState();
  final old=widget.existing;
  title=TextEditingController(text:(old?['title']??widget.initialTitle).toString());
  final raw=old?['rich_delta'];
  quill.Document document;
  if(raw is List){
   try{document=quill.Document.fromJson(
    raw.map((x)=>Map<String,dynamic>.from(x as Map)).toList());}
   catch(_){document=_fromPlain((old?['body']??'').toString());}
  }else{
   document=_fromPlain((old?['body']??widget.initialBody).toString());
  }
  editor=quill.QuillController(document:document,
   selection:const TextSelection.collapsed(offset:0));
  editor.readOnly=!canEdit||archived;
  visibility=(old?['visibility']??'shared').toString();
  pinned=old?['pinned']==true;
  if(editing&&!canEdit){
   revocationWatcher=watchObjectShares(client:db,spaceId:widget.spaceId,
    objectType:'note',onChanged:()async{
     try{
      final result=await db.from('notes').select('id')
       .eq('id',widget.existing!['id']).limit(1);
      if(mounted&&result.isEmpty)Navigator.of(context).pop();
     }catch(_){}
    });
  }
 }
 quill.Document _fromPlain(String value)=>
  quill.Document.fromJson([{'insert':value.endsWith('\n')?value:value+'\n'}]);
 @override void dispose(){
  revocationWatcher?.cancel();title.dispose();editor.dispose();super.dispose();
 }
 Future<void> save()async{
  if(!canEdit||archived||busy)return;
  final name=title.text.trim();
  final plain=editor.document.toPlainText().trim();
  if(!NoteDraftRules.isValid(title:name,body:plain)){
   setState(()=>error='Add a title and keep the note within 30,000 characters.');
   return;
  }
  final delta=editor.document.toDelta().toJson();
  // Protect backend from exceptionally large formatted payloads.
  if(delta.toString().length>120000){
   setState(()=>error='This document is too large. Shorten it or split into two notes.');
   return;
  }
  setState((){busy=true;error=null;});
  final fields=<String,dynamic>{
   'title':name,'body':plain,'rich_delta':delta,'pinned':pinned,
  };
  try{
   if(!editing){
    await db.from('notes').insert({
     ...fields,'space_id':widget.spaceId,
     'visibility':visibility,'created_by':db.auth.currentUser!.id,
    });
   }else{
    final old=widget.existing!;
    final result=await db.from('notes').update(fields)
     .eq('id',old['id']).eq('space_id',widget.spaceId)
     .eq('updated_at',old['updated_at']).select('id');
    if(result.isEmpty){
     if(mounted)setState(()=>error='This note was updated elsewhere. Reopen it to avoid overwriting your partner’s work.');
     return;
    }
   }
   if(mounted)Navigator.of(context).pop();
  }on PostgrestException catch(e){
   if(mounted)setState(()=>error=e.message);
  }catch(_){
   if(mounted)setState(()=>error='Could not save your note.');
  }finally{if(mounted)setState(()=>busy=false);}
 }
 Future<void> archive()async{
  if(!editing||!canEdit||busy)return;
  final old=widget.existing!;
  final archived=old['archived_at']!=null;
  setState(()=>busy=true);
  try{
   final result=await db.from('notes').update({
    'archived_at':archived?null:DateTime.now().toUtc().toIso8601String()
   }).eq('id',old['id']).eq('updated_at',old['updated_at']).select('id');
   if(result.isEmpty){if(mounted)setState(()=>error='Note changed on another device. Reopen it.');return;}
   if(mounted)Navigator.pop(context);
  }on PostgrestException catch(e){if(mounted)setState(()=>error=e.message);}
  finally{if(mounted)setState(()=>busy=false);}
 }
 @override Widget build(BuildContext context){
  final isEditingAllowed=canEdit&&!archived;
  return EditorScaffold(title:editing?'Edit note':'Add note',
   isNew:!editing,isChanged:()=>changed,isComplete:()=>isEditingAllowed&&title.text.trim().isNotEmpty,
   listenTo:[title,editor],saving:busy,onSave:save,
   meta:MetaStrip(value:MetaValues(shared:visibility=='shared'),showBelongs:false,showDate:false,
     enabled:!editing&&!busy,onChanged:(v)=>setState(()=>visibility=v.shared?'shared':'private')),
   body:SafeArea(child:ListView(
    padding:const EdgeInsets.fromLTRB(16,14,16,36),children:[
     if(!isEditingAllowed)const Text('Read-only note',
      style:TextStyle(fontWeight:FontWeight.bold)),
     TextField(controller:title,maxLength:120,autofocus:!editing,
      readOnly:!isEditingAllowed,textCapitalization:TextCapitalization.sentences,
      decoration:const InputDecoration(labelText:'Title *',
       border:OutlineInputBorder())),
     const SizedBox(height:10),
     if(isEditingAllowed)...[
      if(visibility=='shared')Align(
       alignment:Alignment.centerLeft,
       child:RichNoteMentionButton(
        spaceId:widget.spaceId,controller:editor)),
      quill.QuillSimpleToolbar(
       controller:editor,
       config:const quill.QuillSimpleToolbarConfig()),
     ],
     const SizedBox(height:8),
     Container(
      padding:const EdgeInsets.all(12),
      decoration:BoxDecoration(border:Border.all(
       color:Theme.of(context).colorScheme.outlineVariant),
       borderRadius:BorderRadius.circular(12)),
      child:SizedBox(height:MediaQuery.sizeOf(context).height*.42,
       child:quill.QuillEditor.basic(
        controller:editor,config:const quill.QuillEditorConfig())),
     ),
     const SizedBox(height:12),
     if(editing)...[
      NotePhotosPanel(
       noteId:widget.existing!['id'].toString(),canEdit:isEditingAllowed),
      const SizedBox(height:12),
      NoteReferencesPanel(
       noteId:widget.existing!['id'].toString(),
       spaceId:widget.spaceId,
       noteVisibility:visibility,
       canEdit:isEditingAllowed),
     ]else Text('Save the note first, then add photos and links.',
      style:Theme.of(context).textTheme.bodySmall),
     const SizedBox(height:10),
     Align(alignment:Alignment.centerLeft,child:OptionChip(label:'Pin to the top',
      icon:Icons.push_pin_outlined,value:pinned,
      onChanged:isEditingAllowed?(v)=>setState(()=>pinned=v):null)),
     if(error!=null)Padding(padding:const EdgeInsets.all(8),
      child:Text(error!,style:TextStyle(
       color:Theme.of(context).colorScheme.error))),
   ])),
  );
 }
}

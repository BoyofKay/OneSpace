import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../sharing/object_permissions.dart';
import '../sharing/share_grant_watcher.dart';
import 'note_draft_rules.dart';
import 'note_photos_panel.dart';
import 'note_references_panel.dart';
import '../../core/record_action_history_view.dart';
import '../mentions/rich_note_mention_button.dart';
import 'dart:async';

/// OneSpace Notes 2.0: real rich-text editing, native selection/copy/paste,
/// lists, headings, links and basic formatting, not markdown-in-text fields.
class QuillNoteEditorScreen extends StatefulWidget {
 const QuillNoteEditorScreen({super.key,required this.spaceId,this.existing});
 final String spaceId;
 final Map<String,dynamic>? existing;
 @override State<QuillNoteEditorScreen> createState()=>_QuillNoteEditorState();
}
class _QuillNoteEditorState extends State<QuillNoteEditorScreen>{
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
  title=TextEditingController(text:(old?['title']??'').toString());
  final raw=old?['rich_delta'];
  quill.Document document;
  if(raw is List){
   try{document=quill.Document.fromJson(
    raw.map((x)=>Map<String,dynamic>.from(x as Map)).toList());}
   catch(_){document=_fromPlain((old?['body']??'').toString());}
  }else{
   document=_fromPlain((old?['body']??'').toString());
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
  return Scaffold(
   appBar:AppBar(title:Text(editing?'Edit note':'Add new note'),
    actions:[
     if(editing)RecordActionHistoryButton(
       kind:'note',recordId:widget.existing!['id'].toString()),
     if(editing&&canEdit)IconButton(
      onPressed:busy?null:archive,
      tooltip:archived?'Restore note':'Remove note',
      icon:Icon(archived?Icons.unarchive_outlined:Icons.archive_outlined)),
    ]),
   body:SafeArea(child:ListView(
    padding:const EdgeInsets.fromLTRB(16,14,16,36),children:[
     if(!isEditingAllowed)const Text('Read-only note',
      style:TextStyle(fontWeight:FontWeight.bold)),
     TextField(controller:title,maxLength:120,
      readOnly:!isEditingAllowed,
      decoration:const InputDecoration(labelText:'Note title',
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
     ]else const Text(
      'Save this note before attaching photos or linking checklists, '
      'calendar events, occasions and shared experiences.'),
     const SizedBox(height:10),
     if(!editing)...[
      const Text('Visibility'),
      Wrap(spacing:8,children:[
       for(final mode in ['shared','private'])
        ChoiceChip(label:Text(mode=='shared'?'Shared with partner':'Only me'),
         selected:visibility==mode,
         onSelected:(_)=>setState(()=>visibility=mode)),
      ]),
     ],
     SwitchListTile(contentPadding:EdgeInsets.zero,
      title:const Text('Pin to top'),value:pinned,
      onChanged:isEditingAllowed?(v)=>setState(()=>pinned=v):null),
     if(error!=null)Padding(padding:const EdgeInsets.all(8),
      child:Text(error!,style:TextStyle(
       color:Theme.of(context).colorScheme.error))),
     FilledButton.icon(onPressed:!isEditingAllowed||busy?null:save,
      icon:const Icon(Icons.save_outlined),
      label:Text(busy?'Saving…':'Save rich-text note')),
   ])),
  );
 }
}

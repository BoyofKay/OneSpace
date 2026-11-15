import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:onespace/l10n/phrases.dart';

/// Mention partner inside Quill's actual document selection. The note's
/// existing server mention trigger owns notification and permission checks.
class RichNoteMentionButton extends StatefulWidget{
 const RichNoteMentionButton({super.key,required this.spaceId,
  required this.controller,this.enabled=true});
 final String spaceId;
 final quill.QuillController controller;
 final bool enabled;
 @override State<RichNoteMentionButton> createState()=>
  _RichNoteMentionButtonState();
}
class _RichNoteMentionButtonState extends State<RichNoteMentionButton>{
 String? partner;
 @override void initState(){super.initState();load();}
 @override void didUpdateWidget(covariant RichNoteMentionButton old){
  super.didUpdateWidget(old);
  if(old.spaceId!=widget.spaceId){
   partner=null;load();
  }
 }
 Future<void> load()async{
  if(widget.spaceId.isEmpty||!widget.enabled)return;
  final db=Supabase.instance.client;
  final user=db.auth.currentUser?.id;
  if(user==null)return;
  try{
   final members=await db.from('space_members').select('user_id')
    .eq('space_id',widget.spaceId);
   final other=members.where((m)=>m['user_id']!=user).firstOrNull;
   if(other==null)return;
   final profile=await db.from('profiles').select('display_name')
    .eq('id',other['user_id']).maybeSingle();
   final name=profile?['display_name']?.toString().trim();
   if(mounted&&db.auth.currentUser?.id==user){
    setState(()=>partner=name?.isNotEmpty==true?name:null);
   }
  }catch(_){}
 }
 void insert(){
  final name=partner;
  if(!widget.enabled||name==null)return;
  final selection=widget.controller.selection;
  final document=widget.controller.document;
  final length=document.length;
  final offset=selection.isValid?
   selection.start.clamp(0,length-1).toInt():length-1;
  final end=selection.isValid?
   selection.end.clamp(offset,length-1).toInt():offset;
  final mention='@$name ';
  widget.controller.replaceText(offset,end-offset,mention,
   TextSelection.collapsed(offset:offset+mention.length));
 }
 @override Widget build(BuildContext context)=>TextButton.icon(
  onPressed:widget.enabled&&partner!=null?insert:null,
  icon:const Icon(Icons.alternate_email,size:18),
  label:Text(tt(partner==null?'Mention partner':'Mention '+partner!)),
 );
}

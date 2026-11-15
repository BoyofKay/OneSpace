import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:onespace/l10n/phrases.dart';

/// Inserts the authenticated, connected partner's full name exactly as the
/// database mention trigger expects. Disabled for private content.
class PartnerMentionButton extends StatefulWidget{
 const PartnerMentionButton({
  super.key,required this.spaceId,required this.controller,
  this.enabled=true,
 });
 final String spaceId;
 final TextEditingController controller;
 final bool enabled;
 @override State<PartnerMentionButton> createState()=>_PartnerMentionButtonState();
}
class _PartnerMentionButtonState extends State<PartnerMentionButton>{
 String? partner;
 @override void initState(){super.initState();load();}
 @override void didUpdateWidget(covariant PartnerMentionButton old){
  super.didUpdateWidget(old);
  if(old.spaceId!=widget.spaceId||old.enabled!=widget.enabled){
   if(old.spaceId!=widget.spaceId)partner=null;
   if(widget.enabled)load();
  }
 }
 Future<void> load()async{
  // A reusable editor can mount without a shared space; avoid initializing
  // Supabase (including in widget tests) until a real space is available.
  if(widget.spaceId.trim().isEmpty||!widget.enabled)return;
  final client=Supabase.instance.client,me=client.auth.currentUser?.id;
  if(me==null)return;
  try{
   final rows=await client.from('space_members').select('user_id')
    .eq('space_id',widget.spaceId);
   final other=rows.where((m)=>m['user_id']!=me).firstOrNull;
   if(other==null)return;
   final profile=await client.from('profiles').select('display_name')
    .eq('id',other['user_id']).single();
   if(mounted&&client.auth.currentUser?.id==me){
    setState(()=>partner=profile['display_name']?.toString().trim());
   }
  }catch(_){}
 }
 void insert(){
  final name=partner;
  if(!widget.enabled||name==null||name.isEmpty)return;
  final controller=widget.controller;
  final selection=controller.selection;
  final start=selection.isValid?selection.start:controller.text.length;
  final end=selection.isValid?selection.end:controller.text.length;
  final insert='@'+name+' ';
  controller.value=TextEditingValue(
   text:controller.text.replaceRange(start,end,insert),
   selection:TextSelection.collapsed(offset:start+insert.length));
 }
 @override Widget build(BuildContext context)=>TextButton.icon(
  onPressed:widget.enabled&&partner!=null?insert:null,
  icon:const Icon(Icons.alternate_email,size:17),
  label:Text(tt(partner==null?'Mention partner':'Mention '+partner!)),
 );
}

import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'notes_screen.dart';
import 'related_notes_rules.dart';

/// A lazy, read-only reverse reference. No queries while collapsed.
/// RLS filters BOTH note_references and notes on the current account.
class RelatedNotesPanel extends StatefulWidget{
 const RelatedNotesPanel({
  super.key,required this.sourceKind,required this.sourceId,
  this.initiallyExpanded=false,
 });
 final String sourceKind,sourceId;
 final bool initiallyExpanded;
 @override State<RelatedNotesPanel> createState()=>_RelatedNotesPanelState();
}
class _RelatedNotesPanelState extends State<RelatedNotesPanel>{
 final db=Supabase.instance.client;
 late bool expanded;
 Future<List<Map<String,dynamic>>>? pending;
 @override void initState(){
  super.initState();expanded=widget.initiallyExpanded;
  if(expanded)_refresh();
 }
 @override void didUpdateWidget(covariant RelatedNotesPanel old){
  super.didUpdateWidget(old);
  if(old.sourceKind!=widget.sourceKind||old.sourceId!=widget.sourceId){
   expanded=false;pending=null;
  }
 }
 Future<List<Map<String,dynamic>>> _fetch()async{
  if(db.auth.currentUser==null)return const [];
  final links=await db.from('note_references')
    .select('note_id').eq('target_kind',widget.sourceKind)
    .eq('target_id',widget.sourceId).limit(100);
  final ids=links.map((x)=>x['note_id']?.toString()??'')
    .where((x)=>x.isNotEmpty).toSet().toList();
  if(ids.isEmpty)return const [];
  final notes=await db.from('notes').select(
   'id,title,visibility,pinned,updated_at,archived_at')
   .inFilter('id',ids).limit(100);
  return RelatedNotesRules.visible(notes,ids);
 }
 void _refresh(){
  if(mounted)setState(()=>pending=_fetch());
 }
 Future<void> _openNote(String id)async{
  await Navigator.of(context).push<void>(MaterialPageRoute(
   builder:(_)=>NotesScreen(initialNoteId:id)));
  if(mounted)_refresh();
 }
 Future<void> _openLibrary()async{
  await Navigator.of(context).push<void>(MaterialPageRoute(
   builder:(_)=>const NotesScreen()));
  if(mounted)_refresh();
 }
 @override Widget build(BuildContext context){
  final theme=Theme.of(context);
  return Card(elevation:0,child:Column(children:[
   ListTile(
    contentPadding:const EdgeInsets.symmetric(horizontal:12),
    leading:Icon(Icons.sticky_note_2_outlined,
     color:theme.colorScheme.primary),
    title:const Text('Related notes'),
    subtitle:const Text('Notes linked to this item and visible to you'),
    trailing:Icon(expanded?Icons.expand_less:Icons.expand_more),
    onTap:(){
     setState(()=>expanded=!expanded);
     if(expanded)_refresh();
    },
   ),
   if(expanded)...[
    FutureBuilder<List<Map<String,dynamic>>>(
     future:pending,builder:(context,snapshot){
      if(snapshot.hasError)return Padding(
       padding:const EdgeInsets.all(12),
       child:Column(children:[
        const Text('Could not load related notes.'),
        TextButton.icon(icon:const Icon(Icons.refresh),
         label:const Text('Retry'),onPressed:_refresh),
       ]));
      if(!snapshot.hasData)return const LinearProgressIndicator();
      final notes=snapshot.data!;
      if(notes.isEmpty)return const Padding(
       padding:EdgeInsets.symmetric(horizontal:12,vertical:8),
       child:Text('No linked notes visible here yet. Open a saved note and use Link item to connect it.'));
      return Column(children:[
       for(final note in notes)ListTile(
        contentPadding:const EdgeInsets.symmetric(horizontal:12),
        leading:Icon(note['pinned']==true?
         Icons.push_pin_outlined:Icons.notes_outlined),
        title:Text(note['title'].toString(),maxLines:2,
         overflow:TextOverflow.ellipsis),
        subtitle:Text(
         (note['visibility']=='private'?'Only me':'Shared')+
         (note['archived_at']!=null?' · Archived':'')),
        trailing:const Icon(Icons.chevron_right),
        onTap:()=>_openNote(note['id'].toString()),
       ),
      ]);
     }),
    Row(mainAxisAlignment:MainAxisAlignment.end,children:[
     TextButton.icon(icon:const Icon(Icons.refresh),
      onPressed:_refresh,label:const Text('Refresh')),
     TextButton.icon(icon:const Icon(Icons.open_in_new),
      onPressed:_openLibrary,label:const Text('Open Notes')),
    ]),
   ],
  ]));
 }
}

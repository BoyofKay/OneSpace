import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../calendar/calendar_screen.dart';
import '../plans/plans_screen.dart';
import '../occasions/occasions_screen.dart';
import '../connect/shared_experiences_screen.dart';
import 'note_reference_rules.dart';

/// A note may point to real OneSpace objects, not duplicate their contents.
/// The backend validates both note and source RLS at insertion and read time.
class NoteReferencesPanel extends StatefulWidget{
 const NoteReferencesPanel({super.key,required this.noteId,
  required this.spaceId,required this.noteVisibility,
  required this.canEdit});
 final String noteId,spaceId,noteVisibility;
 final bool canEdit;
 @override State<NoteReferencesPanel> createState()=>_NoteReferencesPanelState();
}
class _NoteReferencesPanelState extends State<NoteReferencesPanel>{
 final db=Supabase.instance.client;
 late Stream<List<Map<String,dynamic>>> stream;
 bool busy=false;
 String? error;
 @override void initState(){super.initState();_listen();}
 @override void didUpdateWidget(covariant NoteReferencesPanel old){
  super.didUpdateWidget(old);
  if(old.noteId!=widget.noteId)_listen();
 }
 void _listen(){
  stream=db.from('note_references').stream(primaryKey:['id'])
   .eq('note_id',widget.noteId).order('created_at').limit(80);
 }
 Future<Map<String,Map<String,dynamic>>> _resolve(
  List<Map<String,dynamic>> links)async{
  final visible=<String,Map<String,dynamic>>{};
  for(final entry in NoteReferenceRules.tables.entries){
   final ids=links.where((r)=>r['target_kind']==entry.key)
    .map((r)=>r['target_id']?.toString()??'')
    .where((v)=>v.isNotEmpty).toSet().toList();
   if(ids.isEmpty)continue;
   try{
    final rows=await db.from(entry.value)
     .select('id,title,archived_at').inFilter('id',ids).limit(100);
    for(final row in rows){
     visible[entry.key+':'+row['id'].toString()]=row;
    }
   }catch(_){
    // Revoke access or lose a connection: never use cached/leaked titles.
   }
  }
  return visible;
 }
 Future<void> _link()async{
  if(busy||!widget.canEdit)return;
  final kind=await showModalBottomSheet<String>(
   context:context,showDragHandle:true,
   builder:(ctx)=>SafeArea(child:Column(mainAxisSize:MainAxisSize.min,
    children:[
     Padding(padding:const EdgeInsets.all(12),
      child:Text('Link something in OneSpace',
       style:Theme.of(ctx).textTheme.titleLarge)),
     for(final entry in NoteReferenceRules.labels.entries)
      ListTile(title:Text(entry.value),
       leading:Icon(switch(entry.key){
        'task'=>Icons.checklist_outlined,
        'event'=>Icons.event_outlined,
        'occasion'=>Icons.card_giftcard_outlined,
        _=>Icons.movie_filter_outlined,
       }),
       onTap:()=>Navigator.pop(ctx,entry.key)),
    ])));
  if(kind==null||!mounted)return;
  final table=NoteReferenceRules.table(kind);
  if(table==null)return;
  setState((){busy=true;error=null;});
  try{
   final select=kind=='experience'
    ?'id,title,archived_at'
    :'id,title,archived_at,visibility';
   final rows=await db.from(table).select(select)
    .eq('space_id',widget.spaceId).isFilter('archived_at',null)
    .order('updated_at',ascending:false).limit(75);
   if(!mounted)return;
   final options=NoteReferenceRules.available(
    rows,noteVisibility:widget.noteVisibility,kind:kind);
   if(options.isEmpty){
    setState(()=>error='No accessible active ${NoteReferenceRules.label(kind).toLowerCase()} items to link.');
    return;
   }
   final chosen=await showModalBottomSheet<Map<String,dynamic>>(
    context:context,showDragHandle:true,isScrollControlled:true,
    builder:(ctx)=>FractionallySizedBox(heightFactor:.68,
     child:SafeArea(child:Column(children:[
      Padding(padding:const EdgeInsets.all(14),
       child:Text('Choose ${NoteReferenceRules.label(kind).toLowerCase()}',
        style:Theme.of(ctx).textTheme.titleLarge)),
      Expanded(child:ListView.builder(itemCount:options.length,
       itemBuilder:(ctx,index){
        final item=options[index];
        return ListTile(title:Text(item['title'].toString()),
         trailing:const Icon(Icons.add_link_outlined),
         onTap:()=>Navigator.pop(ctx,item));
       })),
     ]))));
   if(chosen==null||!mounted)return;
   await db.from('note_references').insert({
    'note_id':widget.noteId,'target_kind':kind,'target_id':chosen['id']});
  }on PostgrestException catch(e){
   if(mounted)setState(()=>error=e.code=='23505'
    ?'This note already links to that item.':e.message);
  }catch(_){
   if(mounted)setState(()=>error='Could not add the link. Check the item is still available.');
  }finally{if(mounted)setState(()=>busy=false);}
 }
 Future<void> _unlink(String id)async{
  if(busy||!widget.canEdit)return;
  setState((){busy=true;error=null;});
  try{
   await db.from('note_references').delete().eq('id',id);
  }on PostgrestException catch(e){
   if(mounted)setState(()=>error=e.message);
  }catch(_){
   if(mounted)setState(()=>error='Could not unlink this item.');
  }finally{if(mounted)setState(()=>busy=false);}
 }
 Future<void> _open(String kind,String id)async{
  final table=NoteReferenceRules.table(kind);
  if(table==null)return;
  try{
   // A stale link or revoked source grant must not disclose old content.
   final source=await db.from(table).select('id')
    .eq('id',id).eq('space_id',widget.spaceId).maybeSingle();
   if(!mounted)return;
   if(!NoteReferenceRules.canOpen(source)){
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
     content:Text('This item is no longer available to your account.')));
    return;
   }
   final Widget destination=switch(kind){
    'task'=>PlansScreen(focusTaskId:id),
    'event'=>CalendarScreen(initialEventId:id),
    'occasion'=>OccasionDetail(id:id),
    _=>ExperienceDetail(id:id),
   };
   await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(builder:(_)=>destination));
  }catch(_){
   if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
    content:Text('Could not open the linked item.')));
  }
 }
 @override Widget build(BuildContext context){
  final colors=Theme.of(context).colorScheme;
  return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
   Row(children:[
    Icon(Icons.hub_outlined,color:colors.primary),
    const SizedBox(width:8),
    Expanded(child:Text('Linked OneSpace items',
     style:Theme.of(context).textTheme.titleMedium)),
    if(widget.canEdit)TextButton.icon(onPressed:busy?null:_link,
     icon:const Icon(Icons.add_link),label:const Text('Link item')),
   ]),
   const Text('Keep the original item up to date. Links are checked against its visibility before opening.'),
   if(busy)const LinearProgressIndicator(),
   if(error!=null)Text(error!,style:TextStyle(color:colors.error)),
   StreamBuilder<List<Map<String,dynamic>>>(
    stream:stream,builder:(ctx,snapshot){
     if(snapshot.hasError)return const Text('Links are temporarily unavailable.');
     if(!snapshot.hasData)return const LinearProgressIndicator();
     final refs=snapshot.data!;
     if(refs.isEmpty)return const Padding(
      padding:EdgeInsets.symmetric(vertical:8),
      child:Text('No related items linked yet.'));
     return FutureBuilder<Map<String,Map<String,dynamic>>>(
      future:_resolve(refs),builder:(ctx,details){
       if(!details.hasData)return const LinearProgressIndicator();
       final data=details.data!;
       return Column(children:[
        for(final link in refs)
         Builder(builder:(ctx){
          final kind=link['target_kind'].toString();
          final id=link['target_id'].toString();
          final source=data[kind+':'+id];
          if(source==null)return const SizedBox.shrink();
          return ListTile(
           contentPadding:EdgeInsets.zero,
           leading:Icon(switch(kind){
            'task'=>Icons.checklist_outlined,
            'event'=>Icons.event_outlined,
            'occasion'=>Icons.card_giftcard_outlined,
            _=>Icons.movie_outlined,
           }),
           title:Text(source['title']?.toString()??'Linked item',
            maxLines:2,overflow:TextOverflow.ellipsis),
           subtitle:Text(NoteReferenceRules.label(kind)+
            (source['archived_at']!=null?' • Archived':'')),
           onTap:()=>_open(kind,id),
           trailing:widget.canEdit?IconButton(
            tooltip:'Unlink only (keeps original)',
            onPressed:busy?null:()=>_unlink(link['id'].toString()),
            icon:const Icon(Icons.link_off_outlined)):
             const Icon(Icons.chevron_right),
          );
         }),
       ]);
      });
    }),
  ]);
 }
}

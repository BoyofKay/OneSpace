import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'collection_history_screen.dart';

/// Server-recorded changes only: who changed which fields, and when.
/// Never copies private document bodies into another history surface.
class RecordActionHistoryButton extends StatelessWidget{
 const RecordActionHistoryButton({super.key,required this.kind,
  required this.recordId,this.recordTitle});
 final String kind,recordId;
 final String? recordTitle;

 /// R50 (B-14): an item's change log is the shared history page, filtered
 /// to this item, with the same people and action chips.
 @override Widget build(BuildContext context)=>IconButton(
  tooltip:'Change log',
  icon:const Icon(Icons.history),
  onPressed:()=>openChangeLog(context,kind:kind,recordId:recordId,
   recordTitle:recordTitle),
 );
}
class RecordActionHistoryView extends StatefulWidget{
 const RecordActionHistoryView({super.key,required this.kind,
  required this.recordId});
 final String kind,recordId;
 @override State<RecordActionHistoryView> createState()=>
  _RecordActionHistoryViewState();
}
class _RecordActionHistoryViewState extends State<RecordActionHistoryView>{
 final db=Supabase.instance.client;
 late Future<List<Map<String,dynamic>>> events;
 @override void initState(){super.initState();events=load();}
 Future<List<Map<String,dynamic>>> load()async{
  final rows=await db.from('record_action_history')
   .select('id,actor_id,action,changed_fields,happened_at')
   .eq('record_kind',widget.kind).eq('record_id',widget.recordId)
   .order('happened_at',ascending:false).limit(100);
  final actors=rows.map((x)=>x['actor_id']?.toString())
   .whereType<String>().where((x)=>x.isNotEmpty).toSet().toList();
  final names=<String,String>{};
  if(actors.isNotEmpty){
   try{
    final profiles=await db.from('profiles')
     .select('id,display_name').inFilter('id',actors);
    for(final p in profiles){
     final label=p['display_name']?.toString().trim()??'';
     if(label.isNotEmpty)names[p['id'].toString()]=label;
    }
   }catch(_){/* A missing display name must not hide the event. */}
  }
  for(final row in rows){
   final id=row['actor_id']?.toString();
   row['_actor_name']=id==null?'System':id==db.auth.currentUser?.id
    ?'You':names[id]??'Partner';
  }
  return rows;
 }
 void refresh(){if(mounted)setState(()=>events=load());}
 @override Widget build(BuildContext context){
  final theme=Theme.of(context);
  return SafeArea(child:Padding(
   padding:const EdgeInsets.fromLTRB(16,8,16,20),
   child:Column(children:[
    Row(children:[
     const Icon(Icons.manage_history_outlined),
     const SizedBox(width:10),
     Expanded(child:Text('Record action history',
      style:theme.textTheme.titleLarge)),
     IconButton(tooltip:'Refresh history',
      onPressed:refresh,icon:const Icon(Icons.refresh)),
    ]),
    const Text('Server-recorded actions since action history was enabled. Older edits may not appear.'),
    const SizedBox(height:10),
    Expanded(child:FutureBuilder<List<Map<String,dynamic>>>(
     future:events,builder:(ctx,snapshot){
      if(snapshot.hasError)return Center(child:Column(
       mainAxisSize:MainAxisSize.min,children:[
        const Text('History is unavailable or you no longer have access.'),
        TextButton(onPressed:refresh,child:const Text('Retry')),
       ]));
      if(!snapshot.hasData)return const Center(child:CircularProgressIndicator());
      final rows=snapshot.data!;
      if(rows.isEmpty)return const Center(child:Text('No recorded actions yet.'));
      return ListView.builder(itemCount:rows.length,
       itemBuilder:(ctx,index){
        final row=rows[index];
        final time=DateTime.tryParse(row['happened_at']?.toString()??'')
         ?.toLocal();
        final when=time==null?'Time unavailable':
         MaterialLocalizations.of(ctx).formatMediumDate(time)+' · '+
         TimeOfDay.fromDateTime(time).format(ctx);
        final fields=(row['changed_fields'] as List? ??const [])
         .map((x)=>x.toString().replaceAll('_',' ')).toList();
        return ListTile(
         leading:Icon(switch(row['action']){
          'created'=>Icons.add_circle_outline,
          'archived'=>Icons.archive_outlined,
          'restored'=>Icons.restore,
          'cancelled'=>Icons.cancel_outlined,
          'reopened'=>Icons.restart_alt,
          _=>Icons.edit_note_outlined,
         }),
         title:Text('${row['_actor_name']} · ${row['action']}'),
         subtitle:Text(when+(fields.isEmpty?'':'\nFields: '+fields.join(', '))),
         isThreeLine:fields.isNotEmpty,
        );
       });
     })),
   ]),
  ));
 }
}

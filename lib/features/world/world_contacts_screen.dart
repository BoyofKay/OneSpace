import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/current_space_cache.dart';
import '../coordinate/activity_contact_view.dart';
import '../coordinate/activity_detail_screen.dart';
import 'saved_contact_editor.dart';
import 'world_contact_entry.dart';

/// Searchable, collapsible contact cards. A direct contact is never an Activity.
class WorldContactsScreen extends StatefulWidget{
 const WorldContactsScreen({super.key});
 @override State<WorldContactsScreen> createState()=>_WorldContactsScreenState();
}
class _WorldContactsScreenState extends State<WorldContactsScreen>{
 final query=TextEditingController();
 final db=Supabase.instance.client;
 List<WorldContactEntry> contacts=const [];
 String? space,error;
 bool loading=true,showDeleted=false;
 final expanded=<String>{};
 @override void initState(){
   super.initState();
   query.addListener(_refresh);
   load();
 }
 void _refresh(){if(mounted)setState((){});}
 @override void dispose(){
   query.removeListener(_refresh);query.dispose();super.dispose();
 }
 Future<void> load()async{
   if(mounted)setState((){loading=true;error=null;});
   try{
     final id=await CurrentSpaceCache.instance.get();
     if(id==null){
       if(mounted)setState((){space=null;loading=false;contacts=[];});
       return;
     }
     final raw=await Future.wait([
       db.from('activity_components').select(
         'id,activity_id,created_by,label,payload,archived_at,updated_at,'
         'activities!inner(title,space_id,archived_at)')
         .eq('kind','contact').eq('activities.space_id',id)
         .order('created_at',ascending:false).limit(200),
       db.from('saved_contacts').select(
         'id,created_by,visibility,label,payload,archived_at,updated_at')
         .eq('space_id',id).order('created_at',ascending:false).limit(200),
     ]);
     if(!mounted)return;
     setState((){
       space=id;loading=false;
       contacts=[
         for(final row in raw[0])
           WorldContactEntry.fromRow(Map<String,dynamic>.from(row)),
         for(final row in raw[1])
           WorldContactEntry.fromDirect(Map<String,dynamic>.from(row)),
       ];
     });
   }catch(_){
     if(mounted)setState((){
       loading=false;error='Unable to load contacts. Pull down to retry.';
     });
   }
 }
 Future<void> edit([WorldContactEntry? entry])async{
   final id=space;
   if(id==null)return;
   final saved=await Navigator.of(context).push<bool>(
     MaterialPageRoute<bool>(builder:(_)=>SavedContactEditor(
       spaceId:id,existing:entry)));
   if(saved==true&&mounted)await load();
 }
 Future<void> openUri(Uri uri)async{
   try{
     if(!await launchUrl(uri,mode:LaunchMode.externalApplication)){
       await Clipboard.setData(ClipboardData(text:uri.toString()));
       if(mounted)ScaffoldMessenger.of(context).showSnackBar(
         const SnackBar(content:Text('No compatible app. Link copied.')));
     }
   }catch(_){
     if(mounted)ScaffoldMessenger.of(context).showSnackBar(
       const SnackBar(content:Text('Cannot open that action.')));
   }
 }
 Future<void> maps(String address)async{
   await openUri(Uri.https('www.google.com','/maps/search/',{
     'api':'1','query':address}));
 }
 Future<void> openOrigin(WorldContactEntry item)async{
   if(item.direct||item.activityId.isEmpty)return;
   await Navigator.of(context).push<void>(MaterialPageRoute<void>(
     builder:(_)=>ActivityScreen(id:item.activityId)));
   if(mounted)await load();
 }
 Future<void> removal(WorldContactEntry item,bool remove)async{
   final confirm=await showDialog<bool>(context:context,builder:(ctx)=>
     AlertDialog(
       title:Text(remove?'Move contact to Recently deleted?':'Restore contact?'),
       content:Text(remove
         ?'This contact is recoverable. The original data and edit history '
           'are kept; standalone contacts are eligible for retention review '
           '30 days after removal.'
         :'Make this contact visible again without losing its history.'),
       actions:[
         TextButton(onPressed:()=>Navigator.pop(ctx,false),
           child:const Text('Cancel')),
         FilledButton(onPressed:()=>Navigator.pop(ctx,true),
           child:Text(remove?'Remove':'Restore')),
       ]));
   if(confirm!=true)return;
   try{
     final changes={'archived_at':remove?
       DateTime.now().toUtc().toIso8601String():null};
     if(item.direct){
       await db.from('saved_contacts').update(changes).eq('id',item.id);
     }else{
       await db.from('activity_components').update(changes)
         .eq('id',item.id).eq('activity_id',item.activityId);
     }
     if(mounted)await load();
   }on PostgrestException catch(e){
     if(mounted)ScaffoldMessenger.of(context).showSnackBar(
       SnackBar(content:Text('Could not change this contact: '+e.message)));
   }catch(_){
     if(mounted)ScaffoldMessenger.of(context).showSnackBar(
       const SnackBar(content:Text('Could not update contact.')));
   }
 }
 String creator(WorldContactEntry item){
   return item.createdBy==db.auth.currentUser?.id?'you':'your partner';
 }
 Future<void> showHistory([WorldContactEntry? selected])async{
   final source=selected;
   try{
     final direct=source?.direct;
     final a=await db.from('saved_contact_revisions')
       .select('contact_id,changed_by,changed_at,change_kind,old_label,new_label')
       .order('changed_at',ascending:false).limit(120);
     final b=await db.from('activity_component_revisions')
       .select('component_id,changed_by,changed_at,change_kind,old_label,new_label')
       .order('changed_at',ascending:false).limit(120);
     final entries=<Map<String,dynamic>>[
       for(final row in a)
         if(source==null||(direct==true&&row['contact_id']==source.id))
           {...row,'type':'Standalone contact'},
       for(final row in b)
         if(source==null||(direct==false&&row['component_id']==source.id))
           {...row,'type':'Activity contact'},
     ]..sort((x,y)=>(y['changed_at']?.toString()??'')
        .compareTo(x['changed_at']?.toString()??''));
     if(!mounted)return;
     await Navigator.of(context).push<void>(MaterialPageRoute<void>(
       builder:(_)=>Scaffold(
         appBar:AppBar(title:Text(source==null?
           'Contact edit history':'Contact history')),
         body:entries.isEmpty?
           const Center(child:Text('No edits, removals or restorations yet.')):
           ListView.builder(
             padding:const EdgeInsets.all(14),
             itemCount:entries.length,
             itemBuilder:(ctx,i){
               final x=entries[i];
               final date=DateTime.tryParse(x['changed_at']?.toString()??'')
                 ?.toLocal();
               return Card(elevation:0,child:ListTile(
                 leading:Icon(x['change_kind']=='removed'?
                   Icons.delete_outline:x['change_kind']=='restored'?
                   Icons.restore:Icons.edit_note),
                 title:Text((x['change_kind']?.toString()??'edited')+
                   ' · '+(x['new_label']?.toString()??x['old_label']?.toString()??'Contact')),
                 subtitle:Text((x['type']?.toString()??'')+' · '+
                   (date?.toString().split('.').first??'Time unavailable')+
                   ' · '+(x['changed_by']==db.auth.currentUser?.id?
                     'You':'Partner')),
               ));
             },
           ),
       )));
   }catch(_){
     if(mounted)ScaffoldMessenger.of(context).showSnackBar(
       const SnackBar(content:Text('Contact history could not be loaded.')));
   }
 }
 Widget card(WorldContactEntry item){
   final key=(item.direct?'direct:':'activity:')+item.id;
   final isOpen=expanded.contains(key);
   final deleted=item.isDeleted;
   return Card(elevation:0,clipBehavior:Clip.antiAlias,child:Column(
     crossAxisAlignment:CrossAxisAlignment.stretch,children:[
       ListTile(
         leading:Icon(item.direct?
           Icons.person_outline:Icons.contacts_outlined),
         title:Text(item.label,
           style:Theme.of(context).textTheme.titleMedium),
         subtitle:Text(deleted?'Recently deleted':
           item.direct?'Saved contact':'From shared Activity'),
         onTap:()=>setState((){
           if(isOpen){expanded.remove(key);}else{expanded.add(key);}
         }),
         trailing:Row(mainAxisSize:MainAxisSize.min,children:[
           IconButton(
             tooltip:'Edit contact card',
             icon:const Icon(Icons.edit_outlined),
             onPressed:deleted?null:()=>edit(item)),
           Icon(isOpen?Icons.expand_less:Icons.expand_more),
         ]),
       ),
       if(isOpen)Padding(padding:const EdgeInsets.fromLTRB(15,2,15,12),
         child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
           ActivityContactView(contact:item.contact,
             onPhone:openUri,onEmail:openUri,onMap:maps),
           if(item.contact.note.isNotEmpty)...[
             const Divider(height:20),
             Text('Notes',style:Theme.of(context).textTheme.labelLarge),
             const SizedBox(height:4),
             SelectableText(item.contact.note),
           ],
           const SizedBox(height:10),
           if(item.direct)Text('Created by '+creator(item),
             style:Theme.of(context).textTheme.labelSmall)
           else TextButton(
             onPressed:()=>openOrigin(item),
             child:Text('From: '+item.activityTitle)),
           Wrap(spacing:8,children:[
             OutlinedButton.icon(
               onPressed:()=>showHistory(item),
               icon:const Icon(Icons.history),
               label:const Text('History')),
             OutlinedButton.icon(
               onPressed:()=>removal(item,!deleted),
               icon:Icon(deleted?Icons.restore:Icons.delete_outline),
               label:Text(deleted?'Restore':'Remove')),
           ]),
         ])),
     ],
   ));
 }
 @override Widget build(BuildContext context){
   final visible=WorldContactEntry.filtered(
     contacts.where((e)=>e.isDeleted==showDeleted).toList(),query.text);
   return Scaffold(
     appBar:AppBar(title:const Text('People & contacts'),actions:[
       IconButton(
         tooltip:'Contact edit history',icon:const Icon(Icons.history),
         onPressed:()=>showHistory()),
     ]),
     body:RefreshIndicator(onRefresh:load,child:ListView(
       physics:const AlwaysScrollableScrollPhysics(),
       padding:const EdgeInsets.all(14),
       children:[
         Text('People worth remembering',
           style:Theme.of(context).textTheme.titleMedium),
         const SizedBox(height:5),
         Text('Save people directly, or find contacts linked to our Activities.',
           style:Theme.of(context).textTheme.bodySmall),
         const SizedBox(height:12),
         FilledButton.tonalIcon(
           onPressed:space==null?null:()=>edit(),
           icon:const Icon(Icons.person_add_alt_1_outlined),
           label:const Text('Remember someone')),
         const SizedBox(height:12),
         TextField(controller:query,decoration:InputDecoration(
           prefixIcon:const Icon(Icons.search),
           hintText:'Search names, phones, places or notes',
           border:const OutlineInputBorder(),
           suffixIcon:query.text.isEmpty?null:IconButton(
             icon:const Icon(Icons.clear),tooltip:'Clear',
             onPressed:query.clear))),
         const SizedBox(height:8),
         Row(children:[
           FilterChip(
             selected:showDeleted,
             label:const Text('Recently deleted'),
             onSelected:(v)=>setState(()=>showDeleted=v)),
           const SizedBox(width:8),
           if(showDeleted)Text('Restore an item to keep it',
             style:Theme.of(context).textTheme.labelSmall),
         ]),
         const SizedBox(height:8),
         if(loading)const Center(child:CircularProgressIndicator())
         else if(error!=null)Text(error!,
           style:TextStyle(color:Theme.of(context).colorScheme.error))
         else if(space==null)const Text('Connect your shared space first.')
         else if(visible.isEmpty)Text(showDeleted?
           'No recently deleted contacts.':'No contacts match this view.')
         else for(final item in visible)card(item),
       ],
     )),
   );
 }
}

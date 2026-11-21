import '../../core/item_menu.dart';
import '../../core/editor_scaffold.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/current_space_cache.dart';
import '../../core/account_content_scope.dart';
import '../../core/app_env.dart';
import '../../core/record_list_top_actions.dart';
import '../coordinate/activity_contact_view.dart';
import '../coordinate/activity_detail_screen.dart';
import 'saved_contact_editor.dart';
import 'phone_contact_bridge.dart';
import 'world_contact_entry.dart';
import 'package:onespace/l10n/phrases.dart';

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
 bool personalAvailable=false;
 bool loading=true,showDeleted=false;
 String sourceFilter='all';
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
     final legacy=await CurrentSpaceCache.instance.get();
     final scopes=await AccountContentScope.load(db,legacySpaceId:legacy);
     final id=scopes.sharedSpaceId;
     if(id==null && OneSpaceEnv.usesLegacyBackend){
       if(mounted)setState((){
         space=null;personalAvailable=false;loading=false;contacts=[];
       });
       return;
     }
     var linked=db.from('activity_components').select(
       'id,activity_id,created_by,label,payload,archived_at,updated_at,'
       'activities!inner(title,space_id,archived_at)')
       .eq('kind','contact');
     var standalone=db.from('saved_contacts').select(
       'id,created_by,visibility,label,payload,archived_at,updated_at');
     if(OneSpaceEnv.usesLegacyBackend){
       linked=linked.eq('activities.space_id',id!);
       standalone=standalone.eq('space_id',id);
     }
     // QA RLS merges current pair + account ownership. Never filter out
     // personal contacts using the current or a previous couple space.
     final raw=await Future.wait([
       linked.order('created_at',ascending:false).limit(200),
       standalone.order('created_at',ascending:false).limit(200),
     ]);
     if(!mounted)return;
     setState((){
       space=id;personalAvailable=scopes.canCreatePrivate;loading=false;
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
   if(id==null && !personalAvailable)return;
   final saved=await Navigator.of(context).push<bool>(
     MaterialPageRoute<bool>(builder:(_)=>SavedContactEditor(
       spaceId:id??'',existing:entry)));
   if(saved==true&&mounted)await load();
 }
 Future<void> importFromPhone()async{
  final id=space;
  if(id==null && !personalAvailable)return;
  try{
   final contact=await PhoneContactBridge.pickFromPhone();
   if(contact==null||!mounted)return;
   final saved=await Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(builder:(_)=>SavedContactEditor(
     spaceId:id??'',imported:contact)));
   if(saved==true&&mounted)await load();
  }on PlatformException catch(e){
   if(mounted)ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content:Text(tt(e.code=='CONTACT_PERMISSION_DENIED'?
     'To import a contact, allow Contacts permission in Android Settings.':
     'Could not import the selected contact.'))));
  }catch(_){
   if(mounted)ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content:Text(tt('Contact import is unavailable on this device.'))));
  }
 }
 Future<void> saveToPhone(WorldContactEntry item)async{
  try{
   await PhoneContactBridge.saveToPhone(item.contact);
  }on PlatformException catch(_){
   if(mounted)ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content:Text(tt('Could not open your phone Contacts app.'))));
  }catch(_){
   if(mounted)ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content:Text(tt('Saving to phone is unavailable on this device.'))));
  }
 }
 Future<void> openUri(Uri uri)async{
   try{
     if(!await launchUrl(uri,mode:LaunchMode.externalApplication)){
       await Clipboard.setData(ClipboardData(text:uri.toString()));
       if(mounted)ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(content:Text(tt('No compatible app. Link copied.'))));
     }
   }catch(_){
     if(mounted)ScaffoldMessenger.of(context).showSnackBar(
       SnackBar(content:Text(tt('Cannot open that action.'))));
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
       title:Text(tt(remove?tt('Move contact to Recently deleted?'):tt('Restore contact?'))),
       content:Text(tt(remove
         ?'This contact is recoverable. The original data and edit history '
           'are kept; standalone contacts are eligible for retention review '
           '30 days after removal.'
         :'Make this contact visible again without losing its history.')),
       actions:[
         TextButton(onPressed:()=>Navigator.pop(ctx,false),
           child:Text(tt('Cancel'))),
         FilledButton(onPressed:()=>Navigator.pop(ctx,true),
           child:Text(tt(remove?tt('Remove'):tt('Restore')))),
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
       SnackBar(content:Text(tt('Could not change this contact: ')+e.message)));
   }catch(_){
     if(mounted)ScaffoldMessenger.of(context).showSnackBar(
       SnackBar(content:Text(tt('Could not update contact.'))));
   }
 }
 String creator(WorldContactEntry item){
   return item.createdBy==db.auth.currentUser?.id?'you':'your partner';
 }
 Future<void> showHistory([WorldContactEntry? selected])async{
   final source=selected;
   try{
     final direct=source?.direct;
     // Limit revision queries to actual contacts in the current visible list.
     // Never include revisions from unrelated Activity components.
     final directIds=source!=null?
       (direct==true?<String>[source.id]:<String>[]):
       contacts.where((x)=>x.direct).map((x)=>x.id).toList();
     final linkedIds=source!=null?
       (direct==false?<String>[source.id]:<String>[]):
       contacts.where((x)=>!x.direct).map((x)=>x.id).toList();
     final a=directIds.isEmpty?<Map<String,dynamic>>[]:
      await db.from('saved_contact_revisions')
       .select('contact_id,changed_by,changed_at,change_kind,old_label,new_label')
       .inFilter('contact_id',directIds)
       .order('changed_at',ascending:false).limit(120);
     final b=linkedIds.isEmpty?<Map<String,dynamic>>[]:
      await db.from('activity_component_revisions')
       .select('component_id,changed_by,changed_at,change_kind,old_label,new_label')
       .inFilter('component_id',linkedIds)
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
         appBar:AppBar(title:Text(tt(source==null?
           'Contact edit history':'Contact history'))),
         body:entries.isEmpty?
           Center(child:Text(tt('No edits, removals or restorations yet.'))):
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
                 title:Text(tt((x['change_kind']?.toString()??'edited')+
                   ' · '+(x['new_label']?.toString()??x['old_label']?.toString()??'Contact'))),
                 subtitle:Text(tt((x['type']?.toString()??'')+' · '+
                   (date?.toString().split('.').first??'Time unavailable')+
                   ' · '+(x['changed_by']==db.auth.currentUser?.id?
                     'You':'Partner'))),
               ));
             },
           ),
       )));
   }catch(_){
     if(mounted)ScaffoldMessenger.of(context).showSnackBar(
       SnackBar(content:Text(tt('Contact history could not be loaded.'))));
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
         title:Text(tt(item.label),
           style:Theme.of(context).textTheme.titleMedium),
         subtitle:Text(tt(deleted?'Recently deleted':
           item.direct?'Saved contact':'From shared Activity')),
         onTap:()=>setState((){
           if(isOpen){expanded.remove(key);}else{expanded.add(key);}
         }),
         trailing:ItemMenu(kind:'contact',recordId:item.id,title:item.label,
           onOpen:deleted?null:()=>edit(item),
           moreActions:[
             if(!deleted)ItemMenuAction(tt('Save to phone'),Icons.contact_phone_outlined,()=>saveToPhone(item)),
             if(!item.direct)ItemMenuAction(tt('Open the Activity'),Icons.open_in_new,()=>openOrigin(item)),
           ],
           removed:deleted,onRemove:()=>removal(item,!deleted)),
       ),
       if(isOpen)Padding(padding:const EdgeInsetsDirectional.fromSTEB(15,2,15,12),
         child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
           ActivityContactView(contact:item.contact,
             onPhone:openUri,onEmail:openUri,onMap:maps),
           if(item.contact.note.isNotEmpty)...[
             const Divider(height:20),
             Text(tt('Notes'),style:Theme.of(context).textTheme.labelLarge),
             const SizedBox(height:4),
             SelectableText(item.contact.note),
           ],
           const SizedBox(height:10),
           if(item.direct)Text(tt('Created by ')+creator(item),
             style:Theme.of(context).textTheme.labelSmall)
           else TextButton(
             onPressed:()=>openOrigin(item),
             child:Text(tt('From: ')+item.activityTitle)),
         ])),
     ],
   ));
 }
 /// R55: this screen's filter groups (drawn by the shared panel).
 List<FilterGroupSpec> _filterGroups()=>[FilterGroupSpec(id:'source',label:tt('Source'),options:const {'all':'All','direct':'Saved directly','activity':'From Activities'},selected:sourceFilter,defaultValue:'all')];

 @override Widget build(BuildContext context){
   final visible=WorldContactEntry.filtered(
     contacts.where((e)=>e.isDeleted==showDeleted &&
      (sourceFilter=='all'||(sourceFilter=='direct'?e.direct:!e.direct)))
      .toList(),query.text);
   return Scaffold(
     appBar:AppBar(title:Text(tt('Contact cards')),actions:[
       RecordListTopActions(
        historyKinds:const ['contact'],historyTitle:tt('Contact cards'),
     showHistory:showDeleted,
        onToggleHistory:()=>setState(()=>showDeleted=!showDeleted),
        groups:_filterGroups(),
      onApply:(v)=>setState((){sourceFilter=v['source']!;}),
     ),
     ],bottom:filterShowingBar(_filterGroups(),removed:showDeleted,onClear:()=>setState((){showDeleted=false;sourceFilter='all';}))),
     // R57: one add button; "Import from phone" is one of its choices
     // (it brings a phone contact in — the opposite of Save to phone).
     floatingActionButton:!personalAvailable?null:AddFabMenu(label:tt('Add contact card'),options:[
       AddFabOption(tt('New contact card'),Icons.person_add_alt_outlined,()=>edit()),
       AddFabOption(tt('Import from phone'),Icons.contacts_outlined,importFromPhone),
     ]),
     body:RefreshIndicator(onRefresh:load,child:ListView(
       physics:const AlwaysScrollableScrollPhysics(),
       padding:const EdgeInsetsDirectional.fromSTEB(14,14,14,96),
       children:[
         Text(tt('Contact cards'),
           style:Theme.of(context).textTheme.titleMedium),
         const SizedBox(height:5),
         Text(tt('Save people directly, or find contacts linked to our Activities.'),
           style:Theme.of(context).textTheme.bodySmall),
         const SizedBox(height:12),
         TextField(controller:query,decoration:InputDecoration(
           prefixIcon:const Icon(Icons.search),
           labelText:tt('Search contact cards'),hintText:tt('Names, phones, places or notes'),
           border:const OutlineInputBorder(),
           suffixIcon:query.text.isEmpty?null:IconButton(
             icon:const Icon(Icons.clear),tooltip:tt('Clear'),
             onPressed:query.clear))),
         const SizedBox(height:8),
         if(showDeleted)Padding(
          padding:const EdgeInsets.only(bottom:8),
          child:Text(tt('Recently deleted contacts · Restore an item to keep it.'),
           style:Theme.of(context).textTheme.bodySmall)),
         if(loading)const Center(child:CircularProgressIndicator())
         else if(error!=null)Text(tt(error!),
           style:TextStyle(color:Theme.of(context).colorScheme.error))
         else if(!personalAvailable)Text(tt('Connect your shared space first.'))
         else if(visible.isEmpty)Text(tt(showDeleted?
           'No recently deleted contacts.':'No contacts match this view.'))
         else for(final item in visible)card(item),
       ],
     )),
   );
 }
}

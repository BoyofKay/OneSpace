import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/current_space_cache.dart';
import '../coordinate/activity_contact_view.dart';
import '../coordinate/activity_contact.dart';
import '../coordinate/activity_detail_screen.dart';
import 'world_contact_entry.dart';

/// A contact overview of contacts already contributed to shared Activities.
/// No new contact database or sharing pathway is introduced.
class WorldContactsScreen extends StatefulWidget {
  const WorldContactsScreen({super.key});

  @override
  State<WorldContactsScreen> createState() => _WorldContactsScreenState();
}

class _WorldContactsScreenState extends State<WorldContactsScreen> {
  final query = TextEditingController();
  final db = Supabase.instance.client;
  List<WorldContactEntry> contacts = const [];
  bool loading = true;
  bool hasSpace = true;
  String? error;

  @override
  void initState() {
    super.initState();
    query.addListener(refreshSearch);
    load();
  }

  void refreshSearch() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    query.removeListener(refreshSearch);
    query.dispose();
    super.dispose();
  }

  Future<void> load() async {
    if (mounted) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      final spaceId = await CurrentSpaceCache.instance.get();
      if (spaceId == null) {
        if (mounted) {
          setState(() {
            hasSpace = false;
            contacts = const [];
            loading = false;
          });
        }
        return;
      }
      final rows = await db.from('activity_components').select(
        'id,activity_id,label,payload,archived_at,'
        'activities!inner(title,space_id)',
      ).eq('kind','contact')
       .eq('activities.space_id',spaceId)
       .isFilter('archived_at',null)
       .order('created_at', ascending: false)
       .limit(200)
       .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      setState(() {
        hasSpace = true;
        loading = false;
        contacts = [
          for(final row in rows)
            WorldContactEntry.fromRow(Map<String,dynamic>.from(row)),
        ];
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          error = 'Unable to load saved contacts. Pull down to retry.';
        });
      }
    }
  }

  Future<void> _rememberPerson() async {
    final space=await CurrentSpaceCache.instance.get();
    if(space==null){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:Text('Connect a shared space before adding someone.')));
      return;
    }
    final name=TextEditingController();
    final connection=TextEditingController();
    final contextNote=TextEditingController();
    final phone=TextEditingController();
    final email=TextEditingController();
    var private=false;
    try{
      final accepted=await showDialog<bool>(
        context:context,
        builder:(dialog)=>StatefulBuilder(
          builder:(dialog,change)=>AlertDialog(
            title:const Text('Remember someone'),
            content:SingleChildScrollView(child:Column(
              mainAxisSize:MainAxisSize.min,children:[
                TextField(controller:name,maxLength:120,
                  decoration:const InputDecoration(
                    labelText:'Name',hintText:'A friend, neighbor, family member…')),
                TextField(controller:connection,maxLength:180,
                  decoration:const InputDecoration(
                    labelText:'How do you know them?',
                    hintText:'Neighbor, cousin, colleague…')),
                TextField(controller:contextNote,maxLength:1000,maxLines:3,
                  decoration:const InputDecoration(
                    labelText:'What should we remember?',
                    hintText:'Where you met, their family, helpful details…')),
                TextField(controller:phone,maxLength:80,
                  decoration:const InputDecoration(
                    labelText:'Phone (optional)')),
                TextField(controller:email,maxLength:254,
                  decoration:const InputDecoration(
                    labelText:'Email (optional)')),
                SwitchListTile(
                  contentPadding:EdgeInsets.zero,
                  title:const Text('Only me'),
                  subtitle:const Text('Otherwise both partners can see this person and notes.'),
                  value:private,
                  onChanged:(v)=>change(()=>private=v)),
                const Text('This creates one Activity with a contact card, '
                  'so comments and later details stay together.'),
              ])),
            actions:[
              TextButton(onPressed:()=>Navigator.pop(dialog,false),
                child:const Text('Cancel')),
              FilledButton(onPressed:(){
                if(name.text.trim().isNotEmpty)Navigator.pop(dialog,true);
              },child:const Text('Save person')),
            ],
          ),
        ),
      );
      if(accepted!=true||!mounted)return;
      final person=name.text.trim();
      final relationship=connection.text.trim();
      final note=contextNote.text.trim();
      final contact=ActivityContact(
        person:person,phone:phone.text.trim(),email:email.text.trim(),
        note:[if(relationship.isNotEmpty)relationship,
          if(note.isNotEmpty)note].join(' · '),
      );
      final invalid=contact.validate();
      if(invalid!=null){
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(invalid)));
        return;
      }
      final created=await db.from('activities').insert({
        'space_id':space,'title':'Remember '+person,
        'body':[if(relationship.isNotEmpty)relationship,
          if(note.isNotEmpty)note].join('\n'),
        'visibility':private?'private':'shared',
      }).select('id').single();
      final id=created['id'].toString();
      try{
        await db.from('activity_components').insert({
          'activity_id':id,'kind':'contact',
          'label':person,'payload':contact.toPayload(),
        });
      }catch(_){
        // Keep the new Activity and tell the user where to finish its contact.
        if(mounted)ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content:Text('Person saved as an Activity. '
            'Open it to add contact details.')));
      }
      if(!mounted)return;
      await load();
      if(!mounted)return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder:(_)=>ActivityScreen(id:id)));
      if(mounted)await load();
    }on PostgrestException catch(error){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content:Text('Could not save person: '+error.message)));
    }catch(_){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content:Text('Could not save person. Please retry.')));
    }finally{
      name.dispose();
      connection.dispose();
      contextNote.dispose();
      phone.dispose();
      email.dispose();
    }
  }

  Future<void> openUri(Uri uri) async {
    try {
      final opened = await launchUrl(
        uri, mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        await Clipboard.setData(ClipboardData(text:uri.path));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content:Text('No compatible app. Detail copied.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content:Text('Unable to open this action.')),
        );
      }
    }
  }

  Future<void> openMaps(String address) async {
    await openUri(Uri.https('www.google.com','/maps/search/',{
      'api':'1','query':address,
    }));
  }

  Future<void> openActivity(WorldContactEntry contact) async {
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder: (_) => ActivityScreen(id:contact.activityId),
    ));
    if (mounted) await load();
  }

  @override
  Widget build(BuildContext context) {
    final visible = WorldContactEntry.filtered(contacts,query.text);
    return Scaffold(
      appBar: AppBar(title: const Text('People & contacts'),actions:[
        IconButton(tooltip:'Remember a person',
          onPressed:_rememberPerson,
          icon:const Icon(Icons.person_add_alt_1_outlined)),
      ]),
      body: RefreshIndicator(
        onRefresh: load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(14),
          children: [
            Text('People and places we have researched together',
              style:Theme.of(context).textTheme.titleMedium),
            const SizedBox(height:6),
            Text('Contacts are drawn from visible Activities, not copied into '
              'another address book.',
              style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height:12),
            FilledButton.tonalIcon(
              onPressed:_rememberPerson,
              icon:const Icon(Icons.person_add_alt_1_outlined),
              label:const Text('Remember someone')),
            const SizedBox(height:10),
            TextField(
              controller:query,
              decoration: InputDecoration(
                prefixIcon:const Icon(Icons.search),
                hintText:'Search name, business, phone or location',
                border:const OutlineInputBorder(),
                suffixIcon:query.text.isEmpty?null:IconButton(
                  tooltip:'Clear search',
                  icon:const Icon(Icons.clear),
                  onPressed:query.clear,
                ),
              ),
            ),
            const SizedBox(height:12),
            if (loading)
              const Padding(padding:EdgeInsets.all(24),
                child:Center(child:CircularProgressIndicator()))
            else if (error != null) ...[
              Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
              TextButton.icon(
                icon:const Icon(Icons.refresh),
                onPressed:load,
                label:const Text('Try again'),
              ),
            ] else if (!hasSpace)
              const Text('Connect a shared space to see your contacts.')
            else if (visible.isEmpty)
              Padding(
                padding:const EdgeInsets.symmetric(vertical:30),
                child:Text(contacts.isEmpty
                  ? 'No contacts yet. Add Contact information inside a '
                    'Coordinate Activity to find it here.'
                  : 'No contacts match your search.'),
              )
            else
              for (final item in visible)
                Card(elevation:0,child:Padding(
                  padding:const EdgeInsets.fromLTRB(12,10,12,10),
                  child:Column(
                    crossAxisAlignment:CrossAxisAlignment.start,
                    children:[
                      Row(children:[
                        const Icon(Icons.contact_phone_outlined,size:21),
                        const SizedBox(width:8),
                        Expanded(child:Text(item.label,
                          style:Theme.of(context).textTheme.titleMedium)),
                        IconButton(
                          tooltip:'Open the original Activity',
                          onPressed:()=>openActivity(item),
                          icon:const Icon(Icons.open_in_new,size:19),
                        ),
                      ]),
                      ActivityContactView(
                        contact:item.contact,
                        onPhone:openUri,
                        onEmail:openUri,
                        onMap:openMaps,
                      ),
                      Align(alignment:Alignment.centerRight,
                        child:TextButton(
                          onPressed:()=>openActivity(item),
                          child:Text('From: ${item.activityTitle}'),
                        )),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

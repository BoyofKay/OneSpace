import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../memories/memories_screen.dart';
import '../goals/goals_screen.dart';
import '../checkins/checkins_screen.dart';
import '../world/world_contacts_screen.dart';
import '../../core/current_space_cache.dart';

class SectionHub extends StatelessWidget {
  const SectionHub({super.key, required this.section});
  final String section;

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
  }

  Widget _link(
    BuildContext context, IconData icon, String title,
    String subtitle, Widget destination,
  ) => Card(
    elevation: 0,
    child: ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _open(context, destination),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final isConnect = section == 'connect';
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text(
          isConnect ? 'Connect' : 'World',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 6),
        Text(isConnect
            ? 'The moments and conversations that keep us close.'
            : 'Our people, places, travels and the wider context of our lives.'),
        const SizedBox(height: 16),
        if (isConnect) ...[
          _link(context, Icons.favorite_outline, 'Daily check-ins',
              'Share how you feel today', const CheckinsScreen()),
          _link(context, Icons.photo_library_outlined, 'Memories',
              'Stories and moments worth preserving', const MemoriesScreen()),
          _link(context, Icons.flag_outlined, 'Shared goals',
              'Progress and milestones together', const GoalsScreen()),
          const SizedBox(height: 14),
          const Text(
            'Shared movies, playlists, games, love letters and daily selfies '
            'are planned. They are not active features yet.',
          ),
        ] else ...[
          const RelationshipSettings(),
          const SizedBox(height: 12),
          _link(context, Icons.contacts_outlined,
            'Saved contacts',
            'People, organizations and places from our shared Activities',
            const WorldContactsScreen()),
          const SizedBox(height: 12),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Text(
                'Family and people, journeys, travel and saved life context '
                'will live here in future releases.',
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class RelationshipSettings extends StatefulWidget {
 const RelationshipSettings({super.key,this.compact=false});
 final bool compact;
 @override State<RelationshipSettings> createState()=>_RelationshipSettingsState();
}
class _RelationshipSettingsState extends State<RelationshipSettings> {
 final db=Supabase.instance.client;
 String? spaceId;
 String mode='not_set';
 DateTime? last,next;
 bool loading=true,saving=false;
 String? error;
 @override void initState(){super.initState();load();}
 Future<void> load() async {
   try{
     final id=await CurrentSpaceCache.instance.get();
     if(id==null){if(mounted)setState(()=>loading=false);return;}
     final row=await db.from('spaces').select(
       'relationship_mode,last_met_on,next_meet_on').eq('id',id).single();
     if(mounted) { setState((){
       spaceId=id;
       mode=row['relationship_mode'] as String? ?? 'not_set';
       last=DateTime.tryParse(row['last_met_on'] as String? ?? '');
       next=DateTime.tryParse(row['next_meet_on'] as String? ?? '');
       loading=false;
     }); }
   }catch(_){if(mounted)setState((){loading=false;error='Could not load relationship settings';});}
 }
 String format(DateTime? d)=>d==null?'Not set':'${d.day}/${d.month}/${d.year}';
 int? daysSince(DateTime? date){
   if(date==null)return null;
   final now=DateTime.now();
   return DateTime(now.year,now.month,now.day)
       .difference(DateTime(date.year,date.month,date.day)).inDays;
 }
 Future<void> save() async {
   if(spaceId==null)return;
   setState(()=>saving=true);
   try{
     String? sqlDate(DateTime? d)=>d==null?null:
       '${d.year.toString().padLeft(4,'0')}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
     await db.from('spaces').update({
       'relationship_mode':mode,'last_met_on':sqlDate(last),
       'next_meet_on':sqlDate(next),
     }).eq('id',spaceId!);
     if(mounted) { ScaffoldMessenger.of(context).showSnackBar(
       const SnackBar(content:Text('Shared relationship settings saved'))); }
   }catch(e){if(mounted)setState(()=>error='Unable to save: $e');}
   finally{if(mounted)setState(()=>saving=false);}
 }
 Future<void> pick(bool previous) async {
   final now=DateTime.now();
   final selected=await showDatePicker(context:context,
     firstDate:DateTime(2000),lastDate:DateTime(2100),
     initialDate:(previous?last:next)??now);
   if(mounted&&selected!=null) {setState(() {
     if(previous){last=selected;}else{next=selected;}
   });}
 }
 @override Widget build(BuildContext context){
   if(loading) {return const Padding(padding:EdgeInsets.all(18),
     child:LinearProgressIndicator());}
   if(spaceId==null) {return const Card(child:Padding(
     padding:EdgeInsets.all(16),child:Text('Connect your shared space first.')));}
   final since=daysSince(last),until=daysSince(next);
   return Card(elevation:0,child:Padding(padding:const EdgeInsets.all(15),
     child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
       Text('Our relationship',style:Theme.of(context).textTheme.titleLarge),
       const SizedBox(height:8),
       Text(mode=='living_together'?'Living together':
         mode=='apart_same_tz'?'Living apart · same time zone':
         mode=='apart_different_tz'?'Long-distance · different time zones':
           'Choose our living situation'),
       const SizedBox(height:9),
       Row(children:[
         Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
           Text(since==null?'Last met: not set':'Last met: $since days ago'),
           Text('Date: ${format(last)}',style:Theme.of(context).textTheme.bodySmall),
         ])),
         Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
           Text(until==null?'Next meeting: not set':
             until<0?'Next meeting: in ${-until} days':
             until==0?'Next meeting: today':'Meeting date passed'),
           Text('Date: ${format(next)}',style:Theme.of(context).textTheme.bodySmall),
         ])),
       ]),
       if(!widget.compact)...[
         const SizedBox(height:10),
         DropdownButtonFormField<String>(initialValue:mode,
           decoration:const InputDecoration(labelText:'Living arrangement'),
           items:const [
             DropdownMenuItem(value:'not_set',child:Text('Not set')),
             DropdownMenuItem(value:'living_together',child:Text('Living together')),
             DropdownMenuItem(value:'apart_same_tz',child:Text('Living apart — same time zone')),
             DropdownMenuItem(value:'apart_different_tz',child:Text('Long-distance — different time zones')),
           ],
           onChanged:(v)=>setState(()=>mode=v??mode)),
         const SizedBox(height:8),
         Wrap(spacing:7,children:[
           OutlinedButton.icon(icon:const Icon(Icons.history),
             onPressed:()=>pick(true),label:Text('Last met: ${format(last)}')),
           OutlinedButton.icon(icon:const Icon(Icons.event),
             onPressed:()=>pick(false),label:Text('Next meeting: ${format(next)}')),
           if(next!=null)TextButton(onPressed:()=>setState(()=>next=null),
             child:const Text('Clear next meeting')),
         ]),
         FilledButton(onPressed:saving?null:save,child:const Text('Save for both of us')),
       ],
       if(error!=null)Text(error!,style:const TextStyle(color:Colors.red)),
     ]),
   ));
 }
}

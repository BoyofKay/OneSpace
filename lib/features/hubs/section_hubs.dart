import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../memories/memories_screen.dart';
import '../checkins/checkins_screen.dart';
import '../connect/couple_letters_screen.dart';
import '../connect/partner_gestures_screen.dart';
import '../connect/shared_experiences_screen.dart';
import '../world/trips_screen.dart';
import '../../core/current_space_cache.dart';
import 'package:onespace/l10n/phrases.dart';

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
      title: Text(tt(title)),
      subtitle: Text(tt(subtitle)),
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
          tt(isConnect ? 'Connect' : 'World'),
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 6),
        Text(tt(isConnect
            ? 'The moments and conversations that keep us close.'
            : 'Every trip we take, from the next reunion to a weekend away.')),
        const SizedBox(height: 16),
        if (isConnect) ...[
          _link(context, Icons.mark_email_unread_outlined,
              'Letters',
              'Private drafts, sent letters, replies and read status',
              const CoupleLettersScreen()),
          _link(context, Icons.volunteer_activism_outlined,
              'A little love',
              'Send a hug, a thought, support or sweet dreams',
              const PartnerGesturesScreen()),
          _link(context, Icons.favorite_outline, 'Daily check-ins',
              'Share how you feel today', const CheckinsScreen()),
          _link(context, Icons.movie_filter_outlined,
              'Shared experiences',
              'Movies, shows, music, books and games to enjoy together',
              const SharedExperiencesScreen()),
          _link(context, Icons.photo_library_outlined, 'Memories',
              'Stories and moments worth preserving', const MemoriesScreen()),
        ] else ...[
          _link(context, Icons.luggage_outlined,
              'Trips & journeys',
              'Flights, places to stay, plans, booking details and shared travel notes',
              const TripsScreen()),
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
 String savedMode='not_set';
 DateTime? last,next;
 bool loading=true,saving=false,paired=true;
 String? error;
 @override void initState(){super.initState();load();}
 Future<void> load() async {
   try{
     final id=await CurrentSpaceCache.instance.get();
     if(id==null){if(mounted)setState(()=>loading=false);return;}
     final row=await db.from('spaces').select(
       'relationship_mode,last_met_on,next_meet_on').eq('id',id).single();
     final members=await db.from('space_members').select('user_id').eq('space_id',id);
     if(mounted) { setState((){
       spaceId=id;
       paired=members.length==2;
       mode=row['relationship_mode'] as String? ?? 'not_set';
       savedMode=mode;
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
     // 27 Nov 2026: a change of how we live goes through the same server
     // function as the Today icon, so the partner is notified and "apart" is
     // split into same or different time zones from both phones.
     final together=mode=='living_together';
     final wasTogether=savedMode=='living_together';
     if(mode!='not_set'&&(savedMode=='not_set'||together!=wasTogether)){
       mode=(await db.rpc('set_how_we_live',params:{'p_together':together})).toString();
       savedMode=mode;
     }
     await db.from('spaces').update({
       'last_met_on':sqlDate(last),'next_meet_on':sqlDate(next),
     }).eq('id',spaceId!);
     if(mounted) { ScaffoldMessenger.of(context).showSnackBar(
       SnackBar(content:Text(tt('Shared relationship settings saved')))); }
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
   if(loading)return const Padding(padding:EdgeInsets.all(18),
     child:LinearProgressIndicator());
   if(spaceId==null)return Card(child:Padding(
     padding:EdgeInsets.all(16),child:Text(tt('Connect your shared space first.'))));
   // A space with one person has no relationship to describe yet.
   if(!paired)return Card(elevation:0,child:Padding(
     padding:const EdgeInsets.all(16),child:Column(
       crossAxisAlignment:CrossAxisAlignment.start,children:[
       Text(tt('Our relationship'),style:Theme.of(context).textTheme.titleLarge),
       const SizedBox(height:8),
       Text(tt('Living arrangement and meeting dates can be set once your partner joins.')),
     ])));
   final together=mode=='living_together';
   final since=daysSince(last),until=daysSince(next);
   return Card(elevation:0,child:Padding(
     padding:const EdgeInsets.all(16),
     child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
       Text(tt('Our relationship'),style:Theme.of(context).textTheme.titleLarge),
       const SizedBox(height:7),
       Text(tt('One shared setting, visible to both of you.'),
         style:Theme.of(context).textTheme.bodySmall),
       const SizedBox(height:16),
       SegmentedButton<bool>(
         segments:[
           ButtonSegment(value:false,
             icon:Icon(Icons.flight_takeoff_outlined),
             label:Text(tt('Living apart'))),
           ButtonSegment(value:true,
             icon:Icon(Icons.home_outlined),
             label:Text(tt('Together'))),
         ],
         selected:{together},
         onSelectionChanged:saving?null:(values)=>
           setState(()=>mode=values.first?'living_together':'apart_different_tz'),
       ),
       const SizedBox(height:10),
       Text(tt(together
         ?'Clocks and weather are hidden on Today. Your meaningful dates '
          'and counters remain visible until you clear them.'
         :'Each partner sees their clock and selected city weather. '
          'The phones automatically handle time zones and daylight saving.'),
         style:Theme.of(context).textTheme.bodySmall),
       const Divider(height:27),
       Text(tt('Our important dates'),style:Theme.of(context).textTheme.titleMedium),
       const SizedBox(height:7),
       ListTile(
         contentPadding:EdgeInsets.zero,
         leading:const Icon(Icons.history_outlined),
         title:Text(tt('Last time we met')),
         subtitle:Text(tt(last==null?'Not set':format(last)+
           (since!=null&&since>=0?' · '+since.toString()+' days ago':''))),
         onTap:saving?null:()=>pick(true),
         trailing:Row(mainAxisSize:MainAxisSize.min,children:[
           if(last!=null)IconButton(
             tooltip:tt('Clear last met date'),
             onPressed:saving?null:()=>setState(()=>last=null),
             icon:const Icon(Icons.clear)),
           const Icon(Icons.edit_calendar_outlined),
         ]),
       ),
       const Divider(height:1),
       ListTile(
         contentPadding:EdgeInsets.zero,
         leading:const Icon(Icons.event_available_outlined),
         title:Text(tt('Our next meeting')),
         subtitle:Text(tt(next==null?'Not set':format(next)+
           (until!=null&&until>=0?' · '+until.toString()+' days to go':
             until!=null?' · Meeting date passed':''))),
         onTap:saving?null:()=>pick(false),
         trailing:Row(mainAxisSize:MainAxisSize.min,children:[
           if(next!=null)IconButton(
             tooltip:tt('Clear next meeting date'),
             onPressed:saving?null:()=>setState(()=>next=null),
             icon:const Icon(Icons.clear)),
           const Icon(Icons.edit_calendar_outlined),
         ]),
       ),
       const SizedBox(height:16),
       if(error!=null)Text(tt(error!),
         style:TextStyle(color:Theme.of(context).colorScheme.error)),
       FilledButton.icon(
         onPressed:saving?null:save,
         icon:const Icon(Icons.check),
         label:Text(tt(saving?tt('Saving…'):tt('Save for both of us')))),
     ]),
   ));
 }
}

import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'occasion_budget_rules.dart';
import 'package:onespace/l10n/phrases.dart';

/// Link an Activity decision into an occasion without mutating either object.
/// Privacy follows the destination occasion; DB validates source visibility.
class OccasionOptionLinker extends StatefulWidget{
 const OccasionOptionLinker({super.key,required this.plan});
 final Map<String,dynamic> plan;
 @override State<OccasionOptionLinker> createState()=>_OccasionOptionLinkerState();
}
class _OccasionOptionLinkerState extends State<OccasionOptionLinker>{
 final db=Supabase.instance.client;
 List<Map<String,dynamic>> options=[];
 bool busy=false,loading=true;
 String? error;
 @override void initState(){super.initState();load();}
 Future<void> load()async{
  try{
   final activities=await db.from('activities')
    .select('id,title,visibility').eq('space_id',widget.plan['space_id'])
    .isFilter('archived_at',null).limit(100);
   final ids=activities.where((a)=>
    widget.plan['visibility']=='private'||a['visibility']=='shared')
    .map((a)=>a['id'].toString()).toList();
   if(ids.isEmpty){if(mounted)setState(()=>loading=false);return;}
   final rows=await db.from('activity_components')
    .select('id,activity_id,label,payload')
    .inFilter('activity_id',ids).eq('kind','option')
    .isFilter('archived_at',null).limit(200);
   if(mounted)setState((){
    options=List<Map<String,dynamic>>.from(rows);loading=false;
   });
  }catch(_){
   if(mounted)setState((){loading=false;error='Could not load Activity options.';});
  }
 }
 Future<void> add(Map<String,dynamic> row)async{
  if(busy)return;
  final p=row['payload'] is Map?row['payload'] as Map:const {};
  final rawCurrency=(p['currency']??widget.plan['currency']??'USD').toString().toUpperCase();
  final price=OccasionBudgetRules.amount(p['price']);
  final url=(p['url']??'').toString();
  final notes=(p['note']??p['specs']??'').toString();
  setState((){busy=true;error=null;});
  try{
   await db.from('occasion_budget_items').insert({
    'plan_id':widget.plan['id'],'title':row['label'].toString(),
    'unit_price':price,'currency':RegExp(r'^[A-Z]{3}$').hasMatch(rawCurrency)
      ?rawCurrency:widget.plan['currency'],
    'status':'planned',
    'notes':notes.length>2500?notes.substring(0,2500):notes,
    'source_url':OccasionBudgetRules.isHttpUrl(url)?url:'',
    'source_activity_id':row['activity_id'],
    'source_component_id':row['id'],
   });
   if(mounted)Navigator.pop(context,true);
  }on PostgrestException catch(e){
   if(mounted)setState(()=>error=e.code=='23505'?
    'This option has already been added to the occasion.':e.message);
  }catch(_){
   if(mounted)setState(()=>error='Unable to link this option. Try again.');
  }finally{if(mounted)setState(()=>busy=false);}
 }
 @override Widget build(BuildContext context)=>SafeArea(
  child:SizedBox(height:MediaQuery.sizeOf(context).height*.7,
   child:Column(children:[
    Padding(padding:const EdgeInsets.fromLTRB(18,10,18,12),
     child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(tt('Connect a decision to this occasion'),
       style:Theme.of(context).textTheme.titleLarge),
      const SizedBox(height:5),
      Text(tt('Bring an option from Coordinate into your shopping plan. The source Activity remains unchanged.')),
     ])),
    if(loading)const LinearProgressIndicator(),
    if(error!=null)Padding(padding:const EdgeInsets.all(10),
     child:Text(tt(error!),style:TextStyle(color:Theme.of(context).colorScheme.error))),
    Expanded(child:options.isEmpty?Center(
     child:Text(tt('No eligible options. Compare choices in Coordinate first.'),
      textAlign:TextAlign.center)):
     ListView.builder(itemCount:options.length,itemBuilder:(ctx,i){
      final row=options[i],payload=row['payload'] is Map?
       row['payload'] as Map:const {};
      return ListTile(
       leading:const Icon(Icons.compare_arrows_outlined),
       title:Text(tt(row['label'].toString())),
       subtitle:Text(tt(payload['price']==null?'Estimate not set':
        (payload['currency']??'').toString()+' '+payload['price'].toString())),
       trailing:const Icon(Icons.add_circle_outline),
       onTap:busy?null:()=>add(row));
     })),
   ])));
}
/// Coordinate option -> choose destination, and leave a protected audit trail.
class SendOptionToOccasionSheet extends StatefulWidget{
 const SendOptionToOccasionSheet({super.key,required this.activityId,
  required this.option});
 final String activityId;
 final Map<String,dynamic> option;
 @override State<SendOptionToOccasionSheet> createState()=>_SendOptionToOccasionSheetState();
}
class _SendOptionToOccasionSheetState extends State<SendOptionToOccasionSheet>{
 final db=Supabase.instance.client;
 bool loading=true,busy=false;
 String? error;
 List<Map<String,dynamic>> plans=[];
 @override void initState(){super.initState();load();}
 Future<void> load()async{
  try{
   final a=await db.from('activities').select('space_id,visibility')
    .eq('id',widget.activityId).single();
   final rows=await db.from('occasion_plans')
    .select('id,title,currency,visibility').eq('space_id',a['space_id'])
    .isFilter('archived_at',null).limit(100);
   if(mounted)setState((){
    plans=List<Map<String,dynamic>>.from(rows.where((r)=>
     a['visibility']=='shared'||r['visibility']=='private'));
    loading=false;
   });
  }catch(_){if(mounted)setState((){
   loading=false;error='Could not load eligible occasions.';
  });}
 }
 Future<void> send(Map<String,dynamic> plan)async{
  if(busy)return;
  final option=widget.option;
  final payload=option['payload'] is Map?option['payload'] as Map:const {};
  final c=(payload['currency']??plan['currency']??'USD').toString().toUpperCase();
  final url=(payload['url']??'').toString();
  final description=(payload['note']??payload['specs']??'').toString();
  setState((){busy=true;error=null;});
  try{
   await db.from('occasion_budget_items').insert({
    'plan_id':plan['id'],
    'title':option['label'].toString(),
    'unit_price':OccasionBudgetRules.amount(payload['price']),
    'currency':RegExp(r'^[A-Z]{3}$').hasMatch(c)?c:plan['currency'],
    'status':'planned',
    'source_activity_id':widget.activityId,
    'source_component_id':option['id'],
    'source_url':OccasionBudgetRules.isHttpUrl(url)?url:'',
    'notes':description.length>2500?description.substring(0,2500):description,
   });
   if(mounted)Navigator.pop(context,true);
  }on PostgrestException catch(e){
   if(mounted)setState(()=>error=e.code=='23505'?
    'Already in this occasion plan.':e.message);
  }catch(_){
   if(mounted)setState(()=>error='Could not send the option to this occasion.');
  }finally{if(mounted)setState(()=>busy=false);}
 }
 @override Widget build(BuildContext context)=>SafeArea(
  child:SizedBox(height:MediaQuery.sizeOf(context).height*.55,
   child:Column(children:[
    Padding(padding:const EdgeInsets.all(16),
     child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(tt('Send this choice to an occasion'),
       style:Theme.of(context).textTheme.titleLarge),
      Text(tt('Reserve the estimated cost and connect the original decision. Private ideas remain private.')),
     ])),
    if(loading)const LinearProgressIndicator(),
    if(error!=null)Text(tt(error!),style:TextStyle(color:Theme.of(context).colorScheme.error)),
    Expanded(child:plans.isEmpty?Center(
     child:Text(tt('No eligible occasions yet. Create one in Remember.'))):
     ListView(children:[for(final p in plans)ListTile(
      leading:Icon(p['visibility']=='private'?Icons.lock_outline:
       Icons.celebration_outlined),
      title:Text(tt(p['title'].toString())),
      subtitle:Text(tt((p['visibility']=='private'?tt('Only me'):tt('Both of us'))+
       ' · '+p['currency'].toString())),
      trailing:const Icon(Icons.arrow_forward_ios,size:16),
      onTap:busy?null:()=>send(p),
     )])),
   ])));
}

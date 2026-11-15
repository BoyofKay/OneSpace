import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:onespace/l10n/phrases.dart';

/// Compare and save alternative gift bundles without triggering purchases.
class OccasionCombinationPlanner extends StatefulWidget {
 const OccasionCombinationPlanner({super.key,required this.plan,required this.items});
 final Map<String,dynamic> plan;
 final List<Map<String,dynamic>> items;
 @override State<OccasionCombinationPlanner> createState()=>_CombinationState();
}
class _CombinationState extends State<OccasionCombinationPlanner>{
 final db=Supabase.instance.client;
 final selected=<String>{};
 final name=TextEditingController(),notes=TextEditingController();
 bool saving=false;
 String? error;
 @override void dispose(){name.dispose();notes.dispose();super.dispose();}
 double cost(Map<String,dynamic> i)=>((i['unit_price'] as num?)?.toDouble()??0)*
   ((i['quantity'] as num?)?.toDouble()??1);
 Future<void> save()async{
  if(saving||selected.isEmpty)return;
  if(name.text.trim().isEmpty){setState(()=>error='Name this proposed combination.');return;}
  setState((){saving=true;error=null;});
  try{
   await db.rpc('save_occasion_proposal',params:{
    'p_plan_id':widget.plan['id'],'p_title':name.text.trim(),
    'p_item_ids':selected.toList(),'p_notes':notes.text.trim()});
   if(mounted)Navigator.of(context).pop(true);
  }on PostgrestException catch(e){if(mounted)setState(()=>error=e.message);}
  catch(_){if(mounted)setState(()=>error='Could not save the combination.');}
  finally{if(mounted)setState(()=>saving=false);}
 }
 @override Widget build(BuildContext context){
  final currency=widget.plan['currency']?.toString()??'USD';
  final occasion=DateTime.tryParse(widget.plan['occasion_on']?.toString()??'');
  final valid=widget.items.where((i)=>i['archived_at']==null&&i['status']!='cancelled').toList();
  final chosen=valid.where((i)=>selected.contains(i['id'].toString())).toList();
  final comparable=chosen.where((i)=>i['currency']==currency).toList();
  final total=comparable.fold<double>(0,(n,i)=>n+cost(i));
  final budget=(widget.plan['budget'] as num?)?.toDouble();
  final late=occasion!=null&&chosen.any((i){
   final arrival=DateTime.tryParse(i['estimated_delivery']?.toString()??'');
   return arrival!=null&&arrival.isAfter(occasion);
  });
  final foreign=chosen.length-comparable.length;
  final unpriced=comparable.where((i)=>i['unit_price']==null).length;
  return SafeArea(child:ListView(padding:EdgeInsetsDirectional.fromSTEB(
   16,10,16,MediaQuery.viewInsetsOf(context).bottom+24),children:[
   Text(tt('Build a proposed gift list'),style:Theme.of(context).textTheme.titleLarge),
   const SizedBox(height:8),
   Text(tt('Try different combinations before deciding. No orders or budget reservations are created.')),
   const SizedBox(height:12),
   for(final item in valid)Card(child:CheckboxListTile(
    value:selected.contains(item['id'].toString()),
    onChanged:(v)=>setState((){
     if(v==true){selected.add(item['id'].toString());}
     else{selected.remove(item['id'].toString());}
    }),
    title:Text(tt(item['title']?.toString()??'Option')),
    subtitle:Text(tt([
     if((item['merchant']??'').toString().isNotEmpty)item['merchant'].toString(),
     if(item['unit_price']!=null)(item['currency']??currency).toString()+' '+cost(item).toStringAsFixed(2),
     if(item['estimated_delivery']!=null)'Arrives '+item['estimated_delivery'].toString(),
     if(item['preference_score']!=null)'My score '+item['preference_score'].toString()+'/5',
    ].join(' · '))),
   )),
   const Divider(),
   Text(tt('Selected: ')+chosen.length.toString(),style:Theme.of(context).textTheme.titleMedium),
   Text(tt('Estimated total: ')+currency+' '+total.toStringAsFixed(2),
    style:Theme.of(context).textTheme.headlineSmall),
   if(budget!=null)Text(tt('Budget less selection: ')+currency+' '+(budget-total).toStringAsFixed(2),
    style:TextStyle(color:total>budget?Theme.of(context).colorScheme.error:null)),
   if(foreign>0)Text(tt(foreign.toString()+' items use other currencies and are excluded. No exchange rate is assumed.')),
   if(unpriced>0)Text(tt(unpriced.toString()+' items have no price; total is incomplete.')),
   if(late)Text(tt('Delivery warning: a selected option arrives after the occasion.'),
    style:TextStyle(color:Theme.of(context).colorScheme.error)),
   const SizedBox(height:12),
   TextField(controller:name,maxLength:120,decoration:InputDecoration(
    labelText:tt('Proposed combination name'),border:OutlineInputBorder())),
   TextField(controller:notes,maxLength:1000,maxLines:2,decoration:InputDecoration(
    labelText:tt('Comparison notes (optional)'),border:OutlineInputBorder())),
   if(error!=null)Text(tt(error!),style:TextStyle(color:Theme.of(context).colorScheme.error)),
   FilledButton.icon(onPressed:saving||selected.isEmpty?null:save,
    icon:const Icon(Icons.bookmark_add_outlined),
    label:Text(tt(saving?tt('Saving…'):tt('Save proposed list')))),
  ]));
 }
}

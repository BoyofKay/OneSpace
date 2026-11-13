import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/responsive_field_pair.dart';
import '../coordinate/activity_detail_screen.dart';
import 'occasion_budget_rules.dart';
import 'occasion_budget_item_editor.dart';
import 'occasion_option_linker.dart';

const budgetStages=<String,String>{
 'wish':'Wishlist','shortlisted':'Considering','planned':'Reserved',
 'purchased':'Purchased','cancelled':'Skipped',
};

/// Embedded in Occasion detail: live wishlist, commitments, spending and history.
class OccasionBudgetWorkspace extends StatefulWidget {
 const OccasionBudgetWorkspace({super.key,required this.plan});
 final Map<String,dynamic> plan;
 @override State<OccasionBudgetWorkspace> createState()=>_OccasionBudgetWorkspaceState();
}
class _OccasionBudgetWorkspaceState extends State<OccasionBudgetWorkspace>{
 final db=Supabase.instance.client;
 late Stream<List<Map<String,dynamic>>> stream;
 bool showArchived=false,busy=false;
 String? error;
 @override void initState(){super.initState();_attach();}
 void _attach(){
  stream=db.from('occasion_budget_items').stream(primaryKey:['id'])
   .eq('plan_id',widget.plan['id'].toString()).order('created_at',ascending:false)
   .limit(250);
 }
 @override void didUpdateWidget(covariant OccasionBudgetWorkspace old){
  super.didUpdateWidget(old);
  if(old.plan['id']!=widget.plan['id'])_attach();
 }
 Future<void> edit([Map<String,dynamic>? row,String initial='planned'])async{
  await showModalBottomSheet<bool>(context:context,isScrollControlled:true,
   showDragHandle:true,
   builder:(_)=>OccasionBudgetItemEditor(plan:widget.plan,
    existing:row,initialStatus:initial,
    markPurchase:row!=null&&initial=='purchased'));
 }
 Future<void> setStage(Map<String,dynamic> item,String stage)async{
  if(busy)return;
  setState((){busy=true;error=null;});
  try{
   await db.from('occasion_budget_items').update({'status':stage})
    .eq('id',item['id']).eq('plan_id',widget.plan['id']);
  }on PostgrestException catch(e){
   if(mounted)setState(()=>error=e.message);
  }catch(_){
   if(mounted)setState(()=>error='Could not update this item.');
  }finally{if(mounted)setState(()=>busy=false);}
 }
 Future<void> browseOptions()async{
  await showModalBottomSheet<void>(context:context,showDragHandle:true,
   isScrollControlled:true,
   builder:(_)=>OccasionOptionLinker(plan:widget.plan));
 }
 Future<void> history()async{
  await showModalBottomSheet<void>(context:context,showDragHandle:true,
   isScrollControlled:true,builder:(_)=>_BudgetHistory(id:widget.plan['id'].toString()));
 }
 @override Widget build(BuildContext context){
  final theme=Theme.of(context),colors=theme.colorScheme;
  return StreamBuilder<List<Map<String,dynamic>>>(stream:stream,
   builder:(context,snapshot){
    final data=snapshot.data??const <Map<String,dynamic>>[];
    final budget=OccasionBudgetRules.summarize(widget.plan,data);
    final visible=data.where((r)=>showArchived||(
     r['archived_at']==null&&r['status']!='cancelled')).toList();
    String currency(double? value)=>value==null?'Not set':
     budget.currency+' '+value.toStringAsFixed(2);
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
     Container(padding:const EdgeInsets.all(18),
      decoration:BoxDecoration(
       borderRadius:BorderRadius.circular(22),
       gradient:LinearGradient(colors:[colors.primaryContainer,
        Color.alphaBlend(colors.primary.withValues(alpha:.06),colors.surface)]),
       border:Border.all(color:colors.primary.withValues(alpha:.25))),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
       Row(children:[
        Icon(Icons.account_balance_wallet_outlined,color:colors.primary),
        const SizedBox(width:8),
        Expanded(child:Text('Occasion budget',style:theme.textTheme.titleLarge)),
        IconButton(tooltip:'Planning history',onPressed:history,
         icon:const Icon(Icons.history_outlined)),
       ]),
       const SizedBox(height:9),
       const Text('Available after reservations and purchases'),
       Text(currency(budget.available),
        style:theme.textTheme.headlineMedium?.copyWith(
         fontWeight:FontWeight.w800,
         color:budget.overBudget?colors.error:null)),
       const SizedBox(height:10),
       ClipRRect(borderRadius:BorderRadius.circular(8),
        child:LinearProgressIndicator(value:budget.progress,minHeight:10)),
       const SizedBox(height:12),
       Wrap(spacing:16,runSpacing:12,children:[
        _BudgetStat(label:'Total budget',amount:currency(budget.budget),
         icon:Icons.savings_outlined),
        _BudgetStat(label:'Reserved',amount:currency(budget.planned),
         icon:Icons.shopping_cart_outlined),
        _BudgetStat(label:'Spent',amount:currency(budget.spent),
         icon:Icons.receipt_long_outlined),
        _BudgetStat(label:'Wishlist (not deducted)',amount:currency(budget.wishlist),
         icon:Icons.favorite_outline),
       ]),
       if(budget.overBudget)Padding(padding:const EdgeInsets.only(top:10),
        child:Text('Over budget by '+currency(-budget.available!)+
         '. Review the reserved items or your budget.',
         style:TextStyle(color:colors.error))),
       if(budget.foreignCurrency>0||budget.unpriced>0)
        Padding(padding:const EdgeInsets.only(top:10),
         child:Text('Other currencies: '+budget.foreignCurrency.toString()+
           ' · Committed items without a price: '+budget.unpriced.toString()+
           '. Missing exchange rates are never guessed.',
          style:theme.textTheme.bodySmall)),
      ])),
     const SizedBox(height:12),
     Wrap(spacing:8,runSpacing:8,children:[
      FilledButton.icon(onPressed:()=>edit(null,'planned'),
       icon:const Icon(Icons.add_shopping_cart_outlined),
       label:const Text('Add purchase')),
      OutlinedButton.icon(onPressed:()=>edit(null,'wish'),
       icon:const Icon(Icons.favorite_outline),label:const Text('Add wish')),
      OutlinedButton.icon(onPressed:browseOptions,
       icon:const Icon(Icons.hub_outlined),label:const Text('From Activity')),
     ]),
     const SizedBox(height:12),
     Wrap(spacing:10,runSpacing:8,
      alignment:WrapAlignment.spaceBetween,children:[
       Text('Shopping & wishlist',style:theme.textTheme.titleLarge),
       FilterChip(label:const Text('Show removed'),selected:showArchived,
        onSelected:(v)=>setState(()=>showArchived=v)),
     ]),
     if(snapshot.connectionState==ConnectionState.waiting&&!snapshot.hasData)
      const LinearProgressIndicator(),
     if(snapshot.hasError)
      Text('Could not load the shopping list. Reopen the occasion to retry.',
       style:TextStyle(color:colors.error)),
     if(error!=null)Text(error!,style:TextStyle(color:colors.error)),
     if(visible.isEmpty&&!snapshot.hasError)Card(child:Padding(
      padding:const EdgeInsets.all(18),child:Column(children:[
       Icon(Icons.card_giftcard_outlined,size:32,color:colors.primary),
       const SizedBox(height:8),
       const Text('Collect wishes, reserve decisions and track each purchase without losing your budget.',
        textAlign:TextAlign.center),
      ]))),
     for(final item in visible)Card(child:Padding(
      padding:const EdgeInsets.fromLTRB(12,10,12,10),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
       Row(children:[
        CircleAvatar(child:Icon(item['status']=='purchased'?
         Icons.check_circle_outline:item['status']=='wish'?
         Icons.favorite_outline:Icons.shopping_bag_outlined)),
        const SizedBox(width:10),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
         Text(item['title'].toString(),style:theme.textTheme.titleMedium),
         Text(budgetStages[item['status']]??'Reserved',
          style:theme.textTheme.bodySmall),
        ])),
        IconButton(tooltip:'Edit item',icon:const Icon(Icons.edit_outlined),
         onPressed:()=>edit(item)),
       ]),
       if(item['notes']!=null&&item['notes'].toString().isNotEmpty)
        Text(item['notes'].toString(),maxLines:3,overflow:TextOverflow.ellipsis),
       Wrap(spacing:7,runSpacing:5,children:[
        if(item['unit_price']!=null)Chip(
         label:Text(item['currency'].toString()+' '+
          (item['unit_price'] as num).toStringAsFixed(2)+' × '+
          item['quantity'].toString())),
        if(item['actual_unit_price']!=null)Chip(
         label:Text('Paid '+item['currency'].toString()+' '+
          (item['actual_unit_price'] as num).toStringAsFixed(2)+' each')),
        if(item['source_activity_id']!=null)ActionChip(
         avatar:const Icon(Icons.hub_outlined,size:16),
         label:const Text('Source Activity'),
         onPressed:()=>Navigator.of(context).push(MaterialPageRoute<void>(
          builder:(_)=>ActivityScreen(id:item['source_activity_id'].toString())))),
       ]),
       Wrap(spacing:7,runSpacing:5,children:[
        if(item['status']=='wish'||item['status']=='shortlisted')
         ActionChip(label:const Text('Reserve'),
          onPressed:busy?null:()=>setStage(item,'planned')),
        if(item['status']=='planned')
         ActionChip(label:const Text('Mark purchased'),
          avatar:const Icon(Icons.shopping_cart_checkout_outlined,size:16),
          onPressed:busy?null:()=>edit(item,'purchased')),
        if(item['status']=='planned')
         ActionChip(label:const Text('Back to wishlist'),
          onPressed:busy?null:()=>setStage(item,'wish')),
        if(item['status']=='purchased')
         ActionChip(label:const Text('Undo purchase'),
          onPressed:busy?null:()=>setStage(item,'planned')),
       ]),
      ]))),
    ]);
   });
 }
}
class _BudgetStat extends StatelessWidget{
 const _BudgetStat({required this.label,required this.amount,required this.icon});
 final String label,amount;final IconData icon;
 @override Widget build(BuildContext context)=>SizedBox(width:142,
  child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
   Row(children:[
    Icon(icon,size:15,color:Theme.of(context).colorScheme.primary),
    const SizedBox(width:5),
    Expanded(child:Text(label,style:Theme.of(context).textTheme.labelSmall)),
   ]),
   Text(amount,style:Theme.of(context).textTheme.titleSmall?.copyWith(
    fontWeight:FontWeight.bold)),
  ]));
}
class _BudgetHistory extends StatelessWidget{
 const _BudgetHistory({required this.id});
 final String id;
 @override Widget build(BuildContext context){
  final db=Supabase.instance.client;
  return SafeArea(child:SizedBox(height:MediaQuery.sizeOf(context).height*.68,
   child:FutureBuilder<List<Map<String,dynamic>>>(
    future:db.from('occasion_budget_log')
     .select('event_kind,after_item,logged_at')
     .eq('plan_id',id).order('logged_at',ascending:false).limit(80),
    builder:(context,snapshot){
     if(snapshot.hasError)return const Center(child:Text('Planning log unavailable.'));
     if(!snapshot.hasData)return const Center(child:CircularProgressIndicator());
     return ListView(padding:const EdgeInsets.all(16),children:[
      Text('Planning log',style:Theme.of(context).textTheme.titleLarge),
      const Text('A trail of decisions, changes and purchases.'),
      for(final entry in snapshot.data!)ListTile(
       leading:const Icon(Icons.history_outlined),
       title:Text((entry['after_item'] is Map?
         (entry['after_item'] as Map)['title']:null)?.toString()??'Item'),
       subtitle:Text(entry['event_kind'].toString()+' · '+
        (entry['after_item'] is Map?
         (entry['after_item'] as Map)['status']?.toString():'') .toString()),
      ),
      if(snapshot.data!.isEmpty)const Text('No planning changes yet.'),
     ]);
    })));
 }
}

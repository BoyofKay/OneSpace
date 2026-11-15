import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/item_menu.dart';
import '../coordinate/activity_detail_screen.dart';
import 'occasion_budget_rules.dart';
import 'occasion_planning_insights.dart';
import 'occasion_budget_item_editor.dart';
import 'occasion_combination_planner.dart';
import 'package:onespace/l10n/phrases.dart';

const budgetStages=<String,String>{
 'wish':'Wishlist','shortlisted':'Considering','planned':'Reserved',
 'purchased':'Purchased','cancelled':'Excluded',
};

/// Embedded in Occasion detail: live wishlist, commitments, spending and history.
class OccasionBudgetWorkspace extends StatefulWidget {
 const OccasionBudgetWorkspace({super.key,required this.plan,required this.onEditPlan});
 final Map<String,dynamic> plan;
 final VoidCallback onEditPlan;
 @override State<OccasionBudgetWorkspace> createState()=>_OccasionBudgetWorkspaceState();
}
class _OccasionBudgetWorkspaceState extends State<OccasionBudgetWorkspace>{
 final db=Supabase.instance.client;
 late Stream<List<Map<String,dynamic>>> stream;
 bool showArchived=false,busy=false;
 int _proposalRefresh=0;
 final _itemsAnchor=GlobalKey();
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
 Future<void> edit([Map<String,dynamic>? row])async{
  await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
   builder:(_)=>OccasionBudgetItemEditor(plan:widget.plan,existing:row,initialStatus:'wish')));
 }
 Future<void> purchase(Map<String,dynamic> row)async{
  await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
   builder:(_)=>OccasionPurchaseEditor(plan:widget.plan,item:row)));
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
 Future<void> setRemoved(Map<String,dynamic> item)async{
  if(busy)return;
  setState((){busy=true;error=null;});
  try{
   await db.from('occasion_budget_items').update({
    'archived_at':item['archived_at']==null?DateTime.now().toUtc().toIso8601String():null,
   }).eq('id',item['id']).eq('plan_id',widget.plan['id']);
  }on PostgrestException catch(e){
   if(mounted)setState(()=>error=e.message);
  }catch(_){
   if(mounted)setState(()=>error='Could not update this item.');
  }finally{if(mounted)setState(()=>busy=false);}
 }
 Future<void> openLink(String link)async{
  final uri=Uri.tryParse(link);
  if(uri==null||!['http','https'].contains(uri.scheme))return;
  try{await launchUrl(uri,mode:LaunchMode.externalApplication);}catch(_){}
 }
 Future<void> compareCombinations(List<Map<String,dynamic>> items)async{
  final saved=await showModalBottomSheet<bool>(context:context,
   isScrollControlled:true,showDragHandle:true,builder:(_)=>SizedBox(
    height:MediaQuery.sizeOf(context).height*.88,
    child:OccasionCombinationPlanner(plan:widget.plan,items:items)));
  if(saved==true&&mounted)setState(()=>_proposalRefresh++);
 }
 void followInsight(String action){
  switch(action){
   case 'budget':widget.onEditPlan();
   case 'purchase':edit();
   default:
    final context=_itemsAnchor.currentContext;
    if(context!=null)Scrollable.ensureVisible(context,
     duration:const Duration(milliseconds:250));
  }
 }

 String money(Map<String,dynamic> item){
  final price=(item['unit_price'] as num?)?.toDouble();
  final paid=(item['actual_unit_price'] as num?)?.toDouble();
  final q=(item['quantity'] as num?)?.toInt()??1;
  final each=item['status']=='purchased'?(paid??price):price;
  if(each==null)return '';
  return '${item['currency']} ${each.toStringAsFixed(each%1==0?0:2)}${q>1?' × $q':''}';
 }

 Widget itemCard(Map<String,dynamic> item){
  final theme=Theme.of(context),colors=theme.colorScheme;
  final status=(item['status']??'wish').toString();
  final removed=item['archived_at']!=null;
  final occasion=DateTime.tryParse(widget.plan['occasion_on']?.toString()??'');
  final arrives=DateTime.tryParse(item['estimated_delivery']?.toString()??'');
  final late=arrives!=null&&occasion!=null&&arrives.isAfter(occasion);
  final link=(item['source_url']??'').toString();
  return Card(elevation:0,margin:const EdgeInsets.only(bottom:6),child:Padding(
   padding:const EdgeInsetsDirectional.fromSTEB(12,8,4,10),
   child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Row(children:[
     Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(tt(item['title'].toString()),style:theme.textTheme.titleMedium?.copyWith(
       decoration:removed||status=='cancelled'?TextDecoration.lineThrough:null)),
      Text(tt([
       budgetStages[status]??'Wishlist',
       if(money(item).isNotEmpty)money(item),
       if((item['merchant']??'').toString().isNotEmpty)item['merchant'].toString(),
       if(item['preference_score']!=null)'★ ${item['preference_score']}',
       if(item['product_rating']!=null)'Shop ${item['product_rating']}/5',
       if(removed)'Removed',
      ].join(' · ')),style:theme.textTheme.bodySmall),
     ])),
     AnchoredMenuButton<String>(tooltip:tt('More'),
      onSelected:(v){
       switch(v){
        case 'reserve':setStage(item,'planned');
        case 'purchase':purchase(item);
        case 'ideas':setStage(item,'wish');
        case 'undo':setStage(item,'planned');
        case 'exclude':setStage(item,'cancelled');
        case 'link':openLink(link);
        case 'edit':edit(item);
        case 'remove':setRemoved(item);
       }
      },
      itemBuilder:(_)=>[
       if(!removed&&(status=='wish'||status=='shortlisted'))iconMenuItem('reserve',Icons.bookmark_add_outlined,'Reserve'),
       if(!removed&&status=='planned')iconMenuItem('purchase',Icons.shopping_cart_checkout_outlined,'Mark as purchased'),
       if(!removed&&status=='purchased')iconMenuItem('purchase',Icons.local_shipping_outlined,'Order and delivery'),
       if(!removed&&status=='purchased')iconMenuItem('undo',MenuIcons.reopen,'Undo purchase'),
       if(!removed&&(status=='planned'||status=='cancelled'))iconMenuItem('ideas',Icons.lightbulb_outline,'Back to ideas'),
       if(!removed&&status!='cancelled'&&status!='purchased')iconMenuItem('exclude',MenuIcons.cancel,'Exclude'),
       if(link.isNotEmpty)iconMenuItem('link',Icons.open_in_new,'Open product link'),
       if(!removed)iconMenuItem('edit',MenuIcons.edit,'Edit'),
       iconMenuItem('remove',removed?MenuIcons.restore:MenuIcons.remove,removed?'Restore':'Remove'),
      ]),
    ]),
    if((status=='planned'||status=='purchased')&&
      ((item['order_number']??'').toString().isNotEmpty||arrives!=null||item['order_status']!='not_ordered'))
     Text(tt([
      if(item['order_status']!=null&&item['order_status']!='not_ordered')
       (item['order_status']).toString().replaceAll('_',' '),
      if((item['order_number']??'').toString().isNotEmpty)'#${item['order_number']}',
      if(arrives!=null)'Arrives ${item['estimated_delivery']}',
      if(late)'after the occasion',
     ].join(' · ')),style:TextStyle(color:late?colors.error:null)),
    if((item['notes']??'').toString().isNotEmpty)
     Text(tt(item['notes'].toString()),maxLines:2,overflow:TextOverflow.ellipsis,style:theme.textTheme.bodySmall),
    if(item['source_activity_id']!=null)TextButton.icon(
     icon:const Icon(Icons.hub_outlined,size:16),label:Text(tt('Source Activity')),
     onPressed:()=>Navigator.of(context).push(MaterialPageRoute<void>(
      builder:(_)=>ActivityScreen(id:item['source_activity_id'].toString())))),
   ])));
 }

 Widget group(String title,IconData icon,List<Map<String,dynamic>> rows,{String? total}){
  if(rows.isEmpty)return const SizedBox.shrink();
  final theme=Theme.of(context);
  return Card(elevation:0,clipBehavior:Clip.antiAlias,margin:const EdgeInsets.only(bottom:8),
   color:theme.colorScheme.surfaceContainerLow,
   child:ExpansionTile(
    leading:Icon(icon),
    title:Text(tt(title)+' (${rows.length})',style:theme.textTheme.titleMedium),
    subtitle:total==null?null:Text(tt(total)),
    childrenPadding:const EdgeInsets.fromLTRB(8,0,8,8),
    children:[for(final r in rows)itemCard(r)]));
 }

 @override Widget build(BuildContext context){
  final theme=Theme.of(context),colors=theme.colorScheme;
  return StreamBuilder<List<Map<String,dynamic>>>(stream:stream,
   builder:(context,snapshot){
    final data=snapshot.data??const <Map<String,dynamic>>[];
    final budget=OccasionBudgetRules.summarize(widget.plan,data);
    final live=data.where((r)=>r['archived_at']==null).toList();
    List<Map<String,dynamic>> of(Set<String> s)=>live.where((r)=>s.contains(r['status'])).toList();
    final ideas=of({'wish','shortlisted'}),reserved=of({'planned'}),
     bought=of({'purchased'}),excluded=of({'cancelled'});
    final removed=data.where((r)=>r['archived_at']!=null).toList();
    final comparable=[...ideas,...reserved];
    final suggestions=OccasionPlanningInsights.suggest(
     plan:widget.plan,budget:budget,items:data,today:DateTime.now());
    String currency(double? value)=>value==null?'Not set':
     budget.currency+' '+value.toStringAsFixed(value%1==0?0:2);
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
        Expanded(child:Text(tt('Occasion budget'),style:theme.textTheme.titleLarge)),
       ]),
       const SizedBox(height:9),
       Text(tt('Left after reserved and bought gifts')),
       Text(tt(currency(budget.available)),
        style:theme.textTheme.headlineMedium?.copyWith(
         fontWeight:FontWeight.w800,
         color:budget.overBudget?colors.error:null)),
       const SizedBox(height:10),
       ClipRRect(borderRadius:BorderRadius.circular(8),
        child:LinearProgressIndicator(value:budget.progress,minHeight:10)),
       const SizedBox(height:12),
       Wrap(spacing:16,runSpacing:12,children:[
        _BudgetStat(label:tt('Total budget'),amount:currency(budget.budget),
         icon:Icons.savings_outlined),
        _BudgetStat(label:tt('Wishlist (not deducted)'),amount:currency(budget.wishlist),
         icon:Icons.favorite_outline),
        _BudgetStat(label:tt('Reserved'),amount:currency(budget.planned),
         icon:Icons.bookmark_border),
        _BudgetStat(label:tt('Spent'),amount:currency(budget.spent),
         icon:Icons.receipt_long_outlined),
       ]),
       if(budget.overBudget)Padding(padding:const EdgeInsets.only(top:10),
        child:Text(tt('Over budget by ')+currency(-budget.available!)+
         tt('. Review the reserved gifts or the budget.'),
         style:TextStyle(color:colors.error))),
       if(budget.foreignCurrency>0||budget.unpriced>0)
        Padding(padding:const EdgeInsets.only(top:10),
         child:Text(tt('Other currencies: ')+budget.foreignCurrency.toString()+
           tt(' · Without a price: ')+budget.unpriced.toString()+
           tt('. Exchange rates are never guessed.'),
          style:theme.textTheme.bodySmall)),
      ])),
     const SizedBox(height:12),
     Card(child:Padding(padding:const EdgeInsets.all(14),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
       Row(children:[
        Icon(Icons.auto_awesome_outlined,color:colors.primary),
        const SizedBox(width:8),
        Expanded(child:Text(tt('Planning intelligence'),style:theme.textTheme.titleMedium)),
        FilledButton.tonalIcon(onPressed:()=>edit(),icon:const Icon(Icons.add),
         label:Text(tt('Add a gift option'))),
       ]),
       for(final hint in suggestions.take(2))Padding(
        padding:const EdgeInsets.only(top:8),
        child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
         Expanded(child:Text(tt(hint.message),style:theme.textTheme.bodyMedium)),
         if(hint.action!='purchase')...[
          const SizedBox(width:8),
          TextButton(onPressed:()=>followInsight(hint.action),
           child:Text(tt(hint.actionLabel))),
         ],
        ])),
      ]))),
     const SizedBox(height:12),
     _SavedGiftProposals(key:ValueKey('proposals-$_proposalRefresh'),
      plan:widget.plan,onUsed:()=>setState(()=>_proposalRefresh++)),
     const SizedBox(height:8),
     Row(key:_itemsAnchor,children:[
      Expanded(child:Text(tt('Gifts'),style:theme.textTheme.titleLarge)),
      IconButton(tooltip:tt('Compare and save gift lists'),
       icon:const Icon(Icons.compare_arrows),
       onPressed:comparable.length<2?null:()=>compareCombinations(comparable)),
      if(removed.isNotEmpty)IconButton(
       tooltip:tt(showArchived?'Hide removed':'Show removed'),isSelected:showArchived,
       icon:const Icon(Icons.delete_outline),selectedIcon:const Icon(Icons.delete),
       onPressed:()=>setState(()=>showArchived=!showArchived)),
     ]),
     if(snapshot.connectionState==ConnectionState.waiting&&!snapshot.hasData)
      const LinearProgressIndicator(),
     if(snapshot.hasError)
      Text(tt('Could not load the gifts. Reopen the occasion to retry.'),
       style:TextStyle(color:colors.error)),
     if(error!=null)Text(tt(error!),style:TextStyle(color:colors.error)),
     if(live.isEmpty&&!snapshot.hasError)Card(elevation:0,child:Padding(
      padding:const EdgeInsets.all(18),child:Column(children:[
       Icon(Icons.card_giftcard_outlined,size:32,color:colors.primary),
       const SizedBox(height:8),
       Text(tt('Add gift options, compare them, then reserve and buy within the budget.'),
        textAlign:TextAlign.center),
      ]))),
     group('Ideas',Icons.lightbulb_outline,ideas,
      total:budget.wishlist>0?currency(budget.wishlist):null),
     group('Reserved',Icons.bookmark_border,reserved,
      total:budget.planned>0?currency(budget.planned):null),
     group('Purchased',Icons.shopping_bag_outlined,bought,
      total:budget.spent>0?currency(budget.spent):null),
     group('Excluded',Icons.block,excluded),
     if(showArchived)group('Removed',Icons.delete_outline,removed),
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
    Expanded(child:Text(tt(label),style:Theme.of(context).textTheme.labelSmall)),
   ]),
   Text(tt(amount),style:Theme.of(context).textTheme.titleSmall?.copyWith(
    fontWeight:FontWeight.bold)),
  ]));
}
class _SavedGiftProposals extends StatelessWidget{
 const _SavedGiftProposals({super.key,required this.plan,required this.onUsed});
 final Map<String,dynamic> plan;
 final VoidCallback onUsed;

 /// R68: "Use this list" reserves every gift in it (its cost moves from
 /// the wishlist to Reserved); each is then marked as purchased with its
 /// order number and delivery date.
 Future<void> use(BuildContext context,Map<String,dynamic> proposal)async{
  final db=Supabase.instance.client;
  final messenger=ScaffoldMessenger.of(context);
  final ids=[for(final link in (proposal['occasion_proposal_items'] as List? ??const []))
   link['item_id'].toString()];
  if(ids.isEmpty)return;
  try{
   await db.from('occasion_budget_items').update({'status':'planned'})
    .inFilter('id',ids).inFilter('status',['wish','shortlisted']).eq('plan_id',plan['id']);
   await db.from('occasion_proposals').update({
    'status':'approved','updated_at':DateTime.now().toUtc().toIso8601String(),
   }).eq('id',proposal['id']);
   messenger.showSnackBar(SnackBar(content:Text(
    tt('Gifts reserved. Use ⋮ › Mark as purchased on each when you order it.'))));
   onUsed();
  }on PostgrestException catch(e){
   messenger.showSnackBar(SnackBar(content:Text(e.message)));
  }catch(_){
   messenger.showSnackBar(SnackBar(content:Text(tt('Could not use this list. Try again.'))));
  }
 }

 @override Widget build(BuildContext context){
  final db=Supabase.instance.client;
  return FutureBuilder<List<Map<String,dynamic>>>(
   future:db.from('occasion_proposals')
    .select('id,title,notes,status,created_at,occasion_proposal_items('
      'item_id,occasion_budget_items(title,unit_price,quantity,currency,estimated_delivery,order_status,status))')
    .eq('plan_id',plan['id'].toString())
    .order('created_at',ascending:false).limit(30),
   builder:(context,snapshot){
    if(snapshot.hasError||!snapshot.hasData)return const SizedBox.shrink();
    final proposals=snapshot.data!;
    if(proposals.isEmpty)return const SizedBox.shrink();
    final currency=(plan['currency']??'USD').toString();
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
     Text(tt('Saved gift lists'),style:Theme.of(context).textTheme.titleMedium),
     for(final proposal in proposals)Card(elevation:0,clipBehavior:Clip.antiAlias,child:ExpansionTile(
      leading:Icon(proposal['status']=='approved'?Icons.check_circle:Icons.list_alt_outlined,
       color:proposal['status']=='approved'?const Color(0xFF2E7D32):null),
      title:Text(tt(proposal['title'].toString())),
      subtitle:Text(tt(proposal['status']=='approved'?'In use':'Saved')),
      childrenPadding:const EdgeInsetsDirectional.fromSTEB(12,0,12,12),
      children:[
       if((proposal['notes']??'').toString().isNotEmpty)Text(tt(proposal['notes'].toString())),
       for(final link in (proposal['occasion_proposal_items'] as List? ??const []))
        Builder(builder:(context){
         final item=link['occasion_budget_items'];
         if(item is! Map)return const SizedBox.shrink();
         final cost=(item['unit_price'] as num?)?.toDouble();
         final qty=(item['quantity'] as num?)?.toDouble()??1;
         return ListTile(dense:true,contentPadding:EdgeInsets.zero,
          title:Text(tt((item['title']??'Option').toString())),
          subtitle:Text(tt([
           budgetStages[item['status']]??'',
           if(cost!=null)(item['currency']??currency).toString()+' '+(cost*qty).toStringAsFixed(0),
          ].where((x)=>x.isNotEmpty).join(' · '))));
        }),
       if(proposal['status']!='approved')Align(alignment:AlignmentDirectional.centerEnd,
        child:FilledButton.icon(onPressed:()=>use(context,proposal),
         icon:const Icon(Icons.playlist_add_check),label:Text(tt('Use this list')))),
      ],
     )),
    ]);
   });
 }
}

import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/responsive_field_pair.dart';
import 'occasion_budget_rules.dart';

const occasionItemStages={
 'wish':'Wishlist','shortlisted':'Considering','planned':'Reserved',
 'purchased':'Purchased','cancelled':'Skipped',
};
class OccasionBudgetItemEditor extends StatefulWidget{
 const OccasionBudgetItemEditor({super.key,required this.plan,
  this.existing,this.initialStatus='planned',this.markPurchase=false});
 final Map<String,dynamic> plan;
 final Map<String,dynamic>? existing;
 final String initialStatus;
 final bool markPurchase;
 @override State<OccasionBudgetItemEditor> createState()=>_OccasionBudgetItemEditorState();
}
class _OccasionBudgetItemEditorState extends State<OccasionBudgetItemEditor>{
 final db=Supabase.instance.client;
 late final TextEditingController title,qty,price,paid,currency,notes,url,merchant,orderNumber,trackingUrl,returnReason;
 DateTime? arrival;
 double? rating;
 int? preference;
 String orderStatus='not_ordered';
 late String status;
 bool busy=false;
 String? error;
 @override void initState(){
  super.initState();
  final p=widget.existing??{};
  title=TextEditingController(text:(p['title']??'').toString());
  qty=TextEditingController(text:(p['quantity']??1).toString());
  price=TextEditingController(text:(p['unit_price']??'').toString());
  paid=TextEditingController(text:(p['actual_unit_price']??'').toString());
  currency=TextEditingController(
   text:(p['currency']??widget.plan['currency']??'USD').toString());
  notes=TextEditingController(text:(p['notes']??'').toString());
  url=TextEditingController(text:(p['source_url']??'').toString());
  merchant=TextEditingController(text:(p['merchant']??'').toString());
  orderNumber=TextEditingController(text:(p['order_number']??'').toString());
  trackingUrl=TextEditingController(text:(p['tracking_url']??'').toString());
  returnReason=TextEditingController(text:(p['return_reason']??'').toString());
  arrival=DateTime.tryParse(p['estimated_delivery']?.toString()??'');
  rating=(p['product_rating'] as num?)?.toDouble();
  preference=(p['preference_score'] as num?)?.toInt();
  orderStatus=(p['order_status']??'not_ordered').toString();
  status=widget.markPurchase?'purchased':
    (p['status']??widget.initialStatus).toString();
 }
 @override void dispose(){
  for(final c in [title,qty,price,paid,currency,notes,url,merchant,orderNumber,trackingUrl,returnReason]){c.dispose();}
  super.dispose();
 }
 Future<void> save()async{
  if(busy)return;
  final count=int.tryParse(qty.text.trim());
  final estimated=price.text.trim().isEmpty?null:
    OccasionBudgetRules.amount(price.text);
  final actual=paid.text.trim().isEmpty?null:
    OccasionBudgetRules.amount(paid.text);
  final code=currency.text.trim().toUpperCase();
  if(title.text.trim().isEmpty||title.text.trim().length>200){
   setState(()=>error='Name your item (up to 200 characters).');return;
  }
  if(count==null||count<1||count>999){
   setState(()=>error='Quantity must be between 1 and 999.');return;
  }
  if((price.text.trim().isNotEmpty&&estimated==null)||
     (paid.text.trim().isNotEmpty&&actual==null)||
      (estimated!=null&&estimated>9999999999)||
      (actual!=null&&actual>9999999999)){
   setState(()=>error='Use valid nonnegative prices or leave them empty.');return;
  }
  if(!RegExp(r'^[A-Z]{3}$').hasMatch(code)){
   setState(()=>error='Use a three-letter currency.');return;
  }
  if(!OccasionBudgetRules.isHttpUrl(url.text)){
   setState(()=>error='Enter a valid product URL (http/https).');return;
  }
  if(!OccasionBudgetRules.isHttpUrl(trackingUrl.text)){
   setState(()=>error='Enter a valid carrier tracking URL or leave it blank.');return;
  }
  setState((){busy=true;error=null;});
  try{
   final values=<String,dynamic>{
    'title':title.text.trim(),'quantity':count,
    'unit_price':estimated,'actual_unit_price':actual,
    'currency':code,'status':status,'source_url':url.text.trim(),
    'notes':notes.text.trim(),
    'merchant':merchant.text.trim(),
    'estimated_delivery':arrival==null?null:'${arrival!.year.toString().padLeft(4,'0')}-${arrival!.month.toString().padLeft(2,'0')}-${arrival!.day.toString().padLeft(2,'0')}',
    'product_rating':rating,'preference_score':preference,
    'order_status':orderStatus,'order_number':orderNumber.text.trim(),
    'tracking_url':trackingUrl.text.trim(),
    'return_reason':returnReason.text.trim(),
   };
   if(widget.existing==null){
    await db.from('occasion_budget_items').insert({
     ...values,'plan_id':widget.plan['id']});
   }else{
    await db.from('occasion_budget_items').update(values)
     .eq('id',widget.existing!['id']).eq('plan_id',widget.plan['id']);
   }
   if(mounted)Navigator.of(context).pop(true);
  }on PostgrestException catch(e){
   if(mounted)setState(()=>error=e.message);
  }catch(_){
   if(mounted)setState(()=>error='Could not save this item. Try again.');
  }finally{if(mounted)setState(()=>busy=false);}
 }
 Future<void> pickArrival()async{
  final now=DateTime.now();
  final day=await showDatePicker(context:context,
   initialDate:arrival??now.add(const Duration(days:7)),
   firstDate:DateTime(now.year-2),lastDate:DateTime(now.year+10));
  if(day!=null&&mounted)setState(()=>arrival=day);
 }
 @override Widget build(BuildContext context){
  final theme=Theme.of(context);
  return SafeArea(child:Padding(
   padding:EdgeInsets.fromLTRB(18,8,18,MediaQuery.viewInsetsOf(context).bottom+18),
   child:SingleChildScrollView(child:Column(
    crossAxisAlignment:CrossAxisAlignment.stretch,mainAxisSize:MainAxisSize.min,
    children:[
     Row(children:[
      Icon(Icons.card_giftcard_outlined,color:theme.colorScheme.primary),
      const SizedBox(width:8),
      Expanded(child:Text(widget.existing==null?
       'Add a meaningful item':'Edit purchase or wish',
       style:theme.textTheme.titleLarge)),
     ]),
     const SizedBox(height:12),
     TextField(controller:title,maxLength:200,
      decoration:const InputDecoration(labelText:'Item or experience')),
     if(widget.markPurchase)Padding(padding:const EdgeInsets.only(bottom:10),
      child:Text('Record the final amount paid. This moves the item from reserved to spent.',
       style:theme.textTheme.bodyMedium)),
     DropdownButtonFormField<String>(initialValue:status,
      decoration:const InputDecoration(labelText:'Planning state'),
      items:[for(final e in occasionItemStages.entries)
       DropdownMenuItem(value:e.key,child:Text(e.value))],
      onChanged:(v)=>setState(()=>status=v??status)),
     const SizedBox(height:10),
     ResponsiveFieldPair(firstFlex:1,
      first:TextField(controller:qty,keyboardType:TextInputType.number,
       decoration:const InputDecoration(labelText:'Quantity')),
      second:TextField(controller:currency,maxLength:3,
       textCapitalization:TextCapitalization.characters,
       decoration:const InputDecoration(labelText:'Currency'))),
     const SizedBox(height:10),
     ResponsiveFieldPair(
      first:TextField(controller:price,
       keyboardType:const TextInputType.numberWithOptions(decimal:true),
       decoration:const InputDecoration(labelText:'Estimated unit price')),
      second:TextField(controller:paid,
       keyboardType:const TextInputType.numberWithOptions(decimal:true),
       decoration:const InputDecoration(labelText:'Actual unit price'))),
     const SizedBox(height:10),
     TextField(controller:url,maxLength:1800,
      decoration:const InputDecoration(labelText:'Product link (optional)')),
     TextField(controller:merchant,maxLength:140,
      decoration:const InputDecoration(labelText:'Retailer / merchant (e.g. Amazon, Walmart)')),
     const SizedBox(height:8),
     OutlinedButton.icon(onPressed:busy?null:pickArrival,
      icon:const Icon(Icons.local_shipping_outlined),
      label:Text(arrival==null?'Estimated delivery date (optional)':
       'Estimated delivery: ${arrival!.year}-${arrival!.month.toString().padLeft(2,'0')}-${arrival!.day.toString().padLeft(2,'0')}')),
     if(arrival!=null)TextButton(onPressed:()=>setState(()=>arrival=null),
      child:const Text('Clear estimated delivery')),
     if(arrival!=null&&widget.plan['occasion_on']!=null&&
       arrival!.isAfter(DateTime.tryParse(widget.plan['occasion_on'].toString())??
        DateTime(2100)))
       const Text('Delivery is after the occasion date!',
        style:TextStyle(color:Colors.red)),
     const SizedBox(height:8),
     Text('Your preference: ${preference==null?'Not rated':preference.toString()+'/5'}'),
     Wrap(spacing:3,children:[
      for(var value=1;value<=5;value++)ChoiceChip(
        label:Text(value.toString()),selected:preference==value,
        onSelected:(_)=>setState(()=>preference=preference==value?null:value)),
      ]),
      const SizedBox(height:8),
      DropdownButtonFormField<double?>(
       initialValue:rating,
       decoration:const InputDecoration(labelText:'Retailer rating (out of 5)'),
       items:[const DropdownMenuItem<double?>(value:null,child:Text('Not rated')),
        for(final n in [1.0,2.0,3.0,3.5,4.0,4.5,5.0])
         DropdownMenuItem<double?>(value:n,child:Text(n.toString()))],
       onChanged:(v)=>setState(()=>rating=v)),
      const SizedBox(height:8),
      DropdownButtonFormField<String>(
       initialValue:orderStatus,
       decoration:const InputDecoration(labelText:'Order / delivery status'),
       items:const [
        DropdownMenuItem(value:'not_ordered',child:Text('Not ordered')),
        DropdownMenuItem(value:'ordered',child:Text('Ordered')),
        DropdownMenuItem(value:'shipped',child:Text('Shipped')),
        DropdownMenuItem(value:'delivered',child:Text('Delivered')),
        DropdownMenuItem(value:'return_requested',child:Text('Return requested')),
        DropdownMenuItem(value:'returned',child:Text('Returned')),
        DropdownMenuItem(value:'cancelled',child:Text('Cancelled order'))],
       onChanged:(v)=>setState(()=>orderStatus=v??orderStatus)),
      if(orderStatus!='not_ordered')...[
       TextField(controller:orderNumber,maxLength:160,
        decoration:const InputDecoration(labelText:'Order number (optional)')),
       TextField(controller:trackingUrl,maxLength:1800,
        decoration:const InputDecoration(labelText:'Carrier tracking link (optional)')),
      ],
      if(orderStatus=='return_requested'||orderStatus=='returned')
       TextField(controller:returnReason,maxLength:600,maxLines:2,
        decoration:const InputDecoration(labelText:'Return reason / alternatives needed')),
      const SizedBox(height:10),
     TextField(controller:notes,maxLength:2500,maxLines:3,
      decoration:const InputDecoration(labelText:'Why this item? Notes, ideas, vendor details')),
     const SizedBox(height:7),
     Text('Wishlist items are free to explore. Reserved items reduce available budget. Purchased items use actual spending.',
      style:theme.textTheme.bodySmall),
     if(error!=null)Padding(padding:const EdgeInsets.only(top:9),
      child:Text(error!,style:TextStyle(color:theme.colorScheme.error))),
     const SizedBox(height:14),
     FilledButton.icon(onPressed:busy?null:save,
      icon:const Icon(Icons.save_outlined),
      label:Text(busy?'Saving…':'Save item')),
    ]),
   ),
  ));
 }
}

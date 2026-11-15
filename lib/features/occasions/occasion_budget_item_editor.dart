import '../../core/editor_scaffold.dart';
import '../../core/form_kit.dart';
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
 // Kept for callers; the form uses DateField.
 Future<void> pickArrival()async{
  final now=DateTime.now();
  final day=await showDatePicker(context:context,
   initialDate:arrival??now.add(const Duration(days:7)),
   firstDate:DateTime(now.year-2),lastDate:DateTime(now.year+10));
  if(day!=null&&mounted)setState(()=>arrival=day);
 }
 String get _signature=>[title.text,qty.text,price.text,paid.text,currency.text,notes.text,url.text,
  merchant.text,orderNumber.text,trackingUrl.text,returnReason.text,arrival,rating,preference,orderStatus,status].join('|');
 late final String _start=_signature;

 @override Widget build(BuildContext context){
  final theme=Theme.of(context);
  final occasionDay=DateTime.tryParse(widget.plan['occasion_on']?.toString()??'');
  return EditorScaffold(
   title:widget.markPurchase?'Record the purchase':widget.existing==null?'Add gift or item':'Edit gift or item',
   isNew:widget.existing==null||widget.markPurchase,
   isChanged:()=>_signature!=_start,
   isComplete:()=>title.text.trim().isNotEmpty,
   listenTo:[title,qty,price,paid,currency,notes,url,merchant,orderNumber,trackingUrl,returnReason],
   saving:busy,onSave:save,
   body:ListView(padding:const EdgeInsets.all(18),children:[
     if(widget.markPurchase)Padding(padding:const EdgeInsets.only(bottom:12),
      child:Text('Enter what you actually paid. The item moves from reserved to spent.',
       style:theme.textTheme.bodyMedium)),
     TextField(controller:title,maxLength:200,autofocus:widget.existing==null,
      textCapitalization:TextCapitalization.sentences,
      decoration:const InputDecoration(labelText:'Gift, item or experience *',border:OutlineInputBorder())),
     ChoiceRow<String>(label:'Stage',options:occasionItemStages,selected:status,
      icons:const {'wish':Icons.lightbulb_outline,'shortlisted':Icons.compare_arrows,
       'planned':Icons.bookmark_border,'purchased':Icons.shopping_bag_outlined,'cancelled':Icons.block},
      onSelected:(v)=>setState(()=>status=v??status)),
     Text('Wishlist and Considering are free to explore. Reserved counts against the budget; Purchased uses what you paid.',
      style:theme.textTheme.bodySmall),
     const FormSection('Cost'),
     ResponsiveFieldPair(firstFlex:1,
      first:TextField(controller:qty,keyboardType:TextInputType.number,
       decoration:const InputDecoration(labelText:'Quantity',border:OutlineInputBorder())),
      second:TextField(controller:currency,maxLength:3,
       textCapitalization:TextCapitalization.characters,
       decoration:const InputDecoration(labelText:'Currency',border:OutlineInputBorder()))),
     const SizedBox(height:10),
     ResponsiveFieldPair(
      first:TextField(controller:price,
       keyboardType:const TextInputType.numberWithOptions(decimal:true),
       decoration:const InputDecoration(labelText:'Estimated price (each)',border:OutlineInputBorder())),
      second:TextField(controller:paid,
       keyboardType:const TextInputType.numberWithOptions(decimal:true),
       decoration:InputDecoration(labelText:widget.markPurchase?'Paid (each) *':'Paid (each)',
        border:const OutlineInputBorder()))),
     const FormSection('Where to get it'),
     TextField(controller:merchant,maxLength:140,
      decoration:const InputDecoration(labelText:'Shop',hintText:'Amazon, Walmart…',
       prefixIcon:Icon(Icons.storefront_outlined),border:OutlineInputBorder())),
     const SizedBox(height:10),
     TextField(controller:url,maxLength:1800,keyboardType:TextInputType.url,
      decoration:const InputDecoration(labelText:'Product link',prefixIcon:Icon(Icons.link),
       border:OutlineInputBorder())),
     const SizedBox(height:10),
     ChoiceRow<int>(label:'How much we like it',
      options:const {0:'—',1:'1',2:'2',3:'3',4:'4',5:'5'},selected:preference??0,
      onSelected:(v)=>setState(()=>preference=v==null||v==0?null:v)),
     ChoicePickerField<double>(label:'Shop rating',icon:Icons.star_outline,noneLabel:'Not rated',
      options:{for(final n in [1.0,2.0,3.0,3.5,4.0,4.5,5.0])n:'$n out of 5'},
      selected:rating,onSelected:(v)=>setState(()=>rating=v)),
     const FormSection('Order and delivery'),
     ChoicePickerField<String>(label:'Order status',icon:Icons.local_shipping_outlined,
      options:const {'not_ordered':'Not ordered','ordered':'Ordered','shipped':'Shipped',
       'delivered':'Delivered','return_requested':'Return requested','returned':'Returned',
       'cancelled':'Order cancelled'},
      selected:orderStatus,onSelected:(v)=>setState(()=>orderStatus=v??orderStatus)),
     if(orderStatus!='not_ordered')...[
      TextField(controller:orderNumber,maxLength:160,
       decoration:const InputDecoration(labelText:'Order number',border:OutlineInputBorder())),
      const SizedBox(height:10),
      TextField(controller:trackingUrl,maxLength:1800,keyboardType:TextInputType.url,
       decoration:const InputDecoration(labelText:'Tracking link',border:OutlineInputBorder())),
      const SizedBox(height:10),
     ],
     DateField(label:'Expected delivery',value:arrival,
      first:DateTime(DateTime.now().year-2),last:DateTime(DateTime.now().year+10),
      onChanged:(v)=>setState(()=>arrival=v)),
     if(arrival!=null&&occasionDay!=null&&arrival!.isAfter(occasionDay))Padding(
      padding:const EdgeInsets.only(bottom:10),
      child:Text('Arrives after the occasion date.',style:TextStyle(color:theme.colorScheme.error))),
     if(orderStatus=='return_requested'||orderStatus=='returned')Padding(
      padding:const EdgeInsets.only(bottom:10),
      child:TextField(controller:returnReason,maxLength:600,minLines:2,maxLines:4,
       decoration:const InputDecoration(labelText:'Why return it? Alternatives?',border:OutlineInputBorder()))),
     const FormSection('Notes'),
     TextField(controller:notes,maxLength:2500,minLines:2,maxLines:5,
      decoration:const InputDecoration(labelText:'Why this one? Ideas, details',
       alignLabelWithHint:true,border:OutlineInputBorder())),
     if(error!=null)Padding(padding:const EdgeInsets.only(top:9),
      child:Text(error!,style:TextStyle(color:theme.colorScheme.error))),
   ]));
 }
}
